<#
    Servidor-Painel.ps1
    Painel web LOCAL do ConfigurarCameras. PowerShell 5.1 puro, sem modulo.

    COMO FUNCIONA
      - HttpListener so em 127.0.0.1, porta livre escolhida na subida.
      - A pagina (www\) e servida daqui e aberta no Edge em modo app.
      - UM worker (runspace dedicado) carrega o Motor-Cameras.ps1 e executa
        os comandos em fila, um por vez: o firmware da camera nao aguenta
        concorrencia, e a placa de rede do PC tambem nao.
      - O worker e dono do estado e publica um retrato em JSON a cada mudanca;
        o painel busca esse retrato e o log por polling (GET /api/estado).
      - A senha da sessao vive so na memoria do worker. Nunca vai para disco,
        log, retrato de estado ou resposta HTTP.

    SEGURANCA
      Host tem que ser 127.0.0.1:<porta> (contra DNS rebinding) e todo
      POST/PUT exige Origin identico (contra CSRF de outra aba do navegador).

    USO
      INICIAR-PAINEL.vbs                (sem console: eleva e abre o painel; e o atalho do instalador)
      INICIAR-PAINEL-COM-CONSOLE.bat    (com console, para diagnostico)
      .\Servidor-Painel.ps1 -SemNavegador -SemElevar -PastaDados C:\temp\painel
      .\Servidor-Painel.ps1 -Simular     (nada vai para camera nem placa; so diagnostico e testes)

    SESSAO E PASSO A PASSO
      sessao.json guarda o que o passo a passo monta (placa escolhida, rede
      das cameras, faixa de fabrica, camera, ultima fila). Sem sessao
      completa a pagina abre no passo a passo e o worker recusa trabalho.
      A placa escolhida e a unica via ate as cameras (docs/adr/0003).
      placa-sessao.json e outra coisa: o RASTRO do que o painel fez na placa.

    INSTANCIA UNICA E AUTO-ENCERRAR
      painel.json na pasta de dados diz a porta e o pid do painel aberto: o
      atalho de novo so reabre a janela. Sem pagina (GET /api/estado) por
      -OciosoSeg (180 s) e sem nada em curso, o painel fecha sozinho e
      devolve a placa.

    DADOS
      %ProgramData%\ConfigurarCameras (registro.json, sessao.json, log.txt).
      Sem permissao de escrita ali, %LOCALAPPDATA%\ConfigurarCameras, com aviso.
      O instalador (instalador\ConfigurarCameras.iss) nunca apaga essa pasta.
#>
[CmdletBinding()]
param(
    [int]$Porta = 0,
    [switch]$SemNavegador,
    [switch]$SemElevar,
    [string]$PastaDados = '',
    [switch]$Oculto,
    [int]$OciosoSeg = 180,
    # Atualizacao pelo GitHub Releases: checada 1x por dia (10 s depois de
    # subir). -SemAtualizacao desliga; -UrlAtualizacao troca a API (testes).
    [switch]$SemAtualizacao,
    [string]$UrlAtualizacao = 'https://api.github.com/repos/xyron-robotics/ConfigurarCameras/releases/latest',
    # Simulacao: nada e enviado para camera nem para a placa; registro
    # separado. Nao tem tela (desde a 1.2.0): so por aqui ou POST /api/simular.
    [switch]$Simular
)

$ErrorActionPreference = 'Stop'

# Sem console (-Oculto) o erro vai para uma caixa de mensagem; senao fica no
# console ate o Enter (a janela elevada fecharia antes de dar para ler).
function Show-ErroJanela {
    param([string]$Mensagem)
    # 120 s: a caixa some sozinha se ninguem estiver olhando (o processo e oculto).
    try { $null = (New-Object -ComObject WScript.Shell).Popup($Mensagem, 120, 'Configurar Câmeras', 16) } catch { }
}
function Stop-ComErro {
    param([string]$Mensagem)
    if ($Oculto) { Show-ErroJanela ($Mensagem + "`n`nPara ver o detalhe, abra pelo INICIAR-PAINEL-COM-CONSOLE.bat.") }
    else {
        Write-Host ("  " + $Mensagem) -ForegroundColor Red
        if (-not $SemNavegador) { $null = Read-Host 'Pressione Enter para fechar' }
    }
    exit 1
}
trap { Stop-ComErro ('Erro inesperado: ' + $_.Exception.Message) }

$raizWeb = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($raizWeb)) { $raizWeb = Split-Path -Parent $MyInvocation.MyCommand.Path }
$motor = Join-Path (Split-Path -Parent $raizWeb) 'Motor-Cameras.ps1'
$www   = Join-Path $raizWeb 'www'

. $motor
$VersaoPainel = Get-VersaoPainel -Pasta (Split-Path -Parent $motor)

# Abre a pagina no Edge em modo app (InPrivate: nao oferece salvar a senha
# nem guarda historico); sem Edge, no navegador padrao.
function Open-Navegador {
    param([string]$Url)
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
              "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($edge) { Start-Process -FilePath $edge -ArgumentList @('--app=' + $Url, '--new-window', '--inprivate') }
    else { Start-Process $Url }
}

# ------------------------------------------------------- instancia unica
# ANTES do UAC: com um painel ja aberto, o atalho so reabre a janela dele.
# painel.json fica na pasta de dados (ProgramData ou, sem escrita la,
# LOCALAPPDATA); as duas sao olhadas.
$pastasLock = @()
if ($PastaDados) { $pastasLock += $PastaDados }
else { $pastasLock += (Join-Path $env:ProgramData 'ConfigurarCameras'); $pastasLock += (Join-Path $env:LOCALAPPDATA 'ConfigurarCameras') }
foreach ($pl in $pastasLock) {
    $lock = Read-LockPainel -Caminho (Join-Path $pl 'painel.json')
    if ($null -eq $lock) { continue }
    if ($lock.Pid -eq $PID) { continue }
    $vivo = $null -ne (Get-Process -Id $lock.Pid -ErrorAction SilentlyContinue)
    if (-not $vivo) { continue }
    $resp = ''
    try { $resp = (& curl.exe -s --max-time 1 ('http://127.0.0.1:' + $lock.Porta + '/api/estado')) -join '' } catch { }
    if ($resp -match '"estado"') {
        if (-not $SemNavegador) { Open-Navegador ('http://127.0.0.1:' + $lock.Porta + '/') }
        else { Write-Host ("  Painel ja aberto em http://127.0.0.1:" + $lock.Porta + "/ (pid " + $lock.Pid + ")") -ForegroundColor Yellow }
        exit 0
    }
}

# ---------------------------------------------------------------- elevacao
# Preparar a placa de rede exige Administrador. Eleva uma vez, na subida.
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$ehAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $ehAdmin -and -not $SemElevar) {
    $argus = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($Oculto) { $argus += @('-WindowStyle', 'Hidden') }
    $argus += @('-File', ('"' + $MyInvocation.MyCommand.Path + '"'))
    if ($Porta -gt 0) { $argus += @('-Porta', $Porta) }
    if ($SemNavegador) { $argus += '-SemNavegador' }
    if ($PastaDados) { $argus += @('-PastaDados', ('"' + $PastaDados + '"')) }
    if ($Oculto) { $argus += '-Oculto' }
    if ($OciosoSeg -ne 180) { $argus += @('-OciosoSeg', $OciosoSeg) }
    if ($Simular) { $argus += '-Simular' }
    if ($SemAtualizacao) { $argus += '-SemAtualizacao' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argus -Verb RunAs | Out-Null
    } catch {
        Stop-ComErro "Elevacao recusada. Abra de novo e clique em Sim no pedido do Windows (sem Administrador a placa de rede nao pode ser preparada)."
    }
    exit 0
}

# curl.exe e o unico transporte ate a camera: sem ele o painel nao serve.
try { Assert-Curl } catch { Stop-ComErro $_.Exception.Message }

# Pasta de dados: ProgramData (todos os usuarios). Sem Administrador ela pode
# ser somente leitura; ai o painel usa %LOCALAPPDATA% e avisa - e um segundo
# registro, o operador precisa saber.
function Test-PastaGravavel {
    param([string]$Pasta)
    try {
        if (-not (Test-Path -LiteralPath $Pasta)) { $null = New-Item -ItemType Directory -Force -Path $Pasta -ErrorAction Stop }
        $teste = Join-Path $Pasta ('.teste-' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($teste, 'x')
        Remove-Item -LiteralPath $teste -Force
        return $true
    } catch { return $false }
}
$pastaAlternativa = $false
if ([string]::IsNullOrWhiteSpace($PastaDados)) {
    $PastaDados = Join-Path $env:ProgramData 'ConfigurarCameras'
    if (-not (Test-PastaGravavel $PastaDados)) {
        $PastaDados = Join-Path $env:LOCALAPPDATA 'ConfigurarCameras'
        $pastaAlternativa = $true
        Write-Host ("  Sem permissao de escrita em ProgramData: dados em " + $PastaDados) -ForegroundColor Yellow
    }
}
if (-not (Test-PastaGravavel $PastaDados)) { Stop-ComErro ('Nao consigo gravar na pasta de dados: ' + $PastaDados) }
$arquivos = @{
    Alternativa    = $pastaAlternativa
    # A sessao do passo a passo. padroes.json e ultima-fila.json sao das
    # versoes ate a 1.1.1: viram sessao.json uma vez (Import-SessaoLegada).
    Sessao         = (Join-Path $PastaDados 'sessao.json')
    Padroes        = (Join-Path $PastaDados 'padroes.json')
    UltimaFila     = (Join-Path $PastaDados 'ultima-fila.json')
    Registro       = (Join-Path $PastaDados 'registro.json')
    RegistroSimul  = (Join-Path $PastaDados 'registro-simulado.json')
    Log            = (Join-Path $PastaDados 'log.txt')
    Blacklist      = (Join-Path $PastaDados 'nao-cameras.txt')
    # Rastro do que o painel fez na placa (para devolver ao encerrar, mesmo
    # depois de um fechamento no X).
    SessaoPlaca    = (Join-Path $PastaDados 'placa-sessao.json')
    Lock           = (Join-Path $PastaDados 'painel.json')
    # Cache da ultima checagem de atualizacao e log do instalador silencioso.
    Atualizacao    = (Join-Path $PastaDados 'atualizacao.json')
    LogInstalador  = (Join-Path $PastaDados 'instalador.log')
}

# ------------------------------------------------------- estado compartilhado
# $E e o unico canal entre o listener e o worker. O worker publica em
# $E.Estado um JSON pronto (string: troca atomica, sem colecao mutavel
# atravessando thread). O log e uma lista sincronizada com numero de sequencia.
$E = [hashtable]::Synchronized(@{
    Estado  = '{}'
    Log     = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
    LogSeq  = 0
    Ocupado = $false
    Simular = [bool]$Simular
    Parar   = $false
    # Ultimo GET /api/estado: a pagina sumiu quando isso envelhece (auto-encerrar).
    UltimoPoll = (Get-Date)
    # Atualizacao (runspace atualizador): retrato JSON, pedido do operador e o
    # instalador baixado e conferido, que o finally roda depois de tudo parar.
    Atualizacao = '{"estado":"nenhuma"}'
    AtualizarPedido = $false
    InstaladorPronto = ''
})
$Q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'

$adicionarLog = {
    param($Ts, $Msg, $Cor)
    $lista = $E.Log
    [Threading.Monitor]::Enter($lista.SyncRoot)
    try {
        $E.LogSeq = [int]$E.LogSeq + 1
        [void]$lista.Add([pscustomobject]@{ n = $E.LogSeq; ts = $Ts; msg = $Msg; cor = $Cor })
        if ($lista.Count -gt 3000) { $lista.RemoveRange(0, 500) }
    } finally { [Threading.Monitor]::Exit($lista.SyncRoot) }
}.GetNewClosure()

Set-MotorLog -Arquivo $arquivos.Log -Sink $adicionarLog

# Migracao da 1.1.1 (padroes.json + ultima-fila.json -> sessao.json): antes
# do worker subir, uma vez. Falha aqui nao derruba o painel: fica sem sessao
# e o passo a passo pede tudo.
try { $null = Import-SessaoLegada -CaminhoSessao $arquivos.Sessao -CaminhoPadroes $arquivos.Padroes -CaminhoUltimaFila $arquivos.UltimaFila }
catch { Write-Log ("Migracao dos padroes antigos falhou: " + $_.Exception.Message + ". O passo a passo pede tudo de novo.") 'Yellow' }

# ------------------------------------------------------------------ worker
$scriptWorker = {
    param($E, $Q, $Motor, $Arquivos, $AdicionarLog)
    $ErrorActionPreference = 'Stop'
    . $Motor
    Set-MotorLog -Arquivo $Arquivos.Log -Sink ([scriptblock]::Create($AdicionarLog.ToString()))

    $W = @{
        Senha = ''; Simular = [bool]$E.Simular; FalharEm = ''
        # SenhaGeracao sobe a cada senha informada. Uma falha por senha recusada
        # guarda a geracao: "Tentar de novo" so volta com senha mais nova
        # (repetir senha recusada gasta tentativa do lockout da camera).
        SenhaGeracao = 0
        Fase = 'ocioso'          # ocioso | fila | configurando | escolher | decisao | concluida | encerrada
        Trabalho = ''; Etapa = ''
        TrabalhoBase = ''        # texto da camera em curso; o detalhe do motor passa por cima
        Progresso = $null        # @{ atual; total } quando ha contagem (espera do boot, verificacao)
        Fila = $null             # @{ Itens; Local; Rack; Andar }
        Atual = -1               # indice na fila da camera em configuracao
        Camera = $null           # contexto da configuracao em curso (para "Tentar de novo")
        CameraDoVigia = $false   # a camera em curso foi achada pelo vigia (porta/canal avancam no sucesso)
        Falha = $null; Escolha = @(); Ferramenta = $null; Aviso = ''; Ultimo = ''
        # AvisoOrigem = comando que gerou o aviso (a pagina mostra junto dele).
        # AvisoN sobe a cada aviso novo: o mesmo texto duas vezes seguidas
        # continua sendo dois avisos.
        AvisoOrigem = ''; AvisoN = 0; AvisoPublicado = ''
        Rede = $null
        # Internet do PC: 'ok' | 'sem' | 'nao-testado'. InternetAntes e a
        # baseline da subida: "sem internet" que ja era assim nao e culpa do painel.
        Internet = 'nao-testado'; InternetAntes = 'nao-testado'; InternetQuando = ''
        # SessaoGeracao sobe a cada gravacao de sessao.json: a pagina recarrega
        # os formularios quando ve o numero mudar. SessaoIniciada: o operador
        # ja clicou em "comecar" nesta abertura (so memoria: a cada abertura o
        # passo a passo oferece usar ou revisar a sessao).
        SessaoGeracao = 0; SessaoIniciada = $false
        # Vigia: observa o IP de fabrica com a fila parada. Vistos = MACs de
        # camera ja inicializada ja avisados (um aviso por MAC).
        # SemSucesso: tiques seguidos em que a camera de fabrica apareceu mas
        # nao foi configurada (aviso). Em 5 o vigia desliga em vez de insistir.
        # Broadcast: com a chave ligada o vigia tambem aceita camera de fabrica
        # em qualquer faixa (broadcast DHIP); desligada, so o IP de fabrica.
        Vigia = @{ Ligado = $false; Porta = ''; Canal = ''; Vistos = @{}; Proximo = [datetime]::MinValue; Motivo = ''; SemSucesso = 0; Broadcast = $false }
        # Achados completos da lista de escolha (a pagina so ve o resumo).
        EscolhaAchados = @()
        # Sem Administrador (-SemElevar, ou elevacao recusada) a placa de rede nao muda.
        Admin = [bool](Test-EhAdministrador)
    }
    $TextoSemAdmin = 'O painel está aberto sem permissão de Administrador, e sem ela a placa de rede não muda. ' +
                     'Encerre o painel, abra de novo pelo atalho e aceite o pedido do Windows.'
    # Em simulacao nada pode tocar a rede real, nem so para ler.
    $TextoSoReal = 'Em simulação, Sondar e Procurar ficam desligados: eles leem a rede real.'
    $TextoSemSenha = 'Informe a senha da sessão antes: em Opções, seção Senha.'
    $TextoSemSessao = 'Conclua o passo a passo antes (placa de rede, rede das câmeras e faixa de fábrica). Para revisar, abra Opções.'
    # Lockout Dahua: ~5 senhas erradas trancam o admin por minutos. Nunca repetir.
    $TextoSenhaRecusada = 'A câmera recusou a senha da sessão. Troque a senha (Opções, seção Senha) antes de tentar de novo: cada tentativa com a senha errada conta para o bloqueio da câmera.'
    $TextoBloqueada = 'A câmera bloqueou o admin por senhas erradas. Espere alguns minutos, confirme a senha certa em Opções e só então tente de novo.'
    function Get-TextoRecusa { param([string]$Ip, $Sessao) if ($Sessao.Bloqueada) { return $TextoBloqueada } return ('A câmera em ' + $Ip + ' recusou a senha da sessão. Não repita: cada tentativa conta para o bloqueio. Confira a senha em Opções.') }
    function Get-TextoIpInvalido { param([string]$Ip) return ('IP inválido: ' + $Ip + '. Use quatro números de 0 a 255, como 192.168.1.108.') }

    function Get-CaminhoRegistroAtual {
        if ($W.Simular) { return $Arquivos.RegistroSimul }
        return $Arquivos.Registro
    }

    # --- sessao (sessao.json): so o worker grava; o listener le.

    # Nula sem arquivo (ou ilegivel: o log avisa e o passo a passo pede tudo).
    function Read-SessaoAtual {
        try { return (Read-Sessao -Caminho $Arquivos.Sessao) } catch { Write-Log ("  sessao.json ilegivel: " + $_.Exception.Message) 'Red'; return $null }
    }

    # Sessao ou a de fabrica: para quem so precisa dos campos (devolver a
    # placa, mascara da fila) e nunca pode ficar sem objeto.
    function Get-SessaoOuFabrica {
        $s = Read-SessaoAtual
        if ($null -eq $s) { return (Get-SessaoFabrica) }
        return $s
    }

    # Sessao completa (placa escolhida, sem erro, passo a passo concluido) ou
    # nula com o aviso: todo comando de trabalho passa por aqui.
    function Get-SessaoPronta {
        $s = Read-SessaoAtual
        if ($null -ne $s -and (Test-SessaoCompleta $s)) { return $s }
        $W.Aviso = $TextoSemSessao
        return $null
    }

    function Save-SessaoAtual {
        param($Sessao)
        $s = Save-Sessao -Caminho $Arquivos.Sessao -Sessao $Sessao
        $W.SessaoGeracao = [int]$W.SessaoGeracao + 1
        return $s
    }

    # Retrato da sessao para a pagina (sem o conteudo das secoes: isso vem
    # por GET /api/sessao quando a pagina precisa).
    function Get-ResumoSessao {
        $s = Read-SessaoAtual
        if ($null -eq $s) { return [ordered]@{ existe = $false; completa = $false; iniciada = $false; etapa = 0; geracao = [int]$W.SessaoGeracao; placa = $null; fila = $null; quando = '' } }
        $placa = $null
        if ($null -ne $s.Placa) { $placa = [ordered]@{ nome = [string]$s.Placa.Nome; ifIndex = [int]$s.Placa.IfIndex; mac = (Format-Mac $s.Placa.Mac); tipo = [string]$s.Placa.Tipo } }
        $fila = $null
        if ($null -ne $s.Fila) { $fila = [ordered]@{ inicio = [string]$s.Fila.Inicio; fim = [string]$s.Fila.Fim; local = [string]$s.Fila.Local; rack = [string]$s.Fila.Rack; andar = [string]$s.Fila.Andar; quando = [string]$s.Fila.Quando } }
        return [ordered]@{ existe = $true; completa = (Test-SessaoCompleta $s); iniciada = [bool]$W.SessaoIniciada; etapa = [int]$s.Etapa; geracao = [int]$W.SessaoGeracao; placa = $placa; fila = $fila; quando = [string]$s.Quando }
    }

    function Publicar {
        if ($W.Aviso -ne $W.AvisoPublicado) {
            $W.AvisoPublicado = $W.Aviso
            if ($W.Aviso) { $W.AvisoN = [int]$W.AvisoN + 1 }
        }
        $fila = $null
        if ($null -ne $W.Fila) {
            $fila = [ordered]@{ itens = @($W.Fila.Itens); local = $W.Fila.Local; rack = $W.Fila.Rack; andar = $W.Fila.Andar; inicio = $W.Fila.Inicio; fim = $W.Fila.Fim }
        }
        $o = [ordered]@{
            senhaDefinida = (-not [string]::IsNullOrEmpty($W.Senha)); senhaGeracao = [int]$W.SenhaGeracao
            simular = $W.Simular; falharEm = $W.FalharEm
            fase = $W.Fase; trabalho = $W.Trabalho; etapa = $W.Etapa; progresso = $W.Progresso
            fila = $fila; atual = $W.Atual
            camera = $W.Camera; falha = $W.Falha; escolha = @($W.Escolha)
            ferramenta = $W.Ferramenta; aviso = $W.Aviso; avisoOrigem = $W.AvisoOrigem; avisoN = $W.AvisoN; ultimo = $W.Ultimo
            rede = $W.Rede; ocupado = [bool]$E.Ocupado; admin = $W.Admin
            internet = [ordered]@{ agora = $W.Internet; antes = $W.InternetAntes; quando = $W.InternetQuando }
            sessao = (Get-ResumoSessao)
            vigia = [ordered]@{ ligado = [bool]$W.Vigia.Ligado; porta = $W.Vigia.Porta; canal = $W.Vigia.Canal; motivo = $W.Vigia.Motivo; broadcast = [bool]$W.Vigia.Broadcast }
            pastaDados = (Split-Path -Parent $Arquivos.Registro); pastaDadosAlternativa = [bool]$Arquivos.Alternativa
        }
        $E.Estado = ConvertTo-Json -InputObject $o -Depth 12 -Compress
    }

    # Etapa nova volta ao texto da camera; o detalhe (espera do boot, passos da
    # inicializacao) aparece no lugar dele, com contagem quando ha Total.
    Set-MotorProgresso -Sink {
        param($Etapa, $Detalhe, $Atual, $Total)
        if ($Etapa) { $W.Etapa = $Etapa; $W.Trabalho = $W.TrabalhoBase; $W.Progresso = $null }
        if ($Detalhe) {
            $W.Trabalho = $Detalhe
            if ($Total -gt 0) { $W.Progresso = [ordered]@{ atual = [int]$Atual; total = [int]$Total } } else { $W.Progresso = $null }
        }
        Publicar
    }

    # Sessao da placa gravada em disco (nula sem arquivo ou ilegivel).
    function Read-SessaoPlaca {
        try { return (Read-JsonArquivo $Arquivos.SessaoPlaca) } catch { return $null }
    }

    # Junta com a sessao ja gravada (Preparar duas vezes, IP temporario) e grava.
    function Save-SessaoPlaca {
        param($Sessao)
        if ($null -eq $Sessao) { return }
        $junta = Merge-SessaoPlaca -Antiga (Read-SessaoPlaca) -Nova $Sessao
        Save-JsonAtomico -Caminho $Arquivos.SessaoPlaca -Objeto $junta
    }

    function Remove-SessaoPlaca {
        Remove-Item -LiteralPath $Arquivos.SessaoPlaca -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($Arquivos.SessaoPlaca + '.bak') -Force -ErrorAction SilentlyContinue
    }

    # Estado da placa ESCOLHIDA (so ela conta). Sem sessao completa, a placa
    # nao esta "pronta" nem "faltando": esta sem sessao (a pagina mostra o
    # passo a passo). O rastro (placa-sessao.json) diz se foi preparada.
    function Update-Rede {
        $sessao = Read-SessaoAtual
        $rastro = Read-SessaoPlaca
        $preparada = ($null -ne $rastro)
        $placaRastro = ''; $mexida = $false; $temporarios = @(); $rotas = @()
        if ($preparada) {
            $placaRastro = [string]$rastro.Placa; $mexida = [bool]$rastro.Mexida
            $temporarios = @(@($rastro.Adicionados) | Where-Object { [string]$_.Para -eq 'temporario' } | ForEach-Object { [ordered]@{ ip = [string]$_.Ip; camera = [string]$_.Camera } })
            $rotas = @(@(Get-PropriedadeOuVazio $rastro 'Rotas') | ForEach-Object { [ordered]@{ destino = [string]$_.Destino; camera = [string]$_.Camera } })
        }
        if ($null -eq $sessao -or -not (Test-SessaoCompleta $sessao)) {
            $W.Rede = [ordered]@{ ok = $false; semSessao = $true; faltando = @('conclua o passo a passo'); ips = @(); gateway = ''
                                  placa = $null; preparada = $preparada; placaPreparada = $placaRastro; mexida = $mexida; temporarios = @($temporarios); rotas = @($rotas) }
            return
        }
        $ifIndex = [int]$sessao.Placa.IfIndex
        $r = Get-EstadoRedePc -IpFabrica $sessao.IpFabrica -Gateway $sessao.Gateway -Mascara $sessao.Mascara `
                              -IpPcFabrica $sessao.IpPcFabrica -IpPcCameras $sessao.IpPcCameras -IfIndex $ifIndex
        # A placa ainda existe e tem cabo? Uma consulta so, pelo ifIndex.
        $presente = $false; $cabo = $false
        if (-not $W.Simular) {
            $a = Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue
            if ($null -ne $a) { $presente = $true; $cabo = ([string]$a.MediaConnectionState -eq 'Connected') }
        } else { $presente = $true; $cabo = $true }
        $placa = [ordered]@{ nome = [string]$sessao.Placa.Nome; ifIndex = $ifIndex; tipo = [string]$sessao.Placa.Tipo; presente = $presente; cabo = $cabo }
        $W.Rede = [ordered]@{ ok = ($r.Ok -and $presente); semSessao = $false; faltando = @($r.Faltando); ips = @($r.Ips); gateway = $sessao.Gateway
                              placa = $placa; preparada = $preparada; placaPreparada = $placaRastro; mexida = $mexida; temporarios = @($temporarios); rotas = @($rotas) }
        if (-not $presente) { $W.Rede.faltando = @('a placa escolhida (' + $sessao.Placa.Nome + ') nao esta mais neste PC: escolha outra em Opcoes') }
    }

    # Testa a internet (ate 4 s) e, se ela caiu depois do preparo da placa, avisa.
    function Update-Internet {
        param([switch]$Avisar)
        $W.Internet = Test-Internet
        $W.InternetQuando = (Get-Date).ToString('HH:mm:ss')
        if ($Avisar -and $W.Internet -eq 'sem' -and $W.InternetAntes -eq 'ok') {
            $W.Aviso = 'O PC ficou sem internet depois de preparar a placa de rede. Se precisar dela agora, clique em Restaurar DHCP; ' +
                       'ao encerrar o painel a placa volta ao DHCP sozinha.'
            Write-Log "  ATENCAO: o PC ficou sem internet depois do preparo da placa (tinha antes)." 'Yellow'
        } elseif ($Avisar -and $W.Internet -eq 'ok') {
            Write-Log "  internet do PC continua ok depois do preparo da placa." 'Gray'
        }
    }

    # Prepara a placa escolhida com a sessao, guarda o rastro e testa a internet.
    function Invoke-PrepararPlaca {
        param($Sessao)
        $r = Set-RedeLocalCameras -Gateway $Sessao.Gateway -IpFabrica $Sessao.IpFabrica -Mascara $Sessao.Mascara -Placa $Sessao.Placa `
                                  -IpPcFabrica $Sessao.IpPcFabrica -IpDestinoLocal $Sessao.IpPcCameras -Simular:$W.Simular
        if ($W.Simular) { return [bool]$r.Ok }
        if ($null -ne $r.Sessao) {
            Save-SessaoPlaca $r.Sessao
            Update-Internet -Avisar
        }
        Update-Rede
        return [bool]$r.Ok
    }

    # Devolve a placa (pelo rastro gravado; sem ele, as faixas da sessao dada
    # ou da atual). -Sessao: a sessao com as faixas de ANTES de uma troca.
    function Invoke-RestaurarPlaca {
        param($Sessao = $null)
        if ($null -eq $Sessao) { $Sessao = Get-SessaoOuFabrica }
        $rastro = Read-SessaoPlaca
        $r = Reset-RedeLocalCameras -Gateway $Sessao.Gateway -IpFabrica $Sessao.IpFabrica -Mascara $Sessao.Mascara -Placa $Sessao.Placa -Sessao $rastro
        if ($r.Ok) { Remove-SessaoPlaca }
        Update-Rede
        Update-Internet
        return $r
    }

    function Get-ProximaPendente {
        if ($null -eq $W.Fila) { return -1 }
        $itens = $W.Fila.Itens
        for ($i = 0; $i -lt $itens.Count; $i++) { if ($itens[$i].Estado -eq 'pendente') { return $i } }
        return -1
    }

    function Set-ItemFila {
        param([int]$Indice, [string]$Estado, [string]$Motivo = '', [string]$Mac = '')
        $it = $W.Fila.Itens[$Indice]
        $it.Estado = $Estado
        $it.Motivo = $Motivo
        if ($Mac) { $it.Mac = $Mac }
    }

    # Placa escolhida nas duas faixas (fabrica e gateway). Sem isso tudo vira timeout.
    function Confirm-PlacaPronta {
        param($Sessao)
        if ($W.Simular) { return $true }
        Update-Rede
        if ($W.Rede.ok) { return $true }
        if ($null -ne $W.Rede.placa -and -not $W.Rede.placa.presente) { $W.Aviso = 'A placa de rede escolhida (' + $W.Rede.placa.nome + ') não está mais neste PC. Escolha outra em Opções, seção Placa de rede.'; return $false }
        if (-not $W.Admin) { $W.Aviso = 'A placa de rede do PC não tem as faixas de câmera. ' + $TextoSemAdmin; return $false }
        $W.Trabalho = 'Preparando a placa de rede do PC'; Publicar
        $null = Invoke-PrepararPlaca $Sessao
        if ($W.Rede.ok) { return $true }
        $W.Trabalho = ''; $W.Aviso = 'Não deu para preparar a placa de rede do PC: ela continua sem as faixas de câmera. Veja o log.'
        return $false
    }

    # ------------------------------------------------------------ vigia

    function Get-IntervaloVigia { if ($W.Simular) { return 5 } else { return 3 } }

    function Set-VigiaDesligado {
        param([string]$Motivo)
        if (-not $W.Vigia.Ligado) { return }
        $W.Vigia.Ligado = $false
        $W.Vigia.Vistos = @{}
        $W.Vigia.Motivo = $Motivo
        Write-Log ("Vigia desligado: " + $Motivo + ".") 'Cyan'
    }

    # Desliga sozinho quando a fila acaba, e quando a sessao perde a senha.
    function Update-Vigia {
        if (-not $W.Vigia.Ligado) { return }
        if ($null -eq $W.Fila -or $W.Fase -eq 'ocioso') { Set-VigiaDesligado 'sem fila' }
        elseif ($W.Fase -eq 'concluida') { Set-VigiaDesligado 'fila concluida' }
        elseif ($W.Fase -eq 'encerrada') { Set-VigiaDesligado 'fila encerrada' }
        elseif (-not $W.Simular -and [string]::IsNullOrEmpty($W.Senha)) { Set-VigiaDesligado 'senha da sessao apagada' }
    }

    # So com a fila parada esperando camera: em decisao ou escolher o vigia
    # fica em pausa (continua ligado) ate o operador resolver.
    function Test-VezDoVigia {
        return ($W.Vigia.Ligado -and $W.Fase -eq 'fila' -and (Get-Date) -ge $W.Vigia.Proximo)
    }

    <#
        Um tique do vigia. Camera de fabrica no IP de fabrica -> configura na
        proxima posicao livre, pelo MESMO caminho do "Camera conectada" sem IP
        (varias cameras -> escolher; IP de destino ocupado -> pula a posicao).
        Camera ja inicializada no IP de fabrica: so avisa, uma vez por MAC, sem
        login - retomar e sempre acao do operador (login errado trava a camera).
        Em simulacao, "aparece" uma camera de fabrica a cada tique.
    #>
    # Camera ja inicializada no IP de fabrica: aviso uma vez por MAC, sem login.
    function Add-AvisoJaInicializada {
        param([string]$Ip, [string]$Mac)
        $mac = Get-MacNormalizado $Mac
        if ($W.Vigia.Vistos.ContainsKey($mac)) { return }
        $W.Vigia.Vistos[$mac] = $true
        $quem = ''; if ($mac) { $quem = ' (MAC ' + (Format-Mac $mac) + ')' }
        $W.AvisoOrigem = 'vigia'
        $W.Aviso = 'Câmera já inicializada em ' + $Ip + $quem + ': o vigia não mexe nela. Para retomar, abra "Retomar câmera já inicializada", informe ' +
                   $Ip + ' e clique em Câmera conectada.'
        Write-Log ("Vigia: camera ja inicializada em " + $Ip + $quem + " - nao tocada. Para retomar, informe o IP em Camera conectada.") 'Yellow'
    }

    function Invoke-TiqueVigia {
        $p = Get-SessaoPronta
        if ($null -eq $p) { Set-VigiaDesligado 'sessao incompleta'; return }
        $ipf = $p.IpFabrica
        $achados = $null
        $onde = $ipf
        if (-not $W.Simular) {
            if ($W.Vigia.Broadcast) {
                # Chave ligada: broadcast DHIP + atalho no IP de fabrica, sem varredura
                # (o tique nao pode prender o worker por minutos).
                $todos = @(Find-CamerasNaRede -IpFabrica $ipf -GatewayDestino $p.Gateway -ArquivoBlacklist $Arquivos.Blacklist -SemVarredura -Silencioso -IfIndex ([int]$p.Placa.IfIndex))
                $achados = @($todos | Where-Object { $_.Virgem })
                if ($achados.Count -eq 0) {
                    $noIpf = @($todos | Where-Object { $_.Ip -eq $ipf -and $_.Confirmado -and -not $_.Virgem })
                    if ($noIpf.Count -gt 0) { Add-AvisoJaInicializada -Ip $ipf -Mac $noIpf[0].Mac }
                    return
                }
                $onde = ($achados | ForEach-Object { $_.Ip }) -join ', '
            } else {
                if (@(Invoke-PingSweep -Ips @($ipf) -TimeoutMs 1000).Count -eq 0) { return }
                # 5 s: o tique nao pode prender o worker por 25 s a cada camera muda.
                $st = Get-CamInitStatus -Ip $ipf -Timeout 5
                if (-not $st.Ok) { return }
                if ($st.Init -ne 1) {
                    $m = Get-VizinhosMac -Ips @($ipf)
                    $mac = ''; if ($m.ContainsKey($ipf)) { $mac = $m[$ipf] }
                    Add-AvisoJaInicializada -Ip $ipf -Mac $mac
                    return
                }
            }
        }

        $E.Ocupado = $true
        $W.Aviso = ''; $W.AvisoOrigem = 'vigia'
        $W.CameraDoVigia = $true
        $pos = Get-ProximaPendente
        $txtPos = ''; if ($pos -ge 0) { $txtPos = ' -> posicao ' + $W.Fila.Itens[$pos].Posicao }
        $txtPorta = ''
        if ($W.Vigia.Porta) { $txtPorta += ', porta ' + $W.Vigia.Porta }
        if ($W.Vigia.Canal) { $txtPorta += ', canal ' + $W.Vigia.Canal }
        Write-Log ("Vigia: camera de fabrica em " + $onde + $txtPos + $txtPorta) 'Cyan'
        Publicar
        Invoke-Conectada ([pscustomobject]@{ porta = $W.Vigia.Porta; canal = $W.Vigia.Canal; ip = '' }) -Achados $achados
        # Nao chegou a configurar (aviso, fila concluida): a camera nao e "do vigia".
        if ($W.Fase -notin @('decisao', 'escolher')) { $W.CameraDoVigia = $false }
        if ($W.Aviso) {
            $W.Vigia.SemSucesso = [int]$W.Vigia.SemSucesso + 1
            if ($W.Vigia.SemSucesso -ge 5) { Set-VigiaDesligado '5 tentativas sem configurar' }
        } else { $W.Vigia.SemSucesso = 0 }
    }

    function Invoke-Configurar {
        $p = Get-SessaoOuFabrica
        $W.Fase = 'configurando'; $W.Falha = $null; $W.Aviso = ''; $W.Etapa = ''
        $W.TrabalhoBase = 'Configurando a câmera para ' + $W.Camera.Destino
        $W.Trabalho = $W.TrabalhoBase; $W.Progresso = $null
        Publicar
        $falharEm = ''
        if ($W.Simular) { $falharEm = $W.FalharEm }
        $r = Invoke-ConfiguracaoCamera -Contexto $W.Camera -Padroes $p -Senha $W.Senha `
                                       -CaminhoRegistro (Get-CaminhoRegistroAtual) -Simular:$W.Simular -FalharEm $falharEm
        if ($r.Mac) { $W.Camera.Mac = $r.Mac }
        $W.Etapa = ''
        $W.Trabalho = ''; $W.TrabalhoBase = ''; $W.Progresso = $null
        if ($r.Ok) {
            Set-ItemFila -Indice $W.Atual -Estado 'feita' -Mac $r.Mac
            $W.Ultimo = 'Câmera instalada em ' + $W.Camera.Destino + ' (MAC ' + (Format-Mac $r.Mac) + ').'
            if ($W.CameraDoVigia) {
                # O cabeamento segue a ordem da fila: a proxima camera vem na porta/canal seguinte.
                $W.Vigia.Porta = Step-Rotulo $W.Vigia.Porta
                $W.Vigia.Canal = Step-Rotulo $W.Vigia.Canal
                $W.CameraDoVigia = $false
            }
            $W.Camera = $null; $W.Atual = -1
            if ((Get-ProximaPendente) -lt 0) { $W.Fase = 'concluida' } else { $W.Fase = 'fila' }
        } else {
            # Falha simulada e de uma vez so: o "Tentar de novo" tem que passar.
            if ($W.Simular -and $W.FalharEm) { $W.FalharEm = '' }
            Set-ItemFila -Indice $W.Atual -Estado 'falhou' -Motivo ($r.Falhou + ': ' + $r.Erro) -Mac $r.Mac
            $W.Falha = [ordered]@{ etapa = $r.Falhou; erro = $r.Erro; recusa = $r.Recusa
                                   loginRecusado = [bool]$r.LoginRecusado; bloqueada = [bool]$r.Bloqueada; geracao = [int]$W.SenhaGeracao }
            $W.Fase = 'decisao'
        }
    }

    <#
        Camera achada fora das faixas do PC: da um IP temporario a placa e
        confirma por HTTP que ela e de fabrica (o Init do broadcast e pista,
        nunca base para agir). -SemInit: camera informada pelo operador
        (retomada), que ja esta inicializada por definicao.
    #>
    function Confirm-AlcanceCamera {
        param($Achado, $Sessao, [switch]$SemInit)
        if ($W.Simular) { return $true }
        if (-not [bool]$Achado.Alcancavel) {
            if (-not $W.Admin) { $W.Aviso = 'A câmera em ' + $Achado.Ip + ' está fora das faixas da placa escolhida, e sem Administrador a placa não recebe um IP temporário. ' + $TextoSemAdmin; return $false }
            $W.Trabalho = 'Dando à placa um IP temporário na rede de ' + $Achado.Ip; Publicar
            $r = Add-IpTemporarioPlaca -IpCamera $Achado.Ip -Mascara ([string]$Achado.Mascara) -GatewayCamera ([string]$Achado.Gateway) -Placa $Sessao.Placa
            if ($null -ne $r.Sessao) { Save-SessaoPlaca $r.Sessao }
            Update-Rede
            if (-not $r.Ok) { $W.Trabalho = ''; $W.Aviso = 'Não deu para dar à placa um IP na rede de ' + $Achado.Ip + '. Veja o log.'; return $false }
        }
        if ($SemInit) { return $true }
        if ([bool]$Achado.Confirmado -and [int]$Achado.Init -eq 1) { return $true }
        $st = Get-CamInitStatus -Ip $Achado.Ip -Timeout 10
        if (-not $st.Ok) { $W.Trabalho = ''; $W.Aviso = 'A câmera em ' + $Achado.Ip + ' respondeu ao broadcast, mas não ao DevInit.getStatus por HTTP. Confira o cabo e tente de novo.'; return $false }
        if ($st.Init -ne 1) { $W.Trabalho = ''; $W.Aviso = 'A câmera em ' + $Achado.Ip + ' não está de fábrica (Init=' + $st.Init + '): o painel não mexe nela. Para retomar, abra "Retomar câmera já inicializada" e informe o IP.'; return $false }
        return $true
    }

    # Comeca a configuracao de um achado na posicao da fila. Usado pelo
    # "Camera conectada", pelo vigia e pela escolha entre varias cameras.
    function Start-ConfiguracaoDoAchado {
        param($Achado, [int]$Indice, $Cmd)
        $p = Get-SessaoPronta
        if ($null -eq $p) { return }
        $informada = ([string]$Achado.Como -eq 'informado')
        if (-not (Confirm-AlcanceCamera $Achado $p -SemInit:$informada)) {
            if ($W.Fase -eq 'escolher') { $W.Escolha = @(); $W.EscolhaAchados = @(); $W.Camera = $null; $W.Atual = -1; $W.Fase = 'fila' }
            return
        }
        $porta = 80
        if ($null -ne $Achado.PSObject.Properties['HttpPort'] -and [int]$Achado.HttpPort -gt 0) { $porta = [int]$Achado.HttpPort }
        $W.Atual = $Indice
        $W.Camera = [pscustomobject]@{
            IpOrigem = $Achado.Ip; Destino = $W.Fila.Itens[$Indice].Ip; Mac = [string]$Achado.Mac
            Local = $W.Fila.Local; Rack = $W.Fila.Rack; Andar = $W.Fila.Andar
            Porta = [string]$Cmd.porta; Canal = [string]$Cmd.canal; HttpPort = $porta
        }
        Invoke-Configurar
    }

    # -Achados: cameras de fabrica ja achadas (vigia com broadcast); sem ele,
    # com o campo IP vazio, procura (broadcast + IP de fabrica + varredura).
    function Invoke-Conectada {
        param($Cmd, $Achados = $null)
        if ($null -eq $W.Fila -or $W.Fase -eq 'ocioso') { $W.Aviso = 'Monte a fila antes: informe a faixa de IPs e clique em Montar fila.'; return }
        if ($W.Fase -eq 'encerrada') { $W.Aviso = 'A fila foi encerrada: monte uma fila nova para continuar.'; return }
        if ($W.Fase -in @('decisao', 'configurando', 'escolher')) { $W.Aviso = 'Termine a câmera atual antes: escolha a câmera da lista ou decida o que fazer com a falha.'; return }
        if (-not $W.Simular -and [string]::IsNullOrEmpty($W.Senha)) { $W.Aviso = $TextoSemSenha; return }
        # IP invalido e recusado antes de mexer na placa ou pular posicoes.
        $ipDado = ([string]$Cmd.ip).Trim()
        if ($ipDado -and -not (Test-Ipv4Estrito $ipDado)) { $W.Aviso = Get-TextoIpInvalido $ipDado; return }
        $p = Get-SessaoPronta
        if ($null -eq $p) { return }
        $ifIndex = [int]$p.Placa.IfIndex
        if (-not (Confirm-PlacaPronta $p)) { return }

        # Proxima posicao livre. IP que ja responde e de outro equipamento -
        # a menos que seja a propria camera informada pelo operador.
        while ($true) {
            $i = Get-ProximaPendente
            if ($i -lt 0) { $W.Fase = 'concluida'; $W.Trabalho = ''; $W.Aviso = 'Fila concluída: nenhuma posição pendente. Monte uma fila nova para continuar.'; return }
            $ip = $W.Fila.Itens[$i].Ip
            if (-not $W.Simular -and $ip -ne $ipDado -and (Test-IpEmUso -Ip $ip)) {
                Write-Log ("  posicao " + $W.Fila.Itens[$i].Posicao + ": " + $ip + " ja responde ao ping - pulada") 'Yellow'
                Set-ItemFila -Indice $i -Estado 'pulada' -Motivo 'IP ja responde na rede'
                Publicar
                continue
            }
            break
        }

        $achado = $null
        if ($W.Simular) {
            $achado = [pscustomobject]@{ Ip = $p.IpFabrica; Mac = ''; Alcancavel = $true; Confirmado = $true; Init = 1; HttpPort = 80; Como = 'simulado' }
        } elseif ($ipDado) {
            $null = Invoke-PingSweep -Ips @($ipDado)
            $m = Get-VizinhosMac -Ips @($ipDado)
            $mac = ''; if ($m.ContainsKey($ipDado)) { $mac = $m[$ipDado] }
            $achado = [pscustomobject]@{ Ip = $ipDado; Mac = $mac; Alcancavel = (Test-IpAlcancavel -Ip $ipDado -Locais @(Get-FaixasDaPlaca -IfIndex $ifIndex))
                                         Confirmado = $false; Init = -1; HttpPort = (Get-CamPortaHttp $ipDado); Mascara = ''; Gateway = ''; Como = 'informado' }
        } else {
            $virgens = @()
            if ($null -ne $Achados) { $virgens = @($Achados | Where-Object { $_.Virgem }) }
            else {
                $W.Trabalho = 'Procurando camera de fabrica na rede'; Publicar
                $achados = @(Find-CamerasNaRede -IpFabrica $p.IpFabrica -GatewayDestino $p.Gateway -ArquivoBlacklist $Arquivos.Blacklist -IfIndex $ifIndex)
                $virgens = @($achados | Where-Object { $_.Virgem })
                $W.Trabalho = ''
                if ($virgens.Count -eq 0) {
                    $jaInit = @($achados | Where-Object { $_.EhCamera -and -not $_.Virgem } | ForEach-Object { $_.Ip })
                    $W.Aviso = 'Nenhuma câmera de fábrica encontrada. Confira o cabo, o PoE e a porta P+D do injetor, e tente de novo.'
                    if ($jaInit.Count -gt 0) { $W.Aviso += ' Já inicializadas na rede (não tocadas): ' + ($jaInit -join ', ') + '. Para retomar uma delas, abra "Retomar câmera já inicializada" e informe o IP dela.' }
                    return
                }
            }
            if ($virgens.Count -eq 0) { $W.Aviso = 'Nenhuma câmera de fábrica encontrada.'; return }
            if ($virgens.Count -gt 1) {
                $W.Escolha = @($virgens | ForEach-Object { [ordered]@{ ip = $_.Ip; mac = (Format-Mac $_.Mac); ouiConhecido = $_.OuiConhecido; modelo = [string]$_.Modelo
                                                                        mascara = [string]$_.Mascara; alcancavel = [bool]$_.Alcancavel; confirmado = [bool]$_.Confirmado; httpPort = [int]$_.HttpPort } })
                $W.EscolhaAchados = @($virgens)
                $W.Fase = 'escolher'
                $W.Camera = [pscustomobject]@{ Porta = [string]$Cmd.porta; Canal = [string]$Cmd.canal }
                $W.Atual = $i
                return
            }
            $achado = $virgens[0]
        }

        Start-ConfiguracaoDoAchado -Achado $achado -Indice $i -Cmd $Cmd
    }

    # Monta a fila a partir da faixa e guarda a faixa na sessao (volta como
    # sugestao na proxima abertura). Usado pelo comando 'fila', por
    # 'sessao-concluir' (Montar fila) e pela remontagem depois de trocar a
    # rede em Opcoes. -Silencioso: sem o aviso "nenhuma posicao livre".
    function Invoke-MontarFila {
        param([string]$Inicio, [string]$Fim, [string]$Local = '', [string]$Rack = '', [string]$Andar = '', [switch]$Guardar = $true)
        $p = Get-SessaoPronta
        if ($null -eq $p) { return $false }
        $Inicio = ([string]$Inicio).Trim(); $Fim = ([string]$Fim).Trim()
        try {
            $itens = @(New-FilaDeFaixa -Inicio $Inicio -Fim $Fim -Registro (Read-Registro (Get-CaminhoRegistroAtual)) -Mascara $p.Mascara -Gateway $p.Gateway)
        } catch { $W.Aviso = $_.Exception.Message; return $false }
        $pend = @($itens | Where-Object { $_.Estado -eq 'pendente' }).Count
        if ($pend -eq 0) {
            # Faixa sem lugar para camera nenhuma: recusa e a fila anterior continua.
            $porMotivo = [ordered]@{}
            foreach ($it in $itens) {
                $m = [string]$it.Motivo
                if ($m -like 'ja no registro*') { $m = 'já no registro' }
                elseif ($m -eq 'e o gateway') { $m = 'é o gateway' }
                elseif ($m -like 'endereco de rede*') { $m = 'endereço de rede ou broadcast' }
                if (-not $porMotivo.Contains($m)) { $porMotivo[$m] = 0 }
                $porMotivo[$m] = $porMotivo[$m] + 1
            }
            $partes = @($porMotivo.Keys | ForEach-Object { [string]$porMotivo[$_] + ' ' + $_ })
            $W.Aviso = 'Nenhuma posição livre nessa faixa (' + ($partes -join ', ') + '). Nada mudou: confira a faixa e a rede das câmeras em Opções.'
            return $false
        }
        Set-VigiaDesligado 'fila nova'
        $W.Fila = @{ Itens = $itens; Local = [string]$Local; Rack = [string]$Rack; Andar = [string]$Andar; Inicio = $Inicio; Fim = $Fim }
        $W.Atual = -1; $W.Camera = $null; $W.Falha = $null; $W.Aviso = ''; $W.Escolha = @(); $W.Ultimo = ''
        $W.Fase = 'fila'
        Write-Log ("Fila montada: " + $Inicio + " a " + $Fim + " (" + $pend + " posicao(oes) livre(s) de " + $itens.Count + ")") 'Cyan'
        if ($Guardar) {
            # A proxima abertura do painel volta com esta faixa na sessao.
            try {
                $p.Fila = [pscustomobject]@{ Inicio = $Inicio; Fim = $Fim; Local = [string]$Local; Rack = [string]$Rack; Andar = [string]$Andar; Quando = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
                $null = Save-SessaoAtual $p
            } catch { Write-Log ("  nao deu para guardar a fila na sessao: " + $_.Exception.Message) 'DarkGray' }
        }
        return $true
    }

    function Invoke-Comando {
        param($Cmd)
        switch ([string]$Cmd.tipo) {
            'senha' {
                $W.Senha = [string]$Cmd.senha
                $W.SenhaGeracao = [int]$W.SenhaGeracao + 1
                if ($W.Senha) { Write-Log "Senha da sessao definida (fica so na memoria)." 'Gray' }
                else { Write-Log "Senha da sessao apagada." 'Gray' }
            }
            # Uma secao do passo a passo / Opcoes, ja mesclada e validada pelo
            # listener. aplicarRede: rede ou placa mudaram com a placa preparada
            # (ou fila montada): devolve a placa com a sessao ANTIGA, grava a
            # nova, prepara de novo e remonta a fila se ela ainda cabe.
            'sessao-salvar' {
                $antes = Read-SessaoAtual
                $nova = ConvertTo-Sessao $Cmd.sessao
                $campos = @(Test-SessaoParaGravar -Sessao $nova -Enviados @($Cmd.enviados))
                if ($campos.Count -gt 0) { $W.Aviso = 'Nada foi salvo: ' + (($campos | ForEach-Object { $_.msg }) -join ' '); return }
                $aplicar = [bool]$Cmd.aplicarRede
                if ($aplicar) {
                    Set-VigiaDesligado 'rede da sessao alterada'
                    if (-not $W.Simular -and $W.Admin -and (Test-Path -LiteralPath $Arquivos.SessaoPlaca)) {
                        $W.Trabalho = 'Devolvendo a placa ao estado de antes'; Publicar
                        $null = Invoke-RestaurarPlaca -Sessao $antes
                    }
                }
                $nova = Save-SessaoAtual $nova
                Write-Log ("Sessao salva (etapa " + $nova.Etapa + ")" + $(if (@($Cmd.campos).Count -gt 0) { ': ' + (@($Cmd.campos) -join ', ') } else { '' }) +
                           $(if ($null -ne $nova.Placa) { '; placa ' + $nova.Placa.Nome + ' (ifIndex ' + $nova.Placa.IfIndex + ')' } else { '' }) +
                           '; gw ' + $nova.Gateway + ' /' + (ConvertTo-PrefixoDeMascara $nova.Mascara) + ', IP de fabrica ' + $nova.IpFabrica + '.' +
                           $(if (@($Cmd.outros).Count -gt 0) { ' Mudou: ' + (@($Cmd.outros) -join '; ') + '.' } else { '' })) 'Cyan'
                if ($aplicar) {
                    if ((Test-SessaoCompleta $nova) -and -not $W.Simular -and $W.Admin) {
                        $W.Trabalho = 'Preparando a placa de rede'; Publicar
                        $null = Invoke-PrepararPlaca $nova
                        if (-not $W.Rede.ok) { $W.Aviso = 'A sessão foi salva, mas não deu para preparar a placa de rede com ela. Veja o log.' }
                    }
                    if ($null -ne $W.Fila -and @($W.Fila.Itens).Count -gt 0) {
                        if ((Test-SessaoCompleta $nova) -and (Test-FilaCabeNaRede -Inicio $W.Fila.Inicio -Fim $W.Fila.Fim -Mascara $nova.Mascara -Gateway $nova.Gateway)) {
                            $f = $W.Fila
                            if (Invoke-MontarFila -Inicio $f.Inicio -Fim $f.Fim -Local $f.Local -Rack $f.Rack -Andar $f.Andar -Guardar:$false) {
                                Write-Log "  a fila foi remontada com a rede nova (posicoes com camera instalada ficam de fora)." 'Gray'
                            }
                        } else {
                            $faixa = [string]$W.Fila.Inicio + ' a ' + [string]$W.Fila.Fim
                            $W.Fila = $null; $W.Atual = -1; $W.Camera = $null; $W.Falha = $null; $W.Escolha = @(); $W.Fase = 'ocioso'
                            $W.Aviso = 'A fila foi descartada: a faixa ' + $faixa + ' não cabe na rede nova. Monte outra no Painel.'
                            Write-Log ("  a fila " + $faixa + " nao cabe na rede nova e foi descartada.") 'Yellow'
                        }
                    }
                }
                Update-Rede
            }
            # Fim do passo a passo: etapa 7, placa preparada e, se pedido, a fila da sessao montada.
            'sessao-concluir' {
                $s = Read-SessaoAtual
                if ($null -eq $s) { $W.Aviso = $TextoSemSessao; return }
                $s.Etapa = 7
                $s = Save-SessaoAtual $s
                if (-not (Test-SessaoCompleta $s)) { $W.Aviso = 'Falta alguma coisa na sessão: ' + ((@(Test-Sessao $s) + @($(if ($null -eq $s.Placa) { 'escolha a placa de rede.' } else { @() }))) -join ' '); return }
                $W.SessaoIniciada = $true
                Write-Log ("Passo a passo concluido: placa " + $s.Placa.Nome + " (ifIndex " + $s.Placa.IfIndex + "), rede das cameras gw " + $s.Gateway + " /" + (ConvertTo-PrefixoDeMascara $s.Mascara) +
                           ", IP de fabrica " + $s.IpFabrica + ", e-mail " + $s.EmailRecuperacao + ".") 'Cyan'
                if ($W.Simular) { Write-Log "  [simular] a placa nao e tocada." 'DarkGray' }
                elseif (-not $W.Admin) { $W.Aviso = $TextoSemAdmin }
                else {
                    $W.Trabalho = 'Preparando a placa de rede'; Publicar
                    $null = Invoke-PrepararPlaca $s
                    if (-not $W.Rede.ok) { $W.Aviso = 'Não deu para preparar a placa de rede do PC. Veja o log; o Painel tem o botão Preparar placa.' }
                }
                if ([bool]$Cmd.montarFila -and $null -ne $s.Fila) {
                    $f = $s.Fila
                    $null = Invoke-MontarFila -Inicio $f.Inicio -Fim $f.Fim -Local $f.Local -Rack $f.Rack -Andar $f.Andar
                }
                Update-Rede
            }
            # Volta ao passo a passo (etapa 1): a sessao fica incompleta ate concluir de novo.
            'sessao-refazer' {
                if ($W.Fase -in @('configurando', 'decisao', 'escolher')) { $W.Aviso = 'Termine a câmera atual antes de refazer o passo a passo.'; return }
                $s = Get-SessaoOuFabrica
                $s.Etapa = 1
                $null = Save-SessaoAtual $s
                $W.SessaoIniciada = $false
                Set-VigiaDesligado 'passo a passo reaberto'
                Write-Log "Passo a passo reaberto pelo operador (a sessao continua guardada como sugestao)." 'Cyan'
                Update-Rede
            }
            'simular' {
                $novo = [bool]$Cmd.ligado
                if ($novo -ne $W.Simular) {
                    # Registro diferente: fila, camera em curso, escolha, ultimo
                    # resultado e ferramenta nao valem mais.
                    $W.Fila = $null; $W.Camera = $null; $W.Atual = -1; $W.Falha = $null; $W.Fase = 'ocioso'
                    $W.Escolha = @(); $W.Ultimo = ''; $W.Ferramenta = $null
                }
                $W.Simular = $novo
                $W.FalharEm = [string]$Cmd.falharEm
                $E.Simular = $novo
                Write-Log ("Simulacao " + $(if ($novo) { 'LIGADA - nada e enviado para camera nem para a placa' } else { 'desligada' }) +
                           $(if ($W.FalharEm) { '; falha forcada em ' + $W.FalharEm } else { '' })) 'Yellow'
            }
            'fila' {
                if ($W.Fase -in @('configurando', 'decisao', 'escolher')) { $W.Aviso = 'Termine a câmera atual antes de montar outra fila.'; return }
                $null = Invoke-MontarFila -Inicio ([string]$Cmd.inicio) -Fim ([string]$Cmd.fim) -Local ([string]$Cmd.local) -Rack ([string]$Cmd.rack) -Andar ([string]$Cmd.andar)
            }
            'conectada' {
                if ($W.Fase -notin @('decisao', 'configurando', 'escolher')) { $W.CameraDoVigia = $false }
                Invoke-Conectada $Cmd
            }
            'vigia' {
                if (-not [bool]$Cmd.ligado) { Set-VigiaDesligado 'pelo operador'; return }
                # Ja ligado (pedido repetido): so porta, canal e broadcast; sem
                # novo log nem perder o que o vigia ja viu.
                if ($W.Vigia.Ligado) {
                    $W.Vigia.Porta = ([string]$Cmd.porta).Trim()
                    $W.Vigia.Canal = ([string]$Cmd.canal).Trim()
                    $W.Vigia.Broadcast = [bool]$Cmd.broadcast
                    return
                }
                if ($null -eq $W.Fila -or $W.Fase -in @('ocioso', 'concluida', 'encerrada')) { $W.Aviso = 'Monte uma fila com posição livre antes de ligar o vigia.'; return }
                if (-not $W.Simular -and [string]::IsNullOrEmpty($W.Senha)) { $W.Aviso = $TextoSemSenha; return }
                $p = Get-SessaoPronta
                if ($null -eq $p) { return }
                if (-not (Confirm-PlacaPronta $p)) { return }
                $W.Vigia.Porta = ([string]$Cmd.porta).Trim()
                $W.Vigia.Canal = ([string]$Cmd.canal).Trim()
                $W.Vigia.Broadcast = [bool]$Cmd.broadcast
                $W.Vigia.Vistos = @{}
                $W.Vigia.Motivo = ''
                $W.Vigia.SemSucesso = 0
                $W.Vigia.Proximo = (Get-Date).AddSeconds((Get-IntervaloVigia))
                $W.Vigia.Ligado = $true
                Write-Log ("Vigia ligado: observando " + $(if ($W.Vigia.Broadcast) { 'qualquer faixa (broadcast DHIP) e ' } else { '' }) + $p.IpFabrica +
                           " a cada " + (Get-IntervaloVigia) + " s. Proxima camera: porta '" +
                           $W.Vigia.Porta + "', canal '" + $W.Vigia.Canal + "' (+1 a cada camera instalada).") 'Cyan'
            }
            'escolher' {
                if ($W.Fase -ne 'escolher') { return }
                $sel = @($W.EscolhaAchados | Where-Object { [string]$_.Ip -eq [string]$Cmd.ip }) | Select-Object -First 1
                if ($null -eq $sel) { $W.Aviso = 'Essa câmera não está na lista. Escolha outra ou cancele.'; return }
                $cmdPC = [pscustomobject]@{ porta = [string]$W.Camera.Porta; canal = [string]$W.Camera.Canal }
                $W.Escolha = @(); $W.EscolhaAchados = @()
                Start-ConfiguracaoDoAchado -Achado $sel -Indice $W.Atual -Cmd $cmdPC
            }
            'cancelar-escolha' {
                if ($W.Fase -eq 'escolher') {
                    # Senao o proximo tique acharia as mesmas cameras e voltaria a perguntar.
                    if ($W.CameraDoVigia) { Set-VigiaDesligado 'escolha cancelada' }
                    $W.CameraDoVigia = $false
                    $W.Escolha = @(); $W.EscolhaAchados = @(); $W.Camera = $null; $W.Atual = -1; $W.Fase = 'fila'
                }
            }
            'decisao' {
                if ($W.Fase -ne 'decisao') { return }
                switch ([string]$Cmd.acao) {
                    'tentar'   {
                        # Senha recusada: repetir a mesma senha so gasta tentativa do lockout.
                        if ($W.Falha.loginRecusado -and [int]$W.Falha.geracao -eq [int]$W.SenhaGeracao) {
                            $W.Aviso = $(if ($W.Falha.bloqueada) { $TextoBloqueada } else { $TextoSenhaRecusada })
                            return
                        }
                        Write-Log "Operador: tentar de novo." 'Cyan'; Invoke-Configurar
                    }
                    'pular'    {
                        Write-Log "Operador: pular esta posicao." 'Cyan'
                        Set-ItemFila -Indice $W.Atual -Estado 'pulada' -Motivo ('pulada pelo operador - ' + $W.Falha.etapa + ': ' + $W.Falha.erro)
                        $W.Camera = $null; $W.Atual = -1; $W.Falha = $null; $W.CameraDoVigia = $false
                        $W.Fase = $(if ((Get-ProximaPendente) -lt 0) { 'concluida' } else { 'fila' })
                    }
                    'encerrar' {
                        Write-Log "Operador: encerrar a fila." 'Cyan'
                        $W.Camera = $null; $W.Atual = -1; $W.Falha = $null; $W.CameraDoVigia = $false; $W.Fase = 'encerrada'
                    }
                }
            }
            'sondar' {
                if ($W.Simular) { $W.Aviso = $TextoSoReal; return }
                $ip = ([string]$Cmd.ip).Trim()
                if (-not (Test-Ipv4Estrito $ip)) { $W.Aviso = Get-TextoIpInvalido $ip; return }
                # emCurso ja no inicio: o resultado anterior some da tela.
                $W.Ferramenta = [ordered]@{ tipo = 'sondar'; ip = $ip; emCurso = $true }
                $W.Trabalho = 'Sondando ' + $ip; Publicar
                $res = [ordered]@{ tipo = 'sondar'; ip = $ip; quando = (Get-Date).ToString('HH:mm:ss'); ping = (Test-IpEmUso -Ip $ip) }
                $st = Get-CamInitStatus -Ip $ip
                $res.init = $st.Init
                $res.fabrica = ($st.Ok -and $st.Init -eq 1)
                if ($st.Ok -and $st.Init -ne 1 -and $W.Senha) {
                    $s = New-CamSessao -Ip $ip -Senha $W.Senha
                    $res.login = $s.Ok; $res.erro = $s.Erro
                    if ($s.SenhaErrada -or $s.Bloqueada) { $W.Aviso = Get-TextoRecusa $ip $s }
                    if ($s.Ok) {
                        try {
                            $info = Get-CamInfoRpc -Sessao $s
                            $res.modelo = $info.Modelo; $res.serial = $info.Serial; $res.firmware = $info.Firmware
                            $res.mac = Format-Mac $info.Mac; $res.rede = ($info.IpAtual + ' / ' + $info.Mascara + ' gw ' + $info.Gateway + ' dhcp ' + $info.Dhcp)
                            $enc = Get-CamEncode -Sessao $s
                            if ($enc.Ok) { $res.encoder = Get-ResumoEncode $enc.Tabela }
                        } finally { Close-CamSessao $s }
                    }
                } elseif (-not $st.Ok) { $res.erro = 'nao respondeu ao DevInit.getStatus' }
                $W.Ferramenta = $res
            }
            'verificar' {
                $reg = Read-Registro (Get-CaminhoRegistroAtual)
                $itens = @()
                $instaladas = @($reg.Cameras | Where-Object { $_.Status -eq 'Instalada' })
                $W.Ferramenta = [ordered]@{ tipo = 'verificar'; emCurso = $true }
                $W.Trabalho = 'Lendo o registro'; Publicar
                $k = 0
                $recusadaEm = ''
                foreach ($c in $instaladas) {
                    $k++
                    $it = [ordered]@{ ip = $c.Ip; mac = (Format-Mac $c.Mac); ping = $false; login = $false; ok = $false; detalhe = '' }
                    # Uma senha recusada vale para todas (a senha da sessao e uma so):
                    # seguir tentando so gastaria o lockout de cada camera.
                    if ($recusadaEm) { $it.detalhe = 'não tentado: senha recusada em ' + $recusadaEm; $itens += $it; continue }
                    $W.Trabalho = 'Verificando ' + $c.Ip + ' (' + $k + ' de ' + $instaladas.Count + ')'
                    $W.Progresso = [ordered]@{ atual = $k; total = $instaladas.Count }
                    Publicar
                    if ($W.Simular) { $it.ping = $true; $it.login = $true; $it.ok = $true; $it.detalhe = 'simulado'; $itens += $it; continue }
                    $it.ping = Test-IpEmUso -Ip $c.Ip
                    if ($it.ping -and $W.Senha) {
                        $s = New-CamSessao -Ip $c.Ip -Senha $W.Senha
                        $it.login = $s.Ok
                        if ($s.SenhaErrada -or $s.Bloqueada) {
                            $recusadaEm = $c.Ip
                            $W.Aviso = 'Senha recusada em ' + $c.Ip + ': verificação interrompida para não bloquear as outras câmeras. ' +
                                       $(if ($s.Bloqueada) { $TextoBloqueada } else { 'Confira a senha da sessão em Opções.' })
                        }
                        if ($s.Ok) {
                            try {
                                $info = Get-CamInfoRpc -Sessao $s
                                $it.ok = ($info.Ok -and (Get-MacNormalizado $info.Mac) -eq (Get-MacNormalizado $c.Mac) -and $info.IpAtual -eq $c.Ip)
                                $it.detalhe = $info.Modelo + ' ' + $info.IpAtual + ' / ' + $info.Mascara + ' gw ' + $info.Gateway
                            } finally { Close-CamSessao $s }
                        } else { $it.detalhe = $s.Erro }
                    } elseif (-not $it.ping) { $it.detalhe = 'sem ping' } else { $it.detalhe = 'sem senha na sessao' }
                    $itens += $it
                }
                $W.Ferramenta = [ordered]@{ tipo = 'verificar'; quando = (Get-Date).ToString('HH:mm:ss'); itens = $itens }
                Write-Log ("Verificacao: " + @($itens | Where-Object { $_.ok }).Count + " de " + $itens.Count + " cameras instaladas OK") 'Cyan'
            }
            'descobrir' {
                if ($W.Simular) { $W.Aviso = $TextoSoReal; return }
                $p = Get-SessaoPronta
                if ($null -eq $p) { return }
                $W.Ferramenta = [ordered]@{ tipo = 'descobrir'; emCurso = $true }
                $W.Trabalho = 'Procurando câmeras na rede'; Publicar
                # -IncluirOutros: a ferramenta lista tudo o que respondeu (NVR, BSC), nao so IPC.
                $achados = @(Find-CamerasNaRede -IpFabrica $p.IpFabrica -GatewayDestino $p.Gateway -ArquivoBlacklist $Arquivos.Blacklist -IncluirOutros -IfIndex ([int]$p.Placa.IfIndex))
                $W.Ferramenta = [ordered]@{ tipo = 'descobrir'; quando = (Get-Date).ToString('HH:mm:ss')
                    broadcast = @($achados | Where-Object { $_.Como -eq 'broadcast DHIP' }).Count
                    varredura = @($achados | Where-Object { $_.Como -ne 'broadcast DHIP' }).Count
                    itens = @($achados | ForEach-Object { [ordered]@{ ip = $_.Ip; httpPort = [int]$_.HttpPort; mascara = [string]$_.Mascara; mac = (Format-Mac $_.Mac)
                                                                      modelo = [string]$_.Modelo; serial = [string]$_.Serial; firmware = [string]$_.Firmware; classe = [string]$_.Classe
                                                                      init = $_.Init; fabrica = [bool]$_.Virgem; confirmado = [bool]$_.Confirmado; alcancavel = [bool]$_.Alcancavel
                                                                      ouiConhecido = [bool]$_.OuiConhecido; como = [string]$_.Como } }) }
            }
            'rede-preparar' {
                if (-not $W.Simular -and -not $W.Admin) { $W.Aviso = $TextoSemAdmin; return }
                $p = Get-SessaoPronta
                if ($null -eq $p) { return }
                $W.Trabalho = 'Preparando a placa de rede'; Publicar
                $null = Invoke-PrepararPlaca $p
                if (-not $W.Simular -and -not $W.Rede.ok) { $W.Aviso = 'Não deu para preparar a placa de rede do PC. Veja o log.' }
            }
            'rede-restaurar' {
                if ($W.Simular) { Write-Log "  [simular] devolveria a placa ao DHCP" 'DarkGray' }
                elseif (-not $W.Admin) { $W.Aviso = $TextoSemAdmin }
                else {
                    $W.Trabalho = 'Devolvendo a placa ao DHCP'; Publicar
                    $r = Invoke-RestaurarPlaca
                    if (-not $r.Ok) { $W.Aviso = 'Não deu para devolver a placa de rede. Veja o log.' }
                }
            }
            'rede-atualizar' { }
            'internet-testar' { Update-Internet }
        }
    }

    Update-Rede
    Publicar
    Write-Log ("Painel pronto. Dados em " + (Split-Path -Parent $Arquivos.Registro) +
               $(if ($Arquivos.Alternativa) { ' (pasta alternativa: sem permissao de escrita em ProgramData)' } else { '' })) 'Green'
    if ($W.Simular) { Write-Log "SIMULACAO ligada por parametro (-Simular): nada vai para camera nem para a placa; registro separado." 'Yellow' }
    $resumo = Get-ResumoSessao
    if (-not $resumo.existe) { Write-Log "Sem sessao gravada: a pagina abre no passo a passo." 'Gray' }
    elseif (-not $resumo.completa) { Write-Log ("Sessao incompleta (etapa " + $resumo.etapa + "): a pagina abre no passo a passo.") 'Gray' }
    else { Write-Log ("Sessao de " + $resumo.quando + ": placa " + $resumo.placa.nome + " (ifIndex " + $resumo.placa.ifIndex + "). A pagina oferece usar ou revisar.") 'Gray' }
    # Baseline da internet ANTES de mexer na placa: so assim "ficou sem
    # internet" quer dizer alguma coisa. Sessao pendente = painel fechado no
    # X com a placa preparada: ela volta ao encerrar (ou no Restaurar DHCP).
    $W.InternetAntes = Test-Internet
    $W.Internet = $W.InternetAntes; $W.InternetQuando = (Get-Date).ToString('HH:mm:ss')
    Write-Log ("Internet do PC na subida: " + $(if ($W.InternetAntes -eq 'ok') { 'ok' } else { 'sem (ou so por proxy)' })) 'Gray'
    if ($W.Rede.preparada) {
        Write-Log ("A placa '" + $W.Rede.placaPreparada + "' ficou preparada pelo painel desde a ultima vez (fechado sem Encerrar). Ela volta ao DHCP ao encerrar.") 'Yellow'
        $W.AvisoOrigem = ''
        $W.Aviso = 'A placa ' + $W.Rede.placaPreparada + ' ficou preparada desde a última vez (o painel foi fechado sem Encerrar). Ela volta ao DHCP quando você encerrar, ou agora em Opções, Restaurar DHCP.'
    }
    Publicar

    while (-not $E.Parar) {
        $cmd = $null
        if (-not $Q.TryDequeue([ref]$cmd)) {
            # Comando do operador sempre vem antes: o tique so roda com a fila de comandos vazia.
            if (-not (Test-VezDoVigia)) { Start-Sleep -Milliseconds 120; continue }
            try {
                Invoke-TiqueVigia
            } catch {
                Write-Log ("ERRO interno no vigia: " + $_.Exception.Message) 'Red'
                $W.AvisoOrigem = 'vigia'
                $W.Aviso = 'Erro interno no vigia: ' + $_.Exception.Message + '. Veja o log.'
                if ($W.Fase -eq 'configurando') { $W.Fase = 'decisao'; $W.Falha = [ordered]@{ etapa = $W.Etapa; erro = $_.Exception.Message; recusa = $false } }
                else { Set-VigiaDesligado 'erro interno' }
            } finally {
                $W.Vigia.Proximo = (Get-Date).AddSeconds((Get-IntervaloVigia))
                if ($E.Ocupado) {
                    $W.Trabalho = ''; $W.Progresso = $null
                    try { Update-Rede } catch { }
                    $E.Ocupado = $false
                }
                Update-Vigia
                Publicar
            }
            continue
        }
        $E.Ocupado = $true
        $W.Aviso = ''; $W.AvisoOrigem = [string]$cmd.tipo
        Publicar
        try {
            Invoke-Comando $cmd
        } catch {
            Write-Log ("ERRO interno em '" + $cmd.tipo + "': " + $_.Exception.Message) 'Red'
            $W.Aviso = 'Erro interno: ' + $_.Exception.Message + '. Veja o log.'
            if ($W.Fase -eq 'configurando') { $W.Fase = 'decisao'; $W.Falha = [ordered]@{ etapa = $W.Etapa; erro = $_.Exception.Message; recusa = $false } }
        } finally {
            $W.Trabalho = ''; $W.Progresso = $null
            # Ferramenta interrompida por erro nao fica "em curso" para sempre.
            if ($null -ne $W.Ferramenta -and $W.Ferramenta.emCurso) { $W.Ferramenta = $null }
            try { Update-Rede } catch { }
            Update-Vigia
            $E.Ocupado = $false
            Publicar
        }
    }
}

$rs = [runspacefactory]::CreateRunspace()
$rs.Open()
$ps = [powershell]::Create()
$ps.Runspace = $rs
$null = $ps.AddScript($scriptWorker).AddArgument($E).AddArgument($Q).AddArgument($motor).AddArgument($arquivos).AddArgument($adicionarLog)
$handleWorker = $ps.BeginInvoke()

# ------------------------------------------------------------ atualizador
# Terceiro runspace, independente do worker (a camera nao espera a internet):
# checa releases/latest 1x por dia, publica em $E.Atualizacao e, a pedido,
# baixa o instalador, confere o SHA-256 e o tamanho e deixa pronto para o
# finally rodar. Falha de rede = uma linha cinza no log; tenta no dia seguinte.
$scriptAtualizador = {
    param($E, $Motor, $Arquivos, $VersaoAtual, $Url, $Sem, $AdicionarLog)
    $ErrorActionPreference = 'Stop'
    . $Motor
    Set-MotorLog -Arquivo $Arquivos.Log -Sink ([scriptblock]::Create($AdicionarLog.ToString()))

    $pastaDados = Split-Path -Parent $Arquivos.Atualizacao
    $info = $null
    $ultima = ''
    function Publish-Atualizacao {
        param([string]$Estado, [string]$Erro = '')
        $o = [ordered]@{ estado = $Estado; versaoAtual = $VersaoAtual; ultimaChecagem = $ultima; erro = $Erro }
        if ($null -ne $info) { $o.versao = $info.Versao; $o.tag = $info.Tag; $o.pagina = $info.Pagina; $o.notas = $info.Notas; $o.publicado = $info.Publicado; $o.tamanho = $info.Tamanho }
        $E.Atualizacao = ConvertTo-Json -InputObject $o -Depth 5 -Compress
    }
    function Save-Cache {
        $o = [ordered]@{ ultimaChecagem = $ultima }
        if ($null -ne $info) { $o.release = $info }
        try { Save-JsonAtomico -Caminho $Arquivos.Atualizacao -Objeto $o } catch { }
    }

    # Cache: o aviso volta na hora, mesmo sem internet agora.
    try {
        $c = Read-JsonArquivo $Arquivos.Atualizacao
        if ($null -ne $c) {
            $ultima = [string]$c.ultimaChecagem
            if ($null -ne $c.release -and (Compare-Versao ([string]$c.release.Versao) $VersaoAtual) -gt 0) { $info = $c.release }
        }
    } catch { }
    if ($Sem) { Publish-Atualizacao 'desligada'; return }
    Publish-Atualizacao $(if ($null -ne $info) { 'disponivel' } else { 'nenhuma' })

    $proxima = (Get-Date).AddSeconds(10)
    if (-not (Test-DeveChecarAtualizacao -UltimaChecagem $ultima -Agora (Get-Date) -Horas 24)) { $proxima = (Get-Date).AddHours(24) }

    while (-not $E.Parar) {
        if ((Get-Date) -ge $proxima) {
            $proxima = (Get-Date).AddHours(24)
            $ultima = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $resp = ''
            try {
                $resp = (& curl.exe -s -L --max-time 5 -A ('ConfigurarCameras/' + $VersaoAtual) -H 'Accept: application/vnd.github+json' $Url 2>$null) -join "`n"
            } catch { $resp = '' }
            $r = ConvertFrom-ReleaseGitHub -Json $resp
            if ($null -eq $r) {
                Write-Log "Atualizacao: nao deu para consultar o GitHub (sem internet, proxy ou API fora). Tenta de novo amanha." 'DarkGray'
            } elseif ((Compare-Versao $r.Versao $VersaoAtual) -gt 0) {
                $info = $r
                Write-Log ("Atualizacao: versao " + $r.Versao + " disponivel no GitHub (esta e a " + $VersaoAtual + "). Botao Atualizar no topo.") 'Cyan'
            } else {
                $info = $null
                Write-Log ("Atualizacao: o painel esta na versao mais nova (" + $VersaoAtual + ").") 'DarkGray'
            }
            Save-Cache
            Publish-Atualizacao $(if ($null -ne $info) { 'disponivel' } else { 'nenhuma' })
        }

        if ($E.AtualizarPedido) {
            $E.AtualizarPedido = $false
            if ($null -eq $info) { Publish-Atualizacao 'nenhuma'; continue }
            $exe = Join-Path $pastaDados ('ConfigurarCameras-' + $info.Versao + '-instalador.exe')
            try {
                Publish-Atualizacao 'baixando'
                Write-Log ("Atualizacao: baixando a versao " + $info.Versao + " ...") 'Cyan'
                Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
                $null = & curl.exe -s -L --max-time 600 -A ('ConfigurarCameras/' + $VersaoAtual) -o $exe $info.Url 2>$null
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw ('download falhou (curl ' + $LASTEXITCODE + ')') }

                Publish-Atualizacao 'verificando'
                $tam = (Get-Item -LiteralPath $exe).Length
                if ([long]$info.Tamanho -gt 0 -and $tam -ne [long]$info.Tamanho) { throw ('tamanho diferente: ' + $tam + ' bytes, esperados ' + $info.Tamanho) }
                if ([string]::IsNullOrWhiteSpace($info.Sha256Url)) { throw 'o release nao tem o arquivo .sha256' }
                $txtSha = (& curl.exe -s -L --max-time 30 -A ('ConfigurarCameras/' + $VersaoAtual) $info.Sha256Url 2>$null) -join "`n"
                $esperado = Get-HashDoSha256 $txtSha
                if (-not $esperado) { throw 'nao consegui ler o SHA-256 publicado' }
                $real = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($real -ne $esperado) { throw 'SHA-256 nao confere: o arquivo baixado nao e o publicado' }

                Write-Log ("Atualizacao: instalador " + $info.Versao + " conferido (SHA-256 ok). Instalando: o painel fecha e reabre sozinho.") 'Green'
                $E.InstaladorPronto = $exe
                Publish-Atualizacao 'instalando'
                $E.Parar = $true
            } catch {
                Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
                Write-Log ("Atualizacao FALHOU: " + $_.Exception.Message + ". Nada foi instalado.") 'Red'
                Publish-Atualizacao 'erro' $_.Exception.Message
            }
        }
        Start-Sleep -Milliseconds 250
    }
}
$rsAtu = [runspacefactory]::CreateRunspace()
$rsAtu.Open()
$psAtu = [powershell]::Create()
$psAtu.Runspace = $rsAtu
$null = $psAtu.AddScript($scriptAtualizador).AddArgument($E).AddArgument($motor).AddArgument($arquivos).AddArgument($VersaoPainel).AddArgument($UrlAtualizacao).AddArgument([bool]$SemAtualizacao).AddArgument($adicionarLog)
$handleAtu = $psAtu.BeginInvoke()

# O worker publica o primeiro retrato ao ficar pronto. Se morrer na subida
# (motor com erro, por exemplo), falha aqui e alto, nao com painel mudo.
$limite = (Get-Date).AddSeconds(20)
while ($E.Estado -eq '{}' -and (Get-Date) -lt $limite -and -not $handleWorker.IsCompleted) { Start-Sleep -Milliseconds 100 }
if ($E.Estado -eq '{}') {
    $detalhes = @($ps.Streams.Error | ForEach-Object { $_.ToString() })
    if ($ps.InvocationStateInfo.Reason) { $detalhes += $ps.InvocationStateInfo.Reason.Message }
    Stop-ComErro ("O worker nao subiu:`n    " + ($detalhes -join "`n    "))
}

# ------------------------------------------------------------------- HTTP

if ($Porta -le 0) {
    $t = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $t.Start(); $Porta = $t.LocalEndpoint.Port; $t.Stop()
}
$origem = 'http://127.0.0.1:' + $Porta
$hostEsperado = '127.0.0.1:' + $Porta

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add($origem + '/')
try { $listener.Start() } catch { Stop-ComErro ('Nao consegui abrir a porta ' + $Porta + ' em 127.0.0.1: ' + $_.Exception.Message) }

# Lock da instancia: so depois de a porta estar aberta de verdade.
try {
    [IO.File]::WriteAllText($arquivos.Lock, (ConvertTo-Json -Compress -InputObject ([ordered]@{ porta = $Porta; pid = $PID; inicio = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') })),
                            (New-Object Text.UTF8Encoding($false)))
} catch { Write-Host ("  (nao deu para gravar o painel.json: " + $_.Exception.Message + ")") -ForegroundColor DarkGray }

# So estes arquivos sao servidos: nada de caminho vindo da URL no disco.
$estaticos = @{}
foreach ($f in @(Get-ChildItem -LiteralPath $www -File)) { $estaticos['/' + $f.Name] = $f.FullName }
$estaticos['/'] = Join-Path $www 'index.html'
$tipos = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.svg' = 'image/svg+xml' }

function Send-Resposta {
    param($Ctx, [int]$Status, [string]$Tipo, $Corpo, [hashtable]$Cabecalhos = @{})
    $r = $Ctx.Response
    $r.StatusCode = $Status
    $r.ContentType = $Tipo
    $r.Headers['Cache-Control'] = 'no-store'
    $r.Headers['X-Content-Type-Options'] = 'nosniff'
    $r.Headers['Referrer-Policy'] = 'no-referrer'
    foreach ($k in $Cabecalhos.Keys) { $r.Headers[$k] = $Cabecalhos[$k] }
    if ($Corpo -is [byte[]]) { $bytes = $Corpo } else { $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Corpo) }
    $r.ContentLength64 = $bytes.Length
    try { $r.OutputStream.Write($bytes, 0, $bytes.Length) } finally { $r.OutputStream.Close() }
}

function Send-Json {
    param($Ctx, $Objeto, [int]$Status = 200)
    $txt = $Objeto
    if (-not ($Objeto -is [string])) { $txt = ConvertTo-Json -InputObject $Objeto -Depth 12 -Compress }
    Send-Resposta $Ctx $Status 'application/json; charset=utf-8' $txt
}

function Read-Corpo {
    param($Ctx)
    $sr = New-Object IO.StreamReader($Ctx.Request.InputStream, [Text.Encoding]::UTF8)
    try { $t = $sr.ReadToEnd() } finally { $sr.Dispose() }
    if ([string]::IsNullOrWhiteSpace($t)) { return [pscustomobject]@{} }
    # JSON invalido vira 400 sem ecoar o corpo (a mensagem do parser o repete).
    try { return ($t | ConvertFrom-Json) } catch { throw 'HTTP400:Corpo inválido: envie JSON.' }
}

# Comando de trabalho com o worker ocupado e recusado (409): um clique duplo
# em "Camera conectada" nao pode configurar duas posicoes seguidas.
function Add-Comando {
    param($Ctx, [hashtable]$Cmd, [switch]$Sempre, [hashtable]$Resposta = @{})
    if (-not $Sempre -and ($E.Ocupado -or $Q.Count -gt 0)) {
        Send-Json $Ctx @{ erro = 'Aguarde: o painel está terminando a operação atual.' } 409
        return
    }
    $Q.Enqueue([pscustomobject]$Cmd)
    $r = @{ ok = $true }
    foreach ($k in $Resposta.Keys) { $r[$k] = $Resposta[$k] }
    Send-Json $Ctx $r 202
}

# Leitura da sessao com retentativa: o worker pode estar no meio do Replace.
function Read-SessaoDoDisco {
    for ($i = 0; $i -lt 5; $i++) {
        try { return (Read-Sessao -Caminho $arquivos.Sessao) } catch [IO.IOException] { Start-Sleep -Milliseconds 100 }
    }
    return (Read-Sessao -Caminho $arquivos.Sessao)
}

function Get-EstadoPublicado {
    try { return ($E.Estado | ConvertFrom-Json) } catch { return $null }
}

function Get-LogDesde {
    param([int]$Desde)
    $lista = $E.Log
    [Threading.Monitor]::Enter($lista.SyncRoot)
    try {
        $novos = @($lista | Where-Object { $_.n -gt $Desde })
        $cursor = [int]$E.LogSeq
    } finally { [Threading.Monitor]::Exit($lista.SyncRoot) }
    return @{ Linhas = $novos; Cursor = $cursor }
}

# Leitura do registro com retentativa: o worker pode estar no meio do Replace.
function Read-RegistroAtual {
    $arq = $arquivos.Registro
    if ($E.Simular) { $arq = $arquivos.RegistroSimul }
    for ($i = 0; $i -lt 5; $i++) {
        try { return (Read-Registro $arq) } catch [IO.IOException] { Start-Sleep -Milliseconds 100 }
    }
    return (Read-Registro $arq)
}

function Invoke-Rota {
    param($Ctx)
    $req = $Ctx.Request
    $metodo = $req.HttpMethod
    $rota = $req.Url.AbsolutePath

    if ($req.Headers['Host'] -ne $hostEsperado) { Send-Json $Ctx @{ erro = 'Host recusado' } 403; return }
    if ($metodo -ne 'GET' -and $req.Headers['Origin'] -ne $origem) { Send-Json $Ctx @{ erro = 'Origin recusado' } 403; return }

    if ($metodo -eq 'GET' -and $estaticos.ContainsKey($rota)) {
        $ext = [IO.Path]::GetExtension($estaticos[$rota])
        $tipo = $tipos[$ext]; if (-not $tipo) { $tipo = 'application/octet-stream' }
        Send-Resposta $Ctx 200 $tipo ([IO.File]::ReadAllBytes($estaticos[$rota])) @{ 'Content-Security-Policy' = "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'" }
        return
    }

    $chave = $metodo + ' ' + $rota
    switch ($chave) {
        'GET /favicon.ico' { Send-Resposta $Ctx 204 'image/x-icon' ([byte[]]@()) }
        'GET /api/estado' {
            $E.UltimoPoll = (Get-Date)
            $desde = 0; [void][int]::TryParse([string]$req.QueryString['desde'], [ref]$desde)
            $l = Get-LogDesde $desde
            $logJson = ConvertTo-Json -InputObject @($l.Linhas) -Depth 4 -Compress
            if ($l.Linhas.Count -eq 0) { $logJson = '[]' }
            Send-Json $Ctx ('{"estado":' + $E.Estado + ',"log":' + $logJson + ',"cursor":' + $l.Cursor + ',"comandos":' + $Q.Count +
                            ',"versao":"' + $VersaoPainel + '","atualizacao":' + $E.Atualizacao + '}')
        }
        'POST /api/senha' { $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'senha'; senha = [string]$b.senha } -Sempre }
        # Placas fisicas deste PC, para o passo 2 / secao Placa (Get-NetAdapter
        # leva ate 1 s: a pagina so chama ao entrar na secao ou em Atualizar lista).
        'GET /api/placas' {
            $s = Read-SessaoDoDisco
            $ipf = '192.168.1.108'; if ($null -ne $s) { $ipf = $s.IpFabrica }
            $placas = @(Get-PlacasFisicas)
            $sugerida = Select-PlacaSugerida -Placas $placas -IpFabrica $ipf
            $lista = @($placas | ForEach-Object {
                [ordered]@{ nome = $_.Nome; ifIndex = [int]$_.IfIndex; mac = (Format-Mac $_.Mac); tipo = $_.Tipo; cabo = [bool]$_.Cabo; status = $_.Status
                            dhcp = [bool]$_.Dhcp; rotaPadrao = [bool]$_.RotaPadrao; descricao = $_.Descricao; velocidade = $_.Velocidade
                            ips = @(@($_.Ips) | ForEach-Object { $_.Ip + '/' + $_.Prefixo }); sugerida = ([int]$_.IfIndex -eq $sugerida) } })
            # A sugerida vem primeiro; o resto na ordem do Windows.
            $lista = @($lista | Sort-Object -Property @{ Expression = { -not $_.sugerida } }, @{ Expression = { $_.tipo -ne 'ethernet' } })
            Send-Json $Ctx @{ placas = $lista; sugerida = $sugerida }
        }
        'GET /api/sessao' {
            $s = Read-SessaoDoDisco
            Send-Json $Ctx @{ sessao = $s; existe = ($null -ne $s); completa = [bool]($null -ne $s -and (Test-SessaoCompleta $s)); etapa = $(if ($null -ne $s) { [int]$s.Etapa } else { 0 })
                              resolucoes = @((Get-MapaResolucoes).Keys); resolucoesSecundario = @((Get-MapaResolucoesSecundario).Keys); codecs = @(Get-CodecsAceitos)
                              catalogo = (Get-CatalogoEncoder) }
        }
        # Uma secao (parcial) do passo a passo ou de Opcoes. Mescla com a
        # sessao gravada, valida por campo e manda o worker gravar. Troca de
        # placa/faixas com a placa preparada ou fila montada = aplicarRede: o
        # worker devolve a placa, grava, prepara de novo e remonta a fila se
        # ela cabe; com fila, exige confirmar (409 precisaConfirmar).
        'PUT /api/sessao' {
            $b = Read-Corpo $Ctx
            $atual = Read-SessaoDoDisco
            $nova = Merge-Sessao -Atual $atual -Entrada $b
            # A fila guardada e so sugestao: se a rede nova nao a comporta (e a
            # secao enviada nao e a da fila), ela cai em vez de travar o salvamento.
            if ($null -ne $nova.Fila -and $null -eq $b.PSObject.Properties['Fila'] -and
                -not (Test-FilaCabeNaRede -Inicio $nova.Fila.Inicio -Fim $nova.Fila.Fim -Mascara $nova.Mascara -Gateway $nova.Gateway)) { $nova.Fila = $null }
            $enviados = @($b.PSObject.Properties | ForEach-Object { $_.Name })
            $campos = @(Test-SessaoParaGravar -Sessao $nova -Enviados $enviados)
            if ($campos.Count -gt 0) { Send-Json $Ctx @{ erros = @($campos | ForEach-Object { $_.msg }); campos = $campos } 400; return }
            $mudou = @(Get-CamposRedeAlterados -Antes $atual -Depois $nova)
            $est = Get-EstadoPublicado
            $temFila = ($null -ne $est -and $null -ne $est.fila -and @($est.fila.itens).Count -gt 0)
            $preparada = ($null -ne $est -and $null -ne $est.rede -and [bool]$est.rede.preparada)
            $aplicarRede = ($mudou.Count -gt 0 -and $null -ne $atual -and (Test-SessaoCompleta $atual) -and ($preparada -or $temFila))
            if ($aplicarRede) {
                if ($null -ne $est -and [string]$est.fase -in @('configurando', 'decisao', 'escolher')) {
                    Send-Json $Ctx @{ erro = 'Termine a câmera atual (ou encerre a fila) antes de trocar a placa ou as faixas de rede.' } 409; return
                }
                if ($temFila -and -not [bool]$b.confirmar) {
                    Send-Json $Ctx @{ precisaConfirmar = $true; campos = $mudou
                                      erro = 'Trocar ' + ($mudou -join ', ') + ' devolve a placa de rede e a prepara de novo. A fila atual continua se a faixa couber na rede nova; senão é descartada. Confirmar?' } 409
                    return
                }
            }
            $corpo = ConvertTo-Json -InputObject $nova -Depth 12 -Compress
            $outros = @(Get-MudancasSessao -Antes $atual -Depois $nova)
            Add-Comando $Ctx @{ tipo = 'sessao-salvar'; sessao = ($corpo | ConvertFrom-Json); aplicarRede = $aplicarRede; campos = $mudou; outros = $outros; enviados = $enviados } -Resposta @{ aplicarRede = $aplicarRede; etapa = [int]$nova.Etapa }
        }
        'POST /api/sessao/concluir' {
            $b = Read-Corpo $Ctx
            $s = Read-SessaoDoDisco
            if ($null -eq $s -or $null -eq $s.Placa -or @(Test-SessaoPorCampo $s).Count -gt 0) { Send-Json $Ctx @{ erro = 'A sessão ainda não está completa: escolha a placa de rede e corrija os campos marcados.' } 409; return }
            Add-Comando $Ctx @{ tipo = 'sessao-concluir'; montarFila = [bool]$b.montarFila }
        }
        'POST /api/sessao/refazer' {
            $est = Get-EstadoPublicado
            if ($null -ne $est -and [string]$est.fase -in @('configurando', 'decisao', 'escolher')) { Send-Json $Ctx @{ erro = 'Termine a câmera atual antes de refazer o passo a passo.' } 409; return }
            Add-Comando $Ctx @{ tipo = 'sessao-refazer' }
        }
        'POST /api/fila' {
            $b = Read-Corpo $Ctx
            Add-Comando $Ctx @{ tipo = 'fila'; inicio = $b.inicio; fim = $b.fim; local = $b.local; rack = $b.rack; andar = $b.andar }
        }
        'POST /api/fila/conectada' { $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'conectada'; porta = $b.porta; canal = $b.canal; ip = $b.ip } }
        # -Sempre: desligar o vigia no meio de uma configuracao tem que ser
        # aceito (vale ao terminar, antes do proximo tique).
        'POST /api/vigia' {
            $b = Read-Corpo $Ctx
            Add-Comando $Ctx @{ tipo = 'vigia'; ligado = [bool]$b.ligado; porta = [string]$b.porta; canal = [string]$b.canal; broadcast = [bool]$b.broadcast } -Sempre
        }
        'POST /api/escolher'   { $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'escolher'; ip = $b.ip } }
        'POST /api/escolher/cancelar' { Add-Comando $Ctx @{ tipo = 'cancelar-escolha' } }
        'POST /api/decisao'    { $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'decisao'; acao = [string]$b.acao } }
        'GET /api/registro'    { Send-Json $Ctx @{ cameras = @((Read-RegistroAtual).Cameras); simulado = [bool]$E.Simular } }
        'GET /api/relatorio.csv' {
            $txt = ConvertTo-RelatorioCsv (Read-RegistroAtual)
            $bom = [byte[]](0xEF, 0xBB, 0xBF)
            $nome = 'relatorio-cameras-' + (Get-Date).ToString('yyyyMMdd-HHmm')
            if ($E.Simular) { $nome += '-SIMULADO' }
            Send-Resposta $Ctx 200 'text/csv; charset=utf-8' ([byte[]]($bom + [Text.Encoding]::UTF8.GetBytes($txt))) @{
                'Content-Disposition' = ('attachment; filename="' + $nome + '.csv"') }
        }
        'POST /api/sondar'     { $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'sondar'; ip = $b.ip } }
        'POST /api/verificar'  { Add-Comando $Ctx @{ tipo = 'verificar' } }
        'POST /api/descobrir'  { Add-Comando $Ctx @{ tipo = 'descobrir' } }
        'POST /api/rede/preparar'  { Add-Comando $Ctx @{ tipo = 'rede-preparar' } }
        'POST /api/rede/restaurar' { Add-Comando $Ctx @{ tipo = 'rede-restaurar' } }
        'POST /api/simular'    { $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'simular'; ligado = [bool]$b.ligado; falharEm = [string]$b.falharEm } }
        'POST /api/internet/testar' { Add-Comando $Ctx @{ tipo = 'internet-testar' } }
        # Atualizar: so com o painel parado (nada em curso, vigia desligado),
        # com Administrador e com uma versao nova conhecida. 409 diz o motivo.
        'POST /api/atualizar' {
            $motivo = ''
            $a = $null; try { $a = $E.Atualizacao | ConvertFrom-Json } catch { }
            $s = $null; try { $s = $E.Estado | ConvertFrom-Json } catch { }
            if ($null -eq $a -or [string]$a.estado -notin @('disponivel', 'erro')) { $motivo = 'Não há versão nova conhecida para instalar.' }
            elseif (-not $ehAdmin) { $motivo = 'Atualizar exige o painel aberto como Administrador. Encerre e abra de novo pelo atalho.' }
            elseif ($E.AtualizarPedido) { $motivo = 'A atualização já foi pedida.' }
            elseif ($E.Ocupado -or $Q.Count -gt 0) { $motivo = 'Aguarde: o painel está terminando a operação atual.' }
            elseif ($null -ne $s -and [string]$s.fase -in @('configurando', 'decisao', 'escolher')) { $motivo = 'Termine a câmera atual (ou encerre a fila) antes de atualizar.' }
            elseif ($null -ne $s -and $null -ne $s.vigia -and [bool]$s.vigia.ligado) { $motivo = 'Desligue o vigia antes de atualizar.' }
            if ($motivo) { Send-Json $Ctx @{ erro = $motivo } 409; return }
            $E.AtualizarPedido = $true
            Write-Log ("Operador: atualizar o painel para a versao " + $a.versao + ".") 'Cyan'
            Send-Json $Ctx @{ ok = $true } 202
        }
        # restaurando: a pagina avisa que a placa esta voltando ao DHCP (o finally faz).
        'POST /api/encerrar'   {
            $restaurando = ($ehAdmin -and -not $E.Simular -and (Test-Path -LiteralPath $arquivos.SessaoPlaca))
            Send-Json $Ctx @{ ok = $true; restaurando = [bool]$restaurando }
            $E.Parar = $true
        }
        default { Send-Json $Ctx @{ erro = 'rota desconhecida: ' + $chave } 404 }
    }
}

Write-Host ""
Write-Host ("  Painel v" + $VersaoPainel + " em " + $origem + "/" + $(if ($Simular) { '   [SIMULACAO]' } else { '' })) -ForegroundColor Green
Write-Host ("  Dados em  " + $PastaDados) -ForegroundColor DarkGray
Write-Host  "  Feche esta janela (ou use Encerrar no painel) para parar." -ForegroundColor DarkGray
Write-Host ""

if (-not $SemNavegador) { Open-Navegador ($origem + '/') }

# Auto-encerrar: a cada 5 s, com a pagina sumida ha -OciosoSeg e nada em
# curso, para (o finally devolve a placa). O retrato do worker e a fonte.
$E.UltimoPoll = (Get-Date)
$proximaChecagem = (Get-Date).AddSeconds(5)
function Test-PainelOciosoAgora {
    try {
        $s = $E.Estado | ConvertFrom-Json
        $vigia = $false; if ($null -ne $s.vigia) { $vigia = [bool]$s.vigia.ligado }
        $atualizando = [bool]$E.AtualizarPedido
        try { $a = $E.Atualizacao | ConvertFrom-Json; if ([string]$a.estado -in @('baixando', 'verificando', 'instalando')) { $atualizando = $true } } catch { }
        return (Test-PainelOcioso -Fase ([string]$s.fase) -VigiaLigado $vigia -Ocupado ([bool]$E.Ocupado) -Comandos $Q.Count `
                                  -Atualizando $atualizando -UltimoPoll $E.UltimoPoll -Agora (Get-Date) -LimiteSeg $OciosoSeg)
    } catch { return $false }
}

try {
    # Uma espera assincrona fica pendente entre as voltas: a cada 300 ms o laco
    # volta ao topo para olhar Parar e a ociosidade, sem perder requisicao.
    $pendente = $null
    while (-not $E.Parar) {
        if ((Get-Date) -ge $proximaChecagem) {
            $proximaChecagem = (Get-Date).AddSeconds(5)
            if (Test-PainelOciosoAgora) {
                Write-Log ("Painel fechado sozinho: sem pagina ha " + $OciosoSeg + " s e nada em curso.") 'Cyan'
                $E.Parar = $true
                break
            }
        }
        try {
            if ($null -eq $pendente) { $pendente = $listener.BeginGetContext($null, $null) }
            if (-not $pendente.AsyncWaitHandle.WaitOne(300)) { continue }
            $ctx = $listener.EndGetContext($pendente)
            $pendente = $null
        } catch {
            # Conexao abortada no meio (navegador fechou a aba): o painel continua.
            $pendente = $null
            if ($E.Parar) { break }
            Write-Log ("ERRO no listener: " + $_.Exception.Message) 'Red'
            Start-Sleep -Milliseconds 200
            continue
        }
        try {
            Invoke-Rota $ctx
        } catch {
            $msg = $_.Exception.Message
            if ($msg -like 'HTTP400:*') { try { Send-Json $ctx @{ erro = $msg.Substring(8) } 400 } catch { }; continue }
            Write-Log ("ERRO no servidor: " + $msg) 'Red'
            try { Send-Json $ctx @{ erro = $msg } 500 } catch { }
        }
    }
} finally {
    $E.Parar = $true
    try { $listener.Stop(); $listener.Close() } catch { }
    # 30 s: o worker pode estar no meio de uma gravacao na camera.
    try { $null = $handleWorker.AsyncWaitHandle.WaitOne(30000); $ps.Dispose(); $rs.Close() } catch { }
    try { $null = $handleAtu.AsyncWaitHandle.WaitOne(5000); $psAtu.Dispose(); $rsAtu.Close() } catch { }
    # A placa volta ao estado de antes do painel (sessao gravada em disco).
    # Roda aqui, no thread principal, com o worker ja parado: vale para
    # Encerrar, Ctrl+C e auto-encerrar. Nunca impede o fechamento.
    if ($ehAdmin -and -not $E.Simular -and (Test-Path -LiteralPath $arquivos.SessaoPlaca)) {
        try {
            Write-Host "  Devolvendo a placa de rede ao DHCP..." -ForegroundColor Cyan
            $p = $null; try { $p = Read-Sessao -Caminho $arquivos.Sessao } catch { }
            if ($null -eq $p) { $p = Get-SessaoFabrica }
            $s = $null; try { $s = Read-JsonArquivo $arquivos.SessaoPlaca } catch { }
            $r = Reset-RedeLocalCameras -Gateway $p.Gateway -IpFabrica $p.IpFabrica -Mascara $p.Mascara -Placa $p.Placa -Sessao $s
            if ($r.Ok) {
                Remove-Item -LiteralPath $arquivos.SessaoPlaca, ($arquivos.SessaoPlaca + '.bak') -Force -ErrorAction SilentlyContinue
                Write-Log "Placa devolvida ao encerrar o painel." 'Green'
            } else { Write-Log "Nao deu para devolver a placa ao encerrar; o proximo painel tenta de novo." 'Yellow' }
        } catch { Write-Log ("ERRO ao devolver a placa no encerramento: " + $_.Exception.Message) 'Red' }
    }
    # Lock: so o nosso (outro painel pode ter subido se este demorou a fechar).
    try {
        $l = Read-LockPainel -Caminho $arquivos.Lock
        if ($null -ne $l -and $l.Pid -eq $PID) { Remove-Item -LiteralPath $arquivos.Lock -Force -ErrorAction SilentlyContinue }
    } catch { }
    # Atualizacao: por ultimo, com tudo parado, a placa devolvida e o lock
    # fora. Silencioso; /REABRIR=1 faz o instalador reabrir o painel no fim.
    $instalador = [string]$E.InstaladorPronto
    if ($instalador -and (Test-Path -LiteralPath $instalador)) {
        try {
            Write-Host ("  Instalando a atualizacao: " + (Split-Path -Leaf $instalador)) -ForegroundColor Cyan
            Start-Process -FilePath $instalador -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS',
                                                                  '/REABRIR=1', ('"/LOG=' + $arquivos.LogInstalador + '"')) | Out-Null
        } catch { Write-Log ("ERRO ao iniciar o instalador: " + $_.Exception.Message) 'Red' }
    }
    Write-Host "  Painel encerrado." -ForegroundColor DarkGray
}
