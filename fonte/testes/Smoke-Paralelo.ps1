<#
    Smoke do laco paralelo do servidor, em simulacao (sem rede nem camera).

    Sobe o painel com -Simular -SemElevar -SemNavegador numa pasta de dados
    temporaria e porta livre, grava uma sessao ficticia completa, monta uma
    fila de 3 posicoes e liga o vigia (o DHIP simulado traz 3 cameras de
    fabrica). Consulta GET /api/estado a cada 100 ms, medindo a latencia, e
    imprime as fases de cada camera ao longo do tempo. No fim encerra o
    painel e confere:
      - 3 cameras 'feita';
      - pelo menos 2 'conferindo' ao mesmo tempo;
      - latencia maxima do GET /api/estado abaixo de 500 ms;
      - o processo do painel saiu.

    Fora do CI e do instalador: e um teste de bancada do desenvolvedor.

    Uso (PowerShell 5.1, na raiz do repo):
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\testes\Smoke-Paralelo.ps1
#>
param(
    [int]$TimeoutSeg = 90,
    [int]$LatenciaMaxMs = 500
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fonte = Join-Path $raiz 'fonte'
. (Join-Path $fonte 'Motor-Cameras.ps1')
Add-Type -AssemblyName System.Net.Http

# ------------------------------------------------------------ preparo
$pasta = Join-Path ([IO.Path]::GetTempPath()) ('smoke-paralelo-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $pasta -Force

# Sessao ficticia completa (etapa 7). Valores de documentacao: nada da bancada.
$sessao = @{
    Etapa = 7
    Placa = @{ Nome = 'SIM'; IfIndex = 1; Mac = 'AA:00:00:00:00:F0'; Tipo = 'ethernet' }
    Mascara = '255.255.255.0'; Gateway = '192.0.2.1'
    IpFabrica = '192.168.1.108'
    EmailRecuperacao = 'recuperacao@exemplo.com.br'
}
$null = Save-Sessao -Caminho (Join-Path $pasta 'sessao.json') -Sessao $sessao

# Porta livre: o sistema escolhe.
$tcp = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
$tcp.Start(); $porta = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port; $tcp.Stop()
$base = 'http://127.0.0.1:' + $porta

$servidor = Join-Path $fonte 'web\Servidor-Painel.ps1'
$saida = Join-Path $pasta 'servidor-saida.txt'
$erros = Join-Path $pasta 'servidor-erros.txt'
$argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $servidor + '"'),
                '-Simular', '-SemElevar', '-SemNavegador', '-SemAtualizacao',
                '-PastaDados', ('"' + $pasta + '"'), '-Porta', $porta)
$proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -PassThru -NoNewWindow `
                      -RedirectStandardOutput $saida -RedirectStandardError $erros

$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(10)

# GET /api/estado com o cursor do log (so as linhas novas, como a pagina).
$script:cursor = 0
$script:errosInternos = @()
function Get-Estado {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $txt = $http.GetStringAsync($base + '/api/estado?desde=' + $script:cursor).Result
    $sw.Stop()
    $r = $txt | ConvertFrom-Json
    $script:cursor = [int]$r.cursor
    # Erro interno do worker no log do painel tambem reprova o smoke.
    foreach ($l in @($r.log)) {
        if ($null -ne $l -and [string]$l.msg -like '*ERRO interno*') { $script:errosInternos += [string]$l.msg }
    }
    return @{ Estado = $r.estado; Ms = [int]$sw.ElapsedMilliseconds }
}

function Send-Post {
    param([string]$Rota, $Corpo)
    $json = ConvertTo-Json -InputObject $Corpo -Compress
    for ($i = 0; $i -lt 50; $i++) {
        $msg = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Post), ($base + $Rota)
        $msg.Headers.Add('Origin', $base)
        $msg.Content = New-Object System.Net.Http.StringContent ($json, [Text.Encoding]::UTF8, 'application/json')
        $r = $http.SendAsync($msg).Result
        $codigo = [int]$r.StatusCode
        # 409 "Aguarde": o worker ainda esta no comando anterior.
        if ($codigo -ne 409) { return $codigo }
        Start-Sleep -Milliseconds 200
    }
    return 409
}

function Write-Linha {
    param([double]$Seg, [string]$Texto)
    Write-Host ('[' + $Seg.ToString('00.0', [Globalization.CultureInfo]::InvariantCulture) + 's] ' + $Texto)
}

$relogio = [Diagnostics.Stopwatch]::StartNew()
$ok = $false
$feitas = 0; $maxConferindo = 0; $maxLatencia = 0; $consultas = 0; $saiu = $false
try {
    # Espera o painel responder.
    $pronto = $false
    for ($i = 0; $i -lt 100; $i++) {
        if ($proc.HasExited) { break }
        try { $null = Get-Estado; $pronto = $true; break } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $pronto) { throw 'O painel nao respondeu em /api/estado.' }
    Write-Linha $relogio.Elapsed.TotalSeconds ('painel no ar em ' + $base + ' (dados em ' + $pasta + ')')

    $c = Send-Post '/api/senha' @{ senha = 'smoke-ficticia' }
    Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/senha -> ' + $c)
    $c = Send-Post '/api/fila' @{ inicio = '192.0.2.10'; fim = '192.0.2.12'; local = 'Obra exemplo'; rack = 'R1'; andar = '1' }
    Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/fila -> ' + $c)
    $temFila = $false
    for ($i = 0; $i -lt 50; $i++) {
        $e = (Get-Estado).Estado
        if ($null -ne $e.paralelo) { $temFila = $true; break }
        Start-Sleep -Milliseconds 100
    }
    if (-not $temFila) { throw ('A fila nao foi montada. Aviso: ' + $e.aviso) }
    Write-Linha $relogio.Elapsed.TotalSeconds ('fila montada: ' + @($e.fila.itens).Count + ' posicoes')
    $c = Send-Post '/api/vigia' @{ ligado = $true; porta = '1'; canal = '1'; broadcast = $false }
    Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/vigia -> ' + $c)

    # Consulta a cada 100 ms e imprime as mudancas de fase por camera.
    $fases = @{}
    $ultimoAviso = ''
    $limite = $relogio.Elapsed.TotalSeconds + $TimeoutSeg
    while ($relogio.Elapsed.TotalSeconds -lt $limite) {
        $r = Get-Estado
        $consultas++
        if ($r.Ms -gt $maxLatencia) { $maxLatencia = $r.Ms }
        $e = $r.Estado
        $conferindo = 0
        foreach ($cam in @($e.cameras)) {
            if ($null -eq $cam) { continue }
            $mac = [string]$cam.mac
            $fase = [string]$cam.fase
            if ($fase -eq 'conferindo') { $conferindo++ }
            if ($fases[$mac] -ne $fase) {
                $txt = $mac + '  ' + $(if ($fases.ContainsKey($mac)) { $fases[$mac] } else { '-' }) + ' -> ' + $fase
                if ($cam.destino) { $txt += '  (destino ' + $cam.destino + ')' }
                if ($fase -eq 'decisao' -and $null -ne $cam.falha) { $txt += '  falha: ' + $cam.falha.etapa + ': ' + $cam.falha.erro }
                Write-Linha $relogio.Elapsed.TotalSeconds $txt
                $fases[$mac] = $fase
            }
        }
        if ($conferindo -gt $maxConferindo) { $maxConferindo = $conferindo }
        if ($e.aviso -and $e.aviso -ne $ultimoAviso) { Write-Linha $relogio.Elapsed.TotalSeconds ('aviso: ' + $e.aviso); $ultimoAviso = $e.aviso }
        $feitas = @(@($e.cameras) | Where-Object { $null -ne $_ -and $_.fase -eq 'feita' }).Count
        if ($feitas -ge 3) { break }
        $resto = 100 - $r.Ms
        if ($resto -gt 0) { Start-Sleep -Milliseconds $resto }
    }
    Write-Linha $relogio.Elapsed.TotalSeconds ('fase da fila: ' + $e.fase + '; emCurso ' + $e.paralelo.emCurso)
} catch {
    Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    # Encerra o painel e espera o processo sair.
    try {
        if (-not $proc.HasExited) {
            $c = Send-Post '/api/encerrar' @{}
            Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/encerrar -> ' + $c)
        }
    } catch { Write-Host ('  encerrar falhou: ' + $_.Exception.Message) -ForegroundColor Yellow }
    $saiu = $proc.WaitForExit(40000)
    if (-not $saiu) {
        Write-Host '  o painel nao saiu em 40 s: processo finalizado a forca.' -ForegroundColor Yellow
        try { $proc.Kill() } catch { }
    }
    $http.Dispose()
}

$ok = ($feitas -eq 3 -and $maxConferindo -ge 2 -and $maxLatencia -lt $LatenciaMaxMs -and $saiu -and $script:errosInternos.Count -eq 0)
Write-Host ''
foreach ($m in $script:errosInternos) { Write-Host ('  log: ' + $m) -ForegroundColor Red }
Write-Host ('Resumo: feitas ' + $feitas + '/3; conferindo ao mesmo tempo (max) ' + $maxConferindo +
            '; latencia max ' + $maxLatencia + ' ms em ' + $consultas + ' consultas; erros internos no log ' + $script:errosInternos.Count +
            '; processo encerrado: ' + $saiu)
if ($ok) {
    Write-Host 'SMOKE OK' -ForegroundColor Green
    Remove-Item -LiteralPath $pasta -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}
Write-Host ('SMOKE FALHOU. Log do painel em ' + $pasta) -ForegroundColor Red
exit 1
