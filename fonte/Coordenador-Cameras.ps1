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
      Despachar param($Acao, $Camera, $Geracao)  (a Task 3 liga ao pool)
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
      - despachar: Deps.Despachar(Acao, Camera do estado, Geracao atual), e
        a geração fica em GeracaoDespacho. Câmera fora do estado é erro de
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
            try { $null = & $sb -Acao $a -Camera $camera -Geracao $geracao }
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
