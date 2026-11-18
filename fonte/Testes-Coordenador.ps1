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
        (tabela de vizinhos, IP da placa) e o rastro numa pasta temporaria;
      - Clear-VizinhosRastro: vizinhos que sobraram no rastro saem na
        partida e ao encerrar o painel (com o pool fechado), Deps falsas e
        tabela falsa;
      - pool e jobs: RunspacePool real com o motor em -Simular e o registro
        numa pasta temporaria (5 cameras ate 'feita', no maximo 1 MAC preso,
        conferencias sobrepostas, senha fora dos eventos, job que estoura);
      - estado publicado (contrato da F6): formato com 2 cameras pelo JSON
        e a tabela de derivacao dos campos legados;
      - vigia paralelo: reserva sem DHIP (Max 1, aviso, achado do ARP com
        ConferirInit) e volta do DHIP, aviso de MAC trocando no IP de
        fabrica, inicializada desconhecida sem prender/despachar, decisao
        que nao segura a seguinte, ping das posicoes so na hora de admitir
        e SemSucesso parado com camera em curso;
      - porta/canal por camera: edicao durante a conferencia corrige o
        registro no 'feita', sem edicao o registro nao e tocado, recusa
        para camera fora da fila, 'feita' ou 'pulada', registro sem a
        camera vira aviso; FalharEm de uma vez so (portao x conferencia);
      - encerrar e atualizar (S4): -SemDespacho pula o despacho com log,
        Wait-JobsCoordenador com pool real (portao termina e solta; teto
        menor que o job devolve 1) e a tabela do Test-AtualizacaoEmCurso.

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
    return @{ Mac = ('AA:00:00:00:00:{0:X2}' -f $N); Serial = ('SIM-' + $N); Modelo = 'IPC-EXEMPLO'; Ip = '192.168.1.108'
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
    $script:presos = @{}
    $script:maxPresos = 0
    return @{
        Prender   = {
            param($Mac, $Ip)
            $script:chamadas += ('prender ' + $Mac + ' ' + $Ip)
            if ($script:prenderEstoura) { throw 'tabela de vizinhos travada' }
            if ($script:prenderFalha -ne '') { return [pscustomobject]@{ Ok = $false; Erro = $script:prenderFalha } }
            $script:presos[[string]$Mac] = $true
            if ($script:presos.Count -gt $script:maxPresos) { $script:maxPresos = $script:presos.Count }
            return [pscustomobject]@{ Ok = $true; Erro = '' }
        }
        Soltar    = {
            param($Mac, $Ip)
            $script:chamadas += ('soltar ' + $Mac + ' ' + $Ip)
            $script:presos.Remove([string]$Mac)
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

# ------------------------------------------------- vizinhos do rastro (partida e painel)

Write-Host ""
Write-Host "Clear-VizinhosRastro" -ForegroundColor Cyan

# Rastro com vizinhos que sobraram (painel fechado no X com camera presa).
function Add-VizinhosNoRastro {
    param([string[]]$Ips)
    $s = Read-JsonArquivo $script:rastro
    $v = @()
    $n = 0
    foreach ($ip in $Ips) { $n++; $v += @{ Ip = $ip; Mac = ('AA:00:00:00:00:0' + $n) } }
    $s.Vizinhos = $v
    Save-JsonAtomico -Caminho $script:rastro -Objeto $s
}

T 'Clear-VizinhosRastro com Deps falsas: solta cada vizinho do rastro e junta as falhas' {
    Use-PlacaFalsa
    try {
        Add-VizinhosNoRastro @('192.168.1.108', '192.0.2.11')
        $script:soltos = @()
        $deps = @{ Soltar = {
            param($Mac, $Ip)
            $script:soltos += ($Mac + ' ' + $Ip)
            if ($Ip -eq '192.0.2.11') { return [pscustomobject]@{ Ok = $false; Erro = 'tabela travada' } }
            return [pscustomobject]@{ Ok = $true; Erro = '' }
        } }
        $r = Clear-VizinhosRastro -CaminhoRastro $script:rastro -Deps $deps
        Assert-Igual 'AA:00:00:00:00:01 192.168.1.108|AA:00:00:00:00:02 192.0.2.11' ($script:soltos -join '|') 'soltar para cada vizinho, em ordem'
        Assert-Igual '192.168.1.108' (@($r.Soltos) -join ',') 'soltos'
        Assert-Igual 1 @($r.Falhas).Count 'uma falha'
        Assert-Verdade ((@($r.Falhas)[0]) -like '*192.0.2.11*tabela travada*') ('falha: ' + @($r.Falhas)[0])
    } finally { Remove-PlacaFalsa }
}

T 'Clear-VizinhosRastro sem rastro ou sem vizinhos: nada a soltar' {
    $script:soltos = @()
    $deps = @{ Soltar = { param($Mac, $Ip) $script:soltos += $Ip; return [pscustomobject]@{ Ok = $true; Erro = '' } } }
    $r = Clear-VizinhosRastro -CaminhoRastro (Join-Path ([IO.Path]::GetTempPath()) ('sem-rastro-' + [guid]::NewGuid().ToString('N') + '.json')) -Deps $deps
    Assert-Igual 0 (@($r.Soltos).Count + @($r.Falhas).Count) 'sem rastro'
    Use-PlacaFalsa
    try {
        $r = Clear-VizinhosRastro -CaminhoRastro $script:rastro -Deps $deps
        Assert-Igual 0 (@($r.Soltos).Count + @($r.Falhas).Count) 'rastro sem vizinhos'
        Assert-Igual 0 $script:soltos.Count 'soltar nunca chamado'
    } finally { Remove-PlacaFalsa }
}

T 'Partida: vizinhos que sobraram no rastro saem da tabela e do rastro (placa do rastro)' {
    . $script:falsasPlaca
    Use-PlacaFalsa
    try {
        Add-VizinhosNoRastro @('192.168.1.108', '192.0.2.11')
        # Um ainda na tabela; o outro ja sumiu (reboot): os dois saem do rastro.
        $script:arp = @([pscustomobject]@{ IfIndex = 8; IPAddress = '192.168.1.108'; LinkLayerAddress = 'AA-00-00-00-00-01'; State = 'Permanent' })
        $r = Clear-VizinhosRastro -CaminhoRastro $script:rastro
        Assert-Igual '192.168.1.108,192.0.2.11' (@($r.Soltos) -join ',') 'soltos'
        Assert-Igual 0 @($r.Falhas).Count 'sem falha'
        Assert-Igual 0 @($script:arp).Count 'tabela vazia'
        Assert-Verdade ($script:chamadasViz -contains 'remove 8 192.168.1.108') 'removido na placa do rastro (IfIndex 8)'
        $s = Read-JsonArquivo $script:rastro
        Assert-Igual 0 @($s.Vizinhos).Count 'rastro sem vizinhos'
        Assert-Igual '192.168.1.220' ((@($s.Adicionados) | ForEach-Object { $_.Ip }) -join ',') 'o resto do rastro fica'
    } finally { Remove-PlacaFalsa }
}

T 'Partida: rastro com vizinhos e sem placa vira falha, sem tocar a tabela' {
    . $script:falsasPlaca
    function Get-VizinhoPlaca { throw 'tabela tocada sem placa' }
    Use-PlacaFalsa
    try {
        Add-VizinhosNoRastro @('192.168.1.108')
        $s = Read-JsonArquivo $script:rastro
        $s.IfIndex = 0
        Save-JsonAtomico -Caminho $script:rastro -Objeto $s
        $r = Clear-VizinhosRastro -CaminhoRastro $script:rastro
        Assert-Igual 0 @($r.Soltos).Count 'nada solto'
        Assert-Igual 1 @($r.Falhas).Count 'uma falha'
        Assert-Igual 1 @((Read-JsonArquivo $script:rastro).Vizinhos).Count 'vizinho fica no rastro para o Reset'
    } finally { Remove-PlacaFalsa }
}

T 'Encerrar o painel: pool fechado e o vizinho preso sai da tabela e do rastro' {
    . $script:falsasPlaca
    Use-PlacaFalsa
    $pool = $null
    try {
        $deps = New-DepsFalsas
        $placa = New-DepsPlaca -IfIndex 8 -CaminhoRastro $script:rastro
        $deps.Prender = $placa.Prender
        $deps.Soltar = $placa.Soltar
        $coord = New-Coordenador -Posicoes (New-PosicoesTeste 2) -Deps $deps
        $pool = New-PoolCameras -Max 2
        $coord.Pool = $pool
        $coord.Estado = (Step-Descoberta -Estado $coord.Estado -Achados @((New-AchadoTeste 1))).Estado
        $p = Step-Admissao -Estado $coord.Estado
        $coord.Estado = $p.Estado
        Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
        Assert-Igual 1 @($script:arp).Count 'camera presa antes do encerrar'

        Close-PoolCameras -Pool $coord.Pool
        $r = Clear-VizinhosRastro -CaminhoRastro $script:rastro
        Assert-Igual 'Closed' ([string]$pool.Pool.RunspacePoolStateInfo.State) 'pool fechado'
        Assert-Igual '192.168.1.108' (@($r.Soltos) -join ',') 'solto'
        Assert-Igual 0 @($script:arp).Count 'tabela vazia'
        Assert-Igual 0 @((Read-JsonArquivo $script:rastro).Vizinhos).Count 'rastro sem vizinho'
    } finally {
        Close-PoolCameras -Pool $pool
        Remove-PlacaFalsa
    }
}

# ------------------------------------------------------------------- pool e jobs

Write-Host ""
Write-Host "Pool e jobs" -ForegroundColor Cyan

$script:senhaTeste = 'NaoPodeVazar#9'
$script:pastaPool = ''

# Padroes da sessao com a rede das posicoes de teste (192.0.2.x).
function New-PadroesTeste {
    $p = Get-SessaoFabrica
    $p.Gateway = '192.0.2.1'
    return $p
}

# Coordenador com pool real (1 runspace por posicao), registro temporario,
# deps de placa falsas (contam os presos) e o despacho ligado ao pool. A
# espera simulada e a tabela por etapa do servidor numa escala curta (S3).
function New-CoordPool {
    param([int]$N = 3, [double]$Escala = 0.5)
    $deps = New-DepsFalsas
    $deps.Despachar = (New-DepsPool).Despachar
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste $N) -Deps $deps
    $coord.Pool = New-PoolCameras -Max $N
    $script:pastaPool = Join-Path ([IO.Path]::GetTempPath()) ('coord-pool-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $script:pastaPool
    $coord.Trabalho.Senha = $script:senhaTeste
    $coord.Trabalho.Padroes = New-PadroesTeste
    $coord.Trabalho.CaminhoRegistro = Join-Path $script:pastaPool 'registro-simulacao.json'
    $coord.Trabalho.Simular = $true
    $coord.Trabalho.EsperaSimuladaMs = Get-EsperaSimuladaMs -Escala $Escala
    $coord.Trabalho.Local = 'Obra exemplo'; $coord.Trabalho.Rack = 'R1'; $coord.Trabalho.Andar = '1'
    $achados = @()
    for ($i = 1; $i -le $N; $i++) { $achados += New-AchadoTeste $i }
    $coord.Estado = (Step-Descoberta -Estado $coord.Estado -Achados $achados).Estado
    return $coord
}

function Remove-CoordPool {
    param($Coord)
    if ($null -ne $Coord) { Close-PoolCameras -Pool $Coord.Pool }
    if ($script:pastaPool) { Remove-Item -LiteralPath $script:pastaPool -Recurse -Force -ErrorAction SilentlyContinue }
    $script:pastaPool = ''
}

# O laco do servidor em miniatura: eventos, admissao, acoes. Para quando
# nenhuma camera esta em espera/portao/conferindo e nao ha job; $false no
# tempo esgotado.
function Invoke-LacoTeste {
    param($Coord, [int]$TimeoutSeg = 90)
    $script:eventos = New-Object 'System.Collections.Generic.List[object]'
    $script:logsJob = New-Object 'System.Collections.Generic.List[object]'
    $limite = (Get-Date).AddSeconds($TimeoutSeg)
    while ((Get-Date) -lt $limite) {
        Receive-EventosCoordenador -Coord $Coord -Log { param($Ev) $script:logsJob.Add($Ev) } -Observar { param($Ev) $script:eventos.Add($Ev) }
        $p = Step-Admissao -Estado $Coord.Estado
        $Coord.Estado = $p.Estado
        Invoke-AcoesCoordenador -Coord $Coord -Acoes $p.Acoes
        $vivas = @(@($Coord.Estado.Cameras) | Where-Object { $_.Fase -in @('espera', 'portao', 'conferindo') }).Count
        if ($vivas -eq 0 -and $Coord.Jobs.Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 50
    }
    return $false
}

T 'New-PoolCameras: RunspacePool aberto de 1 a N (N = posicoes da fila)' {
    $pool = New-PoolCameras -Max 3
    try {
        Assert-Igual 'Opened' ([string]$pool.Pool.RunspacePoolStateInfo.State) 'aberto'
        Assert-Igual 3 $pool.Pool.GetMaxRunspaces() 'maximo'
        Assert-Igual 1 $pool.Pool.GetMinRunspaces() 'minimo'
        Assert-Verdade (Test-Path -LiteralPath $pool.CaminhoMotor) ('motor achado: ' + $pool.CaminhoMotor)
    } finally { Close-PoolCameras -Pool $pool }
    Assert-Igual 'Closed' ([string]$pool.Pool.RunspacePoolStateInfo.State) 'fechado'
}

T 'New-ContextoJob: camera do estado, destino da acao, Local/Rack/Andar da fila, porta/canal do cartao' {
    $coord = New-CoordComEspera -N 1
    $c = Get-Camera $coord.Estado 1
    $c.HttpPort = 8080
    $acao = @{ Tipo = 'despachar'; Mac = $c.Mac; AteEtapa = 'rede'; Posicao = 2; Destino = '192.0.2.12' }
    $ctx = New-ContextoJob -Camera $c -Acao $acao -Fila @{ Local = 'Obra exemplo'; Rack = 'R1'; Andar = '3' } -PortaCanal @{ Porta = '5'; Canal = '7' }
    Assert-Igual '192.168.1.108|8080|AA:00:00:00:00:01|SIM-1|192.0.2.12' ($ctx.IpOrigem + '|' + $ctx.HttpPort + '|' + $ctx.Mac + '|' + $ctx.Serial + '|' + $ctx.Destino) 'camera e destino'
    Assert-Igual 'Obra exemplo|R1|3|5|7' ($ctx.Local + '|' + $ctx.Rack + '|' + $ctx.Andar + '|' + $ctx.Porta + '|' + $ctx.Canal) 'fila e cartao'
    Assert-Verdade ($null -ne $ctx.PSObject.Properties['HttpPort']) 'objeto com propriedades (o motor le PSObject.Properties)'
    $ctx2 = New-ContextoJob -Camera $c -Acao $acao -Fila $null -PortaCanal $null
    Assert-Igual '||||' ($ctx2.Local + '|' + $ctx2.Rack + '|' + $ctx2.Andar + '|' + $ctx2.Porta + '|' + $ctx2.Canal) 'sem fila nem cartao: vazios'
}

T 'Get-EsperaSimuladaMs: tabela por etapa vezes a escala; 0 sem espera; negativa estoura' {
    $f = { param($t) (@('inicializada', 'encoder', 'rede', 'conferida') | ForEach-Object { $_ + '=' + $t[$_] }) -join ',' }
    Assert-Igual 'inicializada=400,encoder=400,rede=400,conferida=3000' (& $f (Get-EsperaSimuladaMs)) 'padrao (escala 1)'
    Assert-Igual 'inicializada=100,encoder=100,rede=100,conferida=750' (& $f (Get-EsperaSimuladaMs -Escala 0.25)) 'escala 0,25'
    Assert-Igual 'inicializada=0,encoder=0,rede=0,conferida=0' (& $f (Get-EsperaSimuladaMs -Escala 0)) 'escala 0'
    $estourou = $false
    try { $null = Get-EsperaSimuladaMs -Escala -1 } catch { $estourou = $true }
    Assert-Verdade $estourou 'escala negativa estoura'
    $coord = New-CoordComEspera -N 1
    Assert-Igual 'inicializada=400,encoder=400,rede=400,conferida=3000' (& $f $coord.Trabalho.EsperaSimuladaMs) 'Trabalho do coordenador novo'
    Assert-Falso $coord.Trabalho.ContainsKey('EsperaSimuladaSeg') 'a espera unica antes do motor saiu'
}

T 'despachar sem pool: decisao da camera, sem job' {
    $coord = New-CoordComEspera -N 1
    $coord.Deps.Despachar = (New-DepsPool).Despachar
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
    $c = Get-Camera $coord.Estado 1
    Assert-Igual 'decisao' $c.Fase 'fase'
    Assert-Verdade ($c.Falha.Erro -like '*pool*') ('erro cita o pool: ' + $c.Falha.Erro)
    Assert-Igual 0 $coord.Jobs.Count 'sem job'
}

# Cenario principal: 5 cameras na escala curta (S3); roda uma vez, os testes
# abaixo conferem pedacos dele.
$script:coordTres = $null
$script:fimTres = $false
$script:erroTres = ''
$script:regTres = $null
$script:eventosTres = @()
$script:maxPresosTres = -1
try {
    $script:coordTres = New-CoordPool -N 5
    $script:fimTres = Invoke-LacoTeste -Coord $script:coordTres
    $script:eventosTres = $script:eventos.ToArray()
    $script:maxPresosTres = $script:maxPresos
    $script:regTres = Read-Registro $script:coordTres.Trabalho.CaminhoRegistro
} catch {
    $script:erroTres = $_.Exception.Message
} finally {
    Remove-CoordPool $script:coordTres
}

T 'pool: 5 cameras de fabrica terminam feita' {
    Assert-Igual '' $script:erroTres 'cenario sem excecao'
    Assert-Verdade $script:fimTres 'laco terminou no tempo'
    Assert-Igual 'feita,feita,feita,feita,feita' ((@($script:coordTres.Estado.Cameras) | ForEach-Object { $_.Fase }) -join ',') 'fases'
    Assert-Igual 'feita,feita,feita,feita,feita' ((@($script:coordTres.Estado.Posicoes) | ForEach-Object { $_.Estado }) -join ',') 'posicoes'
    Assert-Igual 0 $script:coordTres.Jobs.Count 'nenhum job sobrando'
}

T 'pool: registro com 5 Instalada, MACs e destinos distintos' {
    $cams = @($script:regTres.Cameras)
    Assert-Igual 5 $cams.Count 'entradas'
    Assert-Igual 'Instalada,Instalada,Instalada,Instalada,Instalada' (($cams | ForEach-Object { $_.Status }) -join ',') 'status'
    Assert-Igual 'AA0000000001=192.0.2.11,AA0000000002=192.0.2.12,AA0000000003=192.0.2.13,AA0000000004=192.0.2.14,AA0000000005=192.0.2.15' `
        ((@($cams | Sort-Object Mac) | ForEach-Object { $_.Mac + '=' + $_.Ip }) -join ',') 'MAC e destino'
    Assert-Igual 'Obra exemplo|R1|1' ($cams[0].Local + '|' + $cams[0].Rack + '|' + $cams[0].Andar) 'Local/Rack/Andar da fila'
}

T 'pool: nunca mais de 1 MAC preso ao mesmo tempo' {
    Assert-Igual 1 $script:maxPresosTres 'maximo de presos'
    Assert-Igual 0 $script:presos.Count 'todos soltos no fim'
}

T 'pool: as conferencias se sobrepoem (janelas de tempo pelos eventos)' {
    $janelas = @()
    foreach ($n in 1..5) {
        $mac = 'AA:00:00:00:00:0' + $n
        $ini = @($script:eventosTres | Where-Object { $_.Mac -eq $mac -and $_.Tipo -eq 'log' -and $_.Texto -like '*confer*ncia ---*' }) | Select-Object -First 1
        $fim = @($script:eventosTres | Where-Object { $_.Mac -eq $mac -and $_.Tipo -eq 'log' -and $_.Texto -like 'RESULTADO: instalada*' }) | Select-Object -Last 1
        Assert-Verdade ($null -ne $ini -and $null -ne $fim) ('janela da conferencia de ' + $mac)
        $janelas += @{ Mac = $mac; Ini = $ini.Quando; Fim = $fim.Quando }
    }
    $sobrepostas = 0
    for ($i = 0; $i -lt 5; $i++) {
        for ($j = $i + 1; $j -lt 5; $j++) {
            if ($janelas[$i].Ini -lt $janelas[$j].Fim -and $janelas[$j].Ini -lt $janelas[$i].Fim) { $sobrepostas++ }
        }
    }
    Assert-Verdade ($sobrepostas -ge 1) ('pares sobrepostos: ' + $sobrepostas)
}

# S1: a conferencia vai ao motor com -SoConferencia (parte do destino, sem
# consultar a origem); o portao nao.
T 'pool: o log da conferencia traz a linha do modo, o do portao nao' {
    $logs = @($script:eventosTres | Where-Object { $_.Tipo -eq 'log' })
    $porJob = @($logs | Group-Object { $_.Job })
    Assert-Igual 10 $porJob.Count 'jobs com log (portao + conferencia de 5)'
    $conf = 0; $portao = 0
    foreach ($g in $porJob) {
        $textos = @($g.Group | ForEach-Object { [string]$_.Texto })
        $modo = @($textos | Where-Object { $_ -match 'confer.ncia a partir do destino 192\.0\.2\.1[1-5]; a origem n.o . consultada' }).Count
        if (@($textos | Where-Object { $_ -match '^--- C.mera .*: confer.ncia ---$' }).Count -gt 0) {
            $conf++
            Assert-Igual 1 $modo ('linha do modo na conferencia do job ' + $g.Name)
        } elseif (@($textos | Where-Object { $_ -match '^--- C.mera .*: port.o, at. a rede ---$' }).Count -gt 0) {
            $portao++
            Assert-Igual 0 $modo ('linha do modo no portao do job ' + $g.Name)
        }
    }
    Assert-Igual '5|5' ([string]$conf + '|' + $portao) 'conferencias|portoes'
}

T 'pool: eventos de log, progresso e fim por MAC, e a senha em nenhum deles' {
    $tipos = (@($script:eventosTres | ForEach-Object { $_.Tipo }) | Sort-Object -Unique) -join ','
    Assert-Igual 'fim,log,progresso' $tipos 'tipos de evento'
    Assert-Igual 10 @($script:eventosTres | Where-Object { $_.Tipo -eq 'fim' }).Count 'um fim por job (portao + conferencia de 5)'
    Assert-Verdade (@($script:eventosTres | Where-Object { $_.Tipo -eq 'progresso' -and $_.Etapa -eq 'rede' }).Count -ge 5) 'progresso da etapa rede'
    $vazou = @($script:eventosTres | Where-Object { (ConvertTo-Json -InputObject $_ -Depth 8 -Compress) -like ('*' + $script:senhaTeste + '*') })
    Assert-Igual 0 $vazou.Count 'eventos com a senha'
    Assert-Igual 0 @($script:logsJob | Where-Object { [string]$_.Texto -like ('*' + $script:senhaTeste + '*') }).Count 'logs com a senha'
    Assert-Verdade ($script:logsJob.Count -gt 0) 'logs entregues ao callback'
}

T 'pool: job que estoura vira decisao daquela camera, e as outras terminam' {
    $coord = $null
    try {
        $coord = New-CoordPool -N 3 -Escala 0.2
        # A conferencia da 2 recebe Padroes nulo: o motor estoura no job.
        $coord.Deps.Despachar = {
            param($Acao, $Camera, $Geracao, $Coord)
            $t = $Coord.Trabalho
            $antes = $t.Padroes
            if ([string]$Acao.Mac -eq 'AA:00:00:00:00:02' -and [string]$Acao.AteEtapa -eq '') { $t.Padroes = $null }
            try { Start-DespachoCoordenador -Coord $Coord -Acao $Acao -Camera $Camera -Geracao $Geracao } finally { $t.Padroes = $antes }
        }
        $coord.Geracao = 4
        Assert-Verdade (Invoke-LacoTeste -Coord $coord) 'laco terminou no tempo'
        Assert-Igual 'feita,decisao,feita' ((@($coord.Estado.Cameras) | ForEach-Object { $_.Fase }) -join ',') 'fases'
        $c = Get-Camera $coord.Estado 2
        Assert-Igual 'conferencia' $c.Falha.Etapa 'etapa da falha'
        Assert-Verdade ($c.Falha.Erro -like 'erro interno no job:*Padroes*') ('erro: ' + $c.Falha.Erro)
        Assert-Igual 4 $c.Falha.Geracao 'geracao do despacho'
        Assert-Igual 'rede' $c.Etapa 'ultima etapa feita continua (o tentar retoma pela conferencia)'
        Assert-Igual 0 $coord.Jobs.Count 'nenhum job sobrando'
    } finally { Remove-CoordPool $coord }
}

T 'pool: handle concluido sem fim vira falha na etapa do ultimo progresso' {
    $coord = $null
    try {
        $coord = New-CoordPool -N 1
        # Despacho falso: o job manda um progresso e estoura antes de qualquer 'fim'.
        $coord.Deps.Despachar = {
            param($Acao, $Camera, $Geracao, $Coord)
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $Coord.Pool.Pool
            $id = [guid]::NewGuid().ToString('N')
            $null = $ps.AddScript({
                param($Eventos, $Mac, $Id)
                $Eventos.Enqueue(@{ Mac = $Mac; Job = $Id; Tipo = 'progresso'; Etapa = 'encoder'; Atual = 0; Total = 0; Detalhe = ''; Quando = [datetime]::Now })
                throw 'runspace quebrou'
            }.ToString()).AddParameter('Eventos', $Coord.Eventos).AddParameter('Mac', [string]$Acao.Mac).AddParameter('Id', $id)
            $Coord.Jobs[(Get-ChaveMac $Acao.Mac)] = @{ Id = $id; Mac = [string]$Acao.Mac; Chave = (Get-ChaveMac $Acao.Mac); PowerShell = $ps
                                                      Handle = $ps.BeginInvoke(); Geracao = $Geracao; AteEtapa = [string]$Acao.AteEtapa; Etapa = '' }
        }
        Assert-Verdade (Invoke-LacoTeste -Coord $coord -TimeoutSeg 30) 'laco terminou no tempo'
        $c = Get-Camera $coord.Estado 1
        Assert-Igual 'decisao' $c.Fase 'fase'
        Assert-Igual 'encoder' $c.Falha.Etapa 'etapa do ultimo progresso'
        Assert-Verdade ($c.Falha.Erro -like 'erro interno no job:*runspace quebrou*') ('erro: ' + $c.Falha.Erro)
        Assert-Igual 0 $coord.Jobs.Count 'job retirado'
        Assert-Igual 0 $script:presos.Count 'solta depois da falha no portao'
    } finally { Remove-CoordPool $coord }
}

# ------------------------------------------------------------ estado publicado

Write-Host ""
Write-Host "ConvertTo-EstadoPublicadoParalelo" -ForegroundColor Cyan

# Aplica um Step no coordenador: estado do Step e acoes executadas (Deps falsas).
function Invoke-PassoTeste {
    param($Coord, $Passo)
    $Coord.Estado = $Passo.Estado
    $null = Invoke-AcoesCoordenador -Coord $Coord -Acoes $Passo.Acoes
}

# Coordenador com N cameras em espera e a camera 1 ja no portao.
function New-CoordNoPortao {
    param([int]$N = 2, [int]$Posicoes = 3)
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste $Posicoes) -Deps (New-DepsFalsas)
    $achados = @()
    for ($i = 1; $i -le $N; $i++) { $achados += New-AchadoTeste $i }
    $coord.Estado = (Step-Descoberta -Estado $coord.Estado -Achados $achados).Estado
    Invoke-PassoTeste $coord (Step-Admissao -Estado $coord.Estado)
    return $coord
}

# Camera 1 conferindo e camera 2 em decisao (falhou na rede no portao, login
# recusado na geracao 3), com progresso, porta/canal, aviso e senha.
function New-CoordPublicado {
    $coord = New-CoordNoPortao -N 2
    Invoke-PassoTeste $coord (Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'rede' })
    Invoke-PassoTeste $coord (Step-Admissao -Estado $coord.Estado)
    Invoke-PassoTeste $coord (Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:02' -Geracao 3 -Resultado @{
        Ok = $false; Etapa = 'inicializada'; Falhou = 'rede'; Erro = 'sem resposta'; LoginRecusado = $true })
    $coord.Progresso['AA0000000001'] = @{ Etapa = 'encoder'; Atual = 2; Total = 5; Detalhe = 'Aguardando o boot' }
    $coord.PortaCanal['AA0000000001'] = @{ Porta = '3'; Canal = '4' }
    $coord.AvisosCamera['AA0000000002'] = 'aviso de teste'
    $coord.Trabalho.Senha = $script:senhaTeste
    $coord.Trabalho.Local = 'Bloco A'
    return $coord
}

# Estado publicado como a UI recebe: ConvertTo-Json e de volta.
function Get-PublicadoJson {
    param($Coord)
    $json = ConvertTo-Json -InputObject (ConvertTo-EstadoPublicadoParalelo -Coord $Coord) -Depth 12
    return @{ Json = $json; Obj = ($json | ConvertFrom-Json) }
}

function Get-Nomes {
    param($Obj)
    return (@($Obj.PSObject.Properties | ForEach-Object { $_.Name }) -join ',')
}

T 'estado publicado: formato com 2 cameras (conferindo e decisao) pelo JSON' {
    $r = Get-PublicadoJson (New-CoordPublicado)
    $j = $r.Obj
    Assert-Igual 'cameras,portao,paralelo,filaItens,fase,atual,camera,falha' (Get-Nomes $j) 'campos do topo'
    Assert-Igual 2 @($j.cameras).Count 'cameras'
    $c1 = @($j.cameras)[0]
    Assert-Igual 'mac,serial,modelo,ipOrigem,indice,posicao,destino,porta,canal,fase,etapa,progresso,trabalho,aviso,falha' (Get-Nomes $c1) 'campos da camera'
    Assert-Igual 'AA:00:00:00:00:01' $c1.mac 'mac 1'
    Assert-Igual 'SIM-1' $c1.serial 'serial 1'
    Assert-Igual 'IPC-EXEMPLO' $c1.modelo 'modelo 1'
    Assert-Igual '192.168.1.108' $c1.ipOrigem 'ipOrigem 1'
    Assert-Igual 0 $c1.indice 'indice 1 (posicao 1 em filaItens)'
    Assert-Igual 1 $c1.posicao 'posicao 1'
    Assert-Igual '192.0.2.11' $c1.destino 'destino 1'
    Assert-Igual '3' $c1.porta 'porta 1'
    Assert-Igual '4' $c1.canal 'canal 1'
    Assert-Igual 'conferindo' $c1.fase 'fase 1'
    Assert-Igual 'encoder' $c1.etapa 'etapa 1 (a do progresso)'
    Assert-Igual 2 $c1.progresso.atual 'progresso.atual 1'
    Assert-Igual 5 $c1.progresso.total 'progresso.total 1'
    Assert-Igual 'Aguardando o boot' $c1.trabalho 'trabalho 1 (detalhe do progresso)'
    Assert-Igual '' $c1.aviso 'aviso 1'
    Assert-Verdade ($null -eq $c1.falha) 'camera 1 sem falha'

    $c2 = @($j.cameras)[1]
    Assert-Igual 'AA:00:00:00:00:02' $c2.mac 'mac 2'
    Assert-Igual 'decisao' $c2.fase 'fase 2'
    Assert-Igual 1 $c2.indice 'indice 2'
    Assert-Igual 2 $c2.posicao 'posicao 2'
    Assert-Igual '192.0.2.12' $c2.destino 'destino 2'
    Assert-Igual '' $c2.porta 'porta 2'
    Assert-Igual 'inicializada' $c2.etapa 'etapa 2 (a ultima feita)'
    Assert-Verdade ($null -eq $c2.progresso) 'camera 2 sem progresso'
    Assert-Igual '' $c2.trabalho 'trabalho 2'
    Assert-Igual 'aviso de teste' $c2.aviso 'aviso 2'
    Assert-Igual 'etapa,erro,recusa,loginRecusado,bloqueada,geracao' (Get-Nomes $c2.falha) 'campos da falha'
    Assert-Igual 'rede' $c2.falha.etapa 'falha.etapa'
    Assert-Igual 'sem resposta' $c2.falha.erro 'falha.erro'
    Assert-Falso $c2.falha.recusa 'falha.recusa'
    Assert-Verdade $c2.falha.loginRecusado 'falha.loginRecusado'
    Assert-Falso $c2.falha.bloqueada 'falha.bloqueada'
    Assert-Igual 3 $c2.falha.geracao 'falha.geracao'

    Assert-Verdade ($null -eq $j.portao) 'portao livre'
    Assert-Igual 'max,admitindo,dhip,emCurso' (Get-Nomes $j.paralelo) 'campos de paralelo'
    Assert-Igual 0 $j.paralelo.max 'paralelo.max'
    Assert-Verdade $j.paralelo.admitindo 'paralelo.admitindo'
    Assert-Igual 'ok' $j.paralelo.dhip 'paralelo.dhip'
    Assert-Igual 1 $j.paralelo.emCurso 'paralelo.emCurso'

    Assert-Igual 3 @($j.filaItens).Count 'filaItens'
    $i0 = @($j.filaItens)[0]
    Assert-Igual 'Posicao,Ip,Estado,Motivo,Mac' (Get-Nomes $i0) 'campos do item da fila (formato de fila.itens)'
    Assert-Igual 'reservada' $i0.Estado 'posicao 1 reservada'
    Assert-Igual 'AA:00:00:00:00:01' $i0.Mac 'posicao 1 com o MAC'
    Assert-Igual 'reservada' @($j.filaItens)[1].Estado 'posicao 2 reservada para a decisao'
    Assert-Igual 'pendente' @($j.filaItens)[2].Estado 'posicao 3 pendente'

    Assert-Igual 'configurando' $j.fase 'fase legada (camera em curso)'
    Assert-Igual 1 $j.atual 'atual legado = camera em decisao'
    Assert-Igual '192.0.2.12' $j.camera.Destino 'camera legada: destino'
    Assert-Igual 'AA:00:00:00:00:02' $j.camera.Mac 'camera legada: mac'
    Assert-Igual 'Bloco A' $j.camera.Local 'camera legada: local da fila'
    Assert-Igual 'rede' $j.falha.etapa 'falha legada'
    Assert-Verdade ($r.Json -notlike ('*' + $script:senhaTeste + '*')) 'senha fora do estado publicado'
}

T 'estado publicado: camera no portao, sem progresso, e dhip sem resposta' {
    $coord = New-CoordNoPortao -N 1
    $coord.Dhip = 'sem-resposta'
    $j = (Get-PublicadoJson $coord).Obj
    $c = @($j.cameras)[0]
    Assert-Igual 'AA:00:00:00:00:01' $j.portao 'portao com o MAC'
    Assert-Igual 'portao' $c.fase 'fase'
    Assert-Igual '' $c.etapa 'sem etapa ainda'
    Assert-Verdade ($null -eq $c.progresso) 'sem progresso'
    Assert-Verdade ($c.trabalho -like '*192.0.2.11') ('trabalho cita o destino: ' + $c.trabalho)
    Assert-Igual 'sem-resposta' $j.paralelo.dhip 'paralelo.dhip'
    Assert-Igual 1 $j.paralelo.emCurso 'emCurso'
    Assert-Igual 1 @($j.cameras).Count 'uma camera vira lista no JSON'
}

# Derivacao dos campos legados: caso -> (fase, atual, tem falha).
$script:casosLegado = @(
    @{ Nome = 'ocioso (sem camera, posicoes pendentes)'; Fase = 'fila'; Atual = -1; Falha = $false; Montar = {
        New-Coordenador -Posicoes (New-PosicoesTeste 3) -Deps (New-DepsFalsas) } }
    @{ Nome = 'cameras so em espera'; Fase = 'fila'; Atual = -1; Falha = $false; Montar = {
        New-CoordComEspera -N 2 } }
    @{ Nome = 'em curso'; Fase = 'configurando'; Atual = 0; Falha = $false; Montar = {
        New-CoordNoPortao -N 2 } }
    @{ Nome = 'decisao'; Fase = 'decisao'; Atual = 0; Falha = $true; Montar = {
        $c = New-CoordNoPortao -N 1
        Invoke-PassoTeste $c (Step-FimDoJob -Estado $c.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $false; Etapa = ''; Falhou = 'inicializada'; Erro = 'x' })
        $c } }
    @{ Nome = 'decisao e outra em curso'; Fase = 'configurando'; Atual = 1; Falha = $true; Montar = {
        New-CoordPublicado } }
    @{ Nome = 'concluida'; Fase = 'concluida'; Atual = -1; Falha = $false; Montar = {
        $c = New-CoordNoPortao -N 1 -Posicoes 1
        Invoke-PassoTeste $c (Step-FimDoJob -Estado $c.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'rede' })
        Invoke-PassoTeste $c (Step-FimDoJob -Estado $c.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'encoder' })
        $c } }
    @{ Nome = 'encerrada (nada em curso)'; Fase = 'encerrada'; Atual = -1; Falha = $false; Montar = {
        $c = New-CoordComEspera -N 1
        Invoke-PassoTeste $c (Step-Decisao -Estado $c.Estado -Acao 'encerrar')
        $c } }
    @{ Nome = 'encerrada com camera em curso'; Fase = 'configurando'; Atual = 0; Falha = $false; Montar = {
        $c = New-CoordNoPortao -N 2
        Invoke-PassoTeste $c (Step-Decisao -Estado $c.Estado -Acao 'encerrar')
        $c } }
)

foreach ($script:caso in $script:casosLegado) {
    T ('campos legados: ' + $script:caso.Nome) {
        $coord = & $script:caso.Montar
        $j = (Get-PublicadoJson $coord).Obj
        Assert-Igual $script:caso.Fase $j.fase 'fase'
        Assert-Igual $script:caso.Atual $j.atual 'atual'
        if ($script:caso.Falha) { Assert-Verdade ($null -ne $j.falha) 'falha publicada' } else { Assert-Verdade ($null -eq $j.falha) 'sem falha' }
        if ($script:caso.Atual -ge 0) {
            Assert-Igual @($j.filaItens)[$script:caso.Atual].Ip $j.camera.Destino 'camera legada aponta para a posicao de atual'
        } else {
            Assert-Verdade ($null -eq $j.camera) 'sem camera legada'
        }
    }
}

# ------------------------------------------------------------ vigia paralelo

Write-Host ""
Write-Host "Vigia paralelo" -ForegroundColor Cyan

$script:ipFabrica = '192.168.1.108'
$script:TextoDuas = ('Duas c' + [char]0x00E2 + 'meras respondem em ')
$script:TextoInicializada = ('C' + [char]0x00E2 + 'mera j' + [char]0x00E1 + ' inicializada: n' + [char]0x00E3 + 'o tocada.')
$script:TextoIpOcupado = ('IP j' + [char]0x00E1 + ' responde na rede')
$script:TextoSemPosicao = ('sem posi' + [char]0x00E7 + [char]0x00E3 + 'o livre')

# Um tique do vigia com a leitura de rede dada; as acoes do tique e as da
# admissao seguinte sao executadas pelas Deps falsas. Devolve o retorno do
# tique mais Todas (as acoes do tique e da admissao, juntas).
function Invoke-TiqueTeste {
    param($Coord, $Achados = @(), $Registro = @(), [bool]$Dhip = $true, [bool]$Ping = $false, [string]$MacArp = '', [bool]$Trocando = $false)
    $r = Invoke-TiqueParalelo -Coord $Coord -Achados $Achados -Registro $Registro -DhipRespondeu $Dhip -PingFabrica $Ping `
                              -MacArp $MacArp -IpFabrica $script:ipFabrica -MacTrocando $Trocando
    $todas = @($r.Acoes)
    Invoke-AcoesCoordenador -Coord $Coord -Acoes $r.Acoes
    $adm = @(Invoke-AdmissaoCoordenador -Coord $Coord)
    $todas += $adm
    Invoke-AcoesCoordenador -Coord $Coord -Acoes $adm
    $r.Todas = $todas
    return $r
}

function Get-Avisos {
    param($Acoes)
    return @(@($Acoes) | Where-Object { $null -ne $_ -and $_.Tipo -eq 'avisar' } | ForEach-Object { [string]$_.Texto })
}

T 'sem DHIP e IP de fabrica respondendo: Max 1, aviso da D9 e achado do ARP com ConferirInit' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Deps (New-DepsFalsas)
    $r = Invoke-TiqueParalelo -Coord $coord -Achados @() -DhipRespondeu $false -PingFabrica $true -MacArp 'AA0000000003' -IpFabrica $script:ipFabrica
    Assert-Igual 1 $coord.Estado.Max 'Max uma por vez'
    Assert-Igual 'sem-resposta' $coord.Dhip 'dhip'
    Assert-Igual 'sem-resposta' (ConvertTo-EstadoPublicadoParalelo -Coord $coord).paralelo.dhip 'dhip publicado'
    $avisos = @(Get-Avisos $r.Acoes)
    Assert-Igual 1 $avisos.Count 'um aviso'
    Assert-Verdade ($avisos[0] -like '*UDP 37810*') ('aviso da D9: ' + $avisos[0])
    $c = Get-Camera $coord.Estado 3
    Assert-Verdade ($null -ne $c) 'achado do ARP entrou'
    Assert-Igual 'espera' $c.Fase 'em espera'
    Assert-Verdade $c.ConferirInit 'ConferirInit: o portao confere'
    Assert-Igual $script:ipFabrica $c.IpOrigem 'no IP de fabrica'
    Assert-Igual 1 @($r.Novas).Count 'uma nova'

    $r = Invoke-TiqueParalelo -Coord $coord -Achados @() -DhipRespondeu $false -PingFabrica $true -MacArp 'AA0000000003' -IpFabrica $script:ipFabrica
    Assert-Igual 0 @(Get-Avisos $r.Acoes).Count 'aviso so na passagem para sem resposta'
    Assert-Igual 1 @($coord.Estado.Cameras).Count 'mesmo MAC nao entra de novo'

    $null = Invoke-TiqueParalelo -Coord $coord -Achados @(New-AchadoTeste 1) -DhipRespondeu $true -IpFabrica $script:ipFabrica
    Assert-Igual 0 $coord.Estado.Max 'DHIP de volta: sem limite'
    Assert-Igual 'ok' $coord.Dhip 'dhip ok'
}

T 'sem DHIP e sem ping: nada muda; sem administrador o DHIP de volta mantem Max 1' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Deps (New-DepsFalsas)
    $r = Invoke-TiqueParalelo -Coord $coord -Achados @() -DhipRespondeu $false -PingFabrica $false -IpFabrica $script:ipFabrica
    Assert-Igual 0 $coord.Estado.Max 'Max'
    Assert-Igual 'ok' $coord.Dhip 'dhip'
    Assert-Igual 0 @($r.Acoes).Count 'sem acoes'

    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Max 1 -Deps (New-DepsFalsas)
    $null = Invoke-TiqueParalelo -Coord $coord -DhipRespondeu $false -PingFabrica $true -MacArp 'AA0000000003' -IpFabrica $script:ipFabrica
    $null = Invoke-TiqueParalelo -Coord $coord -Achados @(New-AchadoTeste 1) -DhipRespondeu $true -IpFabrica $script:ipFabrica
    Assert-Igual 1 $coord.Estado.Max 'Max base 1 (sem administrador) fica'
}

T 'MAC trocando no IP de fabrica: aviso "Duas cameras respondem em", uma vez por passagem' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Deps (New-DepsFalsas)
    $r = Invoke-TiqueParalelo -Coord $coord -DhipRespondeu $false -PingFabrica $true -MacArp 'AA0000000003' -IpFabrica $script:ipFabrica -MacTrocando $true
    $avisos = @(Get-Avisos $r.Acoes)
    Assert-Verdade ($avisos -contains ($script:TextoDuas + $script:ipFabrica + '.')) ('aviso: ' + ($avisos -join ' | '))
    $r = Invoke-TiqueParalelo -Coord $coord -DhipRespondeu $false -PingFabrica $true -MacArp 'AA0000000003' -IpFabrica $script:ipFabrica -MacTrocando $true
    Assert-Igual 0 @(Get-Avisos $r.Acoes).Count 'sem repetir'
    $null = Invoke-TiqueParalelo -Coord $coord -DhipRespondeu $false -PingFabrica $true -MacArp 'AA0000000003' -IpFabrica $script:ipFabrica -MacTrocando $false
    $r = Invoke-TiqueParalelo -Coord $coord -DhipRespondeu $false -PingFabrica $true -MacArp 'AA0000000003' -IpFabrica $script:ipFabrica -MacTrocando $true
    Assert-Igual 1 @(Get-Avisos $r.Acoes).Count 'volta a avisar depois de parar'
}

T 'camera em decisao nao impede a admissao da seguinte' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Deps (New-DepsFalsas)
    $null = Invoke-TiqueTeste $coord -Achados @((New-AchadoTeste 1), (New-AchadoTeste 2))
    Assert-Igual 'portao' (Get-Camera $coord.Estado 1).Fase 'camera 1 no portao'
    Invoke-PassoTeste $coord (Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $false; Etapa = ''; Falhou = 'inicializada'; Erro = 'sem resposta' })
    Assert-Igual 'decisao' (Get-Camera $coord.Estado 1).Fase 'camera 1 em decisao'
    $script:chamadas = @()
    $null = Invoke-TiqueTeste $coord -Achados @((New-AchadoTeste 1), (New-AchadoTeste 2))
    Assert-Igual 'portao' (Get-Camera $coord.Estado 2).Fase 'camera 2 entrou no portao'
    Assert-Igual 2 (Get-Camera $coord.Estado 2).Indice 'camera 2 na posicao 2'
    Assert-Igual 'prender AA:00:00:00:00:02 192.168.1.108|despachar AA:00:00:00:00:02 rede 2 192.0.2.12' ($script:chamadas -join '|') 'acoes da camera 2'
    Assert-Igual 'decisao' (Get-Camera $coord.Estado 1).Fase 'camera 1 continua em decisao'
}

T 'inicializada desconhecida: aviso unico e nenhuma prender/despachar' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Deps (New-DepsFalsas)
    $ini = New-AchadoTeste 4
    $ini.Init = 0
    $todas = @()
    for ($i = 0; $i -lt 3; $i++) { $todas += @((Invoke-TiqueTeste $coord -Achados @($ini)).Todas) }
    Assert-Igual 'avisar' ((@($todas | ForEach-Object { [string]$_.Tipo }) | Sort-Object -Unique) -join ',') 'so avisar em todas as acoes'
    Assert-Igual 1 @($todas).Count 'um aviso em tres tiques'
    Assert-Igual $script:TextoInicializada ([string]@($todas)[0].Texto) 'texto'
    Assert-Igual 0 @($script:chamadas).Count 'nenhuma chamada as Deps'
    Assert-Igual 0 @($coord.Estado.Cameras).Count 'nao entrou no estado'
}

T 'ping das posicoes: so com camera nova esperando e portao livre; IP ocupado pula' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Deps (New-DepsFalsas)
    $script:pings = @()
    $coord.Deps.Pingar = { param($Ips) $script:pings += ($Ips -join ','); return @($Ips | Where-Object { $_ -eq '192.0.2.11' }) }
    Assert-Igual 0 @(Invoke-AdmissaoCoordenador -Coord $coord).Count 'sem camera, sem acao'
    Assert-Igual 0 $script:pings.Count 'sem camera, sem ping'

    $null = Invoke-TiqueTeste $coord -Achados @((New-AchadoTeste 1), (New-AchadoTeste 2))
    Assert-Igual '192.0.2.11,192.0.2.12,192.0.2.13' ($script:pings -join '|') 'um lote com as pendentes'
    Assert-Igual 2 (Get-Camera $coord.Estado 1).Indice 'camera 1 na posicao 2'
    Assert-Igual 'pulada' @($coord.Estado.Posicoes)[0].Estado 'posicao 1 pulada'
    Assert-Igual $script:TextoIpOcupado @($coord.Estado.Posicoes)[0].Motivo 'motivo'

    $script:pings = @()
    $null = Invoke-TiqueTeste $coord -Achados @((New-AchadoTeste 1), (New-AchadoTeste 2))
    Assert-Igual 0 $script:pings.Count 'portao ocupado: sem ping'
}

T 'SemSucesso nao sobe com camera em curso; sobe com camera sem posicao livre' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 1) -Deps (New-DepsFalsas)
    $dois = @((New-AchadoTeste 1), (New-AchadoTeste 2))
    $null = Invoke-TiqueTeste $coord -Achados $dois
    Invoke-PassoTeste $coord (Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'rede' })
    $null = Invoke-AdmissaoCoordenador -Coord $coord
    Assert-Igual 'conferindo' (Get-Camera $coord.Estado 1).Fase 'camera 1 em curso'
    Assert-Igual $script:TextoSemPosicao (Get-Camera $coord.Estado 2).Motivo 'camera 2 sem posicao'
    for ($i = 0; $i -lt 3; $i++) { $null = Invoke-TiqueTeste $coord -Achados $dois }
    Assert-Igual 0 $coord.SemSucesso 'com camera em curso'

    Invoke-PassoTeste $coord (Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'conferencia' })
    $null = Invoke-TiqueTeste $coord -Achados $dois
    $null = Invoke-TiqueTeste $coord -Achados $dois
    Assert-Igual 2 $coord.SemSucesso 'sem camera em curso, camera 2 travada'
    $null = Invoke-TiqueTeste $coord -Achados @()
    Assert-Igual 2 $coord.SemSucesso 'tique sem ver camera nao muda'
}

T 'SemSucesso: camera em decisao nao conta; sem DHIP e sem MAC no ARP conta' {
    $coord = New-Coordenador -Posicoes (New-PosicoesTeste 3) -Deps (New-DepsFalsas)
    $null = Invoke-TiqueTeste $coord -Achados @(New-AchadoTeste 1)
    Invoke-PassoTeste $coord (Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $false; Etapa = ''; Falhou = 'inicializada'; Erro = 'x' })
    $null = Invoke-TiqueTeste $coord -Achados @(New-AchadoTeste 1)
    Assert-Igual 0 $coord.SemSucesso 'decisao nao conta'
    $null = Invoke-TiqueTeste $coord -Dhip $false -Ping $true -MacArp ''
    Assert-Igual 1 $coord.SemSucesso 'IP de fabrica responde sem DHIP e sem MAC'
}

# ------------------------------------------------------------------- porta/canal e FalharEm

Write-Host ""
Write-Host "Porta/canal por camera e FalharEm" -ForegroundColor Cyan

# Coordenador com a camera 1 em 'conferindo' (Deps falsas) e o registro numa
# pasta temporaria, com a entrada que o job do portao teria gravado
# (Porta/Canal do despacho). -Porta/-Canal: o que o cartao tinha antes do
# portao (vazio = nunca editado).
function New-CoordConferindo {
    param([string]$Porta = '', [string]$Canal = '')
    $coord = New-CoordComEspera -N 1
    $script:pastaPc = Join-Path ([IO.Path]::GetTempPath()) ('coord-pc-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:pastaPc -Force
    $coord.Trabalho.CaminhoRegistro = Join-Path $script:pastaPc 'registro.json'
    if ($Porta -ne '' -or $Canal -ne '') {
        $r = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta $Porta -Canal $Canal
        Assert-Verdade $r.Ok 'porta/canal antes do portao aceitos'
    }
    Invoke-PassoTeste $coord (Step-Admissao -Estado $coord.Estado)
    Invoke-PassoTeste $coord (Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'rede' })
    Assert-Igual 'conferindo' (Get-Camera $coord.Estado 1).Fase 'camera 1 conferindo'
    $ent = New-EntradaRegistro -Mac 'AA:00:00:00:00:01' -Ip '192.0.2.11'
    $ent.Status = 'Instalada'; $ent.Etapa = 'conferida'; $ent.Local = 'Obra exemplo'; $ent.Porta = $Porta; $ent.Canal = $Canal
    $null = Update-RegistroCamera -Caminho $coord.Trabalho.CaminhoRegistro -Entrada $ent
    return $coord
}

# Fim da conferencia pelo Complete-JobCoordenador, com um job falso (sem
# runspace: EndInvoke e Dispose falham em silencio, como num job ja fechado).
function Complete-ConferenciaTeste {
    param($Coord, $Resultado = @{ Ok = $true; Etapa = 'conferida' })
    $job = @{ Id = 'job-teste'; Mac = 'AA:00:00:00:00:01'; Chave = 'AA0000000001'; PowerShell = $null; Handle = $null
              Geracao = 0; AteEtapa = ''; Etapa = '' }
    $Coord.Jobs['AA0000000001'] = $job
    Complete-JobCoordenador -Coord $Coord -Job $job -Resultado $Resultado
}

T 'porta/canal editados na conferencia: o feita corrige o registro' {
    $coord = New-CoordConferindo -Porta '1' -Canal '1'
    try {
        Assert-Igual '1|1' ($coord.PortaCanalDespacho['AA0000000001'].Porta + '|' + $coord.PortaCanalDespacho['AA0000000001'].Canal) 'porta/canal do despacho'
        $coord.Sujo = $false
        $r = Set-PortaCanalCoordenador -Coord $coord -Mac 'aa-00-00-00-00-01' -Porta ' 5 ' -Canal '9'
        Assert-Verdade $r.Ok 'edicao na conferencia aceita'
        Assert-Verdade $coord.Sujo 'estado sujo depois da edicao'
        Complete-ConferenciaTeste $coord
        Assert-Igual 'feita' (Get-Camera $coord.Estado 1).Fase 'fase'
        $ent = Find-CameraRegistro -Registro (Read-Registro $coord.Trabalho.CaminhoRegistro) -Mac 'AA:00:00:00:00:01'
        Assert-Igual '5|9' ($ent.Porta + '|' + $ent.Canal) 'porta/canal corrigidos no registro'
        Assert-Igual 'Instalada|Obra exemplo|192.0.2.11' ($ent.Status + '|' + $ent.Local + '|' + $ent.Ip) 'resto da entrada intacto'
        $pub = ConvertTo-EstadoPublicadoParalelo -Coord $coord
        Assert-Igual '5|9' ($pub.cameras[0].porta + '|' + $pub.cameras[0].canal) 'porta/canal publicados'
    } finally { Remove-Item -LiteralPath $script:pastaPc -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'porta/canal sem edicao depois do despacho: o registro nao muda' {
    foreach ($pc in @(@('1', '1'), @('', ''))) {
        $coord = New-CoordConferindo -Porta $pc[0] -Canal $pc[1]
        try {
            if ($pc[0] -ne '') {
                # Mesmo valor de novo: nao conta como edicao.
                $null = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta '1' -Canal '1'
            }
            $antes = [IO.File]::ReadAllText($coord.Trabalho.CaminhoRegistro)
            $quando = (Get-Item -LiteralPath $coord.Trabalho.CaminhoRegistro).LastWriteTimeUtc
            Start-Sleep -Milliseconds 20
            Complete-ConferenciaTeste $coord
            Assert-Igual 'feita' (Get-Camera $coord.Estado 1).Fase ('fase (porta ' + $pc[0] + ')')
            Assert-Igual $antes ([IO.File]::ReadAllText($coord.Trabalho.CaminhoRegistro)) ('registro igual (porta ' + $pc[0] + ')')
            Assert-Igual $quando (Get-Item -LiteralPath $coord.Trabalho.CaminhoRegistro).LastWriteTimeUtc ('registro nao regravado (porta ' + $pc[0] + ')')
        } finally { Remove-Item -LiteralPath $script:pastaPc -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

T 'porta/canal editados e conferencia com falha: registro intacto ate o feita' {
    $coord = New-CoordConferindo -Porta '1' -Canal '1'
    try {
        $null = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta '5' -Canal '9'
        Complete-ConferenciaTeste $coord @{ Ok = $false; Etapa = 'rede'; Falhou = 'conferida'; Erro = 'falha simulada' }
        Assert-Igual 'decisao' (Get-Camera $coord.Estado 1).Fase 'fase'
        $ent = Find-CameraRegistro -Registro (Read-Registro $coord.Trabalho.CaminhoRegistro) -Mac 'AA:00:00:00:00:01'
        Assert-Igual '1|1' ($ent.Porta + '|' + $ent.Canal) 'sem correcao na falha'
        $r = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta '6' -Canal '9'
        Assert-Verdade $r.Ok 'em decisao continua editavel'
    } finally { Remove-Item -LiteralPath $script:pastaPc -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'porta/canal: camera feita aceita e grava direto no registro (C2)' {
    $coord = New-CoordConferindo
    try {
        Complete-ConferenciaTeste $coord
        Assert-Igual 'feita' (Get-Camera $coord.Estado 1).Fase 'fase'
        $coord.Sujo = $false
        $r = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta '7' -Canal '8'
        Assert-Verdade $r.Ok ('feita aceita: ' + $r.Texto)
        Assert-Verdade $coord.Sujo 'estado sujo depois da edicao'
        $ent = Find-CameraRegistro -Registro (Read-Registro $coord.Trabalho.CaminhoRegistro) -Mac 'AA:00:00:00:00:01'
        Assert-Igual '7|8' ($ent.Porta + '|' + $ent.Canal) 'porta/canal no registro'
        Assert-Igual 'Instalada|Obra exemplo|192.0.2.11' ($ent.Status + '|' + $ent.Local + '|' + $ent.Ip) 'resto da entrada intacto'

        $r = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta '9' -Canal '8'
        Assert-Verdade $r.Ok ('segunda edicao aceita: ' + $r.Texto)
        $ent = Find-CameraRegistro -Registro (Read-Registro $coord.Trabalho.CaminhoRegistro) -Mac 'AA:00:00:00:00:01'
        Assert-Igual '9|8' ($ent.Porta + '|' + $ent.Canal) 'segunda edicao no registro'
        $pub = ConvertTo-EstadoPublicadoParalelo -Coord $coord
        Assert-Igual '9|8' ($pub.cameras[0].porta + '|' + $pub.cameras[0].canal) 'porta/canal publicados'
    } finally { Remove-Item -LiteralPath $script:pastaPc -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'porta/canal: feita fora do registro e recusada com aviso, sem estourar' {
    $coord = New-CoordConferindo -Porta '1' -Canal '1'
    try {
        Complete-ConferenciaTeste $coord
        Remove-Item -LiteralPath $coord.Trabalho.CaminhoRegistro -Force
        $r = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta '7' -Canal '7'
        Assert-Falso $r.Ok 'feita fora do registro recusada'
        Assert-Verdade ([string]$r.Texto -like '*porta*') ('texto da recusa: ' + $r.Texto)
        Assert-Verdade ([string]$coord.AvisosCamera['AA0000000001'] -like '*porta*') ('aviso: ' + $coord.AvisosCamera['AA0000000001'])
        Assert-Igual '1|1' ($coord.PortaCanal['AA0000000001'].Porta + '|' + $coord.PortaCanal['AA0000000001'].Canal) 'porta/canal da fila sem a edicao recusada'
    } finally { Remove-Item -LiteralPath $script:pastaPc -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'porta/canal: camera pulada ou fora da fila e recusada, sem mudar nada' {
    $coord = New-CoordConferindo -Porta '1' -Canal '1'
    try {
        $r = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:09' -Porta '7' -Canal '7'
        Assert-Falso $r.Ok 'fora da fila recusada'
        Assert-Falso $coord.PortaCanal.ContainsKey('AA0000000009') 'nada guardado para MAC fora da fila'

        $antes = [IO.File]::ReadAllText($coord.Trabalho.CaminhoRegistro)
        (Get-Camera $coord.Estado 1).Fase = 'pulada'
        $r = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta '7' -Canal '7'
        Assert-Falso $r.Ok 'pulada recusada'
        Assert-Verdade ([string]$r.Texto -like '*AA:00:00:00:00:01*saiu da fila: porta e canal*') ('texto da recusa (pulada): ' + $r.Texto)
        Assert-Igual '1' $coord.PortaCanal['AA0000000001'].Porta 'porta nao mudou'
        Assert-Igual $antes ([IO.File]::ReadAllText($coord.Trabalho.CaminhoRegistro)) 'registro intocado (pulada)'
    } finally { Remove-Item -LiteralPath $script:pastaPc -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'porta/canal: registro sem a camera vira aviso dela, sem estourar' {
    $coord = New-CoordConferindo -Porta '1' -Canal '1'
    try {
        $null = Set-PortaCanalCoordenador -Coord $coord -Mac 'AA:00:00:00:00:01' -Porta '5' -Canal '9'
        Remove-Item -LiteralPath $coord.Trabalho.CaminhoRegistro -Force
        Complete-ConferenciaTeste $coord
        Assert-Igual 'feita' (Get-Camera $coord.Estado 1).Fase 'fase'
        Assert-Verdade ([string]$coord.AvisosCamera['AA0000000001'] -like '*porta*') ('aviso: ' + $coord.AvisosCamera['AA0000000001'])
    } finally { Remove-Item -LiteralPath $script:pastaPc -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'FalharEm: so o primeiro despacho que alcanca a etapa leva a falha' {
    $coord = New-Coordenador -Deps (New-DepsFalsas)
    $coord.Trabalho.FalharEm = 'conferida'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede') 'portao nao alcanca conferida'
    Assert-Igual 'conferida' $coord.Trabalho.FalharEm 'continua armada'
    Assert-Igual 'conferida' (Use-FalharEmCoordenador -Coord $coord -AteEtapa '') 'a conferencia leva'
    Assert-Igual '' $coord.Trabalho.FalharEm 'desarmada'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa '') 'a seguinte passa'

    $coord.Trabalho.FalharEm = 'encoder'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa '') 'conferencia nao alcanca encoder'
    Assert-Igual 'encoder' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede') 'o portao leva'
    Assert-Igual '' $coord.Trabalho.FalharEm 'desarmada (portao)'
}

# S2: cenarios por camera num mapa so.
T 'FalharEm em tabela: so o despacho da camera 2 leva a falha da rede, uma vez' {
    $coord = New-Coordenador -Deps (New-DepsFalsas)
    $coord.Trabalho.FalharEm = Get-FalharEmTrabalho @{ '2' = 'rede' }
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'AA:00:00:00:00:01') 'portao da 1 passa'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa '' -Mac 'AA:00:00:00:00:02') 'conferencia da 2 nao alcanca rede'
    Assert-Igual 'rede' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'aa-00-00-00-00-02') 'portao da 2 leva'
    Assert-Igual 0 $coord.Trabalho.FalharEm.Count 'entrada da 2 saiu'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'AA:00:00:00:00:02') 'o tentar de novo da 2 passa'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'AA:00:00:00:00:03') 'portao da 3 passa'
}

T 'FalharEm em tabela: mac-trocado so no portao daquela camera; as outras entradas ficam' {
    $coord = New-Coordenador -Deps (New-DepsFalsas)
    $coord.Trabalho.FalharEm = Get-FalharEmTrabalho @{ '2' = 'mac-trocado'; '3' = 'conferida' }
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'AA:00:00:00:00:01') 'portao da 1 passa'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa '' -Mac 'AA:00:00:00:00:02') 'conferencia da 2 nao leva mac-trocado'
    Assert-Igual 'mac-trocado' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'AA:00:00:00:00:02') 'portao da 2 leva'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'AA:00:00:00:00:02') 'a readmissao da 2 passa'
    Assert-Igual 'AA0000000003' ((@($coord.Trabalho.FalharEm.Keys) | Sort-Object) -join ',') 'a entrada da 3 continua armada'
    Assert-Igual 'conferida' (Use-FalharEmCoordenador -Coord $coord -AteEtapa '' -Mac 'AA:00:00:00:00:03') 'conferencia da 3 leva'
}

T 'FalharEm em texto: mac-trocado vale para o primeiro portao' {
    $coord = New-Coordenador -Deps (New-DepsFalsas)
    $coord.Trabalho.FalharEm = 'mac-trocado'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa '' -Mac 'AA:00:00:00:00:01') 'conferencia nao leva'
    Assert-Igual 'mac-trocado' $coord.Trabalho.FalharEm 'continua armada'
    Assert-Igual 'mac-trocado' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'AA:00:00:00:00:02') 'primeiro portao leva'
    Assert-Igual '' $coord.Trabalho.FalharEm 'desarmada'
    Assert-Igual '' (Use-FalharEmCoordenador -Coord $coord -AteEtapa 'rede' -Mac 'AA:00:00:00:00:03') 'o portao seguinte passa'
}

T 'ConvertTo-FalharEmSimulado: texto, mapa do JSON, numero fora de 1..N e valor desconhecido' {
    $r = ConvertTo-FalharEmSimulado -Valor 'conferida' -Cameras 3
    Assert-Verdade ($r.Ok -and $r.Valor -eq 'conferida') 'texto passa'
    $r = ConvertTo-FalharEmSimulado -Valor $null -Cameras 3
    Assert-Verdade ($r.Ok -and $r.Valor -eq '') 'nulo = nada armado'
    $r = ConvertTo-FalharEmSimulado -Valor ('{"2":"rede","3":"ja-inicializada"}' | ConvertFrom-Json) -Cameras 3
    Assert-Verdade $r.Ok ('mapa do JSON: ' + $r.Texto)
    Assert-Igual '2=rede,3=ja-inicializada' ((@($r.Valor.Keys) | Sort-Object | ForEach-Object { $_ + '=' + $r.Valor[$_] }) -join ',') 'mapa n -> valor'
    $r = ConvertTo-FalharEmSimulado -Valor ('{}' | ConvertFrom-Json) -Cameras 3
    Assert-Verdade ($r.Ok -and $r.Valor -eq '') 'mapa vazio = nada armado'
    $r = ConvertTo-FalharEmSimulado -Valor @{ '4' = 'rede' } -Cameras 3
    Assert-Falso $r.Ok 'camera 4 com 3 simuladas'
    Assert-Verdade ($r.Texto -like '*de 1 a 3*') ('texto: ' + $r.Texto)
    $r = ConvertTo-FalharEmSimulado -Valor @{ '2' = 'portao' } -Cameras 3
    Assert-Falso $r.Ok 'valor desconhecido'
    Assert-Verdade ($r.Texto -like '*portao*') ('texto: ' + $r.Texto)
}

T 'Get-FalharEmTrabalho: numero vira MAC, ja-inicializada fica de fora, texto passa' {
    $t = Get-FalharEmTrabalho @{ '2' = 'rede'; '11' = 'mac-trocado'; '3' = 'ja-inicializada' }
    Assert-Igual 'AA0000000002=rede,AA000000000B=mac-trocado' ((@($t.Keys) | Sort-Object | ForEach-Object { $_ + '=' + $t[$_] }) -join ',') 'tabela por MAC'
    Assert-Igual 'encoder' (Get-FalharEmTrabalho 'encoder') 'texto'
    Assert-Igual 'AA:00:00:00:00:10' (Get-MacSimulado 16) 'MAC da camera 16'
}

T 'pool: tabela com a camera 2 na rede: so a 2 vai a decisao, e o tentar dela passa' {
    $coord = $null
    try {
        $coord = New-CoordPool -N 3 -Escala 0.1
        $coord.Trabalho.FalharEm = Get-FalharEmTrabalho @{ '2' = 'rede' }
        Assert-Verdade (Invoke-LacoTeste -Coord $coord) 'laco terminou no tempo'
        Assert-Igual 'feita,decisao,feita' ((@($coord.Estado.Cameras) | ForEach-Object { $_.Fase }) -join ',') 'fases'
        Assert-Igual 'rede' (Get-Camera $coord.Estado 2).Falha.Etapa 'etapa da falha'
        Assert-Igual 0 $coord.Trabalho.FalharEm.Count 'entrada consumida'
        $p = Step-Decisao -Estado $coord.Estado -Mac 'AA:00:00:00:00:02' -Acao 'tentar' -Geracao 0
        $coord.Estado = $p.Estado
        Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
        Assert-Verdade (Invoke-LacoTeste -Coord $coord) 'laco do tentar terminou no tempo'
        Assert-Igual 'feita,feita,feita' ((@($coord.Estado.Cameras) | ForEach-Object { $_.Fase }) -join ',') 'fases depois do tentar'
    } finally { Remove-CoordPool $coord }
}

T 'pool: tabela com mac-trocado na camera 2: volta a espera sem decisao e termina feita' {
    $coord = $null
    try {
        $coord = New-CoordPool -N 3 -Escala 0.1
        $coord.Trabalho.FalharEm = Get-FalharEmTrabalho @{ '2' = 'mac-trocado' }
        Assert-Verdade (Invoke-LacoTeste -Coord $coord) 'laco terminou no tempo'
        Assert-Igual 'feita,feita,feita' ((@($coord.Estado.Cameras) | ForEach-Object { $_.Fase }) -join ',') 'fases'
        $portoes2 = @($script:eventos | Where-Object { $_.Mac -eq 'AA:00:00:00:00:02' -and $_.Tipo -eq 'log' -and $_.Texto -match 'port.o, at. a rede ---$' }).Count
        Assert-Igual 2 $portoes2 'a 2 passou duas vezes pelo portao'
        $trocados = @($script:eventos | Where-Object { $_.Tipo -eq 'log' -and $_.Texto -like '*MAC TROCADO*' } | ForEach-Object { $_.Mac })
        Assert-Igual 'AA:00:00:00:00:02' ($trocados -join ',') 'so a 2 levou a trava de MAC'
        Assert-Igual 0 $coord.AvisosCamera.Count 'nenhum aviso de camera'
    } finally { Remove-CoordPool $coord }
}

# ------------------------------------------------------------ encerrar e atualizar (S4)

Write-Host ""
Write-Host "Encerrar e atualizar sem cortar camera (S4)" -ForegroundColor Cyan

T 'SemDespacho: fim do portao solta a camera e pula o despacho da conferencia, com log por camera' {
    $coord = New-CoordComEspera -N 1
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
    $script:chamadas = @()

    $f = Step-FimDoJob -Estado $coord.Estado -Mac 'AA:00:00:00:00:01' -Resultado @{ Ok = $true; Etapa = 'rede' } -Geracao 0
    $coord.Estado = $f.Estado
    $script:logsS4 = New-Object 'System.Collections.Generic.List[object]'
    Invoke-AcoesCoordenador -Coord $coord -Acoes $f.Acoes -SemDespacho -Log { param($Ev) $script:logsS4.Add($Ev) }

    Assert-Igual 'soltar AA:00:00:00:00:01 192.168.1.108' ($script:chamadas -join '|') 'so o soltar, sem despachar'
    Assert-Igual 1 $script:logsS4.Count 'um log'
    Assert-Igual 'AA:00:00:00:00:01' ([string]$script:logsS4[0].Mac) 'log da camera'
    Assert-Verdade ([string]$script:logsS4[0].Texto -like '*pulad*') ('texto do log: ' + $script:logsS4[0].Texto)
    Assert-Igual 'conferindo' (Get-Camera $coord.Estado 1).Fase 'fase'
}

T 'SemDespacho: prender e avisar continuam; sem -Log nao estoura' {
    $coord = New-CoordComEspera -N 1
    $p = Step-Admissao -Estado $coord.Estado
    $coord.Estado = $p.Estado
    $acoes = @($p.Acoes) + @(@{ Tipo = 'avisar'; Mac = ''; Texto = 'aviso de teste' })
    Invoke-AcoesCoordenador -Coord $coord -Acoes $acoes -SemDespacho
    Assert-Igual 'prender AA:00:00:00:00:01 192.168.1.108' ($script:chamadas -join '|') 'prender sim, despachar nao'
    Assert-Igual 'aviso de teste' $coord.AvisoGlobal 'avisar executado'
}

T 'Test-AtualizacaoEmCurso: pedido feito ou baixando/verificando/instalando' {
    $casos = @(
        @($false, 'nenhuma', $false), @($false, 'disponivel', $false), @($false, 'erro', $false), @($false, 'desligada', $false),
        @($false, '', $false), @($true, 'disponivel', $true), @($true, '', $true),
        @($false, 'baixando', $true), @($false, 'verificando', $true), @($false, 'instalando', $true)
    )
    foreach ($c in $casos) {
        Assert-Igual $c[2] (Test-AtualizacaoEmCurso -Pedido $c[0] -Estado $c[1]) ('pedido ' + $c[0] + ', estado "' + $c[1] + '"')
    }
}

T 'Wait-JobsCoordenador: portao em curso termina, soltar acontece, conferencia pulada com log, devolve 0' {
    $coord = $null
    try {
        $coord = New-CoordPool -N 1 -Escala 0.5
        $p = Step-Admissao -Estado $coord.Estado
        $coord.Estado = $p.Estado
        Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
        Assert-Igual 1 $coord.Jobs.Count 'job de portao em curso'
        $script:chamadas = @()
        $script:logsS4 = New-Object 'System.Collections.Generic.List[object]'
        $sobra = Wait-JobsCoordenador -Coord $coord -LimiteSeg 60 -Log { param($Ev) $script:logsS4.Add($Ev) }
        Assert-Igual 0 $sobra 'jobs que sobraram'
        Assert-Igual 0 $coord.Jobs.Count 'nenhum job'
        Assert-Igual 'soltar AA:00:00:00:00:01 192.168.1.108' ($script:chamadas -join '|') 'soltar no fim do portao'
        Assert-Igual 0 $script:presos.Count 'nada preso'
        $c = Get-Camera $coord.Estado 1
        Assert-Igual 'conferindo|rede' ($c.Fase + '|' + $c.Etapa) 'portao feito, conferencia nao despachada'
        $pulados = @($script:logsS4 | Where-Object { [string]$_.Mac -eq 'AA:00:00:00:00:01' -and [string]$_.Texto -like '*pulad*' })
        Assert-Igual 1 $pulados.Count 'log do despacho pulado'
        $ent = Find-CameraRegistro -Registro (Read-Registro $coord.Trabalho.CaminhoRegistro) -Mac 'AA:00:00:00:00:01'
        Assert-Igual 'rede' ([string]$ent.Etapa) 'registro na etapa rede'
        Assert-Verdade ([string]$ent.Status -ne 'Instalada') ('registro nao instalada: ' + $ent.Status)
    } finally { Remove-CoordPool $coord }
}

T 'Wait-JobsCoordenador: teto menor que o job devolve 1; sem job devolve 0 na hora' {
    $coord = $null
    try {
        $coord = New-CoordPool -N 1 -Escala 5
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Assert-Igual 0 (Wait-JobsCoordenador -Coord $coord -LimiteSeg 30) 'sem job'
        Assert-Verdade ($sw.Elapsed.TotalSeconds -lt 1) ('sem job volta na hora: ' + $sw.Elapsed.TotalSeconds + ' s')
        $p = Step-Admissao -Estado $coord.Estado
        $coord.Estado = $p.Estado
        Invoke-AcoesCoordenador -Coord $coord -Acoes $p.Acoes
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Assert-Igual 1 (Wait-JobsCoordenador -Coord $coord -LimiteSeg 1) 'job maior que o teto'
        Assert-Verdade ($sw.Elapsed.TotalSeconds -lt 3) ('respeita o teto: ' + $sw.Elapsed.TotalSeconds + ' s')
        Assert-Igual 1 $coord.Jobs.Count 'o job continua no coordenador'
    } finally { Remove-CoordPool $coord }
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
