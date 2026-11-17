<#
    Testes-Orquestrador.ps1
    Testes do Orquestrador-Cameras.ps1 sem camera, rede, placa nem disco.

    O orquestrador e uma maquina de estado pura: recebe estado mais evento e
    devolve o novo estado e a lista de acoes. Nao executa nada ao carregar,
    entao aqui ele e carregado por dot-source direto. Cobre:
      - estado inicial (posicoes copiadas, Max, portao livre, admitindo);
      - resumo por fase.

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
