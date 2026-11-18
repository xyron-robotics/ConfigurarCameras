<#
    Testes-Coordenador.ps1
    Testes do Coordenador-Cameras.ps1 sem camera, rede, placa nem disco real.

    O coordenador executa as acoes que o orquestrador decide (prender,
    soltar, despachar, avisar, publicar). Tudo que toca o mundo entra por
    Deps, e aqui as Deps sao falsas que so anotam as chamadas. Cobre:
      - estado inicial (estado paralelo, jobs, fila de eventos, avisos);
      - execucao das acoes em ordem (prender -> despachar);
      - prender falho -> decisao na etapa 'portao', sem despachar;
      - soltar no fim do portao, com o IP em que a camera foi presa;
      - roteamento do 'avisar' (camera do estado x global) e 'publicar';
      - ConvertTo-AchadoParalelo com a fixture de duas cameras de fabrica
        no mesmo IP;
      - New-DepsPlaca com as funcoes pequenas do motor trocadas por falsas
        (tabela de vizinhos, IP da placa) e o rastro numa pasta temporaria.

    Valores ficticios: MAC AA:00:00:00:00:0x, serial SIM-x, IPs de
    documentacao (192.0.2.x) e a faixa de fabrica 192.168.1.108.

    Uso:
        .\Testes-Coordenador.ps1
    Sai com codigo 1 se algum teste falhar.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$raiz = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($raiz)) { $raiz = (Get-Location).Path }

. (Join-Path $raiz 'Motor-Cameras.ps1')
. (Join-Path $raiz 'Orquestrador-Cameras.ps1')
. (Join-Path $raiz 'Coordenador-Cameras.ps1')

# Log do motor vai para uma lista, nao para a tela.
$script:logs = New-Object 'System.Collections.Generic.List[string]'
Set-MotorLog -Sink { param($ts, $Msg, $Cor, $Ctx) $script:logs.Add([string]$Msg) }

# ------------------------------------------------------------------ arcabouco

$script:Ok = 0
$script:Falhou = 0
$script:Falhas = @()

function T {
    param([string]$Nome, [scriptblock]$Bloco)
    try {
        & $Bloco
        $script:Ok++
        Write-Host ("  ok     " + $Nome) -ForegroundColor DarkGreen
    } catch {
        $script:Falhou++
        $script:Falhas += ($Nome + ' :: ' + $_.Exception.Message)
        Write-Host ("  FALHOU " + $Nome) -ForegroundColor Red
        Write-Host ("           " + $_.Exception.Message) -ForegroundColor DarkGray
    }
}

function Assert-Igual {
    param($Esperado, $Obtido, [string]$Que = 'valor')
    if ([string]$Esperado -ne [string]$Obtido) {
        throw ($Que + ': esperado <' + $Esperado + '> obtido <' + $Obtido + '>')
    }
}

function Assert-Verdade {
    param($Valor, [string]$Que = 'condicao')
    if (-not $Valor) { throw ($Que + ' deveria ser verdadeiro') }
}

function Assert-Falso {
    param($Valor, [string]$Que = 'condicao')
    if ($Valor) { throw ($Que + ' deveria ser falso') }
}

# Posicoes no formato de New-FilaDeFaixa (Motor-Cameras.ps1).
function New-PosicoesTeste {
    param([int]$N = 3)
    $l = @()
    for ($i = 1; $i -le $N; $i++) {
        $l += [pscustomobject]@{ Posicao = $i; Ip = ('192.0.2.' + (10 + $i)); Estado = 'pendente'; Motivo = ''; Mac = '' }
    }
    return ,$l
}

# Achado DHIP de fabrica no IP de fabrica.
function New-AchadoTeste {
    param([int]$N)
    return @{ Mac = ('AA:00:00:00:00:0' + $N); Serial = ('SIM-' + $N); Modelo = 'IPC-EXEMPLO'; Ip = '192.168.1.108'
              HttpPort = 80; Init = 1; Marca = 'Intelbras' }
}

# Deps falsas: cada chamada vira uma linha em $script:chamadas. $script:prenderFalha
# (texto) faz o Prender devolver Ok falso com esse erro; $script:prenderEstoura,
# lancar excecao.
function New-DepsFalsas {
    $script:chamadas = @()
    $script:despachos = @()
    $script:prenderFalha = ''
    $script:prenderEstoura = $false
    return @{
        Prender   = {
            param($Mac, $Ip)
            $script:chamadas += ('prender ' + $Mac + ' ' + $Ip)
            if ($script:prenderEstoura) { throw 'tabela de vizinhos travada' }
            if ($script:prenderFalha -ne '') { return [pscustomobject]@{ Ok = $false; Erro = $script:prenderFalha } }
            return [pscustomobject]@{ Ok = $true; Erro = '' }
        }
        Soltar    = {
            param($Mac, $Ip)
            $script:chamadas += ('soltar ' + $Mac + ' ' + $Ip)
            return [pscustomobject]@{ Ok = $true; Erro = '' }
        }
        Despachar = {
            param($Acao, $Camera, $Geracao)
            $script:chamadas += ('despachar ' + $Acao.Mac + ' ' + $Acao.AteEtapa + ' ' + $Acao.Posicao + ' ' + $Acao.Destino)
            $script:despachos += @{ Acao = $Acao; Camera = $Camera; Geracao = $Geracao }
        }
        Pingar    = { param($Ips) return @() }
        Descobrir = { return @() }
        Agora     = { return [datetime]'2026-11-18 10:00:00' }
    }
}

function Get-Camera {
    param($Estado, [int]$N)
    foreach ($c in @($Estado.Cameras)) { if ($c.Mac -eq ('AA:00:00:00:00:0' + $N)) { return $c } }
    return $null
}

# Coordenador com N cameras de fabrica em espera (Step-Descoberta ja aplicado).
function New-CoordComEspera {
    param([int]$N = 2, [int]$Max = 0)
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Max $Max -Deps (New-DepsFalsas)
    $achados = @()
    for ($i = 1; $i -le $N; $i++) { $achados += New-AchadoTeste $i }
    $coord.Estado = (Step-Descoberta -Estado $coord.Estado -Achados $achados).Estado
    return $coord
}

# ------------------------------------------------------------------- estado inicial

Write-Host ""
Write-Host "New-Coordenador" -ForegroundColor Cyan

T 'New-Coordenador: estado paralelo, jobs, fila de eventos, avisos e geracao' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Max 2 -Deps (New-DepsFalsas)
    Assert-Igual 3 @($coord.Estado.Posicoes).Count 'posicoes'
    Assert-Igual 2 $coord.Estado.Max 'Max'
    Assert-Igual 0 @($coord.Estado.Cameras).Count 'sem cameras'
    Assert-Verdade ($null -eq $coord.Estado.Portao) 'portao livre'
    Assert-Igual 0 $coord.Jobs.Count 'sem jobs'
    Assert-Verdade ($coord.Eventos -is [System.Collections.Concurrent.ConcurrentQueue[object]]) 'fila de eventos concorrente'
    Assert-Igual '' $coord.AvisoGlobal 'sem aviso global'
    Assert-Igual 0 $coord.AvisosCamera.Count 'sem aviso por camera'
    Assert-Igual 0 $coord.PortaCanal.Count 'sem porta/canal por camera'
    Assert-Igual 0 $coord.GeracaoDespacho.Count 'sem geracao de despacho'
    Assert-Igual 0 $coord.Geracao 'geracao da senha'
    Assert-Verdade $coord.Sujo 'nasce sujo (publica o estado inicial)'
}

T 'New-Coordenador: dependencia que nao e scriptblock para aqui' {
    $deps = New-DepsFalsas
    $deps.Prender = 'nao sou bloco'
    $erro = ''
    try { $null = New-Coordenador -Posicoes (New-PosicoesTeste 1) -Deps $deps } catch { $erro = $_.Exception.Message }
    Assert-Verdade ($erro -like '*Prender*') ('erro cita a dependencia: ' + $erro)
}

T 'Invoke-AcoesCoordenador: dependencia ausente para com erro que a cita' {
    $deps = New-DepsFalsas
    $deps.Remove('Despachar')
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 1) -Deps $deps
    $coord.Estado = (Step-Descoberta -Estado $coord.Estado -Achados @(New-AchadoTeste 1)).Estado
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    $erro = ''
    try { Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes } catch { $erro = $_.Exception.Message }
    Assert-Verdade ($erro -like '*Despachar*') ('erro cita a dependencia: ' + $erro)
}

# ------------------------------------------------------------------- acoes

Write-Host ""
Write-Host "Invoke-AcoesCoordenador" -ForegroundColor Cyan

T 'admissao: prender antes de despachar, com a camera do estado e a geracao da senha' {
    $coord = New-CoordComEspera -N 2
    $coord.Geracao = 3
    $coord.Sujo = $false
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes

    Assert-Igual 'prender AA:00:00:00:00:01 192.168.1.108|despachar AA:00:00:00:00:01 rede 1 192.0.2.11' ($script:chamadas -join '|') 'ordem'
    $d = $script:despachos[0]
    Assert-Igual '192.168.1.108' $d.Camera.IpOrigem 'camera do estado: IP de origem'
    Assert-Igual 'SIM-1' $d.Camera.Serial 'camera do estado: serial'
    Assert-Igual 3 $d.Geracao 'geracao passada ao despacho'
    Assert-Igual 3 $coord.GeracaoDespacho['AA0000000001'] 'geracao guardada por MAC'
    Assert-Igual '192.168.1.108' $coord.Presos['AA0000000001'] 'IP em que a camera foi presa'
    Assert-Igual 'portao' (Get-Camera $coord.Estado 1).Fase 'fase'
}

T 'prender falho: decisao na etapa portao, sem despachar, portao livre para a proxima' {
    $coord = New-CoordComEspera -N 2
    $coord.Geracao = 2
    $script:prenderFalha = 'Nao consegui criar o vizinho estatico 192.168.1.108 -> AA-00-00-00-00-01: acesso negado'
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    $coord.Sujo = $false
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes

    Assert-Igual 0 @($script:chamadas | Where-Object { $_ -like 'despachar*' }).Count 'sem despachar'
    $c = Get-Camera $coord.Estado 1
    Assert-Igual 'decisao' $c.Fase 'fase'
    Assert-Igual 'portao' $c.Falha.Etapa 'etapa da falha'
    Assert-Igual $script:prenderFalha $c.Falha.Erro 'erro da falha'
    Assert-Igual 2 $c.Falha.Geracao 'geracao na falha'
    Assert-Verdade ($null -eq $coord.Estado.Portao) 'portao livre'
    Assert-Falso $coord.Presos.ContainsKey('AA0000000001') 'nao ficou presa'
    Assert-Verdade $coord.Sujo 'estado sujo'

    # A proxima entra no portao.
    $script:prenderFalha = ''
    $p2 = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p2.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p2.Acoes
    Assert-Igual 'portao' (Get-Camera $coord.Estado 2).Fase 'a 2 no portao'
    Assert-Igual 'decisao' (Get-Camera $coord.Estado 1).Fase 'a 1 continua em decisao (nao volta a espera)'
}

T 'prender que estoura: mesma decisao na etapa portao, com o erro da excecao' {
    $coord = New-CoordComEspera -N 1
    $script:prenderEstoura = $true
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
    $c = Get-Camera $coord.Estado 1
    Assert-Igual 'decisao' $c.Fase 'fase'
    Assert-Igual 'portao' $c.Falha.Etapa 'etapa'
    Assert-Verdade ($c.Falha.Erro -like '*tabela de vizinhos travada*') ('erro: ' + $c.Falha.Erro)
    Assert-Igual 0 @($script:chamadas | Where-Object { $_ -like 'despachar*' }).Count 'sem despachar'
}

T 'despachar que estoura: decisao da camera (portao ou conferencia), com a ultima etapa feita' {
    $coord = New-CoordComEspera -N 1
    $coord.Deps.Despachar = { param($Acao, $Camera, $Geracao) $script:chamadas += ('despachar ' + $Acao.Mac); throw 'pool cheio' }
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
    $c = Get-Camera $coord.Estado 1
    Assert-Igual 'decisao' $c.Fase 'fase'
    Assert-Igual 'portao' $c.Falha.Etapa 'etapa da falha no portao'
    Assert-Verdade ($c.Falha.Erro -like '*pool cheio*') ('erro: ' + $c.Falha.Erro)
    Assert-Igual 'prender AA:00:00:00:00:01 192.168.1.108|despachar AA:00:00:00:00:01|soltar AA:00:00:00:00:01 192.168.1.108' ($script:chamadas -join '|') 'solta depois da falha'

    # Na conferencia: a rede ja foi gravada, a etapa feita fica 'rede' (o tentar retoma pela conferencia).
    $coord = New-CoordComEspera -N 1
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
    $coord.Deps.Despachar = { param($Acao, $Camera, $Geracao) throw 'pool cheio' }
    $f = Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'rede' }
    $coord.Estado = $f.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $f.Acoes
    $c = Get-Camera $coord.Estado 1
    Assert-Igual 'decisao' $c.Fase 'fase na conferencia'
    Assert-Igual 'conferencia' $c.Falha.Etapa 'etapa da falha na conferencia'
    Assert-Igual 'rede' $c.Etapa 'ultima etapa feita'
}

T 'fim do portao: soltar no IP em que foi presa, depois despachar a conferencia' {
    $coord = New-CoordComEspera -N 1
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
    $script:chamadas = @()

    $f = Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'rede' } -Geracao 0
    $coord.Estado = $f.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $f.Acoes

    Assert-Igual 'soltar AA:00:00:00:00:01 192.168.1.108|despachar AA:00:00:00:00:01  1 192.0.2.11' ($script:chamadas -join '|') 'ordem'
    Assert-Falso $coord.Presos.ContainsKey('AA0000000001') 'solta'
    Assert-Igual 'conferindo' (Get-Camera $coord.Estado 1).Fase 'fase'
}

T 'avisar: camera do estado vai para o aviso dela; sem MAC ou fora do estado, global' {
    $coord = New-CoordComEspera -N 1
    $coord.Sujo = $false
    Invoke-AcoesCoordenador -Coord $coord -Acoes @(
        @{ Tipo = 'avisar'; Mac = 'aa-00-00-00-00-01'; Texto = 'Camera ja inicializada: nao tocada.' })
    Assert-Igual 'Camera ja inicializada: nao tocada.' $coord.AvisosCamera['AA0000000001'] 'aviso da camera (grafia do MAC nao importa)'
    Assert-Igual '' $coord.AvisoGlobal 'global intacto'
    Assert-Verdade $coord.Sujo 'aviso suja o estado'

    Invoke-AcoesCoordenador -Coord $coord -Acoes @(@{ Tipo = 'avisar'; Mac = ''; Texto = 'Ha 1 camera em configuracao.' })
    Assert-Igual 'Ha 1 camera em configuracao.' $coord.AvisoGlobal 'sem MAC: global'

    Invoke-AcoesCoordenador -Coord $coord -Acoes @(@{ Tipo = 'avisar'; Mac = 'AA:00:00:00:00:09'; Texto = 'Marca nao suportada: nao tocada.' })
    Assert-Igual 'Marca nao suportada: nao tocada.' $coord.AvisoGlobal 'MAC fora do estado: global'
    Assert-Falso $coord.AvisosCamera.ContainsKey('AA0000000009') 'nada por camera para MAC fora do estado'
}

T 'publicar: marca o estado como sujo, sem chamar dependencia' {
    $coord = New-CoordComEspera -N 1
    $coord.Sujo = $false
    Invoke-AcoesCoordenador -Coord $coord -Acoes @(@{ Tipo = 'publicar' })
    Assert-Verdade $coord.Sujo 'sujo'
    Assert-Igual 0 @($script:chamadas).Count 'nenhuma dependencia chamada'
}

T 'acao de tipo desconhecido para aqui' {
    $coord = New-CoordComEspera -N 1
    $erro = ''
    try { Invoke-AcoesCoordenador -Coord $coord -Acoes @(@{ Tipo = 'explodir'; Mac = 'AA:00:00:00:00:01' }) } catch { $erro = $_.Exception.Message }
    Assert-Verdade ($erro -like '*explodir*') ('erro cita o tipo: ' + $erro)
}

# --------------------------------------------------------- achado do DHIP

Write-Host ""
Write-Host "ConvertTo-AchadoParalelo" -ForegroundColor Cyan

$script:dhipDuas = @(([IO.File]::ReadAllText((Join-Path $raiz 'testes\dhip-duas-de-fabrica-mesmo-ip.json'), [Text.Encoding]::ASCII)) | ConvertFrom-Json) |
    ForEach-Object { $_ } | ForEach-Object { ConvertFrom-RespostaDhip -Json ($_ | ConvertTo-Json -Depth 10 -Compress) }

T 'ConvertTo-AchadoParalelo: resposta DHIP da fixture vira achado do orquestrador' {
    Assert-Igual 2 @($script:dhipDuas).Count 'fixture com 2 respostas'
    $a = @($script:dhipDuas | ForEach-Object { ConvertTo-AchadoParalelo $_ })
    Assert-Igual 'AA:00:00:00:00:01,AA:00:00:00:00:02' (($a | ForEach-Object { $_.Mac }) -join ',') 'MAC com dois-pontos, maiusculo'
    Assert-Igual 'SIM-1,SIM-2' (($a | ForEach-Object { $_.Serial }) -join ',') 'serial'
    Assert-Igual 'IPC-EXEMPLO' $a[0].Modelo 'modelo'
    Assert-Igual '192.168.1.108' $a[0].Ip 'IP'
    Assert-Igual 80 $a[0].HttpPort 'porta HTTP'
    Assert-Igual 1 $a[0].Init 'Init normalizado (de fabrica)'
    Assert-Igual 'IntelBras' $a[0].Marca 'marca do Vendor'
    Assert-Igual 'HttpPort,Init,Ip,Mac,Marca,Modelo,Serial' ((@($a[0].Keys) | Sort-Object) -join ',') 'so os campos do contrato'

    # As duas entram em espera pela regra normal do orquestrador.
    $e = (Step-Descoberta -Estado (New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)) -Achados $a).Estado
    Assert-Igual 'espera,espera' ((@($e.Cameras) | ForEach-Object { $_.Fase }) -join ',') 'em espera'
}

T 'ConvertTo-AchadoParalelo: item do Find-CamerasNaRede (sem Fabricante) sai com Marca vazia' {
    $script:achadosFalsos = $script:dhipDuas
    function Invoke-DescobertaDhip { param($Segundos, $IfIndex) return $script:achadosFalsos }
    function Get-FaixasDaPlaca { param($IfIndex) return @(@{ Ip = '192.168.1.220'; Prefixo = 24 }) }
    function Invoke-ProbeInitLote { throw 'probe HTTP real nao pode ser chamado no teste' }
    function Invoke-PingSweep { throw 'ping real nao pode ser chamado no teste' }
    function Get-VizinhosMac { throw 'ARP real nao pode ser chamado no teste' }
    $itens = @(Find-CamerasNaRede -Silencioso -SemVarredura)
    Assert-Igual 2 $itens.Count 'itens'
    $a = @($itens | ForEach-Object { ConvertTo-AchadoParalelo $_ })
    Assert-Igual 'AA:00:00:00:00:01,AA:00:00:00:00:02' (($a | ForEach-Object { $_.Mac }) -join ',') 'MAC'
    Assert-Igual '' $a[0].Marca 'marca vazia (o broadcast e da familia DHIP)'
    Assert-Igual 1 $a[1].Init 'Init'
    $e = (Step-Descoberta -Estado (New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)) -Achados $a).Estado
    Assert-Igual 2 @($e.Cameras).Count 'as duas entram'
}

# ------------------------------------------------------------- deps da placa

Write-Host ""
Write-Host "New-DepsPlaca" -ForegroundColor Cyan

# Tabela de vizinhos e IPs da placa falsos. Os cmdlets reais estouram.
function Use-PlacaFalsa {
    param([string]$Faixa = '192.168.1.220')
    $script:arp = @()
    $script:chamadasViz = @()
    $script:ipsPlaca = @($Faixa)
    $script:faixa = $Faixa
    $script:addTemp = @()
    $script:pasta = Join-Path ([IO.Path]::GetTempPath()) ('coord-teste-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $script:pasta
    $script:rastro = Join-Path $script:pasta 'placa-sessao.json'
    Save-JsonAtomico -Caminho $script:rastro -Objeto @{
        Quando = '2026-11-18 09:00:00'; Placa = 'Ethernet'; IfIndex = 8; Antes = @{ Dhcp = $true; Enderecos = @() }
        Adicionados = @(@{ Ip = $Faixa; Prefixo = 24; Para = 'fabrica'; Camera = '' }); Rotas = @(); Vizinhos = @()
        Devolvidos = @(); Rota = $null; Dns = @(); Mexida = $true
    }
}

function Remove-PlacaFalsa { Remove-Item -LiteralPath $script:pasta -Recurse -Force -ErrorAction SilentlyContinue }

# Corpo comum: as falsas ficam no escopo do bloco que chama.
$script:falsasPlaca = {
    function Get-NetNeighbor { throw 'Get-NetNeighbor real chamado' }
    function New-NetNeighbor { throw 'New-NetNeighbor real chamado' }
    function Remove-NetNeighbor { throw 'Remove-NetNeighbor real chamado' }
    function New-NetIPAddress { throw 'New-NetIPAddress real chamado' }
    function Remove-NetIPAddress { throw 'Remove-NetIPAddress real chamado' }
    function Get-NetAdapter { throw 'Get-NetAdapter real chamado' }
    function Get-VizinhoPlaca { param([int]$IfIndex, [string]$Ip) $script:chamadasViz += ('get ' + $IfIndex + ' ' + $Ip); return @($script:arp | Where-Object { $_.IfIndex -eq $IfIndex -and $_.IPAddress -eq $Ip }) }
    function Remove-VizinhoPlaca { param([int]$IfIndex, [string]$Ip) $script:chamadasViz += ('remove ' + $IfIndex + ' ' + $Ip); $script:arp = @($script:arp | Where-Object { -not ($_.IfIndex -eq $IfIndex -and $_.IPAddress -eq $Ip) }) }
    function New-VizinhoPlaca { param([int]$IfIndex, [string]$Ip, [string]$Mac) $script:chamadasViz += ('new ' + $IfIndex + ' ' + $Ip + ' ' + $Mac); $script:arp += [pscustomobject]@{ IfIndex = $IfIndex; IPAddress = $Ip; LinkLayerAddress = $Mac; State = 'Permanent' } }
    function Get-FaixasDaPlaca { param([int]$IfIndex = 0) return @(@{ Ip = $script:faixa; Prefixo = 24; IfIndex = 8 }) }
    function Remove-IpPlaca { param([int]$IfIndex, [string]$Ip) $script:chamadasViz += ('remove-ip ' + $IfIndex + ' ' + $Ip); $script:ipsPlaca = @($script:ipsPlaca | Where-Object { $_ -ne $Ip }) }
    function Add-IpTemporarioPlaca {
        param([string]$IpCamera, [string]$Mascara = '255.255.255.0', [string]$GatewayCamera = '', $Placa = $null, [switch]$Simular)
        $script:addTemp += ('temp ' + $IpCamera + ' placa ' + [int]$Placa.IfIndex)
        $script:ipsPlaca += '192.168.1.50'
        $s = @{ Quando = 'agora'; Placa = 'Ethernet'; IfIndex = 8; Antes = @{ Dhcp = $true; Enderecos = @() }; Rotas = @(); Vizinhos = @()
                Devolvidos = @(); Rota = $null; Dns = @(); Mexida = $false
                Adicionados = @(@{ Ip = '192.168.1.50'; Prefixo = 24; Para = 'temporario'; Camera = $IpCamera }) }
        return [pscustomobject]@{ Ok = $true; Ip = '192.168.1.50'; Sessao = $s }
    }
}

T 'New-DepsPlaca: prender poe o vizinho na tabela e no rastro; soltar tira dos dois' {
    . $script:falsasPlaca
    Use-PlacaFalsa
    try {
        $deps = New-DepsPlaca -IfIndex 8 -CaminhoRastro $script:rastro
        $r = & $deps.Prender 'AA:00:00:00:00:01' '192.168.1.108'
        Assert-Verdade $r.Ok ('prender ok: ' + $r.Erro)
        Assert-Igual 1 @($script:arp | Where-Object { $_.IPAddress -eq '192.168.1.108' -and $_.LinkLayerAddress -eq 'AA-00-00-00-00-01' -and $_.State -eq 'Permanent' }).Count 'vizinho Permanent na tabela'
        $s = Read-JsonArquivo $script:rastro
        Assert-Igual '192.168.1.108=AA:00:00:00:00:01' ((@($s.Vizinhos) | ForEach-Object { $_.Ip + '=' + $_.Mac }) -join ',') 'vizinho no rastro'
        Assert-Igual '192.168.1.220' ((@($s.Adicionados) | ForEach-Object { $_.Ip }) -join ',') 'o resto do rastro fica'
        Assert-Igual 'Ethernet' $s.Placa 'placa do rastro'
        Assert-Igual 0 $script:addTemp.Count 'origem na faixa da placa: sem IP temporario'

        $r = & $deps.Soltar 'AA:00:00:00:00:01' '192.168.1.108'
        Assert-Verdade $r.Ok ('soltar ok: ' + $r.Erro)
        Assert-Igual 0 @($script:arp | Where-Object { $_.IPAddress -eq '192.168.1.108' }).Count 'vizinho fora da tabela'
        $s = Read-JsonArquivo $script:rastro
        Assert-Igual 0 @($s.Vizinhos).Count 'vizinho fora do rastro'
        Assert-Igual '192.168.1.220' ((@($s.Adicionados) | ForEach-Object { $_.Ip }) -join ',') 'o IP da placa continua no rastro'
    } finally { Remove-PlacaFalsa }
}

T 'New-DepsPlaca: origem fora das faixas da placa ganha IP temporario ao prender, que sai ao soltar' {
    . $script:falsasPlaca
    Use-PlacaFalsa -Faixa '192.0.2.200'
    try {
        $deps = New-DepsPlaca -IfIndex 8 -CaminhoRastro $script:rastro
        $r = & $deps.Prender 'AA:00:00:00:00:02' '192.168.1.108'
        Assert-Verdade $r.Ok ('prender ok: ' + $r.Erro)
        Assert-Igual 'temp 192.168.1.108 placa 8' ($script:addTemp -join '|') 'IP temporario pedido para a origem, na placa'
        $s = Read-JsonArquivo $script:rastro
        Assert-Igual '192.0.2.200,192.168.1.50' ((@($s.Adicionados) | ForEach-Object { $_.Ip }) -join ',') 'temporario no rastro'
        Assert-Igual '192.168.1.108=AA:00:00:00:00:02' ((@($s.Vizinhos) | ForEach-Object { $_.Ip + '=' + $_.Mac }) -join ',') 'vizinho no rastro'

        $r = & $deps.Soltar 'AA:00:00:00:00:02' '192.168.1.108'
        Assert-Verdade $r.Ok ('soltar ok: ' + $r.Erro)
        Assert-Verdade ($script:chamadasViz -contains 'remove-ip 8 192.168.1.50') 'temporario tirado da placa'
        Assert-Igual '192.0.2.200' ($script:ipsPlaca -join ',') 'placa sem o temporario'
        $s = Read-JsonArquivo $script:rastro
        Assert-Igual '192.0.2.200' ((@($s.Adicionados) | ForEach-Object { $_.Ip }) -join ',') 'rastro sem o temporario'
        Assert-Igual 0 @($s.Vizinhos).Count 'rastro sem o vizinho'
    } finally { Remove-PlacaFalsa }
}

T 'New-DepsPlaca: vizinho que nao confere devolve Ok falso e o rastro nao muda' {
    . $script:falsasPlaca
    function New-VizinhoPlaca { param([int]$IfIndex, [string]$Ip, [string]$Mac) throw 'acesso negado' }
    Use-PlacaFalsa
    try {
        $antes = [IO.File]::ReadAllText($script:rastro)
        $deps = New-DepsPlaca -IfIndex 8 -CaminhoRastro $script:rastro
        $r = & $deps.Prender 'AA:00:00:00:00:01' '192.168.1.108'
        Assert-Falso $r.Ok 'prender falhou'
        Assert-Verdade ($r.Erro -like '*acesso negado*') ('erro: ' + $r.Erro)
        Assert-Igual $antes ([IO.File]::ReadAllText($script:rastro)) 'rastro intacto'
    } finally { Remove-PlacaFalsa }
}

T 'New-DepsPlaca -Simular: prender e soltar so logam, sem tocar tabela nem rastro' {
    . $script:falsasPlaca
    function Get-VizinhoPlaca { throw 'tabela tocada em simulacao' }
    function Add-IpTemporarioPlaca { throw 'placa tocada em simulacao' }
    Use-PlacaFalsa
    try {
        $antes = [IO.File]::ReadAllText($script:rastro)
        $script:logs.Clear()
        $deps = New-DepsPlaca -IfIndex 8 -CaminhoRastro $script:rastro -Simular
        $r1 = & $deps.Prender 'AA:00:00:00:00:01' '192.168.1.108'
        $r2 = & $deps.Soltar 'AA:00:00:00:00:01' '192.168.1.108'
        Assert-Verdade ($r1.Ok -and $r2.Ok) 'ok nos dois'
        Assert-Igual 2 @($script:logs | Where-Object { $_ -like '*simular*192.168.1.108*' }).Count 'um log por acao'
        Assert-Igual $antes ([IO.File]::ReadAllText($script:rastro)) 'rastro intacto'
    } finally { Remove-PlacaFalsa }
}

T 'New-DepsPlaca ligado ao coordenador: admissao prende pela tabela falsa e fim do portao solta' {
    . $script:falsasPlaca
    Use-PlacaFalsa
    try {
        $deps = New-DepsFalsas
        $placa = New-DepsPlaca -IfIndex 8 -CaminhoRastro $script:rastro
        $deps.Prender = $placa.Prender
        $deps.Soltar = $placa.Soltar
        $coord = New-Coordenador -Posicoes (New-PosicoesTeste 2) -Deps $deps
        $coord.Estado = (Step-Descoberta -Estado $coord.Estado -Achados @((New-AchadoTeste 1), (New-AchadoTeste 2))).Estado
        $p = Step-Admissao -Estado $coord.Estado
        $coord.Estado = $p.Estado
        Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
        Assert-Igual 'AA-00-00-00-00-01' (@($script:arp | Where-Object { $_.IPAddress -eq '192.168.1.108' })[0].LinkLayerAddress) 'presa pela tabela'
        $f = Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'rede' }
        $coord.Estado = $f.Estado
        Invoke-AcoesCoordenador -Coord $coord -Acoes $f.Acoes
        Assert-Igual 0 @($script:arp).Count 'solta pela tabela'
        Assert-Igual 0 @((Read-JsonArquivo $script:rastro).Vizinhos).Count 'rastro sem vizinho'
    } finally { Remove-PlacaFalsa }
}

# ------------------------------------------------------------------- resultado

Write-Host ""
Write-Host ("  " + $script:Ok + " passaram, " + $script:Falhou + " falharam") -ForegroundColor $(
    if ($script:Falhou -eq 0) { 'Green' } else { 'Red' })
if ($script:Falhou -gt 0) {
    Write-Host ""
    foreach ($f in $script:Falhas) { Write-Host ("  - " + $f) -ForegroundColor Red }
    Write-Host ""
    exit 1
}
Write-Host ""
