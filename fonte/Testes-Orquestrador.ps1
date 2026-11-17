<#
    Testes-Orquestrador.ps1
    Testes do Orquestrador-Cameras.ps1 sem camera, rede, placa nem disco.

    O orquestrador e uma maquina de estado pura: recebe estado mais evento e
    devolve o novo estado e a lista de acoes. Nao executa nada ao carregar,
    entao aqui ele e carregado por dot-source direto. Cobre:
      - estado inicial (posicoes copiadas, Max, portao livre, admitindo);
      - resumo por fase;
      - descoberta (achados DHIP -> espera, dedup por MAC, marca nao suportada);
      - admissao (portao de 1 vaga, Max, posicao na entrada, destino ocupado);
      - fim do job (portao -> conferencia -> feita, falha isolada, MAC trocado);
      - ja inicializada (aviso unico pelo registro, Init desconhecido em espera).

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

# ------------------------------------------------------------------ fim do job

# Resultado do job no formato de Invoke-ConfiguracaoCamera (Motor-Cameras.ps1):
# Ok, Etapa (ultima feita), Falhou (etapa da falha), Erro, Recusa,
# LoginRecusado, Bloqueada e, da frente motor, MacTrocado e MacLido.
function New-ResultadoTeste {
    param([bool]$Ok = $true, [string]$Etapa = 'rede', [string]$Falhou = '', [string]$Erro = '',
          [bool]$Recusa = $false, [bool]$LoginRecusado = $false, [bool]$Bloqueada = $false,
          [bool]$MacTrocado = $false, [string]$MacLido = '')
    return [pscustomobject]@{
        Ok = $Ok; Etapa = $Etapa; Falhou = $Falhou; Erro = $Erro; Recusa = $Recusa
        LoginRecusado = $LoginRecusado; Bloqueada = $Bloqueada; MacTrocado = $MacTrocado; MacLido = $MacLido
    }
}

# Estado com as cameras 1..N em espera e a 1 admitida no portao (posicao 1).
function New-EstadoComPortao {
    param([int]$Cameras = 2, [int]$Posicoes = 3, [int]$Max = 0)
    $e = New-EstadoComEspera -Cameras $Cameras -Posicoes $Posicoes -Max $Max
    return (Step-Admissao -Estado $e).Estado
}

T 'FimDoJob: portao com Ok solta e despacha a conferencia na posicao da camera' {
    $e = New-EstadoComPortao -Cameras 2 -Posicoes 3
    $r = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:01' -Resultado (New-ResultadoTeste -Ok $true -Etapa 'rede')
    $c1 = Get-Camera $r.Estado 1
    Assert-Igual 'conferindo' $c1.Fase 'fase da 1'
    Assert-Igual 'rede' $c1.Etapa 'etapa da 1'
    Assert-Igual 1 $c1.Indice 'indice mantido'
    Assert-Verdade ($null -eq $r.Estado.Portao) 'portao livre'
    Assert-Igual 'reservada' $r.Estado.Posicoes[0].Estado 'posicao 1 continua reservada'
    $a = @($r.Acoes)
    Assert-Igual 2 $a.Count 'duas acoes'
    Assert-Igual 'soltar' $a[0].Tipo 'primeiro soltar'
    Assert-Igual 'AA:00:00:00:00:01' $a[0].Mac 'mac do soltar'
    Assert-Igual 'despachar' $a[1].Tipo 'depois despachar'
    Assert-Igual 'AA:00:00:00:00:01' $a[1].Mac 'mac do despachar'
    Assert-Igual '' $a[1].AteEtapa 'conferencia: AteEtapa vazio'
    Assert-Igual 1 $a[1].Posicao 'posicao do despachar'
    Assert-Igual '192.0.2.11' $a[1].Destino 'destino do despachar'
    Assert-Igual 'espera' (Get-Camera $r.Estado 2).Fase 'a 2 continua em espera'

    # Portao livre: a 2 entra enquanto a 1 confere (Max 0).
    $r2 = Step-Admissao -Estado $r.Estado
    Assert-Igual 'portao' (Get-Camera $r2.Estado 2).Fase 'a 2 entra no portao'
}

T 'FimDoJob: Ok da conferencia deixa a camera feita sem mexer no portao' {
    $e = New-EstadoComPortao -Cameras 2 -Posicoes 3
    $r = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:01' -Resultado (New-ResultadoTeste -Etapa 'rede')
    $r = Step-Admissao -Estado $r.Estado
    Assert-Igual 'AA:00:00:00:00:02' $r.Estado.Portao 'a 2 no portao'
    $r2 = Step-FimDoJob -Estado $r.Estado -Mac 'AA:00:00:00:00:01' -Resultado (New-ResultadoTeste -Etapa 'encoder')
    $c1 = Get-Camera $r2.Estado 1
    Assert-Igual 'feita' $c1.Fase 'fase da 1'
    Assert-Igual 'encoder' $c1.Etapa 'etapa da 1'
    Assert-Igual 'feita' $r2.Estado.Posicoes[0].Estado 'posicao 1 feita'
    Assert-Igual 'AA:00:00:00:00:01' $r2.Estado.Posicoes[0].Mac 'mac da posicao 1'
    Assert-Igual 'AA:00:00:00:00:02' $r2.Estado.Portao 'portao continua com a 2'
    Assert-Igual 0 @(Get-AcoesDoTipo $r2 'soltar').Count 'nada a soltar'
    Assert-Igual 0 @(Get-AcoesDoTipo $r2 'despachar').Count 'nada a despachar'
}

T 'FimDoJob: falha no portao abre decisao so daquele MAC e solta' {
    $e = New-EstadoComPortao -Cameras 3 -Posicoes 3
    $res = New-ResultadoTeste -Ok $false -Etapa 'login' -Falhou 'rede' -Erro 'sem resposta' -Recusa $true
    $r = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:01' -Resultado $res -Geracao 4
    $c1 = Get-Camera $r.Estado 1
    Assert-Igual 'decisao' $c1.Fase 'fase da 1'
    Assert-Igual 'login' $c1.Etapa 'etapa feita'
    Assert-Igual 'rede' $c1.Falha.Etapa 'etapa da falha'
    Assert-Igual 'sem resposta' $c1.Falha.Erro 'erro'
    Assert-Verdade ($c1.Falha.Recusa -eq $true) 'recusa'
    Assert-Verdade ($c1.Falha.LoginRecusado -eq $false) 'login nao recusado'
    Assert-Igual 4 $c1.Falha.Geracao 'geracao'
    Assert-Verdade ($null -eq $r.Estado.Portao) 'portao livre'
    Assert-Verdade ($r.Estado.Admitindo -eq $true) 'admitindo intacto'
    Assert-Igual 'reservada' $r.Estado.Posicoes[0].Estado 'posicao fica com o cartao'
    $a = @($r.Acoes)
    Assert-Igual 1 $a.Count 'uma acao'
    Assert-Igual 'soltar' $a[0].Tipo 'soltar'
    Assert-Igual 'AA:00:00:00:00:01' $a[0].Mac 'mac do soltar'
    Assert-Igual 'espera' (Get-Camera $r.Estado 2).Fase 'a 2 segue em espera'
    Assert-Igual 'espera' (Get-Camera $r.Estado 3).Fase 'a 3 segue em espera'
    Assert-Igual 1 (Get-Resumo -Estado $r.Estado).Fases['decisao'] 'uma decisao so'

    # D6: a fila nao pausa, a 2 entra na posicao 2.
    $r2 = Step-Admissao -Estado $r.Estado
    Assert-Igual 'portao' (Get-Camera $r2.Estado 2).Fase 'a 2 entra'
    Assert-Igual 2 (Get-Camera $r2.Estado 2).Indice 'posicao 2'
}

T 'FimDoJob: falha na conferencia abre decisao sem soltar nem mexer no portao' {
    $e = New-EstadoComPortao -Cameras 2 -Posicoes 3
    $r = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:01' -Resultado (New-ResultadoTeste -Etapa 'rede')
    $r = Step-Admissao -Estado $r.Estado
    $res = New-ResultadoTeste -Ok $false -Etapa 'rede' -Falhou 'encoder' -Erro 'valor recusado'
    $r2 = Step-FimDoJob -Estado $r.Estado -Mac 'AA:00:00:00:00:01' -Resultado $res -Geracao 1
    $c1 = Get-Camera $r2.Estado 1
    Assert-Igual 'decisao' $c1.Fase 'fase da 1'
    Assert-Igual 'encoder' $c1.Falha.Etapa 'etapa da falha'
    Assert-Igual 0 @($r2.Acoes).Count 'nenhuma acao'
    Assert-Igual 'AA:00:00:00:00:02' $r2.Estado.Portao 'portao continua com a 2'
    Assert-Igual 'portao' (Get-Camera $r2.Estado 2).Fase 'a 2 segue no portao'
}

T 'FimDoJob: login recusado guarda a geracao da senha na falha e na camera' {
    $e = New-EstadoComPortao -Cameras 1 -Posicoes 1
    $res = New-ResultadoTeste -Ok $false -Etapa '' -Falhou 'login' -Erro 'senha errada' -LoginRecusado $true -Bloqueada $true
    $r = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:01' -Resultado $res -Geracao 3
    $c1 = Get-Camera $r.Estado 1
    Assert-Igual 'decisao' $c1.Fase 'fase'
    Assert-Verdade ($c1.Falha.LoginRecusado -eq $true) 'login recusado'
    Assert-Verdade ($c1.Falha.Bloqueada -eq $true) 'bloqueada'
    Assert-Igual 3 $c1.Falha.Geracao 'geracao na falha'
    Assert-Igual 3 $c1.GeracaoLogin 'geracao do login recusado na camera'
}

T 'FimDoJob: print 1 (escolhido A, lido B) volta A e B para espera e a posicao a pendente' {
    $e = New-EstadoComPortao -Cameras 2 -Posicoes 3
    Assert-Igual 'AA:00:00:00:00:01' $e.Portao 'A no portao'
    $res = New-ResultadoTeste -Ok $false -Etapa 'login' -Falhou 'encoder' -Erro 'MAC lido nao e o escolhido' -MacTrocado $true -MacLido 'aa-00-00-00-00-02'
    $r = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:01' -Resultado $res -Geracao 2
    $a = Get-Camera $r.Estado 1
    $b = Get-Camera $r.Estado 2
    Assert-Igual 'espera' $a.Fase 'A em espera'
    Assert-Igual 0 $a.Indice 'A sem posicao'
    Assert-Verdade ($null -eq $a.Falha) 'A sem falha'
    Assert-Igual '' $a.Etapa 'A sem etapa'
    Assert-Igual 'espera' $b.Fase 'B em espera'
    Assert-Igual 'pendente' $r.Estado.Posicoes[0].Estado 'posicao 1 pendente'
    Assert-Igual '' $r.Estado.Posicoes[0].Mac 'posicao 1 sem MAC'
    Assert-Verdade ($null -eq $r.Estado.Portao) 'portao livre'
    Assert-Verdade ($r.Estado.Admitindo -eq $true) 'Admitindo intacto'
    Assert-Igual 0 (Get-Resumo -Estado $r.Estado).Fases['decisao'] 'sem decisao'
    $acoes = @($r.Acoes)
    Assert-Igual 1 $acoes.Count 'uma acao'
    Assert-Igual 'soltar' $acoes[0].Tipo 'soltar'
    Assert-Igual 'AA:00:00:00:00:01' $acoes[0].Mac 'solta A'

    # Vigia sem pausa: a admissao seguinte volta a tentar A na posicao 1.
    $r2 = Step-Admissao -Estado $r.Estado
    Assert-Igual 'AA:00:00:00:00:01' $r2.Estado.Portao 'A volta ao portao'
    Assert-Igual 1 (Get-Camera $r2.Estado 1).Indice 'posicao 1 de novo'
}

T 'FimDoJob: MAC lido desconhecido nao entra na espera (o DHIP decide no proximo tique)' {
    $e = New-EstadoComPortao -Cameras 1 -Posicoes 2
    $res = New-ResultadoTeste -Ok $false -Falhou 'encoder' -MacTrocado $true -MacLido 'AA:00:00:00:00:09'
    $r = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:01' -Resultado $res
    Assert-Igual 1 @($r.Estado.Cameras).Count 'so a escolhida'
    Assert-Igual 'espera' (Get-Camera $r.Estado 1).Fase 'escolhida em espera'
    Assert-Igual 'pendente' $r.Estado.Posicoes[0].Estado 'posicao pendente'
}

T 'FimDoJob: evento de MAC desconhecido ou fora de curso nao mexe no estado' {
    $e = New-EstadoComPortao -Cameras 2 -Posicoes 2
    $r = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:09' -Resultado (New-ResultadoTeste)
    Assert-Igual 0 @($r.Acoes).Count 'MAC desconhecido: nenhuma acao'
    Assert-Igual 'AA:00:00:00:00:01' $r.Estado.Portao 'portao intacto'
    $r2 = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:02' -Resultado (New-ResultadoTeste -Ok $false -Falhou 'rede')
    Assert-Igual 0 @($r2.Acoes).Count 'camera em espera: nenhuma acao'
    Assert-Igual 'espera' (Get-Camera $r2.Estado 2).Fase 'a 2 continua em espera'
}

T 'FimDoJob: grafia do MAC nao importa e o estado de entrada nao e mutado' {
    $e = New-EstadoComPortao -Cameras 2 -Posicoes 2
    $r = Step-FimDoJob -Estado $e -Mac 'aa0000000001' -Resultado (New-ResultadoTeste)
    Assert-Igual 'conferindo' (Get-Camera $r.Estado 1).Fase 'saida conferindo'
    Assert-Igual 'portao' (Get-Camera $e 1).Fase 'entrada no portao'
    Assert-Igual 'AA:00:00:00:00:01' $e.Portao 'portao de entrada'
    $res = New-ResultadoTeste -Ok $false -MacTrocado $true -MacLido 'AA:00:00:00:00:02'
    $r2 = Step-FimDoJob -Estado $e -Mac 'AA:00:00:00:00:01' -Resultado $res
    Assert-Igual 'pendente' $r2.Estado.Posicoes[0].Estado 'saida pendente'
    Assert-Igual 'reservada' $e.Posicoes[0].Estado 'entrada reservada'
    Assert-Igual 1 (Get-Camera $e 1).Indice 'indice de entrada'
}

# ------------------------------------------------------------ ja inicializada

# Registro como dado: lista de { Mac, Status, Etapa } (o servidor le o arquivo).
function New-EntradaRegistroTeste {
    param([int]$N, [string]$Status, [string]$Etapa = '')
    return [pscustomobject]@{ Mac = ('AA:00:00:00:00:0' + $N); Status = $Status; Etapa = $Etapa }
}

# Textos com acento, sem acento neste arquivo.
$script:TextoCamera = ('C' + [char]0x00E2 + 'mera')
$script:TextoJaInicializada = ($script:TextoCamera + ' j' + [char]0x00E1 + ' inicializada: n' + [char]0x00E3 + 'o tocada.')
function Get-TextoFilaParada {
    param([string]$Etapa)
    if ($Etapa -eq '') { return ($script:TextoCamera + ' da fila parada. Retome em Ferramentas.') }
    return ($script:TextoCamera + ' da fila parada na etapa ' + $Etapa + '. Retome em Ferramentas.')
}

T 'JaInicializada: registro Em andamento avisa a etapa e nao entra na espera' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)
    $reg = @((New-EntradaRegistroTeste 1 'Em andamento' 'encoder'))
    $r = Step-JaInicializada -Estado $e -Achados @((New-AchadoTeste 1 -Init 0)) -Registro $reg
    $a = @($r.Acoes)
    Assert-Igual 1 $a.Count 'uma acao'
    Assert-Igual 'avisar' $a[0].Tipo 'avisar'
    Assert-Igual 'AA:00:00:00:00:01' $a[0].Mac 'mac do aviso'
    Assert-Igual (Get-TextoFilaParada 'encoder') $a[0].Texto 'texto do aviso'
    Assert-Igual 0 @($r.Estado.Cameras).Count 'fora da espera'
    Assert-Verdade ($r.Estado.Avisados.ContainsKey('AA0000000001')) 'MAC em Avisados'
}

T 'JaInicializada: registro Falhou avisa a etapa; sem etapa, o aviso nao cita etapa' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)
    $reg = @((New-EntradaRegistroTeste 1 'Falhou' 'rede'), (New-EntradaRegistroTeste 2 'Falhou' ''))
    $r = Step-JaInicializada -Estado $e -Achados @((New-AchadoTeste 1 -Init 2), (New-AchadoTeste 2 -Init 3)) -Registro $reg
    $a = @($r.Acoes)
    Assert-Igual 2 $a.Count 'dois avisos'
    Assert-Igual (Get-TextoFilaParada 'rede') $a[0].Texto 'texto com etapa'
    Assert-Igual (Get-TextoFilaParada '') $a[1].Texto 'texto sem etapa'
    Assert-Igual 0 @($r.Estado.Cameras).Count 'fora da espera'
}

T 'JaInicializada: registro Instalada nao avisa nem entra na espera' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)
    $reg = @((New-EntradaRegistroTeste 1 'Instalada' 'conferida'))
    $r = Step-JaInicializada -Estado $e -Achados @((New-AchadoTeste 1 -Init 0)) -Registro $reg
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
    Assert-Igual 0 @($r.Estado.Cameras).Count 'fora da espera'
    Assert-Igual 0 $r.Estado.Avisados.Count 'nada em Avisados'
}

T 'JaInicializada: desconhecida no registro (ou outro status) avisa que nao foi tocada' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)
    $reg = @((New-EntradaRegistroTeste 2 'Resetada' 'reset'))
    $r = Step-JaInicializada -Estado $e -Achados @((New-AchadoTeste 1 -Init 0), (New-AchadoTeste 2 -Init 0)) -Registro $reg
    $a = @($r.Acoes)
    Assert-Igual 2 $a.Count 'dois avisos'
    Assert-Igual $script:TextoJaInicializada $a[0].Texto 'fora do registro'
    Assert-Igual $script:TextoJaInicializada $a[1].Texto 'registro Resetada'
    $r0 = Step-JaInicializada -Estado $e -Achados @((New-AchadoTeste 3 -Init 0))
    Assert-Igual $script:TextoJaInicializada @($r0.Acoes)[0].Texto 'sem registro'
}

T 'JaInicializada: aviso unico por MAC entre tiques, grafia do MAC nao importa' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)
    $entrada = New-EntradaRegistroTeste 1 'Em andamento' 'login'
    $entrada.Mac = 'aa0000000001'
    $reg = @($entrada)
    $r1 = Step-JaInicializada -Estado $e -Achados @((New-AchadoTeste 1 -Init 0), (New-AchadoTeste 1 -Init 0), (New-AchadoTeste 2 -Init 0)) -Registro $reg
    Assert-Igual 2 @($r1.Acoes).Count 'um aviso por MAC no 1o tique'
    Assert-Igual (Get-TextoFilaParada 'login') @($r1.Acoes)[0].Texto 'registro casou pela chave do MAC'
    $outraGrafia = New-AchadoTeste 1 -Init 0
    $outraGrafia.Mac = 'aa-00-00-00-00-01'
    $r2 = Step-JaInicializada -Estado $r1.Estado -Achados @($outraGrafia, (New-AchadoTeste 2 -Init 0), (New-AchadoTeste 3 -Init 0)) -Registro $reg
    $a2 = @($r2.Acoes)
    Assert-Igual 1 $a2.Count 'so o MAC novo avisa no 2o tique'
    Assert-Igual 'AA:00:00:00:00:03' $a2[0].Mac 'mac novo'
    $r3 = Step-JaInicializada -Estado $r2.Estado -Achados @((New-AchadoTeste 1 -Init 0), (New-AchadoTeste 3 -Init 0)) -Registro $reg
    Assert-Igual 0 @($r3.Acoes).Count 'nada no 3o tique'
}

T 'JaInicializada: Init desconhecido vai para espera com ConferirInit, sem acao' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $e.Cameras = @((New-CameraTeste 1 'espera'))
    $semInit = New-AchadoTeste 3
    $semInit.Init = $null
    $r = Step-JaInicializada -Estado $e -Achados @((New-AchadoTeste 2 -Init -1), $semInit)
    $c = @($r.Estado.Cameras)
    Assert-Igual 3 $c.Count 'cameras'
    Assert-Igual 'AA:00:00:00:00:01' $c[0].Mac 'a que ja esperava segue na frente'
    Assert-Igual 'AA:00:00:00:00:02' $c[1].Mac 'Init -1 na ordem de chegada'
    Assert-Igual 'AA:00:00:00:00:03' $c[2].Mac 'Init ausente na ordem de chegada'
    foreach ($x in @($c[1], $c[2])) {
        Assert-Igual 'espera' $x.Fase ('fase de ' + $x.Mac)
        Assert-Verdade ($x.ConferirInit -eq $true) ('ConferirInit de ' + $x.Mac)
        Assert-Igual 0 $x.Indice ('indice de ' + $x.Mac)
        Assert-Igual '192.168.1.108' $x.IpOrigem ('IpOrigem de ' + $x.Mac)
    }
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
    $r2 = Step-JaInicializada -Estado $r.Estado -Achados @((New-AchadoTeste 2 -Init -1))
    Assert-Igual 3 @($r2.Estado.Cameras).Count 'sem duplicar entre tiques'
    $d = Step-Descoberta -Estado (New-EstadoParalelo) -Achados @((New-AchadoTeste 4))
    Assert-Verdade ($d.Estado.Cameras[0].ConferirInit -eq $false) 'de fabrica sem ConferirInit'
}

T 'JaInicializada: de fabrica, MAC ja conhecido e marca nao suportada ficam com os outros Steps' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 3)
    $e.Cameras = @((New-CameraTeste 1 'feita'), (New-CameraTeste 2 'conferindo'))
    $achados = @(
        (New-AchadoTeste 1 -Init 0),
        (New-AchadoTeste 2 -Init 2),
        (New-AchadoTeste 3),
        (New-AchadoTeste 4 -Init 0 -Marca 'OutraMarca'),
        (New-AchadoTeste 5 -Init -1 -Marca 'OutraMarca')
    )
    $r = Step-JaInicializada -Estado $e -Achados $achados
    Assert-Igual 0 @($r.Acoes).Count 'nenhuma acao'
    Assert-Igual 2 @($r.Estado.Cameras).Count 'nenhuma camera nova'
    Assert-Igual 0 $r.Estado.Avisados.Count 'nada em Avisados'
}

T 'JaInicializada: estado de entrada nao e mutado' {
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 2)
    $r = Step-JaInicializada -Estado $e -Achados @((New-AchadoTeste 1 -Init 0), (New-AchadoTeste 2 -Init -1))
    Assert-Igual 1 @($r.Estado.Cameras).Count 'cameras de saida'
    Assert-Igual 1 $r.Estado.Avisados.Count 'avisados de saida'
    Assert-Igual 0 @($e.Cameras).Count 'cameras de entrada'
    Assert-Igual 0 $e.Avisados.Count 'avisados de entrada'
}

T 'JaInicializada: nenhuma acao prender/despachar sai para camera inicializada em varios tiques' {
    $inicializadas = @{ 'AA:00:00:00:00:04' = $true; 'AA:00:00:00:00:05' = $true; 'AA:00:00:00:00:06' = $true }
    $reg = @((New-EntradaRegistroTeste 4 'Em andamento' 'encoder'), (New-EntradaRegistroTeste 5 'Instalada' 'conferida'))
    $achados = @(
        (New-AchadoTeste 4 -Init 0), (New-AchadoTeste 1), (New-AchadoTeste 5 -Init 2),
        (New-AchadoTeste 2 -Init -1), (New-AchadoTeste 6 -Init 3), (New-AchadoTeste 3)
    )
    $e = New-EstadoParalelo -Posicoes (New-PosicoesTeste 6)
    $todas = @()
    for ($tique = 1; $tique -le 6; $tique++) {
        $r = Step-Descoberta -Estado $e -Achados $achados
        $todas += @($r.Acoes)
        $r = Step-JaInicializada -Estado $r.Estado -Achados $achados -Registro $reg
        $todas += @($r.Acoes)
        $r = Step-Admissao -Estado $r.Estado
        $todas += @($r.Acoes)
        $e = $r.Estado
        foreach ($c in @($e.Cameras)) {
            if ($c.Fase -eq 'portao' -or $c.Fase -eq 'conferindo') {
                $r = Step-FimDoJob -Estado $e -Mac $c.Mac -Resultado (New-ResultadoTeste -Etapa 'rede')
                $todas += @($r.Acoes)
                $e = $r.Estado
            }
        }
    }
    $rede = @($todas | Where-Object { $null -ne $_ -and ($_.Tipo -eq 'prender' -or $_.Tipo -eq 'despachar') })
    Assert-Verdade ($rede.Count -gt 0) 'as de fabrica e a de Init desconhecido receberam acao de rede'
    foreach ($x in $rede) { Assert-Verdade (-not $inicializadas.ContainsKey([string]$x.Mac)) ($x.Tipo + ' para inicializada ' + $x.Mac) }
    Assert-Igual 3 (Get-Resumo -Estado $e).Fases['feita'] 'as tres da fila feitas'
    $avisos = @($todas | Where-Object { $null -ne $_ -and $_.Tipo -eq 'avisar' })
    Assert-Igual 2 $avisos.Count 'dois avisos em seis tiques (a Instalada nao avisa)'
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
