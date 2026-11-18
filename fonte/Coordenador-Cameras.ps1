<#
    Coordenador-Cameras.ps1
    Executa o que o orquestrador decide. O orquestrador (Orquestrador-
    Cameras.ps1) é puro: devolve estado e ações. O coordenador guarda o
    estado paralelo e executa as ações ('prender', 'soltar', 'despachar',
    'avisar', 'publicar') pelas dependências injetadas em Deps, para os
    testes (Testes-Coordenador.ps1) trocarem rede, placa e pool por falsas.
    Não executa nada ao carregar. Depende do Motor-Cameras.ps1 e do
    Orquestrador-Cameras.ps1 já carregados (dot-source no servidor e nos
    testes).

    DEPS (hashtable de scriptblocks, chamados com parâmetros nomeados)
      Prender   param($Mac, $Ip)            -> { Ok; Erro }
      Soltar    param($Mac, $Ip)            -> { Ok; Erro }
      Despachar param($Acao, $Camera, $Geracao, $Coord)
                (New-DepsPool liga ao pool: Start-DespachoCoordenador)
      Pingar, Descobrir, Agora              (usadas pelo laço do servidor)
    Dependência ausente só é erro quando alguém a chama.

    COORDENADOR (New-Coordenador)
      Estado          estado paralelo (New-EstadoParalelo)
      Deps            as dependências acima
      Jobs            job em curso por MAC (chave Get-ChaveMac)
      Eventos         ConcurrentQueue de eventos (fim de job etc.)
      AvisoGlobal     último aviso sem câmera (ou de câmera fora do estado)
      AvisosCamera    último aviso por MAC (chave Get-ChaveMac)
      PortaCanal      porta/canal escolhidos por câmera (chave Get-ChaveMac)
      Geracao         geração atual da senha da sessão
      GeracaoDespacho geração da senha usada no último despacho por MAC
      Presos          IP em que cada MAC foi preso (o 'soltar' usa o mesmo)
      Sujo            o estado mudou desde a última publicação
      Pool            New-PoolCameras (o servidor cria ao montar a fila)
      Trabalho        o que todo job recebe: Senha (só memória, nunca vai
                      para o estado publicado), Padroes, CaminhoRegistro,
                      Simular, FalharEm, EsperaSimuladaSeg { Portao;
                      Conferencia } (só em -Simular) e Local/Rack/Andar
      Progresso       último progresso por MAC { Etapa; Atual; Total;
                      Detalhe }, enquanto o job corre
      Dhip            'ok' ou 'sem-resposta' (o vigia sem DHIP põe
                      'sem-resposta'; vai para paralelo.dhip)

    EVENTOS (fila Eventos, enfileirados pelos jobs no pool)
      { Mac; Job; Tipo='log';       Texto; Cor; Quando }
      { Mac; Job; Tipo='progresso'; Etapa; Atual; Total; Detalhe; Quando }
      { Mac; Job; Tipo='fim';       Resultado (ou $null); Erro; Quando }
    Job = Id do job (o evento de um job que já saiu é ignorado).
#>

<#
    Coordenador novo. Deps: hashtable com os scriptblocks de cima; valor que
    não é scriptblock para aqui (erro de fiação, melhor na partida que no
    meio de uma câmera).
#>
function New-Coordenador {
    param(
        $Posicoes = @(),
        [int]$Max = 0,
        [Parameter(Mandatory = $true)]$Deps
    )

    if ($Deps -isnot [System.Collections.IDictionary]) { throw 'As dependências do coordenador devem vir numa hashtable.' }
    foreach ($k in @($Deps.Keys)) {
        if ($Deps[$k] -isnot [scriptblock]) { throw ('Dependência ' + $k + ' do coordenador não é um bloco de código.') }
    }

    return @{
        Estado          = (New-EstadoParalelo -Posicoes $Posicoes -Max $Max)
        Deps            = $Deps
        Jobs            = @{}
        Eventos         = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        AvisoGlobal     = ''
        AvisosCamera    = @{}
        PortaCanal      = @{}
        Geracao         = 0
        GeracaoDespacho = @{}
        Presos          = @{}
        Sujo            = $true
        Pool            = $null
        Trabalho        = @{
            Senha = ''; Padroes = $null; CaminhoRegistro = ''; Simular = $false; FalharEm = ''
            EsperaSimuladaSeg = @{ Portao = 1; Conferencia = 4 }
            Local = ''; Rack = ''; Andar = ''
        }
        Progresso       = @{}
        Dhip            = 'ok'
    }
}

# Scriptblock de uma dependência; ausente é erro de programação.
function Get-DepCoordenador {
    param([Parameter(Mandatory = $true)]$Coord, [Parameter(Mandatory = $true)][string]$Nome)
    $sb = $null
    if ($Coord.Deps.Contains($Nome)) { $sb = $Coord.Deps[$Nome] }
    if ($null -eq $sb) { throw ('Dependência ausente no coordenador: ' + $Nome + '.') }
    return $sb
}

# Câmera do estado pelo MAC (qualquer grafia), ou $null.
function Get-CameraCoordenador {
    param([Parameter(Mandatory = $true)]$Coord, $Mac)
    $chave = Get-ChaveMac $Mac
    if ($chave -eq '') { return $null }
    foreach ($c in @($Coord.Estado.Cameras)) { if ($null -ne $c -and (Get-ChaveMac $c.Mac) -eq $chave) { return $c } }
    return $null
}

# Último objeto de uma saída de dependência (o scriptblock pode emitir mais
# de um), com Ok e Erro garantidos.
function ConvertTo-RespostaDep {
    param($Saida)
    $r = @($Saida) | Select-Object -Last 1
    if ($null -eq $r) { return @{ Ok = $false; Erro = '' } }
    return @{ Ok = [bool]$r.Ok; Erro = [string]$r.Erro }
}

# 'avisar': câmera do estado -> aviso dela; sem MAC ou fora do estado -> global.
function Set-AvisoCoordenador {
    param([Parameter(Mandatory = $true)]$Coord, $Mac, [string]$Texto)
    $camera = Get-CameraCoordenador -Coord $Coord -Mac $Mac
    if ($null -ne $camera) { $Coord.AvisosCamera[(Get-ChaveMac $camera.Mac)] = $Texto }
    else { $Coord.AvisoGlobal = $Texto }
    $Coord.Sujo = $true
}

# Resultado sintético de falha para o Step-FimDoJob: o estado e as ações dele
# entram no coordenador, e as ações vão para o fim da fila em execução.
function Add-FalhaCoordenador {
    param($Coord, $Fila, $Mac, [string]$Etapa, [string]$Falhou, [string]$Erro)
    $res = @{ Ok = $false; Etapa = $Etapa; Falhou = $Falhou; Erro = $Erro }
    $passo = Step-FimDoJob -Estado $Coord.Estado -Mac $Mac -Resultado $res -Geracao ([int]$Coord.Geracao)
    $Coord.Estado = $passo.Estado
    foreach ($n in @($passo.Acoes)) { if ($null -ne $n) { $Fila.Add($n) } }
    $Coord.Sujo = $true
}

<#
    Invoke-AcoesCoordenador: executa as ações de um Step-* em ordem. Quem
    chama já pôs o Estado do Step em Coord.Estado.
      - prender: Deps.Prender(Mac, Ip). Ok guarda o IP em Presos. Falha
        (Ok falso ou exceção) não despacha a câmera e entra no Step-FimDoJob
        como { Ok=$false; Falhou='portao'; Erro } (R6: decisão daquela
        câmera, não volta à espera); as ações dele ('soltar') são
        executadas no fim da mesma chamada;
      - soltar: Deps.Soltar(Mac, Ip), com o IP em que a câmera foi presa (ou
        o de origem dela). Falha vira aviso da câmera;
      - despachar: Deps.Despachar(Acao, Camera do estado, Geracao atual,
        Coord), e a geração fica em GeracaoDespacho. Câmera fora do estado é erro de
        programação. Exceção vira falha da câmera pelo Step-FimDoJob
        (portão, ou conferência), com a última etapa feita;
      - avisar: Set-AvisoCoordenador;
      - publicar: Sujo.
    Tipo desconhecido para aqui.
#>
function Invoke-AcoesCoordenador {
    param([Parameter(Mandatory = $true)]$Coord, $Acoes = @())

    $fila = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in @($Acoes)) { if ($null -ne $a) { $fila.Add($a) } }
    $naoPresos = @{}

    for ($i = 0; $i -lt $fila.Count; $i++) {
        $a = $fila[$i]
        $tipo = [string]$a.Tipo
        $chave = Get-ChaveMac $a.Mac

        if ($tipo -eq 'prender') {
            $sb = Get-DepCoordenador -Coord $Coord -Nome 'Prender'
            try { $r = ConvertTo-RespostaDep (& $sb -Mac ([string]$a.Mac) -Ip ([string]$a.Ip)) }
            catch { $r = @{ Ok = $false; Erro = $_.Exception.Message } }
            if ($r.Ok) {
                $Coord.Presos[$chave] = [string]$a.Ip
                continue
            }
            $erro = $r.Erro
            if ([string]::IsNullOrWhiteSpace($erro)) { $erro = 'Não deu para prender a câmera no IP ' + [string]$a.Ip + '.' }
            $naoPresos[$chave] = $true
            Add-FalhaCoordenador -Coord $Coord -Fila $fila -Mac $a.Mac -Etapa '' -Falhou 'portao' -Erro $erro
        }
        elseif ($tipo -eq 'soltar') {
            $sb = Get-DepCoordenador -Coord $Coord -Nome 'Soltar'
            $ip = ''
            if ($Coord.Presos.ContainsKey($chave)) { $ip = [string]$Coord.Presos[$chave] }
            else {
                $camera = Get-CameraCoordenador -Coord $Coord -Mac $a.Mac
                if ($null -ne $camera) { $ip = [string]$camera.IpOrigem }
            }
            try { $r = ConvertTo-RespostaDep (& $sb -Mac ([string]$a.Mac) -Ip $ip) }
            catch { $r = @{ Ok = $false; Erro = $_.Exception.Message } }
            $Coord.Presos.Remove($chave)
            if (-not $r.Ok) {
                Set-AvisoCoordenador -Coord $Coord -Mac $a.Mac -Texto ('Não deu para soltar a câmera do IP ' + $ip + ': ' + $r.Erro)
            }
        }
        elseif ($tipo -eq 'despachar') {
            $sb = Get-DepCoordenador -Coord $Coord -Nome 'Despachar'
            if ($naoPresos.ContainsKey($chave)) { continue }
            $camera = Get-CameraCoordenador -Coord $Coord -Mac $a.Mac
            if ($null -eq $camera) { throw ('Despacho de câmera fora do estado: ' + [string]$a.Mac + '.') }
            $geracao = [int]$Coord.Geracao
            $Coord.GeracaoDespacho[$chave] = $geracao
            try { $null = & $sb -Acao $a -Camera $camera -Geracao $geracao -Coord $Coord }
            catch {
                $falhou = 'conferencia'
                if ([string]$a.AteEtapa -eq 'rede') { $falhou = 'portao' }
                Add-FalhaCoordenador -Coord $Coord -Fila $fila -Mac $a.Mac -Etapa ([string]$camera.Etapa) -Falhou $falhou `
                    -Erro ('Não deu para começar o trabalho da câmera: ' + $_.Exception.Message)
            }
        }
        elseif ($tipo -eq 'avisar') {
            Set-AvisoCoordenador -Coord $Coord -Mac $a.Mac -Texto ([string]$a.Texto)
        }
        elseif ($tipo -eq 'publicar') {
            $Coord.Sujo = $true
        }
        else {
            throw ('Ação desconhecida do orquestrador: ' + $tipo + '.')
        }
    }
}

<#
    Item de Find-CamerasNaRede (ou resposta de ConvertFrom-RespostaDhip) no
    formato de achado do orquestrador: { Mac, Serial, Modelo, Ip, HttpPort,
    Init, Marca }. MAC com dois-pontos, em maiúscula (AA:00:00:00:00:01);
    Init como veio (já normalizado pelo motor; ausente = -1); Marca =
    Fabricante da resposta DHIP, ou vazia (o item do Find-CamerasNaRede não
    traz o fabricante, e marca vazia conta como família DHIP).
#>
function ConvertTo-AchadoParalelo {
    param([Parameter(Mandatory = $true, Position = 0)]$Item)

    $mac = Get-MacNormalizado ([string](Get-PropriedadeOuVazio $Item 'Mac' ''))
    if ($mac.Length -eq 12) { $mac = (Format-Mac $mac).ToUpperInvariant() }

    $porta = 0
    if (-not [int]::TryParse([string](Get-PropriedadeOuVazio $Item 'HttpPort' ''), [ref]$porta) -or $porta -le 0) { $porta = 80 }
    $init = 0
    if (-not [int]::TryParse([string](Get-PropriedadeOuVazio $Item 'Init' ''), [ref]$init)) { $init = -1 }

    $marca = [string](Get-PropriedadeOuVazio $Item 'Fabricante' '')
    if ($marca -eq '') { $marca = [string](Get-PropriedadeOuVazio $Item 'Marca' '') }

    return @{
        Mac = $mac; Serial = [string](Get-PropriedadeOuVazio $Item 'Serial' ''); Modelo = [string](Get-PropriedadeOuVazio $Item 'Modelo' '')
        Ip = [string](Get-PropriedadeOuVazio $Item 'Ip' ''); HttpPort = $porta; Init = $init; Marca = $marca.Trim()
    }
}

# ------------------------------------------------------------- deps da placa

<#
    Dependências Prender e Soltar ligadas à placa escolhida. Os scriptblocks
    levam IfIndex, rastro e -Simular no próprio texto e chamam
    Invoke-PrenderPlaca / Invoke-SoltarPlaca no escopo de quem os executa
    (no servidor, o worker; nos testes, o bloco com as funções falsas).
#>
function New-DepsPlaca {
    param(
        [Parameter(Mandatory = $true)][int]$IfIndex,
        [Parameter(Mandatory = $true)][string]$CaminhoRastro,
        [switch]$Simular
    )

    $textoSimular = '$false'
    if ($Simular) { $textoSimular = '$true' }
    $resto = ' -IfIndex ' + $IfIndex + " -CaminhoRastro '" + $CaminhoRastro.Replace("'", "''") + "' -Simular:" + $textoSimular
    return @{
        Prender = [scriptblock]::Create('param($Mac, $Ip) Invoke-PrenderPlaca -Mac $Mac -Ip $Ip' + $resto)
        Soltar  = [scriptblock]::Create('param($Mac, $Ip) Invoke-SoltarPlaca -Mac $Mac -Ip $Ip' + $resto)
    }
}

<#
    Prende o MAC no IP (o portão): se o IP está fora das faixas da placa, a
    placa ganha antes um IP temporário na rede dele (Add-IpTemporarioPlaca,
    rastro mesclado); depois a entrada Permanent IP -> MAC
    (Set-VizinhoEstatico) e o vizinho no rastro (Merge-SessaoPlaca +
    Save-JsonAtomico), para o encerrar tirar. Vizinho que não entra no
    rastro sai da tabela, e a prisão falha. -Simular só loga. { Ok; Erro }.
#>
function Invoke-PrenderPlaca {
    param([string]$Mac, [string]$Ip, [int]$IfIndex, [string]$CaminhoRastro, [switch]$Simular)

    if ($Simular) {
        Write-Log ('  [simular] prenderia ' + $Ip + ' -> ' + (Format-MacVizinho $Mac) + ' na placa (vizinho estático)') 'DarkGray'
        return [pscustomobject]@{ Ok = $true; Erro = '' }
    }

    try {
        if (-not (Test-IpAlcancavel -Ip $Ip -Locais @(Get-FaixasDaPlaca -IfIndex $IfIndex))) {
            $rastro = Read-JsonArquivo $CaminhoRastro
            $nome = ''
            if ($null -ne $rastro) { $nome = [string]$rastro.Placa }
            $t = Add-IpTemporarioPlaca -IpCamera $Ip -Placa @{ IfIndex = $IfIndex; Nome = $nome }
            if ($null -ne $t.Sessao) {
                Save-JsonAtomico -Caminho $CaminhoRastro -Objeto (Merge-SessaoPlaca -Antiga (Read-JsonArquivo $CaminhoRastro) -Nova $t.Sessao)
            }
            if (-not $t.Ok) { return [pscustomobject]@{ Ok = $false; Erro = ('Não deu para dar à placa um IP na rede de ' + $Ip + '. Veja o log.') } }
        }

        $v = Set-VizinhoEstatico -IfIndex $IfIndex -Ip $Ip -Mac $Mac
        if (-not $v.Ok) { return [pscustomobject]@{ Ok = $false; Erro = [string]$v.Erro } }

        try {
            $antigo = Read-JsonArquivo $CaminhoRastro
            $nome = ''
            if ($null -ne $antigo) { $nome = [string]$antigo.Placa }
            $novo = @{
                Quando = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Placa = $nome; IfIndex = $IfIndex; Antes = $null
                Adicionados = @(); Rotas = @(); Vizinhos = @(@{ Ip = $Ip; Mac = (Format-Mac $Mac).ToUpperInvariant() })
                Devolvidos = @(); Rota = $null; Dns = @(); Mexida = $false
            }
            Save-JsonAtomico -Caminho $CaminhoRastro -Objeto (Merge-SessaoPlaca -Antiga $antigo -Nova $novo)
        } catch {
            $null = Remove-VizinhoEstatico -IfIndex $IfIndex -Ip $Ip
            return [pscustomobject]@{ Ok = $false; Erro = ('O vizinho estático de ' + $Ip + ' não entrou no rastro da placa e foi tirado: ' + $_.Exception.Message) }
        }
        Write-Log ('  ' + $Ip + ' preso em ' + (Format-MacVizinho $Mac) + ' (vizinho estático)') 'DarkGray'
        return [pscustomobject]@{ Ok = $true; Erro = '' }
    } catch {
        return [pscustomobject]@{ Ok = $false; Erro = $_.Exception.Message }
    }
}

<#
    Solta o IP: tira a entrada da tabela de vizinhos (Remove-VizinhoEstatico)
    e, se saiu, o vizinho do rastro; tira também o IP temporário que a placa
    ganhou para a origem (Remove-IpTemporarioPlaca, guiado pelo rastro). O
    rastro é regravado inteiro (sem Merge, que somaria de volta o que saiu).
    O que não sai fica no rastro para o encerrar. -Simular só loga.
    { Ok; Erro } com os erros juntos.
#>
function Invoke-SoltarPlaca {
    param([string]$Mac, [string]$Ip, [int]$IfIndex, [string]$CaminhoRastro, [switch]$Simular)

    if ($Simular) {
        Write-Log ('  [simular] soltaria ' + $Ip + ' (vizinho estático de ' + (Format-MacVizinho $Mac) + ')') 'DarkGray'
        return [pscustomobject]@{ Ok = $true; Erro = '' }
    }

    $erros = @()
    try {
        $v = Remove-VizinhoEstatico -IfIndex $IfIndex -Ip $Ip
        if (-not $v.Ok) { $erros += [string]$v.Erro }

        $antigo = Read-JsonArquivo $CaminhoRastro
        if ($null -ne $antigo) {
            $rastro = Merge-SessaoPlaca -Antiga $antigo -Nova $antigo
            if ($v.Ok) { $rastro.Vizinhos = @(@($rastro.Vizinhos) | Where-Object { [string]$_.Ip -ne $Ip }) }
            $t = Remove-IpTemporarioPlaca -Sessao $rastro -IpCamera $Ip
            if (-not $t.Ok) { $erros += [string]$t.Erro }
            if ($null -ne $t.Sessao) { $rastro = $t.Sessao }
            Save-JsonAtomico -Caminho $CaminhoRastro -Objeto $rastro
        }
    } catch {
        $erros += $_.Exception.Message
    }

    if ($erros.Count -gt 0) { return [pscustomobject]@{ Ok = $false; Erro = ($erros -join ' ') } }
    Write-Log ('  ' + $Ip + ' solto (vizinho estático de ' + (Format-MacVizinho $Mac) + ')') 'DarkGray'
    return [pscustomobject]@{ Ok = $true; Erro = '' }
}

# ------------------------------------------------------------- pool e jobs

# Motor ao lado deste arquivo: cada runspace do pool faz dot-source dele.
$script:CaminhoMotorCoordenador = Join-Path $PSScriptRoot 'Motor-Cameras.ps1'

<#
    Pool dos jobs de câmera: RunspacePool de 1 a Max runspaces, com Max = o
    número de posições da fila (Q2: sem limite próprio; quem limita é o
    Max do orquestrador). Devolve { Pool; Max; CaminhoMotor }.
#>
function New-PoolCameras {
    param([Parameter(Mandatory = $true)][int]$Max, [string]$CaminhoMotor = '')

    if ($Max -lt 1) { $Max = 1 }
    if ([string]::IsNullOrWhiteSpace($CaminhoMotor)) { $CaminhoMotor = $script:CaminhoMotorCoordenador }
    if (-not (Test-Path -LiteralPath $CaminhoMotor)) { throw ('Motor não achado para o pool de câmeras: ' + $CaminhoMotor + '.') }

    $pool = [runspacefactory]::CreateRunspacePool(1, $Max)
    $pool.Open()
    return @{ Pool = $pool; Max = $Max; CaminhoMotor = $CaminhoMotor }
}

# Fecha o pool (sem pool, nada). Job ainda rodando é parado pelo Close.
function Close-PoolCameras {
    param($Pool)
    if ($null -eq $Pool -or $null -eq $Pool.Pool) { return }
    try { $Pool.Pool.Close() } catch { }
    try { $Pool.Pool.Dispose() } catch { }
}

<#
    Contexto do Invoke-ConfiguracaoCamera para um despacho: a câmera do
    estado (IpOrigem, HttpPort, Mac, Serial), o Destino da ação, Local/Rack/
    Andar da fila e porta/canal do cartão. Objeto com propriedades (o motor
    lê HttpPort por PSObject.Properties).
#>
function New-ContextoJob {
    param([Parameter(Mandatory = $true)]$Camera, [Parameter(Mandatory = $true)]$Acao, $Fila = $null, $PortaCanal = $null)

    $porta = 0
    if (-not [int]::TryParse([string]$Camera.HttpPort, [ref]$porta) -or $porta -le 0) { $porta = 80 }
    $campo = {
        param($Origem, [string]$Nome)
        if ($null -eq $Origem) { return '' }
        return [string](Get-PropriedadeOuVazio $Origem $Nome '')
    }
    return [pscustomobject]@{
        IpOrigem = [string]$Camera.IpOrigem; HttpPort = $porta; Mac = [string]$Camera.Mac; Serial = [string]$Camera.Serial
        Destino  = [string]$Acao.Destino
        Local    = (& $campo $Fila 'Local'); Rack = (& $campo $Fila 'Rack'); Andar = (& $campo $Fila 'Andar')
        Porta    = (& $campo $PortaCanal 'Porta'); Canal = (& $campo $PortaCanal 'Canal')
    }
}

<#
    Corpo do job, rodado num runspace do pool (vai como texto: o runspace
    não enxerga as funções de quem despacha).
      - dot-source do motor uma vez por runspace (o pool reaproveita o
        runspace, e as funções ficam no escopo global dele);
      - Set-MotorLog sem arquivo e Set-MotorProgresso com sinks que
        enfileiram eventos com o MAC; a senha nunca vai num evento;
      - ConferirInit no portão, no real: Get-CamInitStatus na origem (a
        câmera já está presa) antes do motor. Não é de fábrica ->
        NaoDeFabrica, sem chamar o motor (R8). Sem resposta -> falha na
        inicialização, sem chamar o motor (o motor trataria uma câmera
        inicializada como retomada);
      - em -Simular, espera EsperaSimuladaSeg antes do motor (U1);
      - no finally, os sinks saem e vai o evento 'fim': Resultado (só os
        campos que o Step-FimDoJob lê) ou $null com o Erro da exceção.
#>
$script:ScriptJobCamera = {
    param($CaminhoMotor, $Eventos, [string]$JobId, [string]$Mac, $Contexto, $Padroes, [string]$Senha,
          [string]$CaminhoRegistro, [bool]$Simular, [string]$FalharEm, [string]$AteEtapa, [bool]$ConferirInit,
          [double]$EsperaSimuladaSeg)

    $ErrorActionPreference = 'Stop'
    $resultado = $null
    $erro = ''
    try {
        if (-not (Get-Command -Name 'Invoke-ConfiguracaoCamera' -CommandType Function -ErrorAction SilentlyContinue)) { . $CaminhoMotor }

        $fila = $Eventos
        $macJob = $Mac
        $id = $JobId
        Set-MotorLog -Sink ({
            param($Ts, $Msg, $Cor)
            $fila.Enqueue(@{ Mac = $macJob; Job = $id; Tipo = 'log'; Texto = [string]$Msg; Cor = [string]$Cor; Quando = [datetime]::Now })
        }.GetNewClosure())
        Set-MotorProgresso -Sink ({
            param($Etapa, $Detalhe, $Atual, $Total)
            $fila.Enqueue(@{ Mac = $macJob; Job = $id; Tipo = 'progresso'; Etapa = [string]$Etapa; Atual = [int]$Atual; Total = [int]$Total
                             Detalhe = [string]$Detalhe; Quando = [datetime]::Now })
        }.GetNewClosure())

        $fase = 'conferência'
        if ($AteEtapa -eq 'rede') { $fase = 'portão, até a rede' }
        Write-Log ('--- Câmera ' + $Mac + ': ' + $fase + ' ---') 'DarkCyan'

        if ($ConferirInit -and $AteEtapa -eq 'rede' -and -not $Simular) {
            $origem = [string]$Contexto.IpOrigem
            Set-CamPortaHttp -Ip $origem -Porta ([int]$Contexto.HttpPort)
            $st = Get-CamInitStatus -Ip $origem -Timeout 10
            if (-not $st.Ok) {
                $resultado = @{ Ok = $false; Etapa = ''; Falhou = 'inicializada'
                                Erro = ('A câmera presa em ' + $origem + ' não respondeu ao DevInit.getStatus.') }
                return
            }
            if ($st.Init -ne 1) {
                Write-Log ('  Câmera em ' + $origem + ' já inicializada (Init=' + $st.Init + '): não tocada.') 'Yellow'
                $resultado = @{ Ok = $false; Etapa = ''; Falhou = ''; Erro = ''; NaoDeFabrica = $true }
                return
            }
        }

        if ($Simular -and $EsperaSimuladaSeg -gt 0) { Start-Sleep -Milliseconds ([int]($EsperaSimuladaSeg * 1000)) }
        $falharEmJob = ''
        if ($Simular) { $falharEmJob = $FalharEm }
        $r = Invoke-ConfiguracaoCamera -Contexto $Contexto -Padroes $Padroes -Senha $Senha -CaminhoRegistro $CaminhoRegistro `
                                       -Simular:$Simular -FalharEm $falharEmJob -AteEtapa $AteEtapa
        $resultado = @{
            Ok = [bool]$r.Ok; Etapa = [string]$r.Etapa; Falhou = [string]$r.Falhou; Erro = [string]$r.Erro; Recusa = [bool]$r.Recusa
            LoginRecusado = [bool]$r.LoginRecusado; Bloqueada = [bool]$r.Bloqueada; MacTrocado = [bool]$r.MacTrocado
            MacLido = [string]$r.MacLido; NaoDeFabrica = $false; Mac = [string]$r.Mac; Ip = [string]$r.Ip
        }
    } catch {
        $erro = $_.Exception.Message
    } finally {
        try { Set-MotorLog; Set-MotorProgresso } catch { }
        $Eventos.Enqueue(@{ Mac = $Mac; Job = $JobId; Tipo = 'fim'; Resultado = $resultado; Erro = $erro; Quando = [datetime]::Now })
    }
}

<#
    Começa o job de uma câmera no pool. Camera = a do estado (R2), Acao = o
    'despachar' (AteEtapa 'rede' no portão, vazio na conferência), Contexto
    = New-ContextoJob. A senha vai só como parâmetro do runspace (memória).
    Devolve o registro do job { Id; Mac; Chave; PowerShell; Handle;
    Geracao; AteEtapa; Etapa (último progresso); Inicio }.
#>
function Start-JobCamera {
    param(
        [Parameter(Mandatory = $true)]$Pool,
        [Parameter(Mandatory = $true)]$Eventos,
        [Parameter(Mandatory = $true)]$Camera,
        [Parameter(Mandatory = $true)]$Acao,
        [Parameter(Mandatory = $true)]$Contexto,
        [string]$Senha = '',
        $Padroes = $null,
        [Parameter(Mandatory = $true)][string]$CaminhoRegistro,
        [switch]$Simular,
        [string]$FalharEm = '',
        [int]$Geracao = 0,
        [double]$EsperaSimuladaSeg = 0
    )

    $id = [guid]::NewGuid().ToString('N')
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $Pool.Pool
    $null = $ps.AddScript($script:ScriptJobCamera.ToString())
    $null = $ps.AddParameter('CaminhoMotor', [string]$Pool.CaminhoMotor).AddParameter('Eventos', $Eventos).AddParameter('JobId', $id)
    $null = $ps.AddParameter('Mac', [string]$Camera.Mac).AddParameter('Contexto', $Contexto).AddParameter('Padroes', $Padroes)
    $null = $ps.AddParameter('Senha', $Senha).AddParameter('CaminhoRegistro', $CaminhoRegistro).AddParameter('Simular', [bool]$Simular)
    $null = $ps.AddParameter('FalharEm', $FalharEm).AddParameter('AteEtapa', [string]$Acao.AteEtapa)
    $null = $ps.AddParameter('ConferirInit', [bool]$Camera.ConferirInit).AddParameter('EsperaSimuladaSeg', $EsperaSimuladaSeg)
    try { $handle = $ps.BeginInvoke() }
    catch { $ps.Dispose(); throw }

    return @{
        Id = $id; Mac = [string]$Camera.Mac; Chave = (Get-ChaveMac $Camera.Mac); PowerShell = $ps; Handle = $handle
        Geracao = $Geracao; AteEtapa = [string]$Acao.AteEtapa; Etapa = ''; Inicio = [datetime]::Now
    }
}

<#
    O 'despachar' ligado ao pool: monta o contexto (fila e porta/canal do
    coordenador), escolhe a espera simulada do portão ou da conferência e
    começa o job, guardado em Jobs. Sem pool, ou com job em curso para o
    MAC, estoura: o Invoke-AcoesCoordenador transforma em decisão da câmera.
#>
function Start-DespachoCoordenador {
    param([Parameter(Mandatory = $true)]$Coord, [Parameter(Mandatory = $true)]$Acao, [Parameter(Mandatory = $true)]$Camera, [int]$Geracao = 0)

    if ($null -eq $Coord.Pool) { throw 'O pool de câmeras não foi criado.' }
    $chave = Get-ChaveMac $Camera.Mac
    if ($Coord.Jobs.ContainsKey($chave)) { throw ('Já há um trabalho em curso para a câmera ' + [string]$Camera.Mac + '.') }

    $t = $Coord.Trabalho
    $pc = $null
    if ($Coord.PortaCanal.ContainsKey($chave)) { $pc = $Coord.PortaCanal[$chave] }
    $ctx = New-ContextoJob -Camera $Camera -Acao $Acao -Fila $t -PortaCanal $pc

    $espera = 0
    if ($null -ne $t.EsperaSimuladaSeg) {
        if ([string]$Acao.AteEtapa -eq 'rede') { $espera = [double]$t.EsperaSimuladaSeg.Portao } else { $espera = [double]$t.EsperaSimuladaSeg.Conferencia }
    }

    $job = Start-JobCamera -Pool $Coord.Pool -Eventos $Coord.Eventos -Camera $Camera -Acao $Acao -Contexto $ctx `
                           -Senha ([string]$t.Senha) -Padroes $t.Padroes -CaminhoRegistro ([string]$t.CaminhoRegistro) `
                           -Simular:([bool]$t.Simular) -FalharEm ([string]$t.FalharEm) -Geracao $Geracao -EsperaSimuladaSeg $espera
    $Coord.Jobs[$chave] = $job
    $Coord.Progresso[$chave] = @{ Etapa = ''; Atual = 0; Total = 0; Detalhe = '' }
    $Coord.Sujo = $true
}

# Deps que ligam o coordenador ao pool (o servidor junta com as da placa).
function New-DepsPool {
    return @{
        Despachar = {
            param($Acao, $Camera, $Geracao, $Coord)
            Start-DespachoCoordenador -Coord $Coord -Acao $Acao -Camera $Camera -Geracao ([int]$Geracao)
        }
    }
}

<#
    Fecha um job: sai de Jobs e de Progresso, EndInvoke/Dispose, e o
    resultado entra no Step-FimDoJob com a geração do despacho; as ações
    dele são executadas. Resultado $null (exceção no job, ou handle
    concluído sem 'fim') vira { Ok=$false; Etapa = a última feita;
    Falhou = etapa do último progresso (sem progresso: 'portao' ou
    'conferencia'); Erro = 'erro interno no job: ...' }.
#>
function Complete-JobCoordenador {
    param([Parameter(Mandatory = $true)]$Coord, [Parameter(Mandatory = $true)]$Job, $Resultado = $null, [string]$Erro = '')

    $Coord.Jobs.Remove($Job.Chave)
    $Coord.Progresso.Remove($Job.Chave)

    $erroPs = ''
    try { $null = $Job.PowerShell.EndInvoke($Job.Handle) } catch { $erroPs = $_.Exception.Message }
    try {
        if ($erroPs -eq '' -and $Job.PowerShell.Streams.Error.Count -gt 0) { $erroPs = [string]$Job.PowerShell.Streams.Error[0] }
    } catch { }
    try { $Job.PowerShell.Dispose() } catch { }

    if ($null -eq $Resultado) {
        $msg = $Erro
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $erroPs }
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = 'o job terminou sem resultado' }
        $falhou = [string]$Job.Etapa
        if ($falhou -eq '') { if ([string]$Job.AteEtapa -eq 'rede') { $falhou = 'portao' } else { $falhou = 'conferencia' } }
        $feita = ''
        $camera = Get-CameraCoordenador -Coord $Coord -Mac $Job.Mac
        if ($null -ne $camera) { $feita = [string]$camera.Etapa }
        $Resultado = @{ Ok = $false; Etapa = $feita; Falhou = $falhou; Erro = ('erro interno no job: ' + $msg) }
    }

    $passo = Step-FimDoJob -Estado $Coord.Estado -Mac $Job.Mac -Resultado $Resultado -Geracao ([int]$Job.Geracao)
    $Coord.Estado = $passo.Estado
    $Coord.Sujo = $true
    Invoke-AcoesCoordenador -Coord $Coord -Acoes $passo.Acoes
}

<#
    Drena a fila de eventos dos jobs, na ordem em que chegaram.
      - log: vai para -Log (param($Evento): Mac, Texto, Cor, Quando); o
        servidor manda para o log do painel e o arquivo, com o MAC curto;
      - progresso: guarda em Progresso e no job (a etapa do último
        progresso é a da falha se o job morrer);
      - fim: Complete-JobCoordenador com o resultado.
    Job com o handle concluído e sem 'fim' (o runspace quebrou antes do
    finally) vira o resultado sintético de falha. Os handles são lidos ANTES
    de drenar: o job enfileira o 'fim' antes de concluir, então um handle já
    concluído tem o 'fim' (se houver) na fila. -Observar recebe cada evento
    cru, antes de tratar (testes e diagnóstico). Evento de job que já saiu
    só vale como log.
#>
function Receive-EventosCoordenador {
    param([Parameter(Mandatory = $true)]$Coord, [scriptblock]$Log = $null, [scriptblock]$Observar = $null)

    $concluidos = @()
    foreach ($k in @($Coord.Jobs.Keys)) {
        $j = $Coord.Jobs[$k]
        if ($null -ne $j.Handle -and $j.Handle.IsCompleted) { $concluidos += $j }
    }

    $ev = $null
    while ($Coord.Eventos.TryDequeue([ref]$ev)) {
        if ($null -eq $ev) { continue }
        if ($null -ne $Observar) { try { & $Observar $ev } catch { } }
        $tipo = [string]$ev.Tipo
        $chave = Get-ChaveMac $ev.Mac
        $job = $null
        if ($Coord.Jobs.ContainsKey($chave) -and [string]$Coord.Jobs[$chave].Id -eq [string]$ev.Job) { $job = $Coord.Jobs[$chave] }

        if ($tipo -eq 'log') {
            if ($null -ne $Log) { try { & $Log $ev } catch { } }
        }
        elseif ($tipo -eq 'progresso') {
            if ($null -eq $job) { continue }
            $p = $Coord.Progresso[$chave]
            if ($null -eq $p) { $p = @{ Etapa = ''; Atual = 0; Total = 0; Detalhe = '' } }
            if ([string]$ev.Etapa -ne '') { $p.Etapa = [string]$ev.Etapa; $job.Etapa = [string]$ev.Etapa }
            $p.Atual = [int]$ev.Atual; $p.Total = [int]$ev.Total; $p.Detalhe = [string]$ev.Detalhe
            $Coord.Progresso[$chave] = $p
            $Coord.Sujo = $true
        }
        elseif ($tipo -eq 'fim') {
            if ($null -eq $job) { continue }
            Complete-JobCoordenador -Coord $Coord -Job $job -Resultado $ev.Resultado -Erro ([string]$ev.Erro)
        }
    }

    foreach ($j in $concluidos) {
        if ($Coord.Jobs.ContainsKey($j.Chave) -and [string]$Coord.Jobs[$j.Chave].Id -eq [string]$j.Id) {
            Complete-JobCoordenador -Coord $Coord -Job $j
        }
    }
}

# ---------------------------------------------------------- estado publicado

# Falha do estado (Step-FimDoJob) no formato publicado, ou $null.
function ConvertTo-FalhaPublicada {
    param($Falha)
    if ($null -eq $Falha) { return $null }
    return [ordered]@{
        etapa = [string]$Falha.Etapa; erro = [string]$Falha.Erro; recusa = [bool]$Falha.Recusa
        loginRecusado = [bool]$Falha.LoginRecusado; bloqueada = [bool]$Falha.Bloqueada; geracao = [int]$Falha.Geracao
    }
}

<#
    Estado publicado do paralelo: o contrato da F6 (plano docs/plans/
    2026-11-18-frente-servidor-plan.md, Task 4). Não mudar sem atualizar o
    plano e o mapa. A senha nunca entra.
      cameras    na ordem do estado: { mac, serial, modelo, ipOrigem,
                 indice (posição da câmera em filaItens, base 0; -1 sem
                 posição), posicao (número da posição; 0 sem posição),
                 destino (IP da posição), porta, canal (do cartão), fase,
                 etapa (a do último progresso enquanto o job corre; senão a
                 última feita), progresso { atual, total } (só com total;
                 senão null), trabalho (detalhe do progresso, ou o que a
                 câmera está fazendo; vazio fora de portão/conferindo),
                 aviso (último aviso da câmera), falha { etapa, erro,
                 recusa, loginRecusado, bloqueada, geracao } ou null }
      portao     MAC da câmera no portão, ou null
      paralelo   { max, admitindo, dhip: 'ok'|'sem-resposta', emCurso
                 (câmeras em portão + conferindo) }
      filaItens  as posições, no formato de fila.itens ({ Posicao, Ip,
                 Estado, Motivo, Mac })
    Campos legados, para a UI atual seguir até a F6:
      fase       'configurando' com câmera em curso; 'decisao' com câmera
                 em decisão; 'concluida' sem posição pendente ou reservada;
                 'encerrada' sem admitir; senão 'fila' (nessa ordem)
      atual, camera, falha
                 da primeira câmera em decisão, senão da primeira em curso:
                 atual = indice dela (-1 sem câmera), camera = o contexto do
                 job (New-ContextoJob: IpOrigem, Destino, Mac, Porta...),
                 falha = a falha dela; sem câmera, -1, null e null.
#>
function ConvertTo-EstadoPublicadoParalelo {
    param([Parameter(Mandatory = $true)]$Coord)

    $e = $Coord.Estado

    $itens = New-Object 'System.Collections.Generic.List[object]'
    $indicePorNumero = @{}
    $livres = 0
    foreach ($p in @($e.Posicoes)) {
        if ($null -eq $p) { continue }
        $indicePorNumero[[int]$p.Posicao] = $itens.Count
        $itens.Add([ordered]@{ Posicao = [int]$p.Posicao; Ip = [string]$p.Ip; Estado = [string]$p.Estado; Motivo = [string]$p.Motivo; Mac = [string]$p.Mac })
        if ([string]$p.Estado -eq 'pendente' -or [string]$p.Estado -eq 'reservada') { $livres++ }
    }

    $cameras = New-Object 'System.Collections.Generic.List[object]'
    $emCurso = 0
    $alvoDecisao = $null
    $alvoCurso = $null
    foreach ($c in @($e.Cameras)) {
        if ($null -eq $c) { continue }
        $chave = Get-ChaveMac $c.Mac
        $fase = [string]$c.Fase

        $numero = [int]$c.Indice
        $indice = -1
        $destino = ''
        if ($numero -gt 0 -and $indicePorNumero.ContainsKey($numero)) {
            $indice = [int]$indicePorNumero[$numero]
            $destino = [string]$itens[$indice].Ip
        }

        $pc = $null
        if ($Coord.PortaCanal.ContainsKey($chave)) { $pc = $Coord.PortaCanal[$chave] }
        $aviso = ''
        if ($Coord.AvisosCamera.ContainsKey($chave)) { $aviso = [string]$Coord.AvisosCamera[$chave] }

        $etapa = [string]$c.Etapa
        $progresso = $null
        $trabalho = ''
        $curso = ($fase -eq 'portao' -or $fase -eq 'conferindo')
        if ($curso) {
            $emCurso++
            if ($fase -eq 'portao') { $trabalho = 'Gravando a rede da câmera para ' + $destino }
            else { $trabalho = 'Conferindo a câmera em ' + $destino }
            $prog = $null
            if ($Coord.Progresso.ContainsKey($chave)) { $prog = $Coord.Progresso[$chave] }
            if ($null -ne $prog) {
                if ([string]$prog.Etapa -ne '') { $etapa = [string]$prog.Etapa }
                if ([string]$prog.Detalhe -ne '') { $trabalho = [string]$prog.Detalhe }
                if ([int]$prog.Total -gt 0) { $progresso = [ordered]@{ atual = [int]$prog.Atual; total = [int]$prog.Total } }
            }
        }

        $item = @{ Camera = $c; Indice = $indice; Destino = $destino; PortaCanal = $pc }
        if ($fase -eq 'decisao' -and $null -eq $alvoDecisao) { $alvoDecisao = $item }
        if ($curso -and $null -eq $alvoCurso) { $alvoCurso = $item }

        $cameras.Add([ordered]@{
            mac = [string]$c.Mac; serial = [string]$c.Serial; modelo = [string]$c.Modelo; ipOrigem = [string]$c.IpOrigem
            indice = $indice; posicao = $numero; destino = $destino
            porta = [string](Get-PropriedadeOuVazio $pc 'Porta' ''); canal = [string](Get-PropriedadeOuVazio $pc 'Canal' '')
            fase = $fase; etapa = $etapa; progresso = $progresso; trabalho = $trabalho; aviso = $aviso
            falha = (ConvertTo-FalhaPublicada $c.Falha)
        })
    }

    $faseLegada = 'fila'
    if ($emCurso -gt 0) { $faseLegada = 'configurando' }
    elseif ($null -ne $alvoDecisao) { $faseLegada = 'decisao' }
    elseif ($livres -eq 0) { $faseLegada = 'concluida' }
    elseif (-not [bool]$e.Admitindo) { $faseLegada = 'encerrada' }

    $alvo = $alvoDecisao
    if ($null -eq $alvo) { $alvo = $alvoCurso }
    $atual = -1
    $cameraLegada = $null
    $falhaLegada = $null
    if ($null -ne $alvo) {
        $atual = [int]$alvo.Indice
        $cameraLegada = New-ContextoJob -Camera $alvo.Camera -Acao @{ Destino = $alvo.Destino } -Fila $Coord.Trabalho -PortaCanal $alvo.PortaCanal
        $falhaLegada = ConvertTo-FalhaPublicada $alvo.Camera.Falha
    }

    $portao = $null
    if (-not [string]::IsNullOrEmpty([string]$e.Portao)) { $portao = [string]$e.Portao }
    $dhip = 'ok'
    if ([string]$Coord.Dhip -eq 'sem-resposta') { $dhip = 'sem-resposta' }

    return [ordered]@{
        cameras   = $cameras.ToArray()
        portao    = $portao
        paralelo  = [ordered]@{ max = [int]$e.Max; admitindo = [bool]$e.Admitindo; dhip = $dhip; emCurso = $emCurso }
        filaItens = $itens.ToArray()
        fase      = $faseLegada
        atual     = $atual
        camera    = $cameraLegada
        falha     = $falhaLegada
    }
}
