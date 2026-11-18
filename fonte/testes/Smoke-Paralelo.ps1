<#
    Smoke do laco paralelo do servidor, em simulacao (sem rede nem camera).

    Sobe o painel com -Simular -SemElevar -SemNavegador numa pasta de dados
    temporaria e porta livre, grava uma sessao ficticia completa, liga a
    falha simulada na 'conferida' (uma vez so), monta uma fila de N posicoes
    (-Cameras, padrao 3, repassado ao painel como -SimularCameras: o DHIP
    simulado traz N cameras de fabrica) e liga o vigia. Consulta
    GET /api/estado a cada 100 ms, medindo a latencia, e imprime a fase e a
    etapa de cada camera ao longo do tempo. No meio:
      - com 2 cameras em curso, um POST /api/fila sem retentativa: 409 com o
        texto da recusa do orquestrador;
      - com uma camera conferindo, um POST /api/encerrar sem retentativa: 409
        com o texto da recusa (encerrar o painel) e o painel continua;
      - com uma camera em decisao e outra conferindo, POST /api/camera muda a
        porta e o canal da que esta conferindo (7 e 8);
      - com a que falhou em decisao e as outras N-1 feitas, POST /api/decisao
        {mac, acao:'tentar'}: ela volta direto a conferencia (sem portao).
    No fim le GET /api/registro, encerra o painel e confere:
      - N cameras 'feita';
      - pelo menos 2 'conferindo' ao mesmo tempo;
      - as etapas inicializada, encoder e rede visiveis no portao (a espera
        simulada e por etapa, no motor);
      - so 1 camera em decisao (a falha simulada nao repete nas outras);
      - a que tentou de novo nao passou pelo portao e terminou 'feita';
      - o POST /api/fila em curso deu 409 com o texto da recusa;
      - o POST /api/encerrar na conferencia deu 409 com o texto da recusa, e
        o do fim deu 200;
      - o registro tem porta 7 e canal 8 na camera editada;
      - latencia maxima do GET /api/estado abaixo de 500 ms;
      - nenhum erro interno no log e o processo do painel saiu.

    -Cenario (S2, cenarios por camera; cada um sobe o seu painel e arma o
    falharEm em mapa antes de ligar o vigia). Fora do 'basico', so valem as
    conferencias comuns (latencia, erros internos, encerrar 200, processo
    saiu) e as do cenario:
      - falha-rede-2: { "2": "rede" }; 1 e as outras 'feita', so a 2 em
        decisao (falha na rede); POST /api/decisao {mac, acao:'tentar'} e a 2
        termina 'feita';
      - mac-trocado-2: { "2": "mac-trocado" }; nenhuma em decisao, a 2 leva
        a trava de MAC uma vez (log "MAC TROCADO" so dela), passa de novo
        pelo portao e termina 'feita'; nenhum aviso citando MAC;
      - ja-inicializada-3: { "3": "ja-inicializada" }; fila de N-1
        posicoes, as outras 'feita', a 3 nunca em portao nem conferindo e o
        aviso da D8 ("Camera ja inicializada: nao tocada.") uma vez so no log;
      - encerrar (S4): sem falha simulada, na escala 1; com uma camera
        conferindo, POST /api/encerrar sem retentativa da 409 com o texto da
        recusa e o painel continua; com as N 'feita', o POST /api/encerrar
        da 200 e o processo sai em menos de 10 s (-SaidaMaxSeg).

    Fora do CI e do instalador: e um teste de bancada do desenvolvedor.

    Uso (PowerShell 5.1, na raiz do repo):
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\testes\Smoke-Paralelo.ps1 [-Cameras 5] [-Cenario falha-rede-2]
#>
param(
    [int]$TimeoutSeg = 120,
    [int]$LatenciaMaxMs = 500,
    [ValidateRange(2, 16)][int]$Cameras = 3,
    [ValidateSet('basico', 'falha-rede-2', 'mac-trocado-2', 'ja-inicializada-3', 'encerrar')][string]$Cenario = 'basico',
    [int]$SaidaMaxSeg = 10
)

if ($Cenario -eq 'ja-inicializada-3' -and $Cameras -lt 3) { throw 'O cenario ja-inicializada-3 precisa de -Cameras 3 ou mais.' }
$basico = ($Cenario -eq 'basico')
# falharEm do POST /api/simular e quantas cameras a fila configura.
$falharEm = switch ($Cenario) {
    'basico'            { 'conferida' }
    'falha-rede-2'      { @{ '2' = 'rede' } }
    'mac-trocado-2'     { @{ '2' = 'mac-trocado' } }
    'ja-inicializada-3' { @{ '3' = 'ja-inicializada' } }
    'encerrar'          { '' }
}
$esperadas = $Cameras
if ($Cenario -eq 'ja-inicializada-3') { $esperadas = $Cameras - 1 }
$macCenario = ''
if ($Cenario -like '*-2') { $macCenario = 'AA:00:00:00:00:02' }
if ($Cenario -like '*-3') { $macCenario = 'AA:00:00:00:00:03' }

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
                '-Simular', '-SimularCameras', $Cameras, '-SimularEscala', 1, '-SemElevar', '-SemNavegador', '-SemAtualizacao',
                '-PastaDados', ('"' + $pasta + '"'), '-Porta', $porta)
$proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -PassThru -NoNewWindow `
                      -RedirectStandardOutput $saida -RedirectStandardError $erros

$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(10)

# GET /api/estado com o cursor do log (so as linhas novas, como a pagina).
$script:cursor = 0
$script:errosInternos = @()
$script:logs = New-Object 'System.Collections.Generic.List[string]'
function Get-Estado {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $txt = $http.GetStringAsync($base + '/api/estado?desde=' + $script:cursor).Result
    $sw.Stop()
    $r = $txt | ConvertFrom-Json
    $script:cursor = [int]$r.cursor
    # Erro interno do worker no log do painel tambem reprova o smoke.
    foreach ($l in @($r.log)) {
        if ($null -eq $l) { continue }
        $script:logs.Add([string]$l.msg)
        if ([string]$l.msg -like '*ERRO interno*') { $script:errosInternos += [string]$l.msg }
    }
    return @{ Estado = $r.estado; Ms = [int]$sw.ElapsedMilliseconds }
}

# Um POST, sem retentativa: { Codigo; Corpo (texto) }.
function Send-PostUmaVez {
    param([string]$Rota, $Corpo)
    $json = ConvertTo-Json -InputObject $Corpo -Compress
    $msg = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Post), ($base + $Rota)
    $msg.Headers.Add('Origin', $base)
    $msg.Content = New-Object System.Net.Http.StringContent ($json, [Text.Encoding]::UTF8, 'application/json')
    $r = $http.SendAsync($msg).Result
    $bytes = $r.Content.ReadAsByteArrayAsync().Result
    return @{ Codigo = [int]$r.StatusCode; Corpo = [Text.Encoding]::UTF8.GetString($bytes) }
}

function Send-Post {
    param([string]$Rota, $Corpo)
    for ($i = 0; $i -lt 50; $i++) {
        $r = Send-PostUmaVez $Rota $Corpo
        # 409 "Aguarde": o worker ainda esta no comando anterior.
        if ($r.Codigo -ne 409) { return $r.Codigo }
        Start-Sleep -Milliseconds 200
    }
    return 409
}

function Write-Linha {
    param([double]$Seg, [string]$Texto)
    Write-Host ('[' + $Seg.ToString('00.0', [Globalization.CultureInfo]::InvariantCulture) + 's] ' + $Texto)
}

function Get-MacSoHex { param([string]$Mac) return (($Mac -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()) }

$relogio = [Diagnostics.Stopwatch]::StartNew()
$ok = $false
$feitas = 0; $maxConferindo = 0; $maxLatencia = 0; $consultas = 0; $saiu = $false; $relogioSaida = $null; $segSaida = -1
$recusaFila = $null; $recusaFilaOk = $false
$recusaEncerrar = $null; $recusaEncerrarOk = $false; $codigoEncerrar = 0
$macEditada = ''; $codigoCamera = 0
$macDecisao = ''; $emDecisao = @{}; $codigoDecisao = 0
$fasesDepoisTentar = @(); $registroOk = $false; $registroTxt = ''
$etapasPortao = @{}
$fasesCenario = @(); $falhaEtapa = @{}; $avisosMac = @()
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
    $c = Send-Post '/api/simular' @{ ligado = $true; falharEm = $falharEm }
    Write-Linha $relogio.Elapsed.TotalSeconds ('cenario ' + $Cenario + ': POST /api/simular (falharEm ' + (ConvertTo-Json -InputObject $falharEm -Compress) + ') -> ' + $c)
    $c = Send-Post '/api/fila' @{ inicio = '192.0.2.10'; fim = ('192.0.2.' + (9 + $esperadas)); local = 'Obra exemplo'; rack = 'R1'; andar = '1' }
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
    $etapasVistas = @{}
    $ultimoAviso = ''
    $limite = $relogio.Elapsed.TotalSeconds + $TimeoutSeg
    while ($relogio.Elapsed.TotalSeconds -lt $limite) {
        $r = Get-Estado
        $consultas++
        if ($r.Ms -gt $maxLatencia) { $maxLatencia = $r.Ms }
        $e = $r.Estado
        $conferindo = @()
        $decisao = @()
        foreach ($cam in @($e.cameras)) {
            if ($null -eq $cam) { continue }
            $mac = [string]$cam.mac
            $fase = [string]$cam.fase
            if ($fase -eq 'conferindo') { $conferindo += $mac }
            if ($fase -eq 'decisao') {
                $decisao += $mac; $emDecisao[$mac] = $true
                if ($null -ne $cam.falha) { $falhaEtapa[$mac] = [string]$cam.falha.etapa }
            }
            if ($macCenario -and $mac -eq $macCenario -and @($fasesCenario)[-1] -ne $fase) { $fasesCenario += $fase }
            if ([string]$cam.aviso -like '*MAC*' -and $avisosMac -notcontains ($mac + ': ' + $cam.aviso)) { $avisosMac += ($mac + ': ' + $cam.aviso) }
            $etapa = [string]$cam.etapa
            if ($fase -eq 'portao' -and $etapa) { $etapasPortao[$etapa] = $true }
            if ($fases[$mac] -ne $fase) {
                $txt = $mac + '  ' + $(if ($fases.ContainsKey($mac)) { $fases[$mac] } else { '-' }) + ' -> ' + $fase
                if ($etapa) { $txt += ' [' + $etapa + ']' }
                if ($cam.destino) { $txt += '  (destino ' + $cam.destino + ')' }
                if ($fase -eq 'decisao' -and $null -ne $cam.falha) { $txt += '  falha: ' + $cam.falha.etapa + ': ' + $cam.falha.erro }
                Write-Linha $relogio.Elapsed.TotalSeconds $txt
                $fases[$mac] = $fase
                $etapasVistas[$mac] = $etapa
                if ($macDecisao -and $mac -eq $macDecisao) { $fasesDepoisTentar += $fase }
            } elseif ($etapasVistas[$mac] -ne $etapa) {
                # Mesma fase, etapa nova: o progresso andando etapa por etapa.
                Write-Linha $relogio.Elapsed.TotalSeconds ($mac + '  ' + $fase + ' [' + $etapa + ']')
                $etapasVistas[$mac] = $etapa
            }
        }
        if ($conferindo.Count -gt $maxConferindo) { $maxConferindo = $conferindo.Count }
        if ($e.aviso -and $e.aviso -ne $ultimoAviso) {
            Write-Linha $relogio.Elapsed.TotalSeconds ('aviso: ' + $e.aviso); $ultimoAviso = $e.aviso
            if ([string]$e.aviso -like '*MAC*') { $avisosMac += ('global: ' + $e.aviso) }
        }
        $feitas = @(@($e.cameras) | Where-Object { $null -ne $_ -and $_.fase -eq 'feita' }).Count

        # Fila nova com camera em curso: o listener recusa com o texto do orquestrador.
        if ($basico -and $null -eq $recusaFila -and $null -ne $e.paralelo -and [int]$e.paralelo.emCurso -ge 2) {
            $recusaFila = Send-PostUmaVez '/api/fila' @{ inicio = '192.0.2.20'; fim = '192.0.2.21'; local = 'Obra exemplo'; rack = 'R1'; andar = '1' }
            $erroFila = ''
            try { $erroFila = [string]($recusaFila.Corpo | ConvertFrom-Json).erro } catch { }
            $recusaFilaOk = ($recusaFila.Codigo -eq 409 -and $erroFila -like '*configura*' -and $erroFila -like '*montar uma nova fila.*')
            Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/fila com ' + $e.paralelo.emCurso + ' em curso -> ' + $recusaFila.Codigo + ' ' + $recusaFila.Corpo)
        }
        # Encerrar o painel com camera conferindo: 409 com o texto da recusa.
        if (($basico -or $Cenario -eq 'encerrar') -and $null -eq $recusaEncerrar -and $conferindo.Count -ge 1) {
            $recusaEncerrar = Send-PostUmaVez '/api/encerrar' @{}
            $erroEncerrar = ''
            try { $erroEncerrar = [string]($recusaEncerrar.Corpo | ConvertFrom-Json).erro } catch { }
            $recusaEncerrarOk = ($recusaEncerrar.Codigo -eq 409 -and $erroEncerrar -like '*configura*' -and $erroEncerrar -like '*encerrar o painel.*')
            Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/encerrar com camera conferindo -> ' + $recusaEncerrar.Codigo + ' ' + $recusaEncerrar.Corpo)
        }
        # Uma em decisao e outra conferindo: porta e canal novos para a que confere.
        if ($basico -and -not $macEditada -and $decisao.Count -ge 1 -and $conferindo.Count -ge 1) {
            $macEditada = $conferindo[0]
            $codigoCamera = Send-Post '/api/camera' @{ mac = $macEditada; porta = '7'; canal = '8' }
            Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/camera ' + $macEditada + ' porta 7 canal 8 -> ' + $codigoCamera)
        }
        # A que falhou em decisao e as outras feitas: tentar de novo por MAC.
        if (-not $macDecisao -and $decisao.Count -eq 1 -and $feitas -eq ($esperadas - 1)) {
            $macDecisao = $decisao[0]
            $codigoDecisao = Send-Post '/api/decisao' @{ mac = $macDecisao; acao = 'tentar' }
            Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/decisao ' + $macDecisao + ' tentar -> ' + $codigoDecisao)
        }
        if ($feitas -ge $esperadas) { break }
        $resto = 100 - $r.Ms
        if ($resto -gt 0) { Start-Sleep -Milliseconds $resto }
    }
    Write-Linha $relogio.Elapsed.TotalSeconds ('fase da fila: ' + $e.fase + '; emCurso ' + $e.paralelo.emCurso)

    # Registro: a camera editada durante a conferencia ficou com porta 7 e canal 8.
    if ($macEditada) {
        $reg = $http.GetStringAsync($base + '/api/registro').Result | ConvertFrom-Json
        $ent = @(@($reg.cameras) | Where-Object { $null -ne $_ -and (Get-MacSoHex $_.Mac) -eq (Get-MacSoHex $macEditada) }) | Select-Object -First 1
        if ($null -ne $ent) {
            $registroTxt = 'porta ' + [string]$ent.Porta + ', canal ' + [string]$ent.Canal + ', status ' + [string]$ent.Status
            $registroOk = ([string]$ent.Porta -eq '7' -and [string]$ent.Canal -eq '8')
        } else { $registroTxt = 'camera fora do registro' }
        Write-Linha $relogio.Elapsed.TotalSeconds ('registro de ' + $macEditada + ': ' + $registroTxt)
    }
} catch {
    Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    # Encerra o painel e espera o processo sair.
    try {
        if (-not $proc.HasExited) {
            $codigoEncerrar = Send-Post '/api/encerrar' @{}
            Write-Linha $relogio.Elapsed.TotalSeconds ('POST /api/encerrar -> ' + $codigoEncerrar)
            if ($codigoEncerrar -eq 200) { $relogioSaida = [Diagnostics.Stopwatch]::StartNew() }
        }
    } catch { Write-Host ('  encerrar falhou: ' + $_.Exception.Message) -ForegroundColor Yellow }
    $saiu = $proc.WaitForExit(40000)
    if ($saiu -and $null -ne $relogioSaida) { $segSaida = $relogioSaida.Elapsed.TotalSeconds }
    if (-not $saiu) {
        Write-Host '  o painel nao saiu em 40 s: processo finalizado a forca.' -ForegroundColor Yellow
        try { $proc.Kill() } catch { }
    }
    $http.Dispose()
}

$comumOk = ($codigoEncerrar -eq 200 -and $maxLatencia -lt $LatenciaMaxMs -and $saiu -and $script:errosInternos.Count -eq 0)
$comumTxt = ('; encerrar no fim ' + $codigoEncerrar + '; latencia max ' + $maxLatencia + ' ms em ' + $consultas + ' consultas; erros internos no log ' +
             $script:errosInternos.Count + '; processo encerrado: ' + $saiu)
$sufixo = $macCenario
if ($sufixo) { $sufixo = $sufixo.Substring($sufixo.Length - 8) }
Write-Host ''
foreach ($m in $script:errosInternos) { Write-Host ('  log: ' + $m) -ForegroundColor Red }
switch ($Cenario) {
'basico' {
    $tentouOk = ($macDecisao -and $codigoDecisao -eq 202 -and $fasesDepoisTentar -notcontains 'portao' -and
                 $fasesDepoisTentar -contains 'conferindo' -and @($fasesDepoisTentar)[-1] -eq 'feita')
    $editouOk = ($macEditada -and $codigoCamera -eq 202 -and $macEditada -ne $macDecisao -and $registroOk)
    $encerrarOk = ($recusaEncerrarOk -and $codigoEncerrar -eq 200)
    $etapasPortaoOk = ($etapasPortao.ContainsKey('inicializada') -and $etapasPortao.ContainsKey('encoder') -and $etapasPortao.ContainsKey('rede'))
    $ok = ($feitas -eq $Cameras -and $maxConferindo -ge 2 -and $etapasPortaoOk -and $emDecisao.Count -eq 1 -and $tentouOk -and $recusaFilaOk -and $editouOk -and $encerrarOk -and
           $comumOk)
    Write-Host ('Resumo: feitas ' + $feitas + '/' + $Cameras + '; conferindo ao mesmo tempo (max) ' + $maxConferindo +
                '; etapas no portao ' + ((@($etapasPortao.Keys) | Sort-Object) -join '/') + $(if ($etapasPortaoOk) { ' ok' } else { ' FALHOU' }) +
                '; em decisao ' + $emDecisao.Count + '; tentar de novo ' + $(if ($tentouOk) { 'ok' } else { 'FALHOU' }) +
                ' (fases ' + ($fasesDepoisTentar -join ' > ') + ')' +
                '; fila em curso ' + $(if ($recusaFilaOk) { '409 ok' } else { 'FALHOU' }) +
                '; encerrar ' + $(if ($encerrarOk) { '409 na conferencia, 200 no fim' } else { 'FALHOU (fim ' + $codigoEncerrar + ')' }) +
                '; porta/canal ' + $(if ($editouOk) { 'ok' } else { 'FALHOU' }) + ' (' + $registroTxt + ')' + $comumTxt)
}
'falha-rede-2' {
    $soA2 = ((@($emDecisao.Keys) -join ',') -eq $macCenario -and $falhaEtapa[$macCenario] -eq 'rede')
    $tentouOk = ($macDecisao -eq $macCenario -and $codigoDecisao -eq 202 -and @($fasesDepoisTentar)[-1] -eq 'feita')
    $ok = ($feitas -eq $Cameras -and $soA2 -and $tentouOk -and $comumOk)
    Write-Host ('Resumo [' + $Cenario + ']: feitas ' + $feitas + '/' + $Cameras + '; em decisao ' + (@($emDecisao.Keys) -join ',') +
                ' (falha ' + $falhaEtapa[$macCenario] + ')' + $(if ($soA2) { ' ok' } else { ' FALHOU' }) +
                '; tentar de novo ' + $(if ($tentouOk) { 'ok' } else { 'FALHOU' }) + ' (fases ' + ($fasesDepoisTentar -join ' > ') + ')' + $comumTxt)
}
'mac-trocado-2' {
    $trocados = @($script:logs | Where-Object { $_ -like '*MAC TROCADO*' })
    $trocadoOk = ($trocados.Count -eq 1 -and $trocados[0] -like ('*[[]' + $sufixo + ']*'))
    $portoes = @($script:logs | Where-Object { $_ -like ('*[[]' + $sufixo + ']*---*port*o, at* a rede ---*') }).Count
    $voltouOk = ($portoes -ge 2 -and @($fasesCenario)[-1] -eq 'feita')
    $ok = ($feitas -eq $Cameras -and $emDecisao.Count -eq 0 -and $trocadoOk -and $voltouOk -and $avisosMac.Count -eq 0 -and $comumOk)
    Write-Host ('Resumo [' + $Cenario + ']: feitas ' + $feitas + '/' + $Cameras + '; em decisao ' + $emDecisao.Count +
                '; trava de MAC no log ' + $trocados.Count + 'x' + $(if ($trocadoOk) { ' (so a ' + $macCenario + ') ok' } else { ' FALHOU' }) +
                '; portoes da ' + $macCenario + ' ' + $portoes + ' (fases ' + ($fasesCenario -join ' > ') + ')' + $(if ($voltouOk) { ' ok' } else { ' FALHOU' }) +
                '; avisos citando MAC ' + $avisosMac.Count + $(if ($avisosMac.Count) { ' (' + ($avisosMac -join ' | ') + ')' } else { '' }) + $comumTxt)
}
'encerrar' {
    $saidaOk = ($segSaida -ge 0 -and $segSaida -lt $SaidaMaxSeg)
    $encerrarOk = ($recusaEncerrarOk -and $codigoEncerrar -eq 200 -and $saidaOk)
    $ok = ($feitas -eq $Cameras -and $emDecisao.Count -eq 0 -and $encerrarOk -and $comumOk)
    Write-Host ('Resumo [' + $Cenario + ']: feitas ' + $feitas + '/' + $Cameras + '; em decisao ' + $emDecisao.Count +
                '; encerrar na conferencia ' + $(if ($null -ne $recusaEncerrar) { [string]$recusaEncerrar.Codigo } else { 'nao tentado' }) + $(if ($recusaEncerrarOk) { ' ok' } else { ' FALHOU' }) +
                '; encerrar no fim ' + $codigoEncerrar + ', processo saiu em ' + $segSaida.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) + ' s' +
                $(if ($saidaOk) { ' ok' } else { ' FALHOU (limite ' + $SaidaMaxSeg + ' s)' }) + $comumTxt)
}
'ja-inicializada-3' {
    $d8 = @($script:logs | Where-Object { $_ -like '*Aviso do vigia:*inicializada: n*' })
    $nuncaOk = ($fasesCenario -notcontains 'portao' -and $fasesCenario -notcontains 'conferindo')
    $ok = ($feitas -eq $esperadas -and $emDecisao.Count -eq 0 -and $nuncaOk -and $d8.Count -eq 1 -and $comumOk)
    Write-Host ('Resumo [' + $Cenario + ']: feitas ' + $feitas + '/' + $esperadas + ' (fila de ' + $esperadas + ', ' + $Cameras + ' no DHIP); em decisao ' + $emDecisao.Count +
                '; fases da ' + $macCenario + ' [' + ($fasesCenario -join ' > ') + ']' + $(if ($nuncaOk) { ' nunca no portao/conferindo ok' } else { ' FALHOU' }) +
                '; aviso da D8 no log ' + $d8.Count + 'x' + $(if ($d8.Count -eq 1) { ' ok' } else { ' FALHOU' }) + $comumTxt)
}
}
if ($ok) {
    Write-Host 'SMOKE OK' -ForegroundColor Green
    Remove-Item -LiteralPath $pasta -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}
Write-Host ('SMOKE FALHOU. Log do painel em ' + $pasta) -ForegroundColor Red
exit 1
