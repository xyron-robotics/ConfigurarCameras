<#
    Testes-Orquestrador.ps1
    Testes do Orquestrador-Cameras.ps1 sem camera, rede, placa nem disco.

    O orquestrador e uma maquina de estado pura: recebe estado mais evento e
    devolve o novo estado e a lista de acoes. Nao executa nada ao carregar,
    entao aqui ele e carregado por dot-source direto. Cobre:
      - estado inicial (posicoes copiadas, Max, portao livre, admitindo);
      - resumo por fase;
      - descoberta (achados DHIP -> espera, dedup por MAC, marca nao suportada);
      - admissao (portao de 1 vaga, Max, posicao na entrada, destino ocupado).

    Valores ficticios: MAC AA:00:00:00:00:0x, serial SIM-x, IPs de
    documentacao (192.0.2.x) e a faixa de fabrica 192.168.1.108.

    Uso:
        .\Testes-Orquestrador.ps1
    Sai com codigo 1 se algum teste falhar.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$raiz = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($raiz)) { $raiz = (Get-Location).Path }
$orquestrador = Join-Path $raiz 'Orquestrador-Cameras.ps1'

. $orquestrador

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

# Posicoes no formato de New-FilaDeFaixa (Motor-Cameras.ps1).
function New-PosicoesTeste {
    param([int]$N = 3)
    $l = @()
    for ($i = 1; $i -le $N; $i++) {
        $l += [pscustomobject]@{ Posicao = $i; Ip = ('192.0.2.' + (10 + $i)); Estado = 'pendente'; Motivo = ''; Mac = '' }
    }
    return ,$l
}

function New-CameraTeste {
    param([int]$N, [string]$Fase = 'espera')
    return @{
        Mac = ('AA:00:00:00:00:0' + $N); Serial = ('SIM-' + $N); Modelo = 'VIP-SIM'
        IpOrigem = '192.168.1.108'; HttpPort = 80; Indice = 0
        Fase = $Fase; Etapa = ''; Falha = $null; GeracaoLogin = 0
    }
}

# ------------------------------------------------------------------- esqueleto

T 'Estado novo: posicoes copiadas, Max padrao 0, portao livre, admitindo, sem cameras' {
    $pos = New-PosicoesTeste 3
    $e = New-EstadoParalelo -Posicoes $pos
    Assert-Igual 3 @($e.Posicoes).Count 'posicoes'
    Assert-Igual '192.0.2.12' $e.Posicoes[1].Ip 'ip da posicao 2'
    Assert-Igual 'pendente' $e.Posicoes[2].Estado 'estado da posicao 3'
    Assert-Igual 0 $e.Max 'Max'
    Assert-Verdade ($null -eq $e.Portao) 'portao livre'
    Assert-Verdade ($e.Admitindo -eq $true) 'admitindo'
    Assert-Igual 0 @($e.Cameras).Count 'cameras'
    Assert-Igual 0 $e.Avisados.Count 'avisados'
}

T 'Estado novo: Max 1 (modo de reserva) e Max negativo recusado' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2) -Max 1
    Assert-Igual 1 $e.Max 'Max'
    $recusou = $false
    try { New-EstadoParalelo -Posicoes (New-PosicoesTeste 2) -Max -1 | Out-Null } catch { $recusou = $true }
    Assert-Verdade $recusou 'Max negativo recusado'
}

T 'Estado novo: nao muta as posicoes de entrada' {
    $pos = New-PosicoesTeste 2
    $e = New-EstadoParalelo -Posicoes $pos
    $e.Posicoes[0].Estado = 'feita'
    $e.Posicoes[0].Mac = 'AA:00:00:00:00:01'
    Assert-Igual 'pendente' $pos[0].Estado 'estado de entrada'
    Assert-Igual '' $pos[0].Mac 'mac de entrada'
}

T 'Estado novo: zero e uma posicao continuam lista' {
    $e0 = New-EstadoParalelo -Posicoes @()
    Assert-Igual 0 @($e0.Posicoes).Count 'zero posicoes'
    $e1 = New-EstadoParalelo -Posicoes (New-PosicoesTeste 1)
    Assert-Igual 1 @($e1.Posicoes).Count 'uma posicao'
    Assert-Igual '192.0.2.11' $e1.Posicoes[0].Ip 'ip da unica posicao'
}

T 'Resumo de estado novo: todas as fases em zero, portao livre, admitindo' {
    $r = Get-Resumo -Estado (New-EstadoParalelo -Posicoes (New-PosicoesTeste 3))
    foreach ($f in @('espera', 'portao', 'conferindo', 'decisao', 'feita', 'pulada')) {
        Assert-Igual 0 $r.Fases[$f] ('fase ' + $f)
    }
    Assert-Igual 0 $r.Total 'total'
    Assert-Verdade ($null -eq $r.Portao) 'portao livre'
    Assert-Verdade ($r.Admitindo -eq $true) 'admitindo'
}

T 'Resumo conta por fase e mostra portao e admitindo' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $e.Cameras = @(
        (New-CameraTeste 1 'portao'),
        (New-CameraTeste 2 'espera'),
        (New-CameraTeste 3 'espera'),
        (New-CameraTeste 4 'conferindo'),
        (New-CameraTeste 5 'decisao'),
        (New-CameraTeste 6 'feita'),
        (New-CameraTeste 7 'pulada')
    )
    $e.Portao = 'AA:00:00:00:00:01'
    $e.Admitindo = $false
    $r = Get-Resumo -Estado $e
    Assert-Igual 2 $r.Fases['espera'] 'espera'
    Assert-Igual 1 $r.Fases['portao'] 'portao'
    Assert-Igual 1 $r.Fases['conferindo'] 'conferindo'
    Assert-Igual 1 $r.Fases['decisao'] 'decisao'
    Assert-Igual 1 $r.Fases['feita'] 'feita'
    Assert-Igual 1 $r.Fases['pulada'] 'pulada'
    Assert-Igual 7 $r.Total 'total'
    Assert-Igual 'AA:00:00:00:00:01' $r.Portao 'portao'
    Assert-Verdade ($r.Admitindo -eq $false) 'nao admitindo'
}

T 'Resumo recusa fase desconhecida' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 1)
    $e.Cameras = @((New-CameraTeste 1 'inventada'))
    $recusou = $false
    try { Get-Resumo -Estado $e | Out-Null } catch { $recusou = $true }
    Assert-Verdade $recusou 'fase desconhecida recusada'
}

# ------------------------------------------------------------------ descoberta

# Achado DHIP no formato que o servidor entrega ao Step-Descoberta.
# Init: 1 = de fabrica, 0/2/3 = inicializada, -1 = desconhecido.
function New-AchadoTeste {
    param([int]$N, [int]$Init = 1, [string]$Ip = '192.168.1.108', [string]$Marca = 'Intelbras', $HttpPort = 80)
    return [pscustomobject]@{
        Mac = ('AA:00:00:00:00:0' + $N); Serial = ('SIM-' + $N); Modelo = 'VIP-SIM'
        Ip = $Ip; HttpPort = $HttpPort; Init = $Init; Marca = $Marca
    }
}

function Get-AcoesDoTipo {
    param($Resultado, [string]$Tipo)
    return @(@($Resultado.Acoes) | Where-Object { $null -ne $_ -and $_.Tipo -eq $Tipo })
}

# 'Marca nao suportada: nao tocada.' com acento, sem acento neste arquivo.
$script:TextoMarca = ('Marca n' + [char]0x00E3 + 'o suportada: n' + [char]0x00E3 + 'o tocada.')

T 'Descoberta: duas de fabrica no mesmo IP vao para espera, na ordem de chegada' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $r = Step-Descoberta -Estado $e -Achados @((New-AchadoTeste 2), (New-AchadoTeste 1))
    $c = @($r.Estado.Cameras)
    Assert-Igual 2 $c.Count 'cameras'
    Assert-Igual 'AA:00:00:00:00:02' $c[0].Mac 'primeira a chegar'
    Assert-Igual 'AA:00:00:00:00:01' $c[1].Mac 'segunda a chegar'
    foreach ($x in $c) {
        Assert-Igual 'espera' $x.Fase ('fase de ' + $x.Mac)
        Assert-Igual '192.168.1.108' $x.IpOrigem ('IpOrigem de ' + $x.Mac)
        Assert-Igual 0 $x.Indice ('indice de ' + $x.Mac + ' (posicao so no portao)')
        Assert-Igual 0 $x.GeracaoLogin ('GeracaoLogin de ' + $x.Mac)
        Assert-Verdade ($null -eq $x.Falha) ('sem falha em ' + $x.Mac)
    }
    Assert-Igual 'SIM-2' $c[0].Serial 'serial'
    Assert-Igual 'VIP-SIM' $c[0].Modelo 'modelo'
    Assert-Igual 80 $c[0].HttpPort 'porta http'
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
    Assert-Igual 2 (Get-Resumo -Estado $r.Estado).Fases['espera'] 'resumo: espera'
}

T 'Descoberta: estado de entrada nao e mutado' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)
    $r = Step-Descoberta -Estado $e -Achados @((New-AchadoTeste 1), (New-AchadoTeste 9 -Marca 'OutraMarca'))
    Assert-Igual 0 @($e.Cameras).Count 'cameras de entrada'
    Assert-Igual 0 $e.Avisados.Count 'avisados de entrada'
    Assert-Igual 1 @($r.Estado.Cameras).Count 'cameras de saida'
    $r.Estado.Posicoes[0].Estado = 'feita'
    Assert-Igual 'pendente' $e.Posicoes[0].Estado 'posicao de entrada'
}

T 'Descoberta: uma so camera continua lista e porta HTTP ausente vira 80' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 1)
    $r = Step-Descoberta -Estado $e -Achados @((New-AchadoTeste 1 -HttpPort $null))
    Assert-Igual 1 @($r.Estado.Cameras).Count 'cameras'
    Assert-Igual 'AA:00:00:00:00:01' $r.Estado.Cameras[0].Mac 'mac'
    Assert-Igual 80 $r.Estado.Cameras[0].HttpPort 'porta padrao'
    $r2 = Step-Descoberta -Estado $e -Achados @((New-AchadoTeste 2 -HttpPort 8080))
    Assert-Igual 8080 $r2.Estado.Cameras[0].HttpPort 'porta do DHIP'
}

T 'Descoberta: MAC repetido no mesmo tique e entre tiques nao duplica' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $r1 = Step-Descoberta -Estado $e -Achados @((New-AchadoTeste 1), (New-AchadoTeste 1), (New-AchadoTeste 2))
    Assert-Igual 2 @($r1.Estado.Cameras).Count 'cameras no 1o tique'
    $outraGrafia = New-AchadoTeste 1
    $outraGrafia.Mac = 'aa-00-00-00-00-01'
    $r2 = Step-Descoberta -Estado $r1.Estado -Achados @((New-AchadoTeste 2), $outraGrafia, (New-AchadoTeste 3))
    $c = @($r2.Estado.Cameras)
    Assert-Igual 3 $c.Count 'cameras no 2o tique'
    Assert-Igual 'AA:00:00:00:00:01' $c[0].Mac 'ordem: 1'
    Assert-Igual 'AA:00:00:00:00:02' $c[1].Mac 'ordem: 2'
    Assert-Igual 'AA:00:00:00:00:03' $c[2].Mac 'ordem: 3'
    Assert-Igual 0 @($r2.Acoes).Count 'nenhuma acao'
}

T 'Descoberta: camera feita, pulada, em decisao ou em curso reaparecendo e ignorada' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $e.Cameras = @(
        (New-CameraTeste 1 'feita'),
        (New-CameraTeste 2 'pulada'),
        (New-CameraTeste 3 'decisao'),
        (New-CameraTeste 4 'portao'),
        (New-CameraTeste 5 'conferindo'),
        (New-CameraTeste 6 'espera')
    )
    $e.Portao = 'AA:00:00:00:00:04'
    $achados = @(1..6 | ForEach-Object { New-AchadoTeste $_ })
    $r = Step-Descoberta -Estado $e -Achados $achados
    $c = @($r.Estado.Cameras)
    Assert-Igual 6 $c.Count 'cameras'
    $fases = @('feita', 'pulada', 'decisao', 'portao', 'conferindo', 'espera')
    for ($i = 0; $i -lt 6; $i++) { Assert-Igual $fases[$i] $c[$i].Fase ('fase de ' + $c[$i].Mac) }
    Assert-Igual 'AA:00:00:00:00:04' $r.Estado.Portao 'portao'
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
}

T 'Descoberta: marca nao suportada avisa uma vez por MAC e nao entra na espera' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $r1 = Step-Descoberta -Estado $e -Achados @((New-AchadoTeste 7 -Marca 'OutraMarca'), (New-AchadoTeste 7 -Marca 'OutraMarca'), (New-AchadoTeste 1))
    Assert-Igual 1 @($r1.Estado.Cameras).Count 'so a Intelbras na espera'
    Assert-Igual 'AA:00:00:00:00:01' $r1.Estado.Cameras[0].Mac 'a da familia'
    $av = @(Get-AcoesDoTipo $r1 'avisar')
    Assert-Igual 1 @($r1.Acoes).Count 'uma acao'
    Assert-Igual 1 $av.Count 'um aviso'
    Assert-Igual 'AA:00:00:00:00:07' $av[0].Mac 'mac do aviso'
    Assert-Igual $script:TextoMarca $av[0].Texto 'texto do aviso'
    $r2 = Step-Descoberta -Estado $r1.Estado -Achados @((New-AchadoTeste 7 -Marca 'OutraMarca'), (New-AchadoTeste 8 -Marca 'OutraMarca'))
    $av2 = @(Get-AcoesDoTipo $r2 'avisar')
    Assert-Igual 1 $av2.Count 'so o MAC novo avisa no 2o tique'
    Assert-Igual 'AA:00:00:00:00:08' $av2[0].Mac 'mac novo'
    Assert-Igual 1 @($r2.Estado.Cameras).Count 'nenhuma nao suportada na espera'
}

T 'Descoberta: Dahua e marca vazia (achado do DHIP) sao da familia' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $r = Step-Descoberta -Estado $e -Achados @((New-AchadoTeste 1 -Marca 'Dahua'), (New-AchadoTeste 2 -Marca ''), (New-AchadoTeste 3 -Marca 'intelbras'))
    Assert-Igual 3 @($r.Estado.Cameras).Count 'cameras'
    Assert-Igual 0 @($r.Acoes).Count 'nenhum aviso'
}

T 'Descoberta: inicializada nao vai para a espera nem recebe acao de rede' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $r = Step-Descoberta -Estado $e -Achados @((New-AchadoTeste 1 -Init 0), (New-AchadoTeste 2 -Init 2), (New-AchadoTeste 3 -Init 3), (New-AchadoTeste 4))
    $c = @($r.Estado.Cameras)
    Assert-Igual 1 $c.Count 'so a de fabrica'
    Assert-Igual 'AA:00:00:00:00:04' $c[0].Mac 'a de fabrica'
    Assert-Igual 0 @(Get-AcoesDoTipo $r 'prender').Count 'nenhum prender'
    Assert-Igual 0 @(Get-AcoesDoTipo $r 'despachar').Count 'nenhum despachar'
}

T 'Descoberta: achado sem MAC e lista vazia nao mexem no estado' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 1)
    $semMac = New-AchadoTeste 1
    $semMac.Mac = ''
    $r = Step-Descoberta -Estado $e -Achados @($semMac)
    Assert-Igual 0 @($r.Estado.Cameras).Count 'sem MAC fica fora'
    Assert-Igual 0 @($r.Acoes).Count 'sem acao'
    $r0 = Step-Descoberta -Estado $e -Achados @()
    Assert-Igual 0 @($r0.Estado.Cameras).Count 'lista vazia'
    Assert-Igual 0 @($r0.Acoes).Count 'lista vazia sem acao'
}

# -------------------------------------------------------------------- admissao

# Textos com acento, sem acento neste arquivo.
$script:TextoSemPosicao = ('sem posi' + [char]0x00E7 + [char]0x00E3 + 'o livre')
$script:TextoIpOcupado = ('IP j' + [char]0x00E1 + ' responde na rede')

# Estado com as cameras 1..N em espera, na ordem.
function New-EstadoComEspera {
    param([int]$Cameras = 3, [int]$Posicoes = 3, [int]$Max = 0)
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste $Posicoes) -Max $Max
    $e.Cameras = @(1..$Cameras | ForEach-Object { New-CameraTeste $_ 'espera' })
    return $e
}

function Get-Camera {
    param($Estado, [int]$N)
    $mac = ('AA:00:00:00:00:0' + $N)
    return @(@($Estado.Cameras) | Where-Object { $_.Mac -eq $mac })[0]
}

T 'Admissao: Max 0 e 3 em espera, so a primeira entra no portao com a posicao 1' {
    $e = New-EstadoComEspera -Cameras 3 -Posicoes 3 -Max 0
    $r = Step-Admissao -Estado $e
    $c1 = Get-Camera $r.Estado 1
    Assert-Igual 'portao' $c1.Fase 'fase da 1'
    Assert-Igual 1 $c1.Indice 'indice da 1'
    Assert-Igual 'AA:00:00:00:00:01' $r.Estado.Portao 'portao'
    Assert-Igual 'espera' (Get-Camera $r.Estado 2).Fase 'fase da 2'
    Assert-Igual 'espera' (Get-Camera $r.Estado 3).Fase 'fase da 3'
    Assert-Igual 0 (Get-Camera $r.Estado 2).Indice 'indice da 2'
    Assert-Igual 'reservada' $r.Estado.Posicoes[0].Estado 'posicao 1 reservada'
    Assert-Igual 'AA:00:00:00:00:01' $r.Estado.Posicoes[0].Mac 'mac da posicao 1'
    Assert-Igual 'pendente' $r.Estado.Posicoes[1].Estado 'posicao 2 livre'

    $a = @($r.Acoes)
    Assert-Igual 2 $a.Count 'duas acoes'
    Assert-Igual 'prender' $a[0].Tipo 'primeiro prender'
    Assert-Igual 'AA:00:00:00:00:01' $a[0].Mac 'mac do prender'
    Assert-Igual '192.168.1.108' $a[0].Ip 'ip do prender (fabrica)'
    Assert-Igual 'despachar' $a[1].Tipo 'depois despachar'
    Assert-Igual 'AA:00:00:00:00:01' $a[1].Mac 'mac do despachar'
    Assert-Igual 'rede' $a[1].AteEtapa 'despachar ate a rede'
    Assert-Igual 1 $a[1].Posicao 'posicao do despachar'
    Assert-Igual '192.0.2.11' $a[1].Destino 'destino do despachar'

    # Portao ocupado: as outras aguardam so o portao, sem acao nem motivo.
    $r2 = Step-Admissao -Estado $r.Estado
    Assert-Igual 0 @($r2.Acoes).Count 'portao ocupado: nenhuma acao'
    Assert-Igual 'espera' (Get-Camera $r2.Estado 2).Fase 'a 2 aguarda o portao'
    Assert-Verdade ([string]::IsNullOrEmpty((Get-Camera $r2.Estado 2).Motivo)) 'sem motivo enquanto aguarda o portao'

    # Portao livre com a 1 conferindo: Max 0 admite a 2 na posicao 2.
    $s = $r2.Estado
    (Get-Camera $s 1).Fase = 'conferindo'
    $s.Portao = $null
    $r3 = Step-Admissao -Estado $s
    Assert-Igual 'portao' (Get-Camera $r3.Estado 2).Fase 'a 2 entra com a 1 conferindo'
    Assert-Igual 2 (Get-Camera $r3.Estado 2).Indice 'indice da 2'
    Assert-Igual '192.0.2.12' @($r3.Acoes)[1].Destino 'destino da 2'
    Assert-Igual 'espera' (Get-Camera $r3.Estado 3).Fase 'a 3 continua em espera'
}

T 'Admissao: Max 1, a segunda espera a primeira terminar a conferencia' {
    $e = New-EstadoComEspera -Cameras 2 -Posicoes 3 -Max 1
    $r = Step-Admissao -Estado $e
    Assert-Igual 'portao' (Get-Camera $r.Estado 1).Fase 'a 1 entra'
    $s = $r.Estado
    (Get-Camera $s 1).Fase = 'conferindo'
    $s.Portao = $null
    $r2 = Step-Admissao -Estado $s
    Assert-Igual 0 @($r2.Acoes).Count 'sem vaga: nenhuma acao'
    Assert-Igual 'espera' (Get-Camera $r2.Estado 2).Fase 'a 2 espera'
    Assert-Verdade ($null -eq $r2.Estado.Portao) 'portao continua livre'
    (Get-Camera $r2.Estado 1).Fase = 'feita'
    $r3 = Step-Admissao -Estado $r2.Estado
    Assert-Igual 'portao' (Get-Camera $r3.Estado 2).Fase 'a 2 entra depois da conferencia'
    Assert-Igual 2 (Get-Camera $r3.Estado 2).Indice 'posicao 2 (a 1 continua reservada)'
}

T 'Admissao: Max 1 com a primeira em decisao libera a vaga' {
    $e = New-EstadoComEspera -Cameras 2 -Posicoes 3 -Max 1
    (Get-Camera $e 1).Fase = 'decisao'
    $r = Step-Admissao -Estado $e
    Assert-Igual 'portao' (Get-Camera $r.Estado 2).Fase 'decisao nao ocupa vaga'
}

T 'Admissao: sem posicao livre, a camera fica em espera com o motivo' {
    $e = New-EstadoComEspera -Cameras 2 -Posicoes 2 -Max 0
    $e.Posicoes[0].Estado = 'feita'
    $e.Posicoes[1].Estado = 'pulada'
    $r = Step-Admissao -Estado $e
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
    Assert-Verdade ($null -eq $r.Estado.Portao) 'portao livre'
    $c1 = Get-Camera $r.Estado 1
    Assert-Igual 'espera' $c1.Fase 'fase'
    Assert-Igual 0 $c1.Indice 'sem indice'
    Assert-Igual $script:TextoSemPosicao $c1.Motivo 'motivo'
}

T 'Admissao: posicao reservada nao e reaproveitada; motivo some na admissao' {
    $e = New-EstadoComEspera -Cameras 1 -Posicoes 1 -Max 0
    (Get-Camera $e 1).Motivo = $script:TextoSemPosicao
    $r = Step-Admissao -Estado $e
    Assert-Verdade ([string]::IsNullOrEmpty((Get-Camera $r.Estado 1).Motivo)) 'motivo limpo ao entrar'
    $s = $r.Estado
    (Get-Camera $s 1).Fase = 'conferindo'
    $s.Portao = $null
    $s.Cameras = @($s.Cameras) + @((New-CameraTeste 2 'espera'))
    $r2 = Step-Admissao -Estado $s
    Assert-Igual 0 @($r2.Acoes).Count 'unica posicao ja reservada'
    Assert-Igual $script:TextoSemPosicao (Get-Camera $r2.Estado 2).Motivo 'a 2 sem posicao'
}

T 'Admissao: IP de destino ocupado pula a posicao e usa a seguinte' {
    $e = New-EstadoComEspera -Cameras 1 -Posicoes 3 -Max 0
    $r = Step-Admissao -Estado $e -IpsOcupados @('192.0.2.11', '192.0.2.12')
    Assert-Igual 'pulada' $r.Estado.Posicoes[0].Estado 'posicao 1 pulada'
    Assert-Igual $script:TextoIpOcupado $r.Estado.Posicoes[0].Motivo 'motivo da 1'
    Assert-Igual 'pulada' $r.Estado.Posicoes[1].Estado 'posicao 2 pulada'
    Assert-Igual 'reservada' $r.Estado.Posicoes[2].Estado 'posicao 3 reservada'
    Assert-Igual 3 (Get-Camera $r.Estado 1).Indice 'indice 3'
    Assert-Igual '192.0.2.13' @($r.Acoes)[1].Destino 'destino 3'
}

T 'Admissao: todos os destinos ocupados viram sem posicao livre' {
    $e = New-EstadoComEspera -Cameras 1 -Posicoes 2 -Max 0
    $r = Step-Admissao -Estado $e -IpsOcupados @('192.0.2.11', '192.0.2.12')
    Assert-Igual 'pulada' $r.Estado.Posicoes[0].Estado 'posicao 1 pulada'
    Assert-Igual 'pulada' $r.Estado.Posicoes[1].Estado 'posicao 2 pulada'
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
    Assert-Igual $script:TextoSemPosicao (Get-Camera $r.Estado 1).Motivo 'motivo'
}

T 'Admissao: destino ocupado sem camera em espera nao pula nada' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)
    $r = Step-Admissao -Estado $e -IpsOcupados @('192.0.2.11')
    Assert-Igual 'pendente' $r.Estado.Posicoes[0].Estado 'posicao 1 intacta'
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
}

T 'Admissao: sem Admitindo nada entra' {
    $e = New-EstadoComEspera -Cameras 2 -Posicoes 2 -Max 0
    $e.Admitindo = $false
    $r = Step-Admissao -Estado $e
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
    Assert-Igual 'espera' (Get-Camera $r.Estado 1).Fase 'a 1 espera'
    Assert-Igual 'pendente' $r.Estado.Posicoes[0].Estado 'posicao livre'
}

T 'Admissao: a primeira em espera e a da ordem de chegada, apos as ja feitas' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $e.Cameras = @((New-CameraTeste 4 'feita'), (New-CameraTeste 5 'decisao'), (New-CameraTeste 2 'espera'), (New-CameraTeste 1 'espera'))
    $r = Step-Admissao -Estado $e
    Assert-Igual 'AA:00:00:00:00:02' $r.Estado.Portao 'a 2 chegou antes da 1'
    Assert-Igual 'espera' (Get-Camera $r.Estado 1).Fase 'a 1 espera'
}

T 'Admissao: estado de entrada nao e mutado' {
    $e = New-EstadoComEspera -Cameras 2 -Posicoes 2 -Max 0
    $r = Step-Admissao -Estado $e -IpsOcupados @('192.0.2.11')
    Assert-Verdade ($null -eq $e.Portao) 'portao de entrada'
    Assert-Igual 'espera' (Get-Camera $e 1).Fase 'fase de entrada'
    Assert-Igual 0 (Get-Camera $e 1).Indice 'indice de entrada'
    Assert-Igual 'pendente' $e.Posicoes[0].Estado 'posicao 1 de entrada'
    Assert-Igual 'pendente' $e.Posicoes[1].Estado 'posicao 2 de entrada'
    Assert-Igual 'portao' (Get-Camera $r.Estado 1).Fase 'fase de saida'
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
