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
# Orquestrador (puro, nao executa nada ao carregar): o listener usa o texto
# da recusa das guardas globais (Get-TextoRecusaComando).
. (Join-Path (Split-Path -Parent $motor) 'Orquestrador-Cameras.ps1')
$VersaoPainel =Get-VersaoPainel -Pasta (Split-Path -Parent $motor)

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
    # Tema do painel (sistema|claro|escuro): o listener grava, fora da sessao.
    Tema           = (Join-Path $PastaDados 'tema.txt')
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
    # Cameras em portao ou conferindo (Publicar): as guardas do listener leem daqui.
    EmCurso = 0
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
    # Orquestrador (decide) e coordenador (executa) ao lado do motor.
    . (Join-Path (Split-Path -Parent $Motor) 'Orquestrador-Cameras.ps1')
    . (Join-Path (Split-Path -Parent $Motor) 'Coordenador-Cameras.ps1')
    Set-MotorLog -Arquivo $Arquivos.Log -Sink ([scriptblock]::Create($AdicionarLog.ToString()))

    $W = @{
        Senha = ''; Simular = [bool]$E.Simular; FalharEm = ''
        # SenhaGeracao sobe a cada senha informada. Uma falha por senha recusada
        # guarda a geracao: "Tentar de novo" so volta com senha mais nova
        # (repetir senha recusada gasta tentativa do lockout da camera).
        SenhaGeracao = 0
        Trabalho = ''; Etapa = ''
        TrabalhoBase = ''        # texto da retomada manual em curso; o detalhe do motor passa por cima
        Progresso = $null        # @{ atual; total } quando ha contagem (espera do boot, verificacao)
        Fila = $null             # @{ Local; Rack; Andar; Inicio; Fim } (as posicoes moram no Coord)
        # Coordenador da fila (Coordenador-Cameras.ps1): estado paralelo, deps
        # e pool. Nulo sem fila. A fase publicada sai dele (Get-FaseAtual).
        Coord = $null
        # Acoes dos Step-* do laco, executadas juntas no passo 4.
        AcoesPendentes = (New-Object 'System.Collections.Generic.List[object]')
        # Retomada pelo IP (Camera conectada com IP): serial, uma por vez.
        # @{ Fase = 'configurando'|'decisao'; Posicao; Camera; Falha }
        Manual = $null
        # MACs que ja viraram "ultima instalada" (aviso uma vez por camera).
        Feitas = @{}
        # Fase do ultimo Publicar (o vigia consulta sem recalcular o contrato).
        FasePublicada = 'ocioso'
        Ferramenta = $null; Aviso = ''; Ultimo = ''
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
        # Vigia: DHIP na placa escolhida a cada tique, mesmo com camera em
        # curso (os avisos por MAC e o SemSucesso ficam no coordenador; em 5
        # tiques sem poder configurar o vigia desliga em vez de insistir).
        # Broadcast: com a chave ligada o vigia tambem aceita camera de fabrica
        # em qualquer faixa (broadcast DHIP); desligada, so o IP de fabrica.
        Vigia = @{ Ligado = $false; Porta = ''; Canal = ''; Proximo = [datetime]::MinValue; Motivo = ''; Broadcast = $false }
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

    # Fase da fila: 'ocioso' sem coordenador; a da retomada manual enquanto
    # ela existe; senao a fase legada do contrato (fila | configurando |
    # decisao | concluida | encerrada).
    function Get-FaseAtual {
        if ($null -eq $W.Coord) { return 'ocioso' }
        if ($null -ne $W.Manual) { return [string]$W.Manual.Fase }
        return [string](ConvertTo-EstadoPublicadoParalelo -Coord $W.Coord).fase
    }

    # Indice (base 0) da posicao de numero dado nas posicoes do estado, ou -1.
    function Get-IndicePosicao {
        param([int]$Numero)
        if ($null -eq $W.Coord) { return -1 }
        $posicoes = @($W.Coord.Estado.Posicoes)
        for ($i = 0; $i -lt $posicoes.Count; $i++) { if ([int]$posicoes[$i].Posicao -eq $Numero) { return $i } }
        return -1
    }

    # "Ultima instalada": uma vez por camera que chega a 'feita'.
    function Update-UltimaInstalada {
        param($Cameras)
        foreach ($c in @($Cameras)) {
            if ([string]$c.fase -ne 'feita') { continue }
            $k = Get-ChaveMac $c.mac
            if ($W.Feitas.ContainsKey($k)) { continue }
            $W.Feitas[$k] = $true
            $W.Ultimo = 'Câmera instalada em ' + $c.destino + ' (MAC ' + (Format-Mac $c.mac) + ').'
        }
    }

    function Publicar {
        if ($W.Aviso -ne $W.AvisoPublicado) {
            $W.AvisoPublicado = $W.Aviso
            if ($W.Aviso) { $W.AvisoN = [int]$W.AvisoN + 1 }
        }
        $fila = $null; $cameras = @(); $portao = $null; $paralelo = $null
        $fase = 'ocioso'; $atual = -1; $camera = $null; $falha = $null; $emCurso = 0
        $trabalho = $W.Trabalho; $etapa = $W.Etapa; $progresso = $W.Progresso
        if ($null -ne $W.Coord) {
            # Contrato da F6 (Coordenador-Cameras.ps1, ConvertTo-EstadoPublicadoParalelo).
            $c = ConvertTo-EstadoPublicadoParalelo -Coord $W.Coord
            $W.Coord.Sujo = $false
            $fila = [ordered]@{ itens = @($c.filaItens); local = $W.Fila.Local; rack = $W.Fila.Rack; andar = $W.Fila.Andar; inicio = $W.Fila.Inicio; fim = $W.Fila.Fim }
            $cameras = @($c.cameras); $portao = $c.portao; $paralelo = $c.paralelo; $emCurso = [int]$c.paralelo.emCurso
            $fase = [string]$c.fase; $atual = $c.atual; $camera = $c.camera; $falha = $c.falha
            if ($null -ne $W.Manual) {
                $fase = [string]$W.Manual.Fase; $camera = $W.Manual.Camera; $falha = $W.Manual.Falha
                $atual = Get-IndicePosicao ([int]$W.Manual.Posicao)
            } elseif (-not $trabalho) {
                # Campos legados (UI de um cartao): a primeira camera em curso.
                $cur = @($cameras | Where-Object { $_.fase -eq 'portao' -or $_.fase -eq 'conferindo' }) | Select-Object -First 1
                if ($null -ne $cur) { $trabalho = $cur.trabalho; $etapa = $cur.etapa; $progresso = $cur.progresso }
            }
            Update-UltimaInstalada $cameras
        }
        $E.EmCurso = $emCurso
        $W.FasePublicada = $fase
        Update-Vigia -Fase $fase
        $o = [ordered]@{
            senhaDefinida = (-not [string]::IsNullOrEmpty($W.Senha)); senhaGeracao = [int]$W.SenhaGeracao
            simular = $W.Simular; falharEm = $W.FalharEm
            fase = $fase; trabalho = $trabalho; etapa = $etapa; progresso = $progresso
            fila = $fila; atual = $atual
            camera = $camera; falha = $falha
            cameras = $cameras; portao = $portao; paralelo = $paralelo
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

    # ------------------------------------------------------------ fila (coordenador)

    # Posicao do estado paralelo pelo numero (o estado e do coordenador; so a
    # retomada manual mexe direto, com o laco parado no comando). Sem posicao, nada.
    function Set-PosicaoCoord {
        param([int]$Numero, [string]$Estado, [string]$Motivo = '', [string]$Mac = '')
        foreach ($p in @($W.Coord.Estado.Posicoes)) {
            if ([int]$p.Posicao -ne $Numero) { continue }
            $p.Estado = $Estado
            $p.Motivo = $Motivo
            if ($Mac) { $p.Mac = $Mac }
            $W.Coord.Sujo = $true
            return
        }
    }

    # O que todo job recebe (senha so em memoria): a cada fila nova, senha,
    # sessao salva e simulacao trocada.
    function Update-TrabalhoCoord {
        if ($null -eq $W.Coord) { return }
        $t = $W.Coord.Trabalho
        $t.Senha = [string]$W.Senha
        $t.Padroes = Get-SessaoOuFabrica
        $t.CaminhoRegistro = Get-CaminhoRegistroAtual
        $t.Simular = [bool]$W.Simular
        $t.FalharEm = $(if ($W.Simular) { [string]$W.FalharEm } else { '' })
        if ($null -ne $W.Fila) { $t.Local = [string]$W.Fila.Local; $t.Rack = [string]$W.Fila.Rack; $t.Andar = [string]$W.Fila.Andar }
        $W.Coord.Geracao = [int]$W.SenhaGeracao
    }

    # Descarta a fila: fecha o pool (job ainda rodando e parado) e esquece o
    # coordenador e a retomada manual.
    function Clear-Fila {
        if ($null -ne $W.Coord) { Close-PoolCameras -Pool $W.Coord.Pool }
        $W.Coord = $null; $W.Fila = $null; $W.Manual = $null
        $W.AcoesPendentes.Clear()
    }

    # Guarda global (Step-Comando): com camera em portao ou conferindo, o
    # comando e recusado com o texto do orquestrador. $true = recusado.
    function Test-ComandoRecusado {
        param([string]$Comando)
        if ($null -eq $W.Coord) { return $false }
        $g = Step-Comando -Estado $W.Coord.Estado -Comando $Comando
        if ($g.Aceito) { return $false }
        $W.Aviso = [string](@($g.Acoes)[0].Texto)
        return $true
    }

    # Leitura de rede do tique do vigia (Deps.Descobrir do coordenador), para
    # o Invoke-TiqueParalelo: { Achados (formato do orquestrador: Mac, Serial,
    # Modelo, Ip, HttpPort, Init, Marca); DhipRespondeu; PingFabrica; MacArp;
    # MacTrocando }.
    # Em simulacao: as 3 cameras de fabrica ficticias (U1), no IP de fabrica.
    # No real: so o broadcast DHIP na placa escolhida (D9), sem varredura (o
    # tique nao pode prender o worker por minutos) e sem o atalho HTTP no IP
    # de fabrica (com duas cameras nesse IP, o Init do HTTP pode ser da
    # outra). Com a chave de broadcast desligada, so o IP de fabrica conta.
    # DHIP vazio: ping no IP de fabrica e, se responder, o MAC do ARP e duas
    # leituras do vizinho (MAC trocando = duas cameras no mesmo IP).
    $DescobrirAchados = {
        param($Sessao)
        $ipf = [string]$Sessao.IpFabrica
        $l = @{ Achados = @(); DhipRespondeu = $true; PingFabrica = $false; MacArp = ''; MacTrocando = $false }
        if ($W.Simular) {
            $l.Achados = @(1..3 | ForEach-Object {
                @{ Mac = ('AA:00:00:00:00:0' + $_); Serial = ('SIM-' + $_); Modelo = 'SIM-IPC'; Ip = $ipf
                   HttpPort = 80; Init = 1; Marca = 'Intelbras' } })
            return $l
        }
        $todos = @(Find-CamerasNaRede -IpFabrica $ipf -GatewayDestino $Sessao.Gateway -ArquivoBlacklist $Arquivos.Blacklist `
                                      -SemVarredura -SemAtalho -Silencioso -IfIndex ([int]$Sessao.Placa.IfIndex))
        $l.DhipRespondeu = ($todos.Count -gt 0)
        if (-not $W.Vigia.Broadcast) { $todos = @($todos | Where-Object { [string]$_.Ip -eq $ipf }) }
        $l.Achados = @($todos | ForEach-Object { ConvertTo-AchadoParalelo $_ })
        if (-not $l.DhipRespondeu) {
            $l.PingFabrica = (@(Invoke-PingSweep -Ips @($ipf) -TimeoutMs 1000).Count -gt 0)
            if ($l.PingFabrica) {
                $m = Get-VizinhosMac -Ips @($ipf)
                if ($m.ContainsKey($ipf)) { $l.MacArp = [string]$m[$ipf] }
                $l.MacTrocando = [bool](Test-MacTrocandoNoIp -Ip $ipf -IntervaloMs 300)
            }
        }
        return $l
    }

    # Pingar do coordenador (Get-IpsOcupadosAdmissao): IPs da fila que ja
    # respondem. Em simulacao nada toca a rede real: ninguem responde.
    $PingarPosicoes = {
        param($Ips)
        if ($W.Simular) { return @() }
        return @(Invoke-PingSweep -Ips @($Ips) -TimeoutMs 1000)
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
        $W.Vigia.Motivo = $Motivo
        Write-Log ("Vigia desligado: " + $Motivo + ".") 'Cyan'
    }

    # Desliga sozinho quando a fila acaba, e quando a sessao perde a senha.
    # -Fase: a fase que o Publicar acabou de calcular.
    function Update-Vigia {
        param([string]$Fase)
        if (-not $W.Vigia.Ligado) { return }
        if ($null -eq $W.Coord -or $Fase -eq 'ocioso') { Set-VigiaDesligado 'sem fila' }
        elseif ($Fase -eq 'concluida') { Set-VigiaDesligado 'fila concluida' }
        elseif ($Fase -eq 'encerrada') { Set-VigiaDesligado 'fila encerrada' }
        elseif (-not $W.Simular -and [string]::IsNullOrEmpty($W.Senha)) { Set-VigiaDesligado 'senha da sessao apagada' }
    }

    # O vigia roda a cada intervalo com a fila montada, mesmo com camera em
    # curso ou em decisao (paralelo: a proxima camera entra enquanto a outra
    # configura).
    function Test-VezDoVigia {
        return ($W.Vigia.Ligado -and $null -ne $W.Coord -and (Get-Date) -ge $W.Vigia.Proximo)
    }

    <#
        Um tique do vigia, pelo coordenador: Deps.Descobrir le a rede (DHIP na
        placa escolhida; DHIP vazio: ping, ARP e MAC trocando no IP de
        fabrica; em simulacao as 3 cameras de fabrica) e Invoke-TiqueParalelo
        aplica Step-Descoberta e Step-JaInicializada (inicializadas: um aviso
        por MAC, sem login; retomar e sempre acao do operador), a reserva sem
        DHIP (Max=1) e os avisos. As acoes vao para o passo 4 do laco; a
        admissao faz o resto. Em 5 tiques seguidos sem poder configurar (so o
        operador resolve) o vigia desliga.
        -Manual: "Camera conectada" sem IP (procurar agora); sem camera nova,
        aviso para o operador.
    #>
    function Invoke-TiqueVigia {
        param([switch]$Manual)
        $p = Get-SessaoPronta
        if ($null -eq $p) { Set-VigiaDesligado 'sessao incompleta'; return }
        $coord = $W.Coord
        $l = & (Get-DepCoordenador -Coord $coord -Nome 'Descobrir') -Sessao $p
        $achados = @($l.Achados)
        $semDhip = (-not [bool]$l.DhipRespondeu -and [bool]$l.PingFabrica)
        $registro = @()
        if ($semDhip -or @($achados | Where-Object { (Get-InitOrquestrador $_.Init) -ne 1 }).Count -gt 0) {
            $registro = @((Read-Registro (Get-CaminhoRegistroAtual)).Cameras)
        }
        $dhipAntes = [string]$coord.Dhip
        $r = Invoke-TiqueParalelo -Coord $coord -Achados $achados -Registro $registro -DhipRespondeu ([bool]$l.DhipRespondeu) `
                                  -PingFabrica ([bool]$l.PingFabrica) -MacArp ([string]$l.MacArp) -IpFabrica ([string]$p.IpFabrica) `
                                  -MacTrocando ([bool]$l.MacTrocando)
        foreach ($a in @($r.Acoes)) { if ($null -ne $a) { $W.AcoesPendentes.Add($a) } }
        if ([string]$coord.Dhip -ne $dhipAntes) { Write-Log ("Vigia: DHIP " + [string]$coord.Dhip + ", max " + [int]$coord.Estado.Max + ".") 'Cyan' }
        $novas = @($r.Novas)
        if ($novas.Count -gt 0) {
            Write-Log ("Vigia: " + $novas.Count + " camera(s) nova(s) em espera: " + (($novas | ForEach-Object { [string]$_.Mac + ' em ' + [string]$_.IpOrigem }) -join ', ')) 'Cyan'
        } elseif ($Manual) {
            $W.Aviso = 'Nenhuma câmera de fábrica nova encontrada. Confira o cabo, o PoE e a porta P+D do injetor, e tente de novo.'
        }
        if ([int]$coord.SemSucesso -ge 5) { Set-VigiaDesligado '5 tiques sem poder configurar' }
    }

    # Retomada pelo IP (serial, D1): configura a camera de $W.Manual na
    # posicao reservada, bloqueando o worker como antes do paralelo.
    function Invoke-ConfigurarManual {
        $m = $W.Manual
        $p = Get-SessaoOuFabrica
        $m.Fase = 'configurando'; $m.Falha = $null; $W.Aviso = ''; $W.Etapa = ''
        Set-PosicaoCoord -Numero ([int]$m.Posicao) -Estado 'reservada' -Mac ([string]$m.Camera.Mac)
        $W.TrabalhoBase = 'Configurando a câmera para ' + $m.Camera.Destino
        $W.Trabalho = $W.TrabalhoBase; $W.Progresso = $null
        Publicar
        $falharEm = ''
        if ($W.Simular) { $falharEm = $W.FalharEm }
        $r = Invoke-ConfiguracaoCamera -Contexto $m.Camera -Padroes $p -Senha $W.Senha `
                                       -CaminhoRegistro (Get-CaminhoRegistroAtual) -Simular:$W.Simular -FalharEm $falharEm
        if ($r.Mac) { $m.Camera.Mac = $r.Mac }
        $W.Etapa = ''
        $W.Trabalho = ''; $W.TrabalhoBase = ''; $W.Progresso = $null
        if ($r.Ok) {
            Set-PosicaoCoord -Numero ([int]$m.Posicao) -Estado 'feita' -Mac $r.Mac
            $W.Ultimo = 'Câmera instalada em ' + $m.Camera.Destino + ' (MAC ' + (Format-Mac $r.Mac) + ').'
            $W.Manual = $null
        } else {
            # Falha simulada e de uma vez so: o "Tentar de novo" tem que passar.
            if ($W.Simular -and $W.FalharEm) { $W.FalharEm = '' }
            Set-PosicaoCoord -Numero ([int]$m.Posicao) -Estado 'falhou' -Motivo ($r.Falhou + ': ' + $r.Erro) -Mac $r.Mac
            $m.Falha = [ordered]@{ etapa = $r.Falhou; erro = $r.Erro; recusa = $r.Recusa
                                   loginRecusado = [bool]$r.LoginRecusado; bloqueada = [bool]$r.Bloqueada; geracao = [int]$W.SenhaGeracao }
            $m.Fase = 'decisao'
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

    <#
        "Camera conectada". Sem IP: procurar agora (tique imediato do vigia,
        U3); as cameras achadas entram na espera e a admissao as leva.
        Com IP: retomada de camera ja inicializada, serial e uma por vez (D1),
        recusada com camera em curso (Step-Comando 'retomar').
    #>
    function Invoke-Conectada {
        param($Cmd)
        if ($null -eq $W.Coord) { $W.Aviso = 'Monte a fila antes: informe a faixa de IPs e clique em Montar fila.'; return }
        if ($null -ne $W.Manual) { $W.Aviso = 'Termine a câmera atual antes: decida o que fazer com a falha.'; return }
        $fase = Get-FaseAtual
        if ($fase -eq 'encerrada') { $W.Aviso = 'A fila foi encerrada: monte uma fila nova para continuar.'; return }
        if ($fase -eq 'concluida') { $W.Aviso = 'Fila concluída: nenhuma posição pendente. Monte uma fila nova para continuar.'; return }
        if (-not $W.Simular -and [string]::IsNullOrEmpty($W.Senha)) { $W.Aviso = $TextoSemSenha; return }
        # IP invalido e recusado antes de mexer na placa ou pular posicoes.
        $ipDado = ([string]$Cmd.ip).Trim()
        if ($ipDado -and -not (Test-Ipv4Estrito $ipDado)) { $W.Aviso = Get-TextoIpInvalido $ipDado; return }
        if ($ipDado -and (Test-ComandoRecusado 'retomar')) { return }
        $p = Get-SessaoPronta
        if ($null -eq $p) { return }
        if (-not (Confirm-PlacaPronta $p)) { return }

        if (-not $ipDado) {
            Write-Log "Operador: procurar camera de fabrica agora." 'Cyan'
            Invoke-TiqueVigia -Manual
            return
        }

        # Proxima posicao pendente. IP que ja responde e de outro equipamento -
        # a menos que seja a propria camera informada pelo operador.
        $pos = $null
        foreach ($q in @($W.Coord.Estado.Posicoes)) {
            if ([string]$q.Estado -ne 'pendente') { continue }
            if (-not $W.Simular -and [string]$q.Ip -ne $ipDado -and (Test-IpEmUso -Ip $q.Ip)) {
                Write-Log ("  posicao " + $q.Posicao + ": " + $q.Ip + " ja responde ao ping - pulada") 'Yellow'
                Set-PosicaoCoord -Numero ([int]$q.Posicao) -Estado 'pulada' -Motivo 'IP ja responde na rede'
                Publicar
                continue
            }
            $pos = $q
            break
        }
        if ($null -eq $pos) { $W.Aviso = 'Fila concluída: nenhuma posição pendente. Monte uma fila nova para continuar.'; return }

        $mac = ''; $alcancavel = $true; $porta = 80
        if (-not $W.Simular) {
            $null = Invoke-PingSweep -Ips @($ipDado)
            $m = Get-VizinhosMac -Ips @($ipDado)
            if ($m.ContainsKey($ipDado)) { $mac = $m[$ipDado] }
            $alcancavel = (Test-IpAlcancavel -Ip $ipDado -Locais @(Get-FaixasDaPlaca -IfIndex ([int]$p.Placa.IfIndex)))
            $porta = [int](Get-CamPortaHttp $ipDado)
            if ($porta -le 0) { $porta = 80 }
        }
        $achado = [pscustomobject]@{ Ip = $ipDado; Mac = $mac; Alcancavel = $alcancavel; Confirmado = $false; Init = -1; HttpPort = $porta; Mascara = ''; Gateway = ''; Como = 'informado' }
        if (-not (Confirm-AlcanceCamera $achado $p -SemInit)) { return }
        $W.Manual = @{
            Fase = 'configurando'; Posicao = [int]$pos.Posicao; Falha = $null
            Camera = [pscustomobject]@{
                IpOrigem = $ipDado; Destino = [string]$pos.Ip; Mac = $mac
                Local = $W.Fila.Local; Rack = $W.Fila.Rack; Andar = $W.Fila.Andar
                Porta = [string]$Cmd.porta; Canal = [string]$Cmd.canal; HttpPort = $porta
            }
        }
        Invoke-ConfigurarManual
    }

    # Monta a fila a partir da faixa e guarda a faixa na sessao (volta como
    # sugestao na proxima abertura). Usado pelo comando 'fila', por
    # 'sessao-concluir' (Montar fila) e pela remontagem depois de trocar a
    # rede em Opcoes. -Silencioso: sem o aviso "nenhuma posicao livre".
    function Invoke-MontarFila {
        param([string]$Inicio, [string]$Fim, [string]$Local = '', [string]$Rack = '', [string]$Andar = '', [switch]$Guardar = $true)
        # Fila nova com camera em curso e recusada (Step-Comando 'nova-fila').
        if (Test-ComandoRecusado 'nova-fila') { return $false }
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
        Clear-Fila
        $W.Fila = @{ Local = [string]$Local; Rack = [string]$Rack; Andar = [string]$Andar; Inicio = $Inicio; Fim = $Fim }
        # Coordenador + pool: a placa (Prender/Soltar), o despacho dos jobs, a
        # leitura de rede do vigia e o ping das posicoes na admissao.
        # No real sem Administrador a placa nao recebe vizinho fixo: Prender e
        # Soltar viram nada e a fila vai uma camera por vez (Max=1).
        $semAdmin = (-not $W.Simular -and -not $W.Admin)
        $deps = New-DepsPlaca -IfIndex ([int]$p.Placa.IfIndex) -CaminhoRastro $Arquivos.SessaoPlaca -Simular:$W.Simular
        if ($semAdmin) {
            $deps.Prender = { param($Mac, $Ip) [pscustomobject]@{ Ok = $true; Erro = '' } }
            $deps.Soltar  = { param($Mac, $Ip) [pscustomobject]@{ Ok = $true; Erro = '' } }
        }
        $deps.Despachar = (New-DepsPool).Despachar
        $deps.Descobrir = $DescobrirAchados
        $deps.Pingar = $PingarPosicoes
        $W.Coord = New-Coordenador -Posicoes $itens -Max ($(if ($semAdmin) { 1 } else { 0 })) -Deps $deps
        $W.Coord.Pool = New-PoolCameras -Max ([Math]::Max(1, $pend)) -CaminhoMotor $Motor
        Update-TrabalhoCoord
        $W.Aviso = ''; $W.Ultimo = ''; $W.Feitas = @{}
        Write-Log ("Fila montada: " + $Inicio + " a " + $Fim + " (" + $pend + " posicao(oes) livre(s) de " + $itens.Count + ")") 'Cyan'
        if ($semAdmin) {
            $W.Aviso = 'Sem administrador: uma câmera por vez.'
            Write-Log "  sem Administrador: uma camera por vez (sem vizinho fixo na placa)." 'Yellow'
        }
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
                if (Test-ComandoRecusado 'trocar-senha') { return }
                $W.Senha = [string]$Cmd.senha
                $W.SenhaGeracao = [int]$W.SenhaGeracao + 1
                if ($W.Senha) { Write-Log "Senha da sessao definida (fica so na memoria)." 'Gray' }
                else { Write-Log "Senha da sessao apagada." 'Gray' }
                Update-TrabalhoCoord
            }
            # Uma secao do passo a passo / Opcoes, ja mesclada e validada pelo
            # listener. aplicarRede: rede ou placa mudaram com a placa preparada
            # (ou fila montada): devolve a placa com a sessao ANTIGA, grava a
            # nova, prepara de novo e remonta a fila se ela ainda cabe.
            'sessao-salvar' {
                if (Test-ComandoRecusado 'salvar-sessao') { return }
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
                    if ($null -ne $W.Coord -and $null -ne $W.Fila) {
                        if ((Test-SessaoCompleta $nova) -and (Test-FilaCabeNaRede -Inicio $W.Fila.Inicio -Fim $W.Fila.Fim -Mascara $nova.Mascara -Gateway $nova.Gateway)) {
                            $f = $W.Fila
                            if (Invoke-MontarFila -Inicio $f.Inicio -Fim $f.Fim -Local $f.Local -Rack $f.Rack -Andar $f.Andar -Guardar:$false) {
                                Write-Log "  a fila foi remontada com a rede nova (posicoes com camera instalada ficam de fora)." 'Gray'
                            }
                        } else {
                            $faixa = [string]$W.Fila.Inicio + ' a ' + [string]$W.Fila.Fim
                            Clear-Fila
                            $W.Aviso = 'A fila foi descartada: a faixa ' + $faixa + ' não cabe na rede nova. Monte outra no Painel.'
                            Write-Log ("  a fila " + $faixa + " nao cabe na rede nova e foi descartada.") 'Yellow'
                        }
                    }
                }
                Update-TrabalhoCoord
                Update-Rede
            }
            # Fim do passo a passo: etapa 7, placa preparada e, se pedido, a fila da sessao montada.
            'sessao-concluir' {
                if (Test-ComandoRecusado 'salvar-sessao') { return }
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
                if (Test-ComandoRecusado 'refazer-sessao') { return }
                if ($null -ne $W.Manual) { $W.Aviso = 'Termine a câmera atual antes de refazer o passo a passo.'; return }
                $s = Get-SessaoOuFabrica
                $s.Etapa = 1
                $null = Save-SessaoAtual $s
                $W.SessaoIniciada = $false
                Set-VigiaDesligado 'passo a passo reaberto'
                Write-Log "Passo a passo reaberto pelo operador (a sessao continua guardada como sugestao)." 'Cyan'
                Update-Rede
            }
            'simular' {
                if (Test-ComandoRecusado 'simular') { return }
                $novo = [bool]$Cmd.ligado
                if ($novo -ne $W.Simular) {
                    # Registro diferente: fila, retomada, ultimo resultado e
                    # ferramenta nao valem mais.
                    Set-VigiaDesligado 'modo trocado'
                    Clear-Fila
                    $W.Ultimo = ''; $W.Ferramenta = $null
                }
                $W.Simular = $novo
                $W.FalharEm = [string]$Cmd.falharEm
                $E.Simular = $novo
                Update-TrabalhoCoord
                Write-Log ("Simulacao " + $(if ($novo) { 'LIGADA - nada e enviado para camera nem para a placa' } else { 'desligada' }) +
                           $(if ($W.FalharEm) { '; falha forcada em ' + $W.FalharEm } else { '' })) 'Yellow'
            }
            'fila' {
                if ($null -ne $W.Manual) { $W.Aviso = 'Termine a câmera atual antes de montar outra fila.'; return }
                $null = Invoke-MontarFila -Inicio ([string]$Cmd.inicio) -Fim ([string]$Cmd.fim) -Local ([string]$Cmd.local) -Rack ([string]$Cmd.rack) -Andar ([string]$Cmd.andar)
            }
            'conectada' { Invoke-Conectada $Cmd }
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
                if ($null -eq $W.Coord -or (Get-FaseAtual) -in @('ocioso', 'concluida', 'encerrada')) { $W.Aviso = 'Monte uma fila com posição livre antes de ligar o vigia.'; return }
                if (-not $W.Simular -and [string]::IsNullOrEmpty($W.Senha)) { $W.Aviso = $TextoSemSenha; return }
                $p = Get-SessaoPronta
                if ($null -eq $p) { return }
                if (-not (Confirm-PlacaPronta $p)) { return }
                $W.Vigia.Porta = ([string]$Cmd.porta).Trim()
                $W.Vigia.Canal = ([string]$Cmd.canal).Trim()
                $W.Vigia.Broadcast = [bool]$Cmd.broadcast
                $W.Vigia.Motivo = ''
                $W.Coord.SemSucesso = 0
                $W.Vigia.Proximo = (Get-Date).AddSeconds((Get-IntervaloVigia))
                $W.Vigia.Ligado = $true
                Write-Log ("Vigia ligado: observando " + $(if ($W.Vigia.Broadcast) { 'qualquer faixa (broadcast DHIP) e ' } else { '' }) + $p.IpFabrica +
                           " a cada " + (Get-IntervaloVigia) + " s. Porta '" + $W.Vigia.Porta + "', canal '" + $W.Vigia.Canal + "'.") 'Cyan'
            }
            # Decisao sobre uma falha. Retomada manual (serial) em decisao e sem
            # MAC: o caminho antigo. Senao, Step-Decisao no coordenador; sem MAC,
            # 'encerrar' encerra a fila e as outras acoes valem para a primeira
            # camera em decisao (a UI atual ainda nao manda o MAC).
            'decisao' {
                $acao = [string]$Cmd.acao
                if ($acao -notin @('tentar', 'pular', 'encerrar')) { return }
                $mac = [string]$Cmd.mac
                if (-not $mac -and $null -ne $W.Manual -and $W.Manual.Fase -eq 'decisao') {
                    $f = $W.Manual.Falha
                    if ($acao -eq 'tentar') {
                        # Senha recusada: repetir a mesma senha so gasta tentativa do lockout.
                        if ($f.loginRecusado -and [int]$f.geracao -eq [int]$W.SenhaGeracao) {
                            $W.Aviso = $(if ($f.bloqueada) { $TextoBloqueada } else { $TextoSenhaRecusada })
                            return
                        }
                        Write-Log "Operador: tentar de novo." 'Cyan'
                        Invoke-ConfigurarManual
                        return
                    }
                    if ($acao -eq 'pular') {
                        Write-Log "Operador: pular esta posicao." 'Cyan'
                        Set-PosicaoCoord -Numero ([int]$W.Manual.Posicao) -Estado 'pulada' -Motivo ('pulada pelo operador - ' + $f.etapa + ': ' + $f.erro)
                        $W.Manual = $null
                        return
                    }
                    $W.Manual = $null
                }
                if ($null -eq $W.Coord) { return }
                if (-not $mac -and $acao -ne 'encerrar') {
                    $c = @(@($W.Coord.Estado.Cameras) | Where-Object { $_.Fase -eq 'decisao' }) | Select-Object -First 1
                    if ($null -eq $c) { return }
                    $mac = [string]$c.Mac
                }
                switch ($acao) {
                    'tentar'   { Write-Log ("Operador: tentar de novo (MAC " + (Format-Mac $mac) + ").") 'Cyan' }
                    'pular'    { Write-Log ("Operador: pular a camera (MAC " + (Format-Mac $mac) + ").") 'Cyan' }
                    'encerrar' { Write-Log "Operador: encerrar a fila." 'Cyan' }
                }
                $passo = Step-Decisao -Estado $W.Coord.Estado -Mac $mac -Acao $acao -Geracao ([int]$W.SenhaGeracao)
                $W.Coord.Estado = $passo.Estado
                $W.Coord.Sujo = $true
                foreach ($a in @($passo.Acoes)) {
                    if ($null -ne $a -and [string]$a.Tipo -eq 'avisar' -and [string]$a.Texto) { $W.Aviso = [string]$a.Texto }
                }
                Invoke-AcoesCoordenador -Coord $W.Coord -Acoes @($passo.Acoes)
            }
            # Porta e canal do cartao de uma camera, editaveis ate a conferencia
            # terminar (o 'feita' corrige o registro se mudaram depois do despacho).
            'camera' {
                if ($null -eq $W.Coord) { $W.Aviso = 'Monte uma fila antes de mudar a porta e o canal de uma câmera.'; return }
                $r = Set-PortaCanalCoordenador -Coord $W.Coord -Mac ([string]$Cmd.mac) -Porta ([string]$Cmd.porta) -Canal ([string]$Cmd.canal)
                if (-not $r.Ok) { $W.Aviso = [string]$r.Texto; return }
                Write-Log ("Porta '" + ([string]$Cmd.porta).Trim() + "', canal '" + ([string]$Cmd.canal).Trim() + "' para a camera " + (Format-Mac ([string]$Cmd.mac)) + ".") 'Cyan'
            }
            'sondar' {
                if (Test-ComandoRecusado 'ferramenta') { return }
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
                if (Test-ComandoRecusado 'ferramenta') { return }
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
                if (Test-ComandoRecusado 'ferramenta') { return }
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
                if (Test-ComandoRecusado 'preparar-placa') { return }
                if (-not $W.Simular -and -not $W.Admin) { $W.Aviso = $TextoSemAdmin; return }
                $p = Get-SessaoPronta
                if ($null -eq $p) { return }
                $W.Trabalho = 'Preparando a placa de rede'; Publicar
                $null = Invoke-PrepararPlaca $p
                if (-not $W.Simular -and -not $W.Rede.ok) { $W.Aviso = 'Não deu para preparar a placa de rede do PC. Veja o log.' }
            }
            'rede-restaurar' {
                if (Test-ComandoRecusado 'restaurar-placa') { return }
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

    # Log dos jobs de camera: vai para o log do painel com o MAC curto.
    $logJob = {
        param($Ev)
        $quem = Format-Mac ([string]$Ev.Mac)
        if ($quem.Length -gt 8) { $quem = $quem.Substring($quem.Length - 8) }
        $cor = [string]$Ev.Cor
        if (-not $cor) { $cor = 'Gray' }
        Write-Log ('  [' + $quem + '] ' + [string]$Ev.Texto) $cor
    }
    $ultimaPublicacao = [datetime]::Now

    <#
        Laco que nao bloqueia. A cada volta, em ordem:
          1. comando do operador (um por volta);
          2. eventos dos jobs (log, progresso, fim);
          3. tique do vigia, quando for a vez, e admissao das cameras em espera;
          4. acoes do coordenador (prender, despachar, soltar, avisar);
          5. Publicar se o estado mudou, ou a cada ~250 ms.
        As cameras rodam nos jobs do pool; o worker so decide e publica.
    #>
    while (-not $E.Parar) {
        $cmd = $null
        $temComando = $Q.TryDequeue([ref]$cmd)
        if ($temComando) {
            $E.Ocupado = $true
            $W.Aviso = ''; $W.AvisoOrigem = [string]$cmd.tipo
            Publicar
            try {
                Invoke-Comando $cmd
            } catch {
                Write-Log ("ERRO interno em '" + $cmd.tipo + "': " + $_.Exception.Message) 'Red'
                $W.Aviso = 'Erro interno: ' + $_.Exception.Message + '. Veja o log.'
                if ($null -ne $W.Manual -and $W.Manual.Fase -eq 'configurando') {
                    $W.Manual.Falha = [ordered]@{ etapa = $W.Etapa; erro = $_.Exception.Message; recusa = $false; loginRecusado = $false; bloqueada = $false; geracao = [int]$W.SenhaGeracao }
                    $W.Manual.Fase = 'decisao'
                }
            } finally {
                $W.Trabalho = ''; $W.Progresso = $null
                # Ferramenta interrompida por erro nao fica "em curso" para sempre.
                if ($null -ne $W.Ferramenta -and $W.Ferramenta.emCurso) { $W.Ferramenta = $null }
                try { Update-Rede } catch { }
                $E.Ocupado = $false
                Publicar
                $ultimaPublicacao = [datetime]::Now
            }
        }

        $coord = $W.Coord
        if ($null -ne $coord) {
            try {
                Receive-EventosCoordenador -Coord $coord -Log $logJob
                if (Test-VezDoVigia) {
                    try {
                        Invoke-TiqueVigia
                    } catch {
                        Write-Log ("ERRO interno no vigia: " + $_.Exception.Message) 'Red'
                        $W.AvisoOrigem = 'vigia'
                        $W.Aviso = 'Erro interno no vigia: ' + $_.Exception.Message + '. Veja o log.'
                        Set-VigiaDesligado 'erro interno'
                    } finally {
                        $W.Vigia.Proximo = (Get-Date).AddSeconds((Get-IntervaloVigia))
                    }
                }
                # Admissao: com camera em espera e o portao livre, pinga so as
                # proximas posicoes pendentes (IP ja ocupado fica de fora).
                foreach ($a in @(Invoke-AdmissaoCoordenador -Coord $coord)) { if ($null -ne $a) { $W.AcoesPendentes.Add($a) } }
                if ($W.AcoesPendentes.Count -gt 0) {
                    $acoes = $W.AcoesPendentes.ToArray()
                    $W.AcoesPendentes.Clear()
                    Invoke-AcoesCoordenador -Coord $coord -Acoes $acoes
                }
                if ([string]$coord.AvisoGlobal) {
                    $W.AvisoOrigem = 'vigia'
                    $W.Aviso = [string]$coord.AvisoGlobal
                    $coord.AvisoGlobal = ''
                    $coord.Sujo = $true
                }
                # Falha simulada e de uma vez so: o despacho que a levou desarmou
                # o Trabalho (Use-FalharEmCoordenador); o worker esquece tambem,
                # senao o proximo Update-TrabalhoCoord a armaria de novo.
                if ($W.Simular -and $W.FalharEm -and [string]$coord.Trabalho.FalharEm -eq '') { $W.FalharEm = '' }
            } catch {
                Write-Log ("ERRO interno no coordenador: " + $_.Exception.Message) 'Red'
            }
        }

        $agora = [datetime]::Now
        if (($null -ne $W.Coord -and $W.Coord.Sujo) -or ($agora - $ultimaPublicacao).TotalMilliseconds -ge 250) {
            Publicar
            $ultimaPublicacao = $agora
        }
        if (-not $temComando) { Start-Sleep -Milliseconds 50 }
    }
    if ($null -ne $W.Coord) { Close-PoolCameras -Pool $W.Coord.Pool }
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
    # Decisao, vigia e camera passam com o worker ocupado: com cameras em
    # paralelo o operador age num cartao enquanto as outras seguem.
    $livre = $Sempre -or ([string]$Cmd.tipo -in @('decisao', 'vigia', 'camera'))
    if (-not $livre -and ($E.Ocupado -or $Q.Count -gt 0)) {
        Send-Json $Ctx @{ erro = 'Aguarde: o painel está terminando a operação atual.' } 409
        return
    }
    $Q.Enqueue([pscustomobject]$Cmd)
    $r = @{ ok = $true }
    foreach ($k in $Resposta.Keys) { $r[$k] = $Resposta[$k] }
    Send-Json $Ctx $r 202
}

# Guarda global no listener: com camera em portao ou conferindo ($E.EmCurso,
# do Publicar), o comando guardado e recusado com 409 e o texto do
# orquestrador. O worker confere de novo (Step-Comando), pela corrida entre
# este retrato e a fila de comandos. $true = recusado (a resposta ja saiu).
function Test-RecusaGuardada {
    param($Ctx, [string]$Comando)
    $n = [int]$E.EmCurso
    if ($n -lt 1) { return $false }
    Send-Json $Ctx @{ erro = (Get-TextoRecusaComando -Comando $Comando -EmCurso $n) } 409
    return $true
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
        $corpo = [IO.File]::ReadAllBytes($estaticos[$rota])
        # index.html sai com data-tema no <html>: abre no tema certo, sem flash.
        if ($ext -eq '.html') { $corpo = Add-TemaNoHtml -Html ([Text.Encoding]::UTF8.GetString($corpo)) -Tema (Read-Tema -Caminho $arquivos.Tema) }
        Send-Resposta $Ctx 200 $tipo $corpo @{ 'Content-Security-Policy' = "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'" }
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
        # Tema: so preferencia visual. O listener grava direto (arquivo pequeno,
        # sem hardware, sem fila); a sessao.json continua so do worker.
        'GET /api/tema' { Send-Json $Ctx @{ tema = (Read-Tema -Caminho $arquivos.Tema) } }
        'PUT /api/tema' {
            $b = Read-Corpo $Ctx
            try { $v = Save-Tema -Caminho $arquivos.Tema -Valor ([string]$b.tema) } catch { Send-Json $Ctx @{ erro = $_.Exception.Message } 400; return }
            Send-Json $Ctx @{ ok = $true; tema = $v }
        }
        'POST /api/senha' { if (Test-RecusaGuardada $Ctx 'trocar-senha') { return }; $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'senha'; senha = [string]$b.senha } -Sempre }
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
            if (Test-RecusaGuardada $Ctx 'salvar-sessao') { return }
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
            if (Test-RecusaGuardada $Ctx 'salvar-sessao') { return }
            $b = Read-Corpo $Ctx
            $s = Read-SessaoDoDisco
            if ($null -eq $s -or $null -eq $s.Placa -or @(Test-SessaoPorCampo $s).Count -gt 0) { Send-Json $Ctx @{ erro = 'A sessão ainda não está completa: escolha a placa de rede e corrija os campos marcados.' } 409; return }
            Add-Comando $Ctx @{ tipo = 'sessao-concluir'; montarFila = [bool]$b.montarFila }
        }
        'POST /api/sessao/refazer' {
            if (Test-RecusaGuardada $Ctx 'refazer-sessao') { return }
            $est = Get-EstadoPublicado
            if ($null -ne $est -and [string]$est.fase -in @('configurando', 'decisao', 'escolher')) { Send-Json $Ctx @{ erro = 'Termine a câmera atual antes de refazer o passo a passo.' } 409; return }
            Add-Comando $Ctx @{ tipo = 'sessao-refazer' }
        }
        'POST /api/fila' {
            if (Test-RecusaGuardada $Ctx 'nova-fila') { return }
            $b = Read-Corpo $Ctx
            Add-Comando $Ctx @{ tipo = 'fila'; inicio = $b.inicio; fim = $b.fim; local = $b.local; rack = $b.rack; andar = $b.andar }
        }
        # Sem IP = procurar agora (passa); com IP = retomada serial, guardada.
        'POST /api/fila/conectada' { $b = Read-Corpo $Ctx; if (([string]$b.ip).Trim() -and (Test-RecusaGuardada $Ctx 'retomar')) { return }; Add-Comando $Ctx @{ tipo = 'conectada'; porta = $b.porta; canal = $b.canal; ip = $b.ip } }
        # -Sempre: desligar o vigia no meio de uma configuracao tem que ser
        # aceito (vale ao terminar, antes do proximo tique).
        'POST /api/vigia' {
            $b = Read-Corpo $Ctx
            Add-Comando $Ctx @{ tipo = 'vigia'; ligado = [bool]$b.ligado; porta = [string]$b.porta; canal = [string]$b.canal; broadcast = [bool]$b.broadcast } -Sempre
        }
        # Decisao por MAC (sem MAC: 'encerrar' = encerrar a fila; as outras
        # acoes valem para a retomada manual ou a primeira camera em decisao).
        'POST /api/decisao'    { $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'decisao'; mac = [string]$b.mac; acao = [string]$b.acao } }
        # Porta e canal do cartao, editaveis ate a conferencia terminar.
        'POST /api/camera'     { $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'camera'; mac = [string]$b.mac; porta = [string]$b.porta; canal = [string]$b.canal } }
        'GET /api/registro'    { Send-Json $Ctx @{ cameras = @((Read-RegistroAtual).Cameras); simulado = [bool]$E.Simular } }
        'GET /api/relatorio.csv' {
            $txt = ConvertTo-RelatorioCsv (Read-RegistroAtual)
            $bom = [byte[]](0xEF, 0xBB, 0xBF)
            $nome = 'relatorio-cameras-' + (Get-Date).ToString('yyyyMMdd-HHmm')
            if ($E.Simular) { $nome += '-SIMULADO' }
            Send-Resposta $Ctx 200 'text/csv; charset=utf-8' ([byte[]]($bom + [Text.Encoding]::UTF8.GetBytes($txt))) @{
                'Content-Disposition' = ('attachment; filename="' + $nome + '.csv"') }
        }
        'POST /api/sondar'     { if (Test-RecusaGuardada $Ctx 'ferramenta') { return }; $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'sondar'; ip = $b.ip } }
        'POST /api/verificar'  { if (Test-RecusaGuardada $Ctx 'ferramenta') { return }; Add-Comando $Ctx @{ tipo = 'verificar' } }
        'POST /api/descobrir'  { if (Test-RecusaGuardada $Ctx 'ferramenta') { return }; Add-Comando $Ctx @{ tipo = 'descobrir' } }
        'POST /api/rede/preparar'  { if (Test-RecusaGuardada $Ctx 'preparar-placa') { return }; Add-Comando $Ctx @{ tipo = 'rede-preparar' } }
        'POST /api/rede/restaurar' { if (Test-RecusaGuardada $Ctx 'restaurar-placa') { return }; Add-Comando $Ctx @{ tipo = 'rede-restaurar' } }
        'POST /api/simular'    { if (Test-RecusaGuardada $Ctx 'simular') { return }; $b = Read-Corpo $Ctx; Add-Comando $Ctx @{ tipo = 'simular'; ligado = [bool]$b.ligado; falharEm = [string]$b.falharEm } }
        'POST /api/internet/testar' { Add-Comando $Ctx @{ tipo = 'internet-testar' } }
        # Atualizar: so com o painel parado (nada em curso, vigia desligado),
        # com Administrador e com uma versao nova conhecida. 409 diz o motivo.
        'POST /api/atualizar' {
            if (Test-RecusaGuardada $Ctx 'atualizar') { return }
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
