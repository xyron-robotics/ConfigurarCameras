<#
    Testes-Motor.ps1
    Testes do Motor-Cameras.ps1 sem camera nem rede.

    O motor nao executa nada ao carregar, entao aqui ele e carregado por
    dot-source direto. Cobre as pecas que falham em silencio:
      - hash do login RPC2 contra vetor calculado por fora (md5sum);
      - ajuste de encoder sobre a tabela REAL da VIP-1230-D-G3;
      - rede, fila, registro, retomada, padroes, gravacao atomica, relatorio;
      - configuracao completa em simulacao, com falha e retomada.

    Uso:
        .\Testes-Motor.ps1
    Sai com codigo 1 se algum teste falhar.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$raiz = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($raiz)) { $raiz = (Get-Location).Path }
$motor = Join-Path $raiz 'Motor-Cameras.ps1'
$fix   = Join-Path $raiz 'testes'

. $motor
$script:Linhas = New-Object 'System.Collections.Generic.List[string]'
Set-MotorLog -Sink { param($Ts, $Msg, $Cor) $script:Linhas.Add($Msg) }

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

function Assert-Estoura {
    param([scriptblock]$Bloco, [string]$Que = 'chamada')
    $estourou = $false
    try { & $Bloco } catch { $estourou = $true }
    if (-not $estourou) { throw ($Que + ' deveria ter estourado e nao estourou') }
}

function Get-Fixture {
    param([string]$Nome)
    return ([IO.File]::ReadAllText((Join-Path $fix $Nome), [Text.Encoding]::UTF8) | ConvertFrom-Json).table
}

function New-Temp { return (Join-Path $env:TEMP ('motor-' + [Guid]::NewGuid().ToString('N'))) }

# ------------------------------------------------------------ higiene

Write-Host ""
Write-Host "Higiene do motor" -ForegroundColor Cyan

T 'Motor nao tem Read-Host fora de comentario' {
    $a = [System.Management.Automation.Language.Parser]::ParseFile($motor, [ref]$null, [ref]$null)
    $cmds = @($a.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Read-Host' }, $true))
    Assert-Igual 0 $cmds.Count 'Read-Host no motor'
}

# Sem BOM o PS 5.1 le o arquivo na pagina ANSI e os avisos acentuados
# chegam quebrados ao painel.
T 'Motor e Servidor-Painel salvos em UTF-8 com BOM e sem erro de sintaxe' {
    foreach ($arq in @($motor, (Join-Path $raiz 'web\Servidor-Painel.ps1'))) {
        $b = [IO.File]::ReadAllBytes($arq)
        Assert-Verdade ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) ('BOM em ' + (Split-Path -Leaf $arq))
        $erros = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($arq, [ref]$null, [ref]$erros)
        Assert-Igual 0 @($erros).Count ('erros de sintaxe em ' + (Split-Path -Leaf $arq))
    }
}

# O servidor nao tem teste de HTTP aqui (so pela API, em simulacao): o que
# da para conferir sem subir e a forma - rotas da sessao presentes, reset e
# padroes fora, -Simular no param.
T 'Servidor: rotas da sessao e -Simular presentes; padroes e resetar fora' {
    $txt = [IO.File]::ReadAllText((Join-Path $raiz 'web\Servidor-Painel.ps1'), [Text.Encoding]::UTF8)
    foreach ($rota in @("'GET /api/placas'", "'GET /api/sessao'", "'PUT /api/sessao'", "'POST /api/sessao/concluir'", "'POST /api/sessao/refazer'", "'POST /api/senha'", "'POST /api/simular'")) {
        Assert-Verdade ($txt.Contains($rota)) ('rota ' + $rota)
    }
    foreach ($fora in @('/api/padroes', '/api/resetar', 'Read-Padroes', 'Get-PadroesFabrica', 'Read-UltimaFila', 'Save-UltimaFila', 'Invoke-CamResetFabrica', 'Set-CameraResetada', 'NomePlaca', "'POST /api/sessao'")) {
        Assert-Falso ($txt.Contains($fora)) ('ainda tem ' + $fora)
    }
    $a = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $raiz 'web\Servidor-Painel.ps1'), [ref]$null, [ref]$null)
    $nomes = @($a.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    Assert-Verdade ($nomes -contains 'Simular') 'param -Simular'
    Assert-Verdade ($nomes -contains 'SemElevar') 'param -SemElevar'
}

T 'Servidor: GET /api/sessao publica o catalogo; vigia ja ligado nao loga de novo' {
    $txt = [IO.File]::ReadAllText((Join-Path $raiz 'web\Servidor-Painel.ps1'), [Text.Encoding]::UTF8)
    Assert-Verdade ($txt -match 'catalogo = \(Get-CatalogoEncoder\)') 'catalogo no GET /api/sessao'
    $i = $txt.IndexOf("'vigia' {")
    $bloco = $txt.Substring($i, $txt.IndexOf('Vigia ligado:', $i) - $i)
    Assert-Verdade ($bloco -match 'if \(\$W\.Vigia\.Ligado\) \{[^}]*return') 'retorno antes do log quando ja ligado'
    Assert-Verdade ($txt -match 'outros = \$outros') 'mudancas do encoder vao para o log'
}

# ------------------------------------------------------ login RPC2

Write-Host ""
Write-Host "Login RPC2" -ForegroundColor Cyan

T 'Hash do login bate com vetor calculado por fora (md5sum)' {
    $realm  = 'Login to 83337A6FA216CC3F'
    $random = 'ba45c9e0-260e-4399-8984-c27668ac6d13'
    Assert-Igual 'BAF46C562BE8259B8E49E69C8299B97A' (Get-Md5Maiusculo ('admin:' + $realm + ':SenhaFicticia@1')) 'MD5 interno'
    Assert-Igual 'BF5C41C1E97F9AF7D9DA3D6229988130' (Get-HashLoginRpc -Usuario 'admin' -Senha 'SenhaFicticia@1' -Realm $realm -Random $random) 'hash final'
}

T 'Classificacao da recusa de login' {
    Assert-Igual 'bloqueada' (Get-ClassificacaoErroLogin 268632081 '') 'codigo de bloqueio'
    Assert-Igual 'bloqueada' (Get-ClassificacaoErroLogin 1 'User locked') 'mensagem de bloqueio'
    Assert-Igual 'senha'     (Get-ClassificacaoErroLogin 268632085 '') 'codigo de senha'
    Assert-Igual 'senha'     (Get-ClassificacaoErroLogin 1 'Password not valid') 'mensagem de senha'
    Assert-Igual 'outro'     (Get-ClassificacaoErroLogin 268632079 'Component error: login challenge!') 'desafio nao e senha'
}

# ------------------------------------------------------ encoder

Write-Host ""
Write-Host "Ajuste de encoder (tabela real da VIP-1230-D-G3)" -ForegroundColor Cyan

# A sessao de fabrica tem os mesmos campos que os Padroes tinham: o motor
# continua recebendo-a como -Padroes. Gateway e e-mail sao da obra e a
# fabrica vem sem eles: os testes que precisam de sessao valida usam a de
# teste (fabrica + rede e e-mail de exemplo).
$script:GatewayTeste = '10.70.20.1'
$script:EmailTeste = 'recuperacao@exemplo.com.br'
function Get-SessaoTeste {
    $s = Get-SessaoFabrica
    $s.Gateway = $script:GatewayTeste; $s.EmailRecuperacao = $script:EmailTeste
    return $s
}
# ConvertTo-Sessao de uma hashtable parcial, com gateway e e-mail de exemplo
# quando a entrada nao traz.
function ConvertTo-SessaoTeste($Entrada) {
    $h = @{ Gateway = $script:GatewayTeste; EmailRecuperacao = $script:EmailTeste }
    foreach ($k in $Entrada.Keys) { $h[$k] = $Entrada[$k] }
    return ConvertTo-Sessao $h
}
$padroes = Get-SessaoTeste

T 'Stream principal: todas as 4 entradas recebem 1920x1080 / 20 fps / 1596 kbps / GOP 40 / H.264' {
    $t = Get-Fixture 'encode-vip1230-d-g3.json'
    $n = @(ConvertTo-EncodeAjustado -Tabela $t -Padroes $padroes)
    $main = @($n[0].MainFormat)
    Assert-Igual 4 $main.Count 'entradas MainFormat'
    foreach ($f in $main) {
        Assert-Igual 1920 $f.Video.Width 'Width'
        Assert-Igual 1080 $f.Video.Height 'Height'
        Assert-Igual 20 $f.Video.FPS 'FPS'
        Assert-Igual 1596 $f.Video.BitRate 'BitRate'
        Assert-Igual '1080P' $f.Video.CustomResolutionName 'CustomResolutionName'
        Assert-Igual 40 $f.Video.GOP 'GOP = 2 x fps'
        Assert-Igual 'H.264' $f.Video.Compression 'codec'
        Assert-Igual 'CBR' $f.Video.BitRateControl 'CBR mantido'
        Assert-Igual 'Main' $f.Video.Profile 'perfil mantido'
    }
}

T 'Stream secundario: as 3 entradas recebem 704x480 (D1) / 12 fps / 512 kbps / GOP 24 / H.264' {
    $t = Get-Fixture 'encode-vip1230-d-g3.json'
    $n = @(ConvertTo-EncodeAjustado -Tabela $t -Padroes $padroes)
    $x = @($n[0].ExtraFormat)
    Assert-Igual 3 $x.Count 'entradas ExtraFormat'
    foreach ($f in $x) {
        Assert-Igual 704 $f.Video.Width 'Width'
        Assert-Igual 480 $f.Video.Height 'Height'
        Assert-Igual 12 $f.Video.FPS 'FPS'
        Assert-Igual 512 $f.Video.BitRate 'BitRate'
        Assert-Igual 24 $f.Video.GOP 'GOP = 2 x fps'
        Assert-Igual 'H.264' $f.Video.Compression 'codec'
        Assert-Igual 'D1' $f.Video.CustomResolutionName 'nome'
        Assert-Igual 'CBR' $f.Video.BitRateControl 'CBR mantido'
    }
    Assert-Igual 1 @($n[0].SnapFormat)[0].Video.FPS 'SnapFormat intocado'
}

T 'Ajuste nao altera a tabela lida (copia)' {
    $t = Get-Fixture 'encode-vip1230-d-g3.json'
    $null = @(ConvertTo-EncodeAjustado -Tabela $t -Padroes $padroes)
    Assert-Igual 30 @(@($t)[0].MainFormat)[0].Video.FPS 'FPS original'
    Assert-Igual 4096 @(@($t)[0].MainFormat)[0].Video.BitRate 'BitRate original'
}

T 'Corpo do setConfig leva table como ARRAY (retorno de funcao desembrulha)' {
    $t = Get-Fixture 'encode-vip1230-d-g3.json'
    $n = @(ConvertTo-EncodeAjustado -Tabela $t -Padroes $padroes)
    $json = ConvertTo-Json -Compress -Depth 30 -InputObject @{ name = 'Encode'; table = [object[]]@($n); options = @() }
    Assert-Verdade ($json -match '"table":\[\{') 'table serializado como array'
    Assert-Verdade ($json -match '"options":\[\]') 'options vazio como array'
    Assert-Verdade ($json -match '"Channels":\[0\]') 'array de 1 elemento preservado'
}

T 'Leitura de volta: ajustada confere, original acusa 21 divergencias' {
    $t = Get-Fixture 'encode-vip1230-d-g3.json'
    $n = @(ConvertTo-EncodeAjustado -Tabela $t -Padroes $padroes)
    Assert-Igual 0 @(Compare-EncodeAplicado -Tabela $n -Padroes $padroes).Count 'ajustada'
    Assert-Igual 21 @(Compare-EncodeAplicado -Tabela $t -Padroes $padroes).Count 'original (7 entradas x fps+bitrate+GOP)'
}

T 'Leitura de volta acusa codec e resolucao do secundario divergentes' {
    $n = @(ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $padroes)
    @($n[0].MainFormat)[2].Video.Compression = 'H.265'
    @($n[0].ExtraFormat)[1].Video.Width = 352
    $dif = @(Compare-EncodeAplicado -Tabela $n -Padroes $padroes)
    Assert-Igual 2 $dif.Count ('divergencias: ' + ($dif -join ' | '))
    Assert-Verdade ($dif[0] -match 'principal \[2\]: codec H.265') 'codec'
    Assert-Verdade ($dif[1] -match 'secundario \[1\]: resolucao 352x480') 'resolucao do secundario'
}

T 'Resumo do encoder para o relatorio' {
    $n = @(ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $padroes)
    $r = Get-ResumoEncode $n
    Assert-Igual '1920x1080|20|1596|H.264|40' ($r.Resolucao + '|' + $r.FpsPrincipal + '|' + $r.BitratePrincipal + '|' +
                                               $r.CodecPrincipal + '|' + $r.GopPrincipal) 'principal'
    Assert-Igual '704x480|12|512|H.264|24' ($r.ResolucaoSecundario + '|' + $r.FpsSecundario + '|' + $r.BitrateSecundario + '|' +
                                            $r.CodecSecundario + '|' + $r.GopSecundario) 'secundario'
}

T 'Resolucao 1280x720 vira 720P; fora da lista e tabela sem MainFormat estouram' {
    $p = Copy-ObjetoJson $padroes
    $p.Encoder.Principal.Resolucao = '1280x720'
    $n = @(ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $p)
    Assert-Igual '720P' @($n[0].MainFormat)[0].Video.CustomResolutionName '720P'
    $p.Encoder.Principal.Resolucao = '1980x1080'
    Assert-Estoura { ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $p } '1980x1080'
    $vazia = @([pscustomobject]@{ ExtraFormat = @() })
    Assert-Estoura { ConvertTo-EncodeAjustado -Tabela $vazia -Padroes $padroes } 'sem MainFormat'
}

T 'H.265 grava Compression; secundario 1280x720 vira 720P; fora da lista estoura' {
    $p = Copy-ObjetoJson $padroes
    $p.Encoder.Principal.Codec = 'H.265'
    $p.Encoder.Secundario.Resolucao = '1280x720'
    $p.Encoder.Secundario.Fps = 15
    $n = @(ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $p)
    Assert-Igual 'H.265' @($n[0].MainFormat)[3].Video.Compression 'codec principal'
    Assert-Igual 'H.264' @($n[0].ExtraFormat)[0].Video.Compression 'codec secundario'
    $x = @($n[0].ExtraFormat)[2].Video
    Assert-Igual '1280|720|720P|30' ([string]$x.Width + '|' + $x.Height + '|' + $x.CustomResolutionName + '|' + $x.GOP) 'secundario 720P'
    Assert-Igual 0 @(Compare-EncodeAplicado -Tabela $n -Padroes $p).Count 'confere'
    $p.Encoder.Secundario.Resolucao = '1920x1080'
    Assert-Estoura { ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $p } '1080p no secundario'
    $p.Encoder.Secundario.Resolucao = '704x480'
    $p.Encoder.Secundario.Codec = 'MJPG'
    Assert-Estoura { ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $p } 'codec fora da lista'
}

T 'Catalogo do encoder: faixas nos degraus, recomendado dentro, toda resolucao dos mapas coberta' {
    $c = Get-CatalogoEncoder
    $br = @($c.bitrates)
    for ($i = 1; $i -lt $br.Count; $i++) { Assert-Verdade ($br[$i] -gt $br[$i - 1]) ('degraus crescentes em ' + $br[$i]) }
    Assert-Verdade ($br[0] -ge 64 -and $br[-1] -le 16384) 'degraus dentro de 64 a 16384'
    Assert-Verdade (@($c.fps | Where-Object { $_ -lt 1 -or $_ -gt 60 }).Count -eq 0) 'fps dentro de 1 a 60'
    Assert-Verdade (@($c.fps) -contains 24) '24 fps na lista (aceito na bancada, 02/10)'
    $res = @(@((Get-MapaResolucoes).Keys) + @((Get-MapaResolucoesSecundario).Keys) | Select-Object -Unique)
    foreach ($r in $res) {
        $f = $c.faixas[$r]
        Assert-Verdade ($null -ne $f) ('faixa de ' + $r)
        Assert-Verdade ($f.min -lt $f.max) ('min < max em ' + $r)
        foreach ($k in 'min', 'max', 'H.264', 'H.265') { Assert-Verdade ($br -contains $f[$k]) ($r + ' ' + $k + ' nos degraus') }
        foreach ($k in 'H.264', 'H.265') { Assert-Verdade ($f[$k] -ge $f.min -and $f[$k] -le $f.max) ($r + ' ' + $k + ' dentro da faixa') }
    }
    foreach ($par in @(@('principal', (Get-MapaResolucoes)), @('secundario', (Get-MapaResolucoesSecundario)))) {
        foreach ($lista in $c.testado[$par[0]], $c.recusado[$par[0]]) {
            foreach ($r in @($lista.resolucoes)) { Assert-Verdade ($par[1].Contains($r)) ($par[0] + ': ' + $r + ' fora do mapa') }
            foreach ($k in @($lista.codecs)) { Assert-Verdade ((Get-CodecsAceitos) -contains $k) ($par[0] + ': codec ' + $k) }
        }
    }
    foreach ($st in 'principal', 'secundario') {
        foreach ($r in @($c.recusado[$st].resolucoes)) { Assert-Falso (@($c.testado[$st].resolucoes) -contains $r) ($st + ': ' + $r + ' testado e recusado') }
    }
    Assert-Verdade (@($c.recusado.secundario.resolucoes) -contains '1280x720') 'secundario 1280x720 recusado na bancada (02/10)'
}

T 'SoFormato: resolucao, fps e codec trocados; BitRate e GOP ficam como lidos' {
    $p = Copy-ObjetoJson $padroes
    $p.Encoder.Principal.Codec = 'H.265'
    $n = @(ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $p -SoFormato)
    foreach ($f in @($n[0].MainFormat)) {
        Assert-Igual '1920|1080|20|H.265|4096|60' ([string]$f.Video.Width + '|' + $f.Video.Height + '|' + $f.Video.FPS + '|' +
                                                   $f.Video.Compression + '|' + $f.Video.BitRate + '|' + $f.Video.GOP) 'principal'
    }
    foreach ($f in @($n[0].ExtraFormat)) {
        Assert-Igual '704|480|12|H.264|1024|60' ([string]$f.Video.Width + '|' + $f.Video.Height + '|' + $f.Video.FPS + '|' +
                                                 $f.Video.Compression + '|' + $f.Video.BitRate + '|' + $f.Video.GOP) 'secundario'
    }
}

T 'Resumo do encoder no log mostra GOP' {
    $r = Get-ResumoEncode (Get-Fixture 'encode-vip1230-d-g3.json')
    Assert-Igual 'stream principal 1920x1080 30 fps 4096 kbps H.264 GOP 60; secundario 704x480 30 fps 1024 kbps H.264 GOP 60' (Format-ResumoEncode $r) 'linha'
}

# Camera de mentira para o encoder: guarda a tabela, registra cada
# gravacao e recusa a gravacao de numero $script:RecusarGravacao.
function Use-CameraEncoderFalsa {
    param($Tabela, [int]$Recusar = 0)
    $script:CamTabela = $Tabela
    $script:Gravadas = New-Object 'System.Collections.Generic.List[object]'
    $script:RecusarGravacao = $Recusar
}
$script:StubsEncoder = {
    function Get-CamEncode { param($Sessao) return [pscustomobject]@{ Ok = $true; Tabela = (Copy-ObjetoJson @($script:CamTabela)); Erro = '' } }
    function Set-CamEncode {
        param($Sessao, $Tabela)
        $script:Gravadas.Add((Copy-ObjetoJson @($Tabela)))
        if ($script:Gravadas.Count -eq $script:RecusarGravacao) {
            return [pscustomobject]@{ Ok = $false; SemResposta = $false; Erro = 'configManager.setConfig recusado (codigo 268959743)' }
        }
        $script:CamTabela = Copy-ObjetoJson @($Tabela)
        return [pscustomobject]@{ Ok = $true; SemResposta = $false; Erro = '' }
    }
}

T 'Encoder em 2 passos: 1o so formato (taxa e GOP lidos), 2o completo; formato igual = 1 gravacao; tudo igual = nenhuma' {
    . $script:StubsEncoder
    Use-CameraEncoderFalsa (Get-Fixture 'encode-vip1230-d-g3.json')
    $r = Set-CamEncodeEmPassos -Sessao $null -Padroes $padroes -Espera 0
    Assert-Verdade $r.Ok $r.Erro
    Assert-Igual 2 $r.Gravacoes 'gravacoes'
    $v1 = @(@($script:Gravadas[0])[0].MainFormat)[0].Video
    Assert-Igual '20|4096|60' ([string]$v1.FPS + '|' + $v1.BitRate + '|' + $v1.GOP) 'passo 1: fps novo, taxa e GOP lidos'
    $v2 = @(@($script:Gravadas[1])[0].ExtraFormat)[0].Video
    Assert-Igual '12|512|24' ([string]$v2.FPS + '|' + $v2.BitRate + '|' + $v2.GOP) 'passo 2 completo'
    Assert-Igual 0 @(Compare-EncodeAplicado -Tabela $r.Volta -Padroes $padroes).Count 'volta confere'

    # Retomada depois do passo 1: so o passo 2.
    Use-CameraEncoderFalsa @(ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $padroes -SoFormato)
    $r = Set-CamEncodeEmPassos -Sessao $null -Padroes $padroes -Espera 0
    Assert-Verdade $r.Ok $r.Erro
    Assert-Igual 1 $r.Gravacoes 'formato ja igual'

    Use-CameraEncoderFalsa $r.Volta
    $r = Set-CamEncodeEmPassos -Sessao $null -Padroes $padroes -Espera 0
    Assert-Igual 0 $r.Gravacoes 'tudo igual'
}

T 'Encoder em 2 passos: recusa diz o passo e o que ele grava' {
    . $script:StubsEncoder
    Use-CameraEncoderFalsa (Get-Fixture 'encode-vip1230-d-g3.json') -Recusar 1
    $r = Set-CamEncodeEmPassos -Sessao $null -Padroes $padroes -Espera 0
    Assert-Falso $r.Ok 'passo 1 recusado'
    Assert-Verdade $r.Recusa 'recusa de valor'
    Assert-Igual 1 $r.Passo 'passo'
    Assert-Verdade ($r.Erro -match 'passo 1 \(formato: principal 1920x1080 20 fps H\.264; secundario 704x480 12 fps H\.264\): .*268959743') $r.Erro

    Use-CameraEncoderFalsa (Get-Fixture 'encode-vip1230-d-g3.json') -Recusar 2
    $r = Set-CamEncodeEmPassos -Sessao $null -Padroes $padroes -Espera 0
    Assert-Igual 2 $r.Passo 'passo'
    Assert-Verdade ($r.Erro -match 'passo 2 \(taxa e GOP: principal 1596 kbps GOP 40; secundario 512 kbps GOP 24\)') $r.Erro
    Assert-Igual 20 @(@($script:CamTabela)[0].MainFormat)[0].Video.FPS 'passo 1 ficou gravado'
}

T 'Mudancas da sessao para o log: encoder, DNS e e-mail; sem sessao antes, nada' {
    $a = Get-SessaoFabrica
    $d = Copy-ObjetoJson $a
    $d.Encoder.Principal.Codec = 'H.265'; $d.Encoder.Principal.Fps = 24
    $d.Encoder.Secundario.Resolucao = '1280x720'; $d.EmailRecuperacao = 'outro@exemplo.com'; $d.Dns2 = '1.1.1.1'
    $m = @(Get-MudancasSessao -Antes $a -Depois $d)
    $txt = $m -join '; '
    Assert-Igual 5 $m.Count $txt
    foreach ($e in 'Dns2 8.8.4.4 -> 1.1.1.1', 'e-mail de recuperacao', 'principal 20 fps -> 24 fps', 'principal H.264 -> H.265', 'secundario 704x480 -> 1280x720') {
        Assert-Verdade ($m -contains $e) ('falta: ' + $e + ' em ' + $txt)
    }
    Assert-Falso ($txt -match '@') 'e-mail nao vai para o log'
    Assert-Igual 0 @(Get-MudancasSessao -Antes $null -Depois $d).Count 'sem sessao antes'
    Assert-Igual 0 @(Get-MudancasSessao -Antes $a -Depois (Copy-ObjetoJson $a)).Count 'nada mudou'
}

T 'Configuracao real (stubs): encoder em 2 gravacoes, conferido, segue para a rede; recusa no passo 2 para no encoder' {
    $d = New-Temp
    try {
        . $script:StubsEncoder
        function Get-EstadoCamera { param($IpOrigem, $Destino) return 'fabrica' }
        function Initialize-Cam { param($Ip, $Senha, $Email, [switch]$Simular) return $true }
        function New-CamSessao { param($Ip, $Senha) return [pscustomobject]@{ Ok = $true; Session = 1 } }
        function Get-CamInfoRpc { param($Sessao) return [pscustomobject]@{ Ok = $true; Modelo = 'VIP'; Serial = 'S'; Firmware = 'f'; Mac = 'D8365F000090' } }
        function Get-CamRedeRpc { param($Sessao) return [pscustomobject]@{ Ok = $false; Erro = 'parar aqui' } }
        function Close-CamSessao { }
        function Test-IpLocal { param($Ip) return $false }
        function Test-IpEmUso { param($Ip) return $false }
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.90'; Mac = '' }

        Use-CameraEncoderFalsa (Get-Fixture 'encode-vip1230-d-g3.json')
        $script:Linhas.Clear()
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro (Join-Path $d 'r.json')
        Assert-Igual 'rede' $r.Falhou ('parou na rede: ' + $r.Erro)
        Assert-Igual 2 $script:Gravadas.Count 'gravacoes do encoder'
        Assert-Igual 60 @(@($script:Gravadas[0])[0].MainFormat)[0].Video.GOP '1a gravacao com o GOP lido'
        $log = $script:Linhas -join "`n"
        Assert-Verdade ($log -match 'lido: stream principal 1920x1080 30 fps 4096 kbps H\.264 GOP 60') 'log do lido'
        Assert-Verdade ($log -match 'conferido: .*GOP 40') 'log do conferido'

        Use-CameraEncoderFalsa (Get-Fixture 'encode-vip1230-d-g3.json') -Recusar 2
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro (Join-Path $d 'r2.json')
        Assert-Igual 'encoder' $r.Falhou 'parou no encoder'
        Assert-Verdade $r.Recusa 'recusa'
        Assert-Verdade ($r.Erro -match 'passo 2') $r.Erro
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# ------------------------------------------------------ rede

Write-Host ""
Write-Host "Rede" -ForegroundColor Cyan

T 'Network ajustado: IP fixo, DHCP desligado, 2 DNS, resto intacto' {
    $t = Get-Fixture 'network-vip1230-d-g3.json'
    $n = ConvertTo-NetworkAjustado -Tabela $t -Ip '10.70.20.50' -Mascara '255.255.255.0' `
                                   -Gateway '10.70.20.1' -Dns1 '8.8.8.8' -Dns2 '8.8.4.4'
    Assert-Igual '10.70.20.50' $n.eth0.IPAddress 'IP'
    Assert-Igual '255.255.255.0' $n.eth0.SubnetMask 'mascara'
    Assert-Igual '10.70.20.1' $n.eth0.DefaultGateway 'gateway'
    Assert-Igual 'False' $n.eth0.DhcpEnable 'DHCP'
    Assert-Igual '8.8.8.8,8.8.4.4' (@($n.eth0.DnsServers) -join ',') 'DNS'
    Assert-Igual 1500 $n.eth0.MTU 'MTU intacto'
    Assert-Igual 'IPC' $n.Hostname 'hostname intacto'
    Assert-Igual '10.16.251.208' $t.eth0.IPAddress 'original intacto'
    $r = Get-ResumoRede $t
    Assert-Igual 'd8:36:5f:00:00:f4' $r.Mac 'MAC no resumo'
}

T 'Network sem eth0 nem DefaultInterface estoura' {
    Assert-Estoura { ConvertTo-NetworkAjustado -Tabela ([pscustomobject]@{ Hostname = 'x' }) -Ip '1.1.1.2' `
                     -Mascara '255.255.255.0' -Gateway '1.1.1.1' -Dns1 '8.8.8.8' -Dns2 '8.8.4.4' } 'sem interface'
}

T 'Destino na rede do gateway' {
    Assert-Verdade (Test-DestinoNaRede '10.70.20.50' '255.255.255.0' '10.70.20.1') 'mesma /24'
    Assert-Falso   (Test-DestinoNaRede '10.70.21.50' '255.255.255.0' '10.70.20.1') 'outra /24'
    Assert-Falso   (Test-DestinoNaRede '10.70.20.1'  '255.255.255.0' '10.70.20.1') 'o proprio gateway'
    Assert-Verdade (Test-DestinoNaRede '10.16.251.9' '255.255.252.0' '10.16.248.1') '/22 atravessando octeto'
    Assert-Falso   (Test-DestinoNaRede '10.0.0.5' '255.0.255.0' '10.0.0.1') 'mascara nao contigua'
}

# ------------------------------------------------------ fila

Write-Host ""
Write-Host "Fila" -ForegroundColor Cyan

T 'Fila da faixa: posicoes em ordem, bordas incluidas' {
    $f = @(New-FilaDeFaixa -Inicio '10.70.20.50' -Fim '10.70.20.52')
    Assert-Igual 3 $f.Count 'tamanho'
    Assert-Igual '10.70.20.50' $f[0].Ip 'primeiro'
    Assert-Igual '10.70.20.52' $f[2].Ip 'ultimo'
    Assert-Igual 3 $f[2].Posicao 'posicao'
    Assert-Igual 1 @(New-FilaDeFaixa -Inicio '10.70.20.50' -Fim '10.70.20.50').Count 'faixa de 1'
}

T 'Fila recusa faixa invertida, IP invalido e faixa grande demais' {
    Assert-Estoura { New-FilaDeFaixa -Inicio '10.70.20.52' -Fim '10.70.20.50' } 'invertida'
    Assert-Estoura { New-FilaDeFaixa -Inicio '10.70.20' -Fim '10.70.20.50' } 'truncado'
    Assert-Estoura { New-FilaDeFaixa -Inicio '10.70.0.1' -Fim '10.70.20.1' } 'grande'
}

# O texto vira o aviso do painel: diz o que fazer. Regex com '.' no lugar da
# letra acentuada (este arquivo e ASCII).
T 'Mensagens da fila dizem o que fazer' {
    $msg = { param($b) try { & $b; '' } catch { $_.Exception.Message } }
    Assert-Verdade ((& $msg { New-FilaDeFaixa -Inicio '10.70.20.52' -Fim '10.70.20.50' }) -match 'Troque o primeiro e o .ltimo IP') 'invertida'
    Assert-Verdade ((& $msg { New-FilaDeFaixa -Inicio '10.70.20' -Fim '10.70.20.50' }) -match '^Primeiro IP inv.lido: .*quatro n.meros') 'truncado'
    Assert-Verdade ((& $msg { New-FilaDeFaixa -Inicio '10.70.0.1' -Fim '10.70.20.1' }) -match 'Divida em faixas menores') 'grande'
}

T 'Fila pula registrado, gateway, broadcast e fora da rede' {
    $reg = New-Registro
    $e = New-EntradaRegistro -Mac 'aa:bb:cc:00:00:01' -Ip '10.70.20.51'; $e.Status = 'Instalada'
    Set-CameraRegistro $reg $e
    $f = @(New-FilaDeFaixa -Inicio '10.70.20.1' -Fim '10.70.21.1' -Registro $reg -Maximo 300 `
                           -Mascara '255.255.255.0' -Gateway '10.70.20.1')
    $por = @{}; foreach ($x in $f) { $por[$x.Ip] = $x }
    Assert-Igual 'pulada' $por['10.70.20.1'].Estado 'gateway'
    Assert-Igual 'e o gateway' $por['10.70.20.1'].Motivo 'motivo gateway'
    Assert-Igual 'pulada' $por['10.70.20.51'].Estado 'registrado'
    Assert-Verdade ($por['10.70.20.51'].Motivo -match 'Instalada') 'motivo registrado'
    Assert-Igual 'pulada' $por['10.70.20.255'].Estado 'broadcast'
    Assert-Igual 'pulada' $por['10.70.21.0'].Estado 'fora da rede'
    Assert-Igual 'pendente' $por['10.70.20.50'].Estado 'livre'
}

T 'Porta e canal do vigia: soma 1 ao ultimo numero' {
    Assert-Igual '16' (Step-Rotulo '15') 'numero'
    Assert-Igual 'Gi1/0/16' (Step-Rotulo 'Gi1/0/15') 'porta de switch'
    Assert-Igual '10' (Step-Rotulo '09') 'passa de 9'
    Assert-Igual '008' (Step-Rotulo '007') 'zeros a esquerda'
    Assert-Igual 'D2-B' (Step-Rotulo 'D1-B') 'numero no meio'
    Assert-Igual '' (Step-Rotulo '') 'vazio'
    Assert-Igual 'A' (Step-Rotulo 'A') 'sem numero'
}

T 'Fila numa /22: .255 do meio e host valido' {
    $f = @(New-FilaDeFaixa -Inicio '10.16.249.254' -Fim '10.16.250.1' -Mascara '255.255.252.0' -Gateway '10.16.248.1')
    Assert-Igual 'pendente,pendente,pendente,pendente' (($f | ForEach-Object { $_.Estado }) -join ',') 'todos validos'
}

# ------------------------------------------------------ registro e retomada

Write-Host ""
Write-Host "Registro e retomada" -ForegroundColor Cyan

T 'Registro: upsert por MAC substitui (qualquer grafia) e preserva os outros' {
    $reg = New-Registro
    Set-CameraRegistro $reg (New-EntradaRegistro -Mac 'D8:36:5F:00:00:F4' -Ip '10.70.20.50')
    Set-CameraRegistro $reg (New-EntradaRegistro -Mac '98e55b000001' -Ip '10.70.20.51')
    $nova = New-EntradaRegistro -Mac 'd8-36-5f-00-00-f4' -Ip '10.70.20.60'
    Set-CameraRegistro $reg $nova
    Assert-Igual 2 @($reg.Cameras).Count 'sem duplicar'
    Assert-Igual '10.70.20.60' (Find-CameraRegistro $reg 'd8365f0000f4').Ip 'entrada substituida'
    Assert-Igual '10.70.20.51' (Find-CameraRegistro $reg '98:E5:5B:00:00:01').Ip 'outra preservada'
    Assert-Estoura { Set-CameraRegistro $reg (New-EntradaRegistro -Mac '' -Ip '1.1.1.1') } 'sem MAC'
}

T 'Etapas em ordem' {
    Assert-Igual 'inicializada' (Get-ProximaEtapa '') 'inicio'
    Assert-Igual 'encoder' (Get-ProximaEtapa 'inicializada') 'depois da inicializacao'
    Assert-Igual 'rede' (Get-ProximaEtapa 'encoder') 'depois do encoder'
    Assert-Igual 'conferida' (Get-ProximaEtapa 'rede') 'depois da rede'
    Assert-Igual '' (Get-ProximaEtapa 'conferida') 'fim'
    Assert-Estoura { Get-ProximaEtapa 'xyz' } 'desconhecida'
}

T 'Retomada escolhe a etapa certa' {
    $emAndamento = [pscustomobject]@{ Status = 'Em andamento'; Etapa = 'encoder'; Ip = '10.0.0.50'; Data = '' }
    $naRede      = [pscustomobject]@{ Status = 'Falhou'; Etapa = 'rede'; Ip = '10.0.0.50'; Data = '' }
    $instalada   = [pscustomobject]@{ Status = 'Instalada'; Etapa = 'conferida'; Ip = '10.0.0.50'; Data = 'd' }

    $p = Get-PlanoRetomada $null 'fabrica' '192.168.1.108' '10.0.0.50'
    Assert-Igual 'configurar|' ($p.Acao + '|' + $p.Concluida) 'fabrica nova'
    $p = Get-PlanoRetomada $instalada 'fabrica' '192.168.1.108' '10.0.0.50'
    Assert-Igual 'configurar|' ($p.Acao + '|' + $p.Concluida) 'resetada recomeca'
    Assert-Verdade ($p.Motivo -match 'reset') 'motivo reset'
    $p = Get-PlanoRetomada $instalada 'inicializada' '192.168.1.108' '10.0.0.50'
    Assert-Igual 'recusar' $p.Acao 'instalada nunca e reconfigurada'
    $p = Get-PlanoRetomada $null 'inicializada' '10.16.251.208' '10.0.0.50'
    Assert-Igual 'inicializada' $p.Concluida 'inicializada por fora: segue do encoder'
    $p = Get-PlanoRetomada $emAndamento 'inicializada' '192.168.1.108' '10.0.0.50'
    Assert-Igual 'encoder' $p.Concluida 'retoma depois do encoder'
    $p = Get-PlanoRetomada $naRede 'inicializada' '192.168.1.108' '10.0.0.50'
    Assert-Igual 'encoder' $p.Concluida 'ainda no IP velho: refaz a rede'
    $p = Get-PlanoRetomada $naRede 'destino' '192.168.1.108' '10.0.0.50'
    Assert-Igual 'rede|10.0.0.50' ($p.Concluida + '|' + $p.Ip) 'ja no destino: so conferir'
    $p = Get-PlanoRetomada $null 'destino' '192.168.1.108' '10.0.0.50'
    Assert-Igual 'recusar' $p.Acao 'destino ocupado por desconhecido'
    $p = Get-PlanoRetomada $emAndamento 'muda' '192.168.1.108' '10.0.0.50'
    Assert-Igual 'recusar' $p.Acao 'nao responde'
}

# ------------------------------------------------------ sessao

Write-Host ""
Write-Host "Sessao (passo a passo)" -ForegroundColor Cyan

T 'Sessao de fabrica: sem gateway nem e-mail (sao da obra), incompleta (sem placa, etapa 0), encoder pedido' {
    $f = Get-SessaoFabrica
    $c = @(Test-SessaoPorCampo $f)
    Assert-Igual 'Gateway,EmailRecuperacao' (($c | ForEach-Object { $_.campo }) -join ',') 'faltam so gateway e e-mail'
    Assert-Verdade ($c[0].msg -match '^Informe o gateway' -and $c[1].msg -match '^Informe o e-mail') ('textos: ' + (($c | ForEach-Object { $_.msg }) -join ' | '))
    Assert-Igual 0 @(Test-Sessao $padroes).Count 'com gateway e e-mail, sem erro'
    Assert-Falso (Test-SessaoCompleta $padroes) 'incompleta sem placa'
    Assert-Igual '0|' ([string]$f.Etapa + '|' + $f.Quando) 'etapa 0, sem data'
    Assert-Verdade ($null -eq $f.Placa -and $null -eq $f.Fila) 'placa e fila nulas'
    $pr = $f.Encoder.Principal; $se = $f.Encoder.Secundario
    Assert-Igual '1920x1080|20|1596|H.264' ($pr.Resolucao + '|' + $pr.Fps + '|' + $pr.BitRate + '|' + $pr.Codec) 'principal'
    Assert-Igual '704x480|12|512|H.264' ($se.Resolucao + '|' + $se.Fps + '|' + $se.BitRate + '|' + $se.Codec) 'secundario'
    Assert-Igual '192.168.1.108' $f.IpFabrica 'IP de fabrica'
}

T 'Gravar secao: gateway e e-mail vazios so barram quando a secao os envia' {
    $s = ConvertTo-Sessao @{ Etapa = 2; Placa = @{ Nome = 'Ethernet'; IfIndex = 8 } }
    Assert-Igual 0 @(Test-SessaoParaGravar -Sessao $s -Enviados @('Placa', 'Etapa')).Count 'passo 2 grava com a fabrica vazia'
    Assert-Igual 'Gateway' ((@(Test-SessaoParaGravar -Sessao $s -Enviados @('Mascara', 'Gateway', 'Dns1', 'Dns2')) | ForEach-Object { $_.campo }) -join ',') 'passo 3 enviou o gateway vazio'
    Assert-Igual 'EmailRecuperacao' ((@(Test-SessaoParaGravar -Sessao $s -Enviados @('EmailRecuperacao', 'Encoder')) | ForEach-Object { $_.campo }) -join ',') 'passo 5 enviou o e-mail vazio'
    $s.Gateway = '10.70.20'
    Assert-Igual 'Gateway' ((@(Test-SessaoParaGravar -Sessao $s -Enviados @('Placa')) | ForEach-Object { $_.campo }) -join ',') 'gateway preenchido e invalido barra sempre'
    Assert-Igual 2 @(Test-SessaoPorCampo (ConvertTo-Sessao @{ Placa = @{ Nome = 'E'; IfIndex = 8 } })).Count 'concluir continua exigindo os dois'
}

T 'ConvertTo-Sessao: campo ausente herda a fabrica; Placa e Fila ausentes ficam nulas; ifIndex/etapa viram int' {
    $antigo = '{"Mascara":"255.255.252.0","Gateway":"10.16.250.1","Dns1":"8.8.8.8","Dns2":"8.8.4.4",' +
              '"EmailRecuperacao":"a@b.com","Encoder":{"Principal":{"Resolucao":"1280x720","Fps":15,"BitRate":2048},' +
              '"Secundario":{"Fps":10}}}' | ConvertFrom-Json
    $p = ConvertTo-Sessao $antigo
    Assert-Igual 0 @(Test-Sessao $p).Count ('erros: ' + (@(Test-Sessao $p) -join ' | '))
    Assert-Igual '10.16.250.1|192.168.1.108' ($p.Gateway + '|' + $p.IpFabrica) 'mantem o gravado e herda o IP de fabrica'
    Assert-Igual '1280x720|15|2048|H.264' ($p.Encoder.Principal.Resolucao + '|' + $p.Encoder.Principal.Fps + '|' +
                                           $p.Encoder.Principal.BitRate + '|' + $p.Encoder.Principal.Codec) 'principal'
    Assert-Igual '704x480|10|512|H.264' ($p.Encoder.Secundario.Resolucao + '|' + $p.Encoder.Secundario.Fps + '|' +
                                         $p.Encoder.Secundario.BitRate + '|' + $p.Encoder.Secundario.Codec) 'secundario'
    Assert-Verdade ($null -eq $p.Placa -and $null -eq $p.Fila) 'placa e fila nulas'
    $s = ConvertTo-Sessao ('{"Etapa":"5","Placa":{"Nome":" Ethernet ","IfIndex":"8","Mac":"d8-36-5f-00-00-f4"},"Fila":{"Inicio":"10.70.20.50","Fim":"10.70.20.60"}}' | ConvertFrom-Json)
    Assert-Verdade ($s.Etapa -is [int] -and $s.Placa.IfIndex -is [int]) 'ints'
    Assert-Igual '5|Ethernet|8|D8365F0000F4|ethernet' ([string]$s.Etapa + '|' + $s.Placa.Nome + '|' + $s.Placa.IfIndex + '|' + $s.Placa.Mac + '|' + $s.Placa.Tipo) 'placa com trim, MAC normalizado, tipo padrao'
    Assert-Igual '10.70.20.50|10.70.20.60|' ($s.Fila.Inicio + '|' + $s.Fila.Fim + '|' + $s.Fila.Local) 'fila'
    Assert-Igual 7 (ConvertTo-Sessao ([pscustomobject]@{ Etapa = 99 })).Etapa 'etapa limitada a 7'
    Assert-Igual 0 (ConvertTo-Sessao ([pscustomobject]@{ Etapa = 'x' })).Etapa 'etapa invalida = 0'
    # Hashtable in-process tambem serve de entrada.
    $h = ConvertTo-Sessao @{ Gateway = '10.0.0.1'; Placa = @{ Nome = 'USB'; IfIndex = 3 } }
    Assert-Igual '10.0.0.1|USB|3' ($h.Gateway + '|' + $h.Placa.Nome + '|' + $h.Placa.IfIndex) 'hashtable'
}

T 'Campo presente e vazio NAO herda a fabrica (vira erro)' {
    $p = Copy-ObjetoJson $padroes
    $p.IpFabrica = ''
    $p.Encoder.Secundario.Codec = ''
    $erros = @(Test-Sessao (ConvertTo-Sessao $p))
    Assert-Igual 2 $erros.Count ('erros: ' + ($erros -join ' | '))
}

T 'Sessao invalida: secundario, codec e IP de fabrica' {
    $p = Copy-ObjetoJson $padroes
    $p.Encoder.Principal.Codec = 'MJPG'
    $p.Encoder.Secundario.Resolucao = '1920x1080'
    $p.Encoder.Secundario.Fps = 0
    $p.Encoder.Secundario.BitRate = 20000
    $erros = @(Test-Sessao (ConvertTo-Sessao $p))
    Assert-Igual 4 $erros.Count ('erros: ' + ($erros -join ' | '))

    $p = Copy-ObjetoJson $padroes
    $p.IpFabrica = '10.70.20.108'
    $erros = @(Test-Sessao $p)
    Assert-Verdade (($erros -join ' ') -match 'dentro da rede do gateway') 'IP de fabrica na rede do gateway'
    $p.IpFabrica = '192.168.1.220'
    Assert-Verdade ((@(Test-Sessao $p) -join ' ') -match '\.220') 'IP de fabrica .220'
    $p.IpFabrica = '192.168.1'
    Assert-Verdade ((@(Test-Sessao $p) -join ' ') -match 'IP de f.brica inv.lido') 'IP de fabrica truncado'
    $p.IpFabrica = '192.168.0.108'
    Assert-Igual 0 @(Test-Sessao $p).Count 'outro IP de fabrica valido'
}

T 'Sessao invalida e apontada um campo por vez' {
    $p = Copy-ObjetoJson $padroes
    $p.Mascara = '255.0.255.0'
    $p.Gateway = '10.70.20'
    $p.EmailRecuperacao = 'sem-arroba'
    $p.Encoder.Principal.Resolucao = '1980x1080'
    $p.Encoder.Principal.Fps = 0
    $p.Encoder.Principal.BitRate = 'abc'
    $p.Encoder.Secundario.Fps = 99
    $erros = @(Test-Sessao (ConvertTo-Sessao $p))
    Assert-Igual 7 $erros.Count ('erros: ' + ($erros -join ' | '))
}

T 'Erros por campo: nome do campo do formulario do painel, placa e fila inclusive' {
    $p = Copy-ObjetoJson $padroes
    $p.Mascara = '255.0.255.0'
    $p.Dns2 = 'x'
    $p.IpFabrica = '10.70.20.108'
    $p.Encoder.Principal.BitRate = 'abc'
    $p.Encoder.Secundario.Fps = 99
    $p.Encoder.Secundario.Codec = 'MJPG'
    $c = @(Test-SessaoPorCampo (ConvertTo-Sessao $p))
    Assert-Igual 'Mascara,Dns2,IpFabrica,BitRate,FpsSecundario,CodecSecundario' (($c | ForEach-Object { $_.campo }) -join ',') 'campos'
    Assert-Verdade ($c[3].msg -match '^Bitrate do stream principal') 'texto do stream'
    Assert-Igual ((@($c | ForEach-Object { $_.msg })) -join '|') ((@(Test-Sessao (ConvertTo-Sessao $p))) -join '|') 'Test-Sessao = so os textos'
    Assert-Igual 0 @(Test-SessaoPorCampo $padroes).Count 'sessao de teste sem erro'
    # Placa sem ifIndex e fila invertida / fora da rede.
    $s = ConvertTo-SessaoTeste @{ Placa = @{ Nome = ''; IfIndex = 0 }; Fila = @{ Inicio = '10.70.20.60'; Fim = '10.70.20.50' } }
    $c = @(Test-SessaoPorCampo $s)
    Assert-Igual 'Placa,FilaInicio' (($c | ForEach-Object { $_.campo }) -join ',') 'placa e faixa invertida'
    Assert-Verdade ($c[1].msg -match 'invertida') 'texto da faixa'
    $s = ConvertTo-SessaoTeste @{ Placa = @{ Nome = 'Ethernet'; IfIndex = 8 }; Fila = @{ Inicio = '10.70.21.50'; Fim = '10.70.21.60' } }
    $c = @(Test-SessaoPorCampo $s)
    Assert-Igual 'FilaInicio' (($c | ForEach-Object { $_.campo }) -join ',') 'fila fora da rede do gateway'
    Assert-Verdade ($c[0].msg -match 'fora da rede do gateway') 'texto'
    $s = ConvertTo-SessaoTeste @{ Fila = @{ Inicio = 'x'; Fim = '' } }
    Assert-Igual 'FilaInicio,FilaFim' ((@(Test-SessaoPorCampo $s) | ForEach-Object { $_.campo }) -join ',') 'fila com IPs invalidos'
}

T 'Sessao vinda do painel como texto vira numero' {
    $entrada = '{"Mascara":"255.255.255.0","Gateway":"10.70.20.1","Dns1":"8.8.8.8","Dns2":"8.8.4.4",' +
               '"EmailRecuperacao":"a@b.com","Encoder":{"Principal":{"Resolucao":"1920x1080","Fps":"20","BitRate":"1596"},' +
               '"Secundario":{"Fps":"12"}}}' | ConvertFrom-Json
    $p = ConvertTo-Sessao $entrada
    Assert-Verdade ($p.Encoder.Principal.Fps -is [int]) 'fps inteiro'
    Assert-Igual 0 @(Test-Sessao $p).Count 'valido'
}

T 'Merge-Sessao: so o que veio muda, Encoder/Placa/Fila inteiras, Etapa nunca volta' {
    $base = ConvertTo-Sessao @{ Etapa = 4; Gateway = '10.0.0.1'; Placa = @{ Nome = 'Ethernet'; IfIndex = 8; Mac = 'aa' } }
    $m = Merge-Sessao -Atual $base -Entrada ([pscustomobject]@{ etapa = 2; Dns1 = '1.1.1.1'; Fila = @{ Inicio = '10.0.0.50'; Fim = '10.0.0.60'; Local = 'X' } })
    Assert-Igual '4|10.0.0.1|1.1.1.1|8|10.0.0.50|X' ([string]$m.Etapa + '|' + $m.Gateway + '|' + $m.Dns1 + '|' + $m.Placa.IfIndex + '|' + $m.Fila.Inicio + '|' + $m.Fila.Local) 'parcial'
    $m2 = Merge-Sessao -Atual $m -Entrada @{ Etapa = 6; Placa = @{ Nome = 'USB'; IfIndex = 3 }; Encoder = @{ Principal = @{ Fps = 25 } } }
    Assert-Igual '6|USB|3|25|1920x1080|12' ([string]$m2.Etapa + '|' + $m2.Placa.Nome + '|' + $m2.Placa.IfIndex + '|' + $m2.Encoder.Principal.Fps + '|' + $m2.Encoder.Principal.Resolucao + '|' + $m2.Encoder.Secundario.Fps) 'placa trocada inteira; encoder parcial herda a fabrica'
    Assert-Igual '10.0.0.50' $m2.Fila.Inicio 'fila ficou'
    Assert-Igual '4' ([string]$m.Etapa) 'merge nao altera a atual'
    $m3 = Merge-Sessao -Atual $null -Entrada @{ Gateway = '192.168.5.1'; Versao = 9; Quando = 'x'; confirmar = $true; Lixo = 1 }
    Assert-Igual '192.168.5.1|1||0' ($m3.Gateway + '|' + $m3.Versao + '|' + $m3.Quando + '|' + $m3.Etapa) 'sem atual = fabrica; Versao/Quando/desconhecidos ignorados'
    Assert-Verdade ($null -eq $m3.PSObject.Properties['confirmar']) 'confirmar nao entra na sessao'
}

T 'Test-SessaoCompleta exige placa com ifIndex, zero erros e Etapa 7; fila e opcional' {
    $s = ConvertTo-SessaoTeste @{ Etapa = 7; Placa = @{ Nome = 'Ethernet'; IfIndex = 8 } }
    Assert-Verdade (Test-SessaoCompleta $s) 'completa sem fila'
    $s.Etapa = 6
    Assert-Falso (Test-SessaoCompleta $s) 'etapa 6'
    $s = ConvertTo-SessaoTeste @{ Etapa = 7; Placa = @{ Nome = 'Ethernet'; IfIndex = 0 } }
    Assert-Falso (Test-SessaoCompleta $s) 'placa sem ifIndex'
    $s = ConvertTo-SessaoTeste @{ Etapa = 7; Placa = @{ Nome = 'Ethernet'; IfIndex = 8 }; Gateway = 'x' }
    Assert-Falso (Test-SessaoCompleta $s) 'com erro'
    $s = ConvertTo-Sessao @{ Etapa = 7; Placa = @{ Nome = 'Ethernet'; IfIndex = 8 } }
    Assert-Falso (Test-SessaoCompleta $s) 'fabrica sem gateway e e-mail nao completa'
    Assert-Falso (Test-SessaoCompleta $null) 'nula'
}

T 'Get-CamposRedeAlterados e Test-FilaCabeNaRede' {
    $a = ConvertTo-Sessao @{ Placa = @{ Nome = 'E'; IfIndex = 8 }; Gateway = '10.0.0.1' }
    $b = ConvertTo-Sessao @{ Placa = @{ Nome = 'E'; IfIndex = 8 }; Gateway = '10.0.0.1'; Dns1 = '9.9.9.9'; EmailRecuperacao = 'x@y.z' }
    Assert-Igual 0 @(Get-CamposRedeAlterados $a $b).Count 'dns e e-mail nao mexem na placa'
    $c = ConvertTo-Sessao @{ Placa = @{ Nome = 'U'; IfIndex = 3 }; Gateway = '10.0.1.1'; IpPcCameras = '10.0.1.200' }
    Assert-Igual 'Placa,Gateway,IpPcCameras' (@(Get-CamposRedeAlterados $a $c) -join ',') 'placa, gateway e IP do PC'
    Assert-Igual 'Placa' (@(Get-CamposRedeAlterados $a (ConvertTo-Sessao @{ Gateway = '10.0.0.1' })) -join ',') 'placa que sumiu'
    Assert-Verdade (Test-FilaCabeNaRede -Inicio '10.70.20.50' -Fim '10.70.20.99' -Mascara '255.255.255.0' -Gateway '10.70.20.1') 'cabe'
    Assert-Falso (Test-FilaCabeNaRede -Inicio '10.70.20.50' -Fim '10.70.21.5' -Mascara '255.255.255.0' -Gateway '10.70.20.1') 'fim fora'
    Assert-Verdade (Test-FilaCabeNaRede -Inicio '10.16.249.5' -Fim '10.16.251.5' -Mascara '255.255.252.0' -Gateway '10.16.248.1') '/22'
    Assert-Falso (Test-FilaCabeNaRede -Inicio 'x' -Fim '1.1.1.1' -Mascara '255.255.255.0' -Gateway '1.1.1.254') 'invalido'
}

T 'Read-Sessao nula sem arquivo; Save-Sessao carimba Quando e le de volta igual' {
    $d = New-Temp
    $arq = Join-Path $d 'sessao.json'
    try {
        Assert-Verdade ($null -eq (Read-Sessao -Caminho $arq)) 'ausente = nula'
        $s = ConvertTo-SessaoTeste @{ Etapa = 7; Placa = @{ Nome = 'Ethernet'; IfIndex = 8; Mac = 'd8365f0000f4'; Tipo = 'ethernet' }; Fila = @{ Inicio = '10.70.20.50'; Fim = '10.70.20.60'; Local = 'OBRA1' } }
        $g = Save-Sessao -Caminho $arq -Sessao $s
        Assert-Verdade ($g.Quando -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}') 'quando'
        $l = Read-Sessao -Caminho $arq
        Assert-Igual '7|Ethernet|8|D8365F0000F4|10.70.20.50|OBRA1' ([string]$l.Etapa + '|' + $l.Placa.Nome + '|' + $l.Placa.IfIndex + '|' + $l.Placa.Mac + '|' + $l.Fila.Inicio + '|' + $l.Fila.Local) 'lida'
        Assert-Verdade ($l.Placa.IfIndex -is [int]) 'ifIndex int depois do JSON'
        Assert-Verdade (Test-SessaoCompleta $l) 'completa'
        Assert-Falso ([IO.File]::ReadAllText($arq) -cmatch '"Senha"') 'senha nunca vai para o arquivo'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# Get-PlacasFisicas trocada por lista fixa: a migracao resolve NomePlaca por nome.
T 'Import-SessaoLegada: padroes.json + ultima-fila.json viram sessao.json uma vez; NomePlaca resolvido = etapa 7, vazio = etapa 0' {
    function Get-PlacasFisicas { return @(@{ Nome = 'Ethernet 2'; IfIndex = 12; Mac = 'AABBCC001122'; Tipo = 'ethernet' }) }
    $d = New-Temp
    try {
        $null = New-Item -ItemType Directory -Force -Path $d
        $ses = Join-Path $d 'sessao.json'; $pad = Join-Path $d 'padroes.json'; $ult = Join-Path $d 'ultima-fila.json'
        Assert-Verdade ($null -eq (Import-SessaoLegada -CaminhoSessao $ses -CaminhoPadroes $pad -CaminhoUltimaFila $ult)) 'nada para migrar'
        [IO.File]::WriteAllText($pad, '{"Mascara":"255.255.252.0","Gateway":"10.16.250.1","Dns1":"8.8.8.8","Dns2":"8.8.4.4","EmailRecuperacao":"a@b.com","IpFabrica":"192.168.1.108","NomePlaca":"Ethernet 2","IpPcFabrica":"","IpPcCameras":"10.16.251.240","Encoder":{"Principal":{"Resolucao":"1920x1080","Fps":20,"BitRate":1596,"Codec":"H.264"},"Secundario":{"Resolucao":"704x480","Fps":12,"BitRate":512,"Codec":"H.264"}}}')
        [IO.File]::WriteAllText($pad + '.bak', '{}')
        [IO.File]::WriteAllText($ult, '{"Inicio":"10.16.250.50","Fim":"10.16.250.60","Local":"OBRA1","Rack":"R1","Andar":"T","Quando":"2026-10-01 10:00:00"}')
        $script:Linhas.Clear()
        $s = Import-SessaoLegada -CaminhoSessao $ses -CaminhoPadroes $pad -CaminhoUltimaFila $ult
        Assert-Igual '7|Ethernet 2|12|AABBCC001122|10.16.250.1|10.16.251.240|10.16.250.50|R1' ([string]$s.Etapa + '|' + $s.Placa.Nome + '|' + $s.Placa.IfIndex + '|' + $s.Placa.Mac + '|' + $s.Gateway + '|' + $s.IpPcCameras + '|' + $s.Fila.Inicio + '|' + $s.Fila.Rack) 'migrada'
        Assert-Verdade (Test-SessaoCompleta $s) 'completa'
        Assert-Verdade (Test-Path $ses) 'sessao.json gravado'
        Assert-Verdade ((Test-Path ($pad + '.migrado')) -and -not (Test-Path $pad) -and -not (Test-Path ($pad + '.bak'))) 'padroes.json renomeado, .bak fora'
        Assert-Verdade ((Test-Path ($ult + '.migrado')) -and -not (Test-Path $ult)) 'ultima-fila.json renomeado'
        Assert-Verdade (($script:Linhas -join "`n") -match 'viraram a sessao.*placa Ethernet 2 reconhecida') 'log'
        # Segunda chamada: sessao.json ja existe, so le (nao reimporta).
        $s2 = Import-SessaoLegada -CaminhoSessao $ses -CaminhoPadroes $pad -CaminhoUltimaFila $ult
        Assert-Igual 'Ethernet 2' $s2.Placa.Nome 'leu a existente'
        # Apagar sessao.json de proposito nao reimporta (os antigos ja sao .migrado).
        Remove-Item $ses -Force
        Assert-Verdade ($null -eq (Import-SessaoLegada -CaminhoSessao $ses -CaminhoPadroes $pad -CaminhoUltimaFila $ult)) 'nao reimporta'
        # NomePlaca vazio ou que nao existe mais: etapa 0, sem placa.
        [IO.File]::WriteAllText($pad, '{"Gateway":"10.0.0.1","NomePlaca":"Sumida"}')
        $s3 = Import-SessaoLegada -CaminhoSessao $ses -CaminhoPadroes $pad
        Assert-Igual '0|10.0.0.1' ([string]$s3.Etapa + '|' + $s3.Gateway) 'placa nao achada = etapa 0'
        Assert-Verdade ($null -eq $s3.Placa -and $null -eq $s3.Fila) 'sem placa nem fila'
        Assert-Falso (Test-SessaoCompleta $s3) 'incompleta'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# ------------------------------------------------------ persistencia

Write-Host ""
Write-Host "Gravacao atomica" -ForegroundColor Cyan

T 'Gravar de novo guarda a versao anterior em .bak' {
    $d = New-Temp
    $arq = Join-Path $d 'registro.json'
    try {
        Assert-Igual '' ([string](Read-JsonArquivo $arq)) 'ausente = nulo'
        Save-JsonAtomico -Caminho $arq -Objeto ([pscustomobject]@{ v = 1 })
        Save-JsonAtomico -Caminho $arq -Objeto ([pscustomobject]@{ v = 2 })
        Assert-Igual 2 (Read-JsonArquivo $arq).v 'atual'
        Assert-Igual 1 ([IO.File]::ReadAllText($arq + '.bak') | ConvertFrom-Json).v 'backup'
        Assert-Falso (Test-Path ($arq + '.tmp')) 'sem .tmp sobrando'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'Arquivo corrompido cai para o .bak; os dois corrompidos estouram' {
    $d = New-Temp
    $arq = Join-Path $d 'registro.json'
    try {
        Save-JsonAtomico -Caminho $arq -Objeto ([pscustomobject]@{ v = 1 })
        Save-JsonAtomico -Caminho $arq -Objeto ([pscustomobject]@{ v = 2 })
        [IO.File]::WriteAllText($arq, '{ quebrado')
        Assert-Igual 1 (Read-JsonArquivo $arq).v 'leu o .bak'
        [IO.File]::WriteAllText($arq + '.bak', 'tambem quebrado')
        Assert-Estoura { Read-JsonArquivo $arq } 'nada legivel'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'Registro com UMA camera volta como lista depois de gravar e ler' {
    $d = New-Temp
    $arq = Join-Path $d 'registro.json'
    try {
        $reg = New-Registro
        Set-CameraRegistro $reg (New-EntradaRegistro -Mac 'aabbcc000001' -Ip '10.0.0.5')
        Save-JsonAtomico -Caminho $arq -Objeto $reg
        Assert-Verdade ([IO.File]::ReadAllText($arq) -match '"Cameras":\s*\[') 'Cameras como array no disco'
        $lido = Read-Registro $arq
        Assert-Igual 1 @($lido.Cameras).Count 'uma camera'
        Assert-Igual '10.0.0.5' (Find-CameraRegistro $lido 'AA:BB:CC:00:00:01').Ip 'achada'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# ------------------------------------------------------ relatorio

Write-Host ""
Write-Host "Relatorio" -ForegroundColor Cyan

T 'Relatorio: 27 colunas, SENHA vazia, MAC formatado, ordem por IP' {
    $reg = New-Registro
    $a = New-EntradaRegistro -Mac 'D8365F0000F4' -Ip '10.70.20.60'
    $a.Status = 'Instalada'; $a.Modelo = 'VIP-1230-D-G3'
    $a.Aplicado = $padroes
    $a.Encoder = Get-ResumoEncode @(ConvertTo-EncodeAjustado -Tabela (Get-Fixture 'encode-vip1230-d-g3.json') -Padroes $padroes)
    $b = New-EntradaRegistro -Mac '98E55B000001' -Ip '10.70.20.9'
    $b.Status = 'Falhou'; $b.Etapa = 'encoder'; $b.Erro = 'recusou'
    # Entrada gravada antes do secundario completo: colunas novas saem vazias.
    $c = New-EntradaRegistro -Mac '98E55B000002' -Ip '10.70.20.10'
    $c.Status = 'Instalada'
    $c.Encoder = [pscustomobject]@{ Resolucao = '1920x1080'; FpsPrincipal = '20'; BitratePrincipal = '1596'; FpsSecundario = '12' }
    Set-CameraRegistro $reg $a
    Set-CameraRegistro $reg $b
    Set-CameraRegistro $reg $c
    $csv = @(ConvertTo-RelatorioCsv $reg | ConvertFrom-Csv -Delimiter ';')
    $nomes = @($csv[0].PSObject.Properties | ForEach-Object { $_.Name })
    Assert-Igual 27 $nomes.Count 'colunas'
    Assert-Igual ((@(Get-ColunasInventario) + @('FIRMWARE', 'SERIAL', 'RESOLUCAO', 'FPS-PRINCIPAL', 'BITRATE-PRINCIPAL',
                  'FPS-SECUNDARIO')) -join ';') (($nomes[0..22]) -join ';') '23 primeiras como antes'
    Assert-Igual (($nomes -join ';')) ((Get-ColunasRelatorio) -join ';') 'cabecalho = Get-ColunasRelatorio'
    Assert-Igual 'H.264|704x480|512|H.264' ($csv[2].'CODEC-PRINCIPAL' + '|' + $csv[2].'RESOLUCAO-SECUNDARIO' + '|' +
                                            $csv[2].'BITRATE-SECUNDARIO' + '|' + $csv[2].'CODEC-SECUNDARIO') 'colunas novas'
    Assert-Igual '|12' ($csv[1].'CODEC-SECUNDARIO' + '|' + $csv[1].'FPS-SECUNDARIO') 'entrada antiga'
    $csv = @($csv[0], $csv[2])
    Assert-Igual '10.70.20.9' $csv[0].IP 'ordem numerica por IP (.9 antes de .60)'
    Assert-Igual 'd8:36:5f:00:00:f4' $csv[1].'MAC-ADRESS' 'MAC'
    Assert-Igual '' $csv[1].SENHA 'senha vazia'
    Assert-Igual '1596' $csv[1].'BITRATE-PRINCIPAL' 'bitrate'
    Assert-Igual '10.70.20.1' $csv[1].GATEWAY 'gateway aplicado'
    Assert-Verdade ($csv[0].STATUS -match 'Falhou em encoder') 'status de falha'
    $vazio = ConvertTo-RelatorioCsv (New-Registro)
    Assert-Verdade ($vazio -match '^"TIPO";') 'registro vazio ainda tem cabecalho'
}

# ------------------------------------------------------ configuracao simulada

Write-Host ""
Write-Host "Configuracao completa (simulacao)" -ForegroundColor Cyan

T 'Simulacao instala e grava a camera como Instalada' {
    $d = New-Temp
    $arq = Join-Path $d 'registro.json'
    try {
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.50'; Mac = 'D8:36:5F:00:00:01'
                                  Local = 'OBRA1'; Rack = 'R1'; Andar = 'T'; Porta = '3'; Canal = '' }
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 'SenhaFicticia@1' -CaminhoRegistro $arq -Simular
        Assert-Verdade $r.Ok ('resultado: ' + $r.Erro)
        $e = Find-CameraRegistro (Read-Registro $arq) 'D8365F000001'
        Assert-Igual 'Instalada|conferida|10.70.20.50|OBRA1|3' ($e.Status + '|' + $e.Etapa + '|' + $e.Ip + '|' + $e.Local + '|' + $e.Porta) 'registro'
        Assert-Igual '1596' $e.Encoder.BitratePrincipal 'encoder no registro'
        Assert-Igual '704x480|512|H.264' ($e.Encoder.ResolucaoSecundario + '|' + $e.Encoder.BitrateSecundario + '|' +
                                          $e.Encoder.CodecSecundario) 'secundario no registro'

        $r2 = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 'x' -CaminhoRegistro $arq -Simular
        Assert-Falso $r2.Ok 'segunda passada'
        Assert-Verdade ($r2.Erro -match 'uma vez so') 'recusa de reconfigurar'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'Falha na rede grava Falhou e a nova tentativa retoma sem reinicializar' {
    $d = New-Temp
    $arq = Join-Path $d 'registro.json'
    try {
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.51'; Mac = '' }
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro $arq -Simular -FalharEm 'rede'
        Assert-Falso $r.Ok 'primeira tentativa'
        Assert-Igual 'rede' $r.Falhou 'etapa da falha'
        Assert-Verdade ($r.Mac.Length -eq 12) 'MAC devolvido para a retomada'
        $e = Find-CameraRegistro (Read-Registro $arq) $r.Mac
        Assert-Igual 'Falhou|encoder' ($e.Status + '|' + $e.Etapa) 'registro apos a falha'

        $ctx.Mac = $r.Mac
        $script:Linhas.Clear()
        $r2 = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro $arq -Simular
        Assert-Verdade $r2.Ok ('retomada: ' + $r2.Erro)
        $log = $script:Linhas -join "`n"
        Assert-Falso ($log -match 'inicializacao de fabrica') 'nao reinicializou'
        Assert-Falso ($log -match 'ajuste de encoder') 'nao refez o encoder'
        Assert-Verdade ($log -match 'retomando depois da etapa encoder') 'avisou a retomada'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'Falha na conferencia: retomada vai direto conferir e devolve o MAC' {
    $d = New-Temp
    $arq = Join-Path $d 'registro.json'
    try {
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.53'; Mac = '' }
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro $arq -Simular -FalharEm 'conferida'
        Assert-Igual 'conferida' $r.Falhou 'etapa da falha'
        $ctx.Mac = $r.Mac
        $script:Linhas.Clear()
        $r2 = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro $arq -Simular
        Assert-Verdade $r2.Ok ('retomada: ' + $r2.Erro)
        Assert-Igual $r.Mac $r2.Mac 'MAC devolvido'
        Assert-Falso (($script:Linhas -join "`n") -match '--- rede ---') 'nao regravou a rede'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'Destino fora da rede do gateway e recusado antes de tocar na camera' {
    $d = New-Temp
    try {
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.9.9.9'; Mac = '' }
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro (Join-Path $d 'r.json') -Simular
        Assert-Falso $r.Ok 'resultado'
        Assert-Verdade ($r.Erro -match 'nao esta na rede') 'motivo'
        Assert-Falso (Test-Path (Join-Path $d 'r.json')) 'registro nem foi criado'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# Test-IpEmUso e Start-Sleep trocados por funcoes locais: valem so dentro do
# bloco (escopo dinamico) e o teste nao espera nem pinga nada.
T 'Espera do boot publica a contagem no mesmo orcamento do limite' {
    $pub = New-Object 'System.Collections.Generic.List[string]'
    Set-MotorProgresso -Sink { param($Etapa, $Detalhe, $Atual, $Total) $pub.Add($Detalhe + '|' + $Atual + '|' + $Total) }
    try {
        function Test-IpEmUso { param($Ip) return $false }
        function Start-Sleep { param($Seconds) }
        Assert-Falso (Wait-CamOnline -Ip '10.70.20.50' -Segundos 15) 'sem resposta'
        Assert-Igual 4 $pub.Count ('publicacoes: ' + ($pub -join ' / '))
        Assert-Verdade ($pub[0] -match '^Esperando 10.70.20\.50 voltar na rede: 0 de 15 s\|0\|15$') $pub[0]
        Assert-Verdade ($pub[3] -match ': 15 de 15 s\|15\|15$') $pub[3]

        $pub.Clear()
        $script:pings = 0
        function Test-IpEmUso { param($Ip) $script:pings++; return ($script:pings -ge 2) }
        Assert-Verdade (Wait-CamOnline -Ip '10.70.20.50' -Segundos 120) 'respondeu no segundo ping'
        Assert-Igual 2 $pub.Count 'parou de contar ao responder'
    } finally { Set-MotorProgresso -Sink $null }
}

T 'Senha nunca aparece no log da configuracao' {
    $d = New-Temp
    try {
        $script:Linhas.Clear()
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.52'; Mac = '' }
        $null = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 'NaoPodeVazar#9' -CaminhoRegistro (Join-Path $d 'r.json') -Simular
        Assert-Falso (($script:Linhas -join "`n") -match 'NaoPodeVazar') 'senha no log'
        Assert-Falso ([IO.File]::ReadAllText((Join-Path $d 'r.json')) -match 'NaoPodeVazar') 'senha no registro'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# Camera ja inicializada com OUTRA senha: o login e recusado. O resultado tem
# que dizer isso (LoginRecusado/Bloqueada) para o painel travar o "Tentar de
# novo" - repetir a senha recusada gasta o lockout da camera. Sem simulacao:
# ping, getStatus e login sao trocados por funcoes locais.
T 'Login recusado na configuracao devolve LoginRecusado e Bloqueada' {
    $d = New-Temp
    try {
        function Test-IpEmUso { param($Ip) return ($Ip -eq '192.168.1.108') }
        function Test-IpLocal { param($Ip) return $false }
        function Get-CamInitStatus { param($Ip, $Timeout) return [pscustomobject]@{ Ok = $true; Init = 0; Find = ''; Bruto = '' } }
        $script:resposta = 'senha'
        function New-CamSessao {
            param($Ip, $Senha, $Usuario, $Timeout)
            return [pscustomobject]@{ Ip = $Ip; Ok = $false; Erro = 'senha recusada pela camera (codigo 268632085)'; SemResposta = $false
                                      SenhaErrada = ($script:resposta -eq 'senha'); Bloqueada = ($script:resposta -eq 'bloqueada'); Session = $null }
        }
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.61'; Mac = '' }
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro (Join-Path $d 'r.json')
        Assert-Falso $r.Ok 'resultado'
        Assert-Igual 'encoder' $r.Falhou 'etapa da falha (login da identidade)'
        Assert-Verdade $r.LoginRecusado 'LoginRecusado'
        Assert-Falso $r.Bloqueada 'Bloqueada com senha errada'
        Assert-Falso $r.Recusa 'nao e recusa de valor'
        Assert-Verdade ($r.Erro -match 'login em 192\.168\.1\.108') $r.Erro

        $script:resposta = 'bloqueada'
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro (Join-Path $d 'r.json')
        Assert-Verdade $r.LoginRecusado 'LoginRecusado com bloqueio'
        Assert-Verdade $r.Bloqueada 'Bloqueada'

        $script:resposta = 'outro'
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro (Join-Path $d 'r.json')
        Assert-Falso $r.LoginRecusado 'login recusado por outro motivo nao trava a senha'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# -------------------------------------------------------- mascara na placa

Write-Host ""
Write-Host "Placa de rede e mascara dos padroes" -ForegroundColor Cyan

T 'Estado da rede do PC: /22 aceita IP local em outro /24; /24 nao' {
    function Get-IpsLocais { return @('192.168.1.220', '10.204.12.201') }
    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.204.13.1' -Mascara '255.255.252.0'
    Assert-Verdade $e.Ok ('/22: ' + ($e.Faltando -join '; '))

    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.204.13.1' -Mascara '255.255.255.0'
    Assert-Falso $e.Ok '/24 nao enxerga 10.204.13.x'
    Assert-Igual '10.204.13.0/24 (conferencia no IP definitivo)' $e.Faltando[0] 'faltando'

    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.204.13.1' -Mascara 'furada'
    Assert-Falso $e.Ok 'mascara furada cai para /24'

    function Get-IpsLocais { return @('10.204.12.201') }
    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.204.13.1' -Mascara '255.255.252.0'
    Assert-Falso $e.Ok 'sem a faixa de fabrica'
    Assert-Verdade ($e.Faltando[0] -match '^192\.168\.1\.x') 'fabrica continua /24'
}

# Get-NetIPAddress trocado por lista fixa com InterfaceIndex: o filtro -IfIndex
# e o que faz "so a placa escolhida conta".
T 'Get-IpsLocais, Get-FaixasDaPlaca e Get-InterfacesBroadcast filtram por -IfIndex; 0 = todas' {
    function Get-NetIPAddress {
        return @([pscustomobject]@{ IPAddress = '10.16.251.207'; PrefixLength = 22; InterfaceIndex = 15 },
                 [pscustomobject]@{ IPAddress = '192.168.1.220'; PrefixLength = 24; InterfaceIndex = 8 },
                 [pscustomobject]@{ IPAddress = '10.70.20.227'; PrefixLength = 24; InterfaceIndex = 8 },
                 [pscustomobject]@{ IPAddress = '100.100.1.5'; PrefixLength = 32; InterfaceIndex = 28 },
                 [pscustomobject]@{ IPAddress = '169.254.3.3'; PrefixLength = 16; InterfaceIndex = 8 },
                 [pscustomobject]@{ IPAddress = '127.0.0.1'; PrefixLength = 8; InterfaceIndex = 1 })
    }
    Assert-Igual '10.16.251.207,192.168.1.220,10.70.20.227,100.100.1.5' (@(Get-IpsLocais) -join ',') 'todas (sem loopback nem APIPA)'
    Assert-Igual '192.168.1.220,10.70.20.227' (@(Get-IpsLocais -IfIndex 8) -join ',') 'so a Ethernet'
    Assert-Igual 0 @(Get-IpsLocais -IfIndex 99).Count 'placa sem IP'
    $f = @(Get-FaixasDaPlaca -IfIndex 8)
    Assert-Igual '192.168.1.220/24/8,10.70.20.227/24/8' (@($f | ForEach-Object { $_.Ip + '/' + $_.Prefixo + '/' + $_.IfIndex }) -join ',') 'faixas da Ethernet com IfIndex'
    Assert-Igual 4 @(Get-FaixasDaPlaca).Count 'todas as faixas'
    Assert-Igual '10.16.251.255' (@(Get-InterfacesBroadcast -IfIndex 15) | ForEach-Object { $_.Broadcast }) 'broadcast so do Wi-Fi'
    Assert-Igual 3 @(Get-InterfacesBroadcast).Count 'todas menos o /32'
    # Alcance: a camera .208 na faixa do Wi-Fi NAO e alcancavel pela Ethernet.
    Assert-Verdade (Test-IpAlcancavel -Ip '10.16.251.208' -Locais @(Get-FaixasDaPlaca)) 'por todas as placas, parece alcancavel'
    Assert-Falso (Test-IpAlcancavel -Ip '10.16.251.208' -Locais @(Get-FaixasDaPlaca -IfIndex 8)) 'pela placa escolhida, nao'
}

T 'Estado da rede so conta a placa escolhida: o IP certo no Wi-Fi nao deixa a placa pronta' {
    function Get-IpsLocais { param([int]$IfIndex = 0) if ($IfIndex -eq 8) { return @('192.168.1.220') }; return @('10.16.251.207', '192.168.1.220') }
    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.16.250.1' -Mascara '255.255.252.0'
    Assert-Verdade $e.Ok 'sem ifIndex: todas as placas (o Wi-Fi conta)'
    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.16.250.1' -Mascara '255.255.252.0' -IfIndex 8
    Assert-Falso $e.Ok 'com a placa escolhida: falta a rede das cameras'
    Assert-Igual '10.16.248.0/22 (conferencia no IP definitivo)' $e.Faltando[0] 'faltando'
    Assert-Igual '192.168.1.220' ($e.Ips -join ',') 'so os IPs da placa'
    Assert-Falso (Test-PreRequisitosRede -IpFabrica '192.168.1.108' -IpDestino '10.16.250.1' -Mascara '255.255.252.0' -IfIndex 8 -Silencioso) 'Test-PreRequisitosRede repassa'
}

T 'Preparar a placa em simulacao: fabrica /24 e conferencia com o prefixo da mascara' {
    function Test-EhAdministrador { return $true }
    function Resolve-PlacaSessao { param($Placa) return [pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'teste'; LinkSpeed = '1 Gbps'; MacAddress = '00-11-22-33-44-55'; ifIndex = 99 } }
    function Get-IpsLocais { return @() }
    function Test-IpEmUso { param($Ip) return $false }
    function Get-IpLocalSugerido { param($Faixa, $MacPlaca) return ($Faixa + '.201') }
    $script:Linhas.Clear()
    $r = Set-RedeLocalCameras -Gateway '10.204.13.1' -Mascara '255.255.252.0' -Simular
    Assert-Verdade $r.Ok 'simulacao devolve Ok'
    Assert-Verdade ($null -eq $r.Sessao) 'simulacao nao tem sessao'
    $log = $script:Linhas -join "`n"
    Assert-Verdade ($log -match 'adicionaria 192\.168\.1\.220/24') 'fabrica /24'
    Assert-Verdade ($log -match 'adicionaria 10\.204\.13\.201/22') ('conferencia /22: ' + $log)

    # Ja tem IP na rede do gateway (em outro /24 da mesma /22): nao adiciona.
    function Get-IpsLocais { return @('192.168.1.220', '10.204.12.7') }
    $script:Linhas.Clear()
    $null = Set-RedeLocalCameras -Gateway '10.204.13.1' -Mascara '255.255.252.0' -Simular
    $log = $script:Linhas -join "`n"
    Assert-Falso ($log -match 'adicionaria') ('nada a adicionar: ' + $log)
    Assert-Verdade ($log -match 'ja ok +10\.204\.13\.x/22') 'reconheceu a rede do gateway'
}

T 'Preparar: "ja ok" so vale na placa escolhida (o mesmo IP no Wi-Fi nao conta)' {
    function Test-EhAdministrador { return $true }
    function Resolve-PlacaSessao { param($Placa) return [pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'teste'; LinkSpeed = '1 Gbps'; MacAddress = '00-11-22-33-44-55'; ifIndex = 8 } }
    function Get-IpsDaPlaca { param($Placa) return @('192.168.1.220') }
    function Get-IpsLocais { param([int]$IfIndex = 0) if ($IfIndex -eq 8) { return @('192.168.1.220') }; return @('10.16.251.207', '192.168.1.220') }
    function Test-IpLocal { param($Ip) return $false }
    function Test-IpEmUso { param($Ip) return $false }
    function Get-IpLocalSugerido { param($Faixa, $MacPlaca, $IfIndex) return ($Faixa + '.201') }
    $script:Linhas.Clear()
    $r = Set-RedeLocalCameras -Gateway '10.16.250.1' -Mascara '255.255.252.0' -Placa @{ Nome = 'Ethernet'; IfIndex = 8 } -Simular
    $log = $script:Linhas -join "`n"
    Assert-Verdade ($log -match 'ja ok +192\.168\.1\.x') 'fabrica ja na placa'
    Assert-Verdade ($log -match 'adicionaria 10.16.250\.201/22') ('rede das cameras: o IP do Wi-Fi nao serve: ' + $log)
    Assert-Verdade ($log -match 'Placa: Ethernet') 'placa resolvida'
}

# ------------------------------------------- IPs do PC na sessao e rastro da placa

Write-Host ""
Write-Host "IPs do PC na sessao, internet e rastro da placa" -ForegroundColor Cyan

T 'Sessao: IPs do PC vazios sao validos; sessao antiga herda vazio' {
    Assert-Igual '|' ($padroes.IpPcFabrica + '|' + $padroes.IpPcCameras) 'fabrica vazio'
    $p = ConvertTo-Sessao ([pscustomobject]@{ Gateway = '10.70.20.1' })
    Assert-Igual '|' ($p.IpPcFabrica + '|' + $p.IpPcCameras) 'antigo sem os campos'
    $p = ConvertTo-SessaoTeste @{ IpPcFabrica = ' 192.168.1.230 '; IpPcCameras = '10.70.20.240' }
    Assert-Igual '192.168.1.230|10.70.20.240' ($p.IpPcFabrica + '|' + $p.IpPcCameras) 'com trim'
    Assert-Igual 0 @(Test-Sessao $p).Count 'validos'
}

T 'Sessao: IP do PC na faixa de fabrica precisa ser do mesmo /24, diferente do IP de fabrica, nem .0/.255' {
    $erro = { param($v) $p = Copy-ObjetoJson $padroes; $p.IpPcFabrica = $v; $c = @(Test-SessaoPorCampo $p); if ($c.Count) { $c[0].campo + ':' + $c[0].msg } else { '' } }
    Assert-Verdade ((& $erro '192.168.2.230') -match '^IpPcFabrica:.*faixa 192\.168\.1\.x') 'outro /24'
    Assert-Verdade ((& $erro '192.168.1.108') -match '^IpPcFabrica:.*pr.prio IP de f.brica') 'igual ao IP de fabrica'
    Assert-Verdade ((& $erro '192.168.1.255') -match '^IpPcFabrica:.*\.255') 'broadcast'
    Assert-Verdade ((& $erro '192.168.1') -match '^IpPcFabrica:.*inv.lido') 'truncado'
    Assert-Igual '' (& $erro '192.168.1.5') 'valido'
}

T 'Sessao: IP do PC na rede das cameras precisa estar na rede do gateway, sem ser gateway, rede ou broadcast' {
    $erro = { param($v) $p = Copy-ObjetoJson $padroes; $p.IpPcCameras = $v; $c = @(Test-SessaoPorCampo $p); if ($c.Count) { $c[0].campo + ':' + $c[0].msg } else { '' } }
    Assert-Verdade ((& $erro '10.70.21.5') -match '^IpPcCameras:.*fora da rede do gateway') 'fora da rede'
    Assert-Verdade ((& $erro '10.70.20.1') -match '^IpPcCameras:.*gateway') 'o gateway'
    Assert-Verdade ((& $erro '10.70.20.0') -match '^IpPcCameras:.*rede ou o broadcast') 'endereco de rede'
    Assert-Verdade ((& $erro '10.70.20.255') -match '^IpPcCameras:.*rede ou o broadcast') 'broadcast'
    Assert-Igual '' (& $erro '10.70.20.240') 'valido'
    # Numa /22 o IP pode estar em outro /24.
    $p = Copy-ObjetoJson $padroes; $p.Mascara = '255.255.252.0'; $p.Gateway = '10.16.248.1'; $p.IpPcCameras = '10.16.251.240'
    Assert-Igual 0 @(Test-Sessao $p).Count '/22 em outro /24'
}

T 'Sessao: IP de fabrica .220 so e proibido com o IP do PC vazio' {
    $p = Copy-ObjetoJson $padroes
    $p.IpFabrica = '192.168.1.220'
    Assert-Verdade ((@(Test-Sessao $p) -join ' ') -match '\.220') 'proibido sem IP do PC'
    $p.IpPcFabrica = '192.168.1.5'
    Assert-Igual 0 @(Test-Sessao $p).Count 'permitido com IP do PC em outro numero'
}

T 'Estado da rede com IP do PC explicito exige o IP exato' {
    function Get-IpsLocais { return @('192.168.1.220', '10.70.20.201') }
    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.70.20.1' -IpPcFabrica '192.168.1.230' -IpPcCameras '10.70.20.240'
    Assert-Falso $e.Ok 'tem a faixa mas nao o IP pedido'
    Assert-Igual 2 @($e.Faltando).Count 'dois faltando'
    Assert-Verdade ($e.Faltando[0] -match '^192\.168\.1\.230 \(IP do PC na faixa de fabrica, da sessao') 'cita o IP e a sessao'
    Assert-Verdade ($e.Faltando[1] -match '^10.70.20\.240 \(IP do PC na rede das cameras') 'idem cameras'
    function Get-IpsLocais { return @('192.168.1.230', '10.70.20.240') }
    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.70.20.1' -IpPcFabrica '192.168.1.230' -IpPcCameras '10.70.20.240'
    Assert-Verdade $e.Ok 'com os IPs exatos'
    $e = Get-EstadoRedePc -IpFabrica '192.168.1.108' -Gateway '10.70.20.1'
    Assert-Verdade $e.Ok 'sem IP explicito, qualquer um da faixa serve'
}

T 'Preparar com IPs da sessao: usa os IPs exatos; recusa IP que ja e de outra placa' {
    function Test-EhAdministrador { return $true }
    function Resolve-PlacaSessao { param($Placa) return [pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'teste'; LinkSpeed = '1 Gbps'; MacAddress = '00-11-22-33-44-55'; ifIndex = 99 } }
    function Get-IpsDaPlaca { param($Placa) return @() }
    function Get-IpsLocais { return @() }
    function Test-IpLocal { param($Ip) return $false }
    function Test-IpEmUso { param($Ip) return $false }
    $script:Linhas.Clear()
    $r = Set-RedeLocalCameras -Gateway '10.70.20.1' -IpPcFabrica '192.168.1.230' -IpDestinoLocal '10.70.20.240' -Simular
    Assert-Verdade $r.Ok 'ok'
    $log = $script:Linhas -join "`n"
    Assert-Verdade ($log -match 'adicionaria 192\.168\.1\.230/24') ('fabrica explicito: ' + $log)
    Assert-Verdade ($log -match 'adicionaria 10.70.20\.240/24') 'cameras explicito'
    Assert-Falso ($log -match 'derivado do MAC') 'nao sorteou'

    # Ja tem OUTRO IP da faixa: com IP explicito nao serve, adiciona o pedido.
    function Get-IpsLocais { return @('192.168.1.220', '10.70.20.201') }
    $script:Linhas.Clear()
    $null = Set-RedeLocalCameras -Gateway '10.70.20.1' -IpPcFabrica '192.168.1.230' -IpDestinoLocal '10.70.20.240' -Simular
    Assert-Verdade (($script:Linhas -join "`n") -match 'adicionaria 192\.168\.1\.230/24') 'faixa presente nao basta'

    # IP pedido ja e do Wi-Fi: aborta antes de mexer.
    function Test-IpLocal { param($Ip) return ($Ip -eq '10.70.20.240') }
    $script:Linhas.Clear()
    $r = Set-RedeLocalCameras -Gateway '10.70.20.1' -IpDestinoLocal '10.70.20.240' -Simular
    Assert-Falso $r.Ok 'abortou'
    Assert-Verdade (($script:Linhas -join "`n") -match 'ABORTADO: 10.70.20\.240 ja e um IP deste PC em outra placa') 'motivo'

    # IP pedido responde ao ping: pulado com dica.
    function Test-IpLocal { param($Ip) return $false }
    function Test-IpEmUso { param($Ip) return ($Ip -eq '192.168.1.230') }
    $script:Linhas.Clear()
    $null = Set-RedeLocalCameras -Gateway '10.70.20.1' -IpPcFabrica '192.168.1.230' -Simular
    Assert-Verdade (($script:Linhas -join "`n") -match 'PULADO +192\.168\.1\.230 responde ao ping.*Troque o IP do PC em Opcoes') 'pulado com dica'
}

# ------------------------------------------------------ placa escolhida

Write-Host ""
Write-Host "Placa escolhida (lista, sugestao, resolucao)" -ForegroundColor Cyan

# Cmdlets de rede trocados por listas fixas: Ethernet com cabo e DHCP, Wi-Fi
# com a rota padrao, Bluetooth PAN (tipo 6, descricao Bluetooth) e um
# adaptador desativado (Get-NetIPInterface estoura).
T 'Get-PlacasFisicas: Ethernet e Wi-Fi, sem Bluetooth; cabo, DHCP, rota padrao e IPs de cada uma' {
    function Get-NetAdapter {
        return @([pscustomobject]@{ Name = 'Ethernet'; InterfaceType = 6; MediaConnectionState = 'Connected'; ifIndex = 8; MacAddress = 'D8-36-5F-00-00-08'; InterfaceDescription = 'Realtek PCIe GbE'; Status = 'Up'; LinkSpeed = '1 Gbps' },
                 [pscustomobject]@{ Name = 'Wi-Fi'; InterfaceType = 71; MediaConnectionState = 'Connected'; ifIndex = 15; MacAddress = 'D8-36-5F-00-00-15'; InterfaceDescription = 'Intel Wi-Fi 6'; Status = 'Up'; LinkSpeed = '300 Mbps' },
                 [pscustomobject]@{ Name = 'Bluetooth'; InterfaceType = 6; MediaConnectionState = 'Disconnected'; ifIndex = 20; MacAddress = ''; InterfaceDescription = 'Bluetooth Device (Personal Area Network)'; Status = 'Disconnected'; LinkSpeed = '3 Mbps' },
                 [pscustomobject]@{ Name = 'Ethernet 2'; InterfaceType = 6; MediaConnectionState = 'Disconnected'; ifIndex = 31; MacAddress = 'D8-36-5F-00-00-31'; InterfaceDescription = 'USB Ethernet'; Status = 'Disabled'; LinkSpeed = '0 bps' })
    }
    function Get-NetIPInterface { param($InterfaceIndex, $AddressFamily) if ($InterfaceIndex -eq 31) { throw 'desativada' }; return [pscustomobject]@{ Dhcp = $(if ($InterfaceIndex -eq 8) { 'Enabled' } else { 'Disabled' }) } }
    function Get-NetIPAddress { param($InterfaceIndex, $AddressFamily)
        if ($InterfaceIndex -eq 8) { return @([pscustomobject]@{ IPAddress = '192.168.1.220'; PrefixLength = 24; PrefixOrigin = 'Manual' }, [pscustomobject]@{ IPAddress = '169.254.9.9'; PrefixLength = 16; PrefixOrigin = 'WellKnown' }) }
        if ($InterfaceIndex -eq 15) { return @([pscustomobject]@{ IPAddress = '10.16.251.207'; PrefixLength = 22; PrefixOrigin = 'Dhcp' }) }
        return @()
    }
    function Get-PlacasComRotaPadrao { return @(15) }
    $p = @(Get-PlacasFisicas)
    Assert-Igual 'Ethernet,Wi-Fi,Ethernet 2' (@($p | ForEach-Object { $_.Nome }) -join ',') 'sem Bluetooth'
    Assert-Igual 'ethernet|8|D8365F000008|True|True|False|192.168.1.220/24' ($p[0].Tipo + '|' + $p[0].IfIndex + '|' + $p[0].Mac + '|' + $p[0].Cabo + '|' + $p[0].Dhcp + '|' + $p[0].RotaPadrao + '|' + (@($p[0].Ips | ForEach-Object { $_.Ip + '/' + $_.Prefixo }) -join ',')) 'Ethernet (sem o APIPA)'
    Assert-Igual 'wifi|15|True|False|True|10.16.251.207/22' ($p[1].Tipo + '|' + $p[1].IfIndex + '|' + $p[1].Cabo + '|' + $p[1].Dhcp + '|' + $p[1].RotaPadrao + '|' + (@($p[1].Ips | ForEach-Object { $_.Ip + '/' + $_.Prefixo }) -join ',')) 'Wi-Fi leva a internet'
    Assert-Igual 'ethernet|31|False|False|0' ($p[2].Tipo + '|' + $p[2].IfIndex + '|' + $p[2].Cabo + '|' + $p[2].Dhcp + '|' + @($p[2].Ips).Count) 'desativada nao estoura'
    Assert-Verdade ($p[0].IfIndex -is [int]) 'ifIndex int'
}

T 'Select-PlacaSugerida: so Ethernet; uma com cabo; varias: a com a faixa de fabrica, senao a sem rota; senao 0' {
    $eth = { param($n, $i, $cabo, $rota, $ips) @{ Nome = $n; IfIndex = $i; Tipo = 'ethernet'; Cabo = $cabo; RotaPadrao = $rota; Ips = @($ips | ForEach-Object { @{ Ip = $_; Prefixo = 24 } }) } }
    $wifi = @{ Nome = 'Wi-Fi'; IfIndex = 15; Tipo = 'wifi'; Cabo = $true; RotaPadrao = $true; Ips = @(@{ Ip = '192.168.1.50'; Prefixo = 24 }) }
    Assert-Igual 0 (Select-PlacaSugerida -Placas @($wifi)) 'so Wi-Fi: nunca sugerida, mesmo com a faixa de fabrica'
    Assert-Igual 8 (Select-PlacaSugerida -Placas @($wifi, (& $eth 'Ethernet' 8 $true $false @()))) 'uma Ethernet com cabo'
    Assert-Igual 8 (Select-PlacaSugerida -Placas @((& $eth 'Ethernet' 8 $false $false @()), $wifi)) 'uma Ethernet sem cabo: ainda e ela'
    $dock = & $eth 'Dock' 1 $true $true @('10.16.251.71'); $usb = & $eth 'USB' 2 $true $false @('10.9.9.9')
    Assert-Igual 2 (Select-PlacaSugerida -Placas @($dock, $usb)) 'duas com cabo: a que nao leva a internet'
    $dock2 = & $eth 'Dock' 1 $true $true @('192.168.1.220')
    Assert-Igual 1 (Select-PlacaSugerida -Placas @($dock2, $usb) -IpFabrica '192.168.1.108') 'duas com cabo: a que ja tem a faixa de fabrica manda'
    $usb2 = & $eth 'USB' 2 $true $true @()
    Assert-Igual 0 (Select-PlacaSugerida -Placas @($dock, $usb2)) 'duas com cabo e rota: nao da para saber'
    Assert-Igual 0 (Select-PlacaSugerida -Placas @((& $eth 'A' 1 $false $false @()), (& $eth 'B' 2 $false $false @()))) 'duas sem cabo: nao da para saber'
    Assert-Igual 0 (Select-PlacaSugerida -Placas @()) 'nenhuma'
}

# Get-NetAdapter trocado por lista fixa: a sessao guarda ifIndex, MAC e nome;
# o Windows renumera placas USB e o MAC e o segundo criterio.
T 'Resolve-PlacaSessao: ifIndex, depois MAC, depois nome; nula com log quando nao existe mais' {
    function Get-NetAdapter {
        return @([pscustomobject]@{ Name = 'Dock'; InterfaceType = 6; ifIndex = 1; MacAddress = 'AA-00-00-00-00-01' },
                 [pscustomobject]@{ Name = 'USB'; InterfaceType = 6; ifIndex = 2; MacAddress = 'AA-00-00-00-00-02' },
                 [pscustomobject]@{ Name = 'Wi-Fi'; InterfaceType = 71; ifIndex = 15; MacAddress = 'AA-00-00-00-00-15' })
    }
    Assert-Igual 'USB' (Resolve-PlacaSessao -Placa @{ Nome = 'Dock'; IfIndex = 2; Mac = 'AA0000000001' }).Name 'ifIndex manda sobre MAC e nome'
    $script:Linhas.Clear()
    Assert-Igual 'Dock' (Resolve-PlacaSessao -Placa @{ Nome = 'USB'; IfIndex = 9; Mac = 'aa:00:00:00:00:01' }).Name 'ifIndex sumiu: MAC manda sobre o nome'
    Assert-Verdade (($script:Linhas -join "`n") -match 'achada por MAC') 'loga o criterio'
    Assert-Igual 'Wi-Fi' (Resolve-PlacaSessao -Placa ([pscustomobject]@{ Nome = 'Wi-Fi'; IfIndex = 0; Mac = '' })).Name 'so o nome (PSCustomObject do JSON)'
    $script:Linhas.Clear()
    Assert-Verdade ($null -eq (Resolve-PlacaSessao -Placa @{ Nome = 'Sumida'; IfIndex = 77; Mac = 'AA0000000077' })) 'nao existe mais'
    Assert-Verdade (($script:Linhas -join "`n") -match 'nao existe mais neste PC.*Dock, USB, Wi-Fi.*Opcoes') 'log vermelho lista as placas'
    Assert-Verdade ($null -eq (Resolve-PlacaSessao -Placa $null)) 'sem placa'
}

# Cmdlets de rede trocados por funcoes locais que so anotam o que seria feito.
T 'Restore-ConexaoPlaca registra na sessao o que devolveu, com a metrica da rota' {
    $script:feitoRede = @()
    function Get-NetIPInterface { return [pscustomobject]@{ Dhcp = 'Disabled' } }
    function Get-NetIPAddress { return @([pscustomobject]@{ IPAddress = '192.168.1.220' }) }
    function Get-NetRoute { return @() }
    function New-NetIPAddress { param($InterfaceIndex, $IPAddress, $PrefixLength) $script:feitoRede += ('ip ' + $IPAddress + '/' + $PrefixLength) }
    function New-NetRoute { param($InterfaceIndex, $DestinationPrefix, $NextHop, $RouteMetric) $script:feitoRede += ('rota ' + $NextHop + ' m' + $RouteMetric) }
    function Set-DnsClientServerAddress { param($InterfaceIndex, $ServerAddresses) $script:feitoRede += ('dns ' + ($ServerAddresses -join ',')) }
    $placa = [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 7 }
    $antes = @{ Dhcp = $true; TemLeaseDhcp = $true; Gateway = '10.16.250.1'; GatewayMetrica = 35; Dns = @('10.0.0.1', '10.0.0.2')
                Enderecos = @(@{ Ip = '10.16.251.207'; Prefixo = 22; Origem = 'Dhcp' }) }
    $sessao = New-SessaoPlaca -Placa $placa -Antes $antes
    $msgs = @(Restore-ConexaoPlaca -Placa $placa -Antes $antes -Feito $sessao)
    Assert-Igual 'ip 10.16.251.207/22|rota 10.16.250.1 m35|dns 10.0.0.1,10.0.0.2' ($script:feitoRede -join '|') 'o que foi feito'
    Assert-Verdade $sessao.Mexida 'Mexida'
    Assert-Igual '10.16.251.207' $sessao.Devolvidos[0].Ip 'devolvido na sessao'
    Assert-Igual '10.16.250.1|35' ($sessao.Rota.NextHop + '|' + $sessao.Rota.Metrica) 'rota na sessao'
    Assert-Igual 2 @($sessao.Dns).Count 'dns na sessao'
    Assert-Verdade ((($msgs | ForEach-Object { $_.Msg }) -join "`n") -match 'volta ao DHCP sozinha') 'avisa que o painel devolve'

    # APIPA (DHCP sem lease): nada a devolver, so marca Mexida.
    $script:feitoRede = @()
    $antes2 = @{ Dhcp = $true; TemLeaseDhcp = $false; Gateway = ''; GatewayMetrica = 0; Dns = @(); Enderecos = @() }
    $s2 = New-SessaoPlaca -Placa $placa -Antes $antes2
    $null = Restore-ConexaoPlaca -Placa $placa -Antes $antes2 -Feito $s2
    Assert-Igual 0 $script:feitoRede.Count 'nada feito'
    Assert-Verdade $s2.Mexida 'Mexida mesmo assim (DHCP vai ser religado)'

    # Placa ja estatica: nao mexe.
    $s3 = New-SessaoPlaca -Placa $placa -Antes @{ Dhcp = $false; TemLeaseDhcp = $false; Enderecos = @() }
    $null = Restore-ConexaoPlaca -Placa $placa -Antes $s3.Antes -Feito $s3
    Assert-Falso $s3.Mexida 'estatica: nao mexida'
}

T 'IPs a remover: com sessao so o que o painel pos, o devolvido e manuais nas faixas; o fixo de antes fica' {
    $end = @(@{ Ip = '192.168.1.220'; Prefixo = 24; Origem = 'Manual' },
             @{ Ip = '10.16.251.207'; Prefixo = 22; Origem = 'Manual' },   # devolvido do DHCP
             @{ Ip = '10.16.251.201'; Prefixo = 22; Origem = 'Manual' },   # posto pelo painel
             @{ Ip = '10.16.249.9';   Prefixo = 22; Origem = 'Manual' },   # fixo do operador, ja estava
             @{ Ip = '10.9.9.9';       Prefixo = 24; Origem = 'Manual' },   # fora das faixas
             @{ Ip = '192.168.0.50';   Prefixo = 24; Origem = 'Manual' })   # temporario da descoberta
    $sessao = @{ Placa = 'Ethernet'; Mexida = $true
                 Antes = @{ Dhcp = $true; TemLeaseDhcp = $true; Enderecos = @(@{ Ip = '10.16.249.9'; Prefixo = 22; Origem = 'Manual' }) }
                 Adicionados = @(@{ Ip = '192.168.1.220'; Prefixo = 24; Para = 'fabrica' }, @{ Ip = '10.16.251.201'; Prefixo = 22; Para = 'cameras' },
                                 @{ Ip = '192.168.0.50'; Prefixo = 24; Para = 'temporario'; Camera = '192.168.0.64' })
                 Devolvidos = @(@{ Ip = '10.16.251.207'; Prefixo = 22 }); Rota = @{ NextHop = '10.16.250.1'; Metrica = 35 } }
    $r = @(Get-IpsARemover -Enderecos $end -Gateway '10.16.248.1' -IpFabrica '192.168.1.108' -Mascara '255.255.252.0' -Sessao $sessao)
    Assert-Igual '192.168.1.220,10.16.251.207,10.16.251.201,192.168.0.50' ($r -join ',') 'com sessao'
    # Placa estatica antes (o .207 era o IP fixo dela): nada foi devolvido e o
    # que ja estava na placa fica, mesmo dentro da rede das cameras.
    $sessao.Antes = @{ Dhcp = $false; TemLeaseDhcp = $false
                       Enderecos = @(@{ Ip = '10.16.251.207'; Prefixo = 22; Origem = 'Manual' }, @{ Ip = '10.16.249.9'; Prefixo = 22; Origem = 'Manual' }) }
    $sessao.Devolvidos = @()
    $r = @(Get-IpsARemover -Enderecos $end -Gateway '10.16.248.1' -IpFabrica '192.168.1.108' -Mascara '255.255.252.0' -Sessao $sessao)
    Assert-Igual '192.168.1.220,10.16.251.201,192.168.0.50' ($r -join ',') 'estatica: o IP fixo fica'
    # Sem sessao: manuais nas duas faixas (pela mascara /22), nada mais.
    $r = @(Get-IpsARemover -Enderecos $end -Gateway '10.16.248.1' -IpFabrica '192.168.1.108' -Mascara '255.255.252.0')
    Assert-Igual '192.168.1.220,10.16.251.207,10.16.251.201,10.16.249.9' ($r -join ',') 'sem sessao'
    # Sem sessao, /24: o .249.9 fica fora.
    $r = @(Get-IpsARemover -Enderecos $end -Gateway '10.16.251.1' -IpFabrica '192.168.1.108')
    Assert-Igual '192.168.1.220,10.16.251.207,10.16.251.201' ($r -join ',') 'sem sessao /24'
}

T 'Reset com sessao: rota pelo NextHop, DHCP so se era DHCP, renovar so com lease' {
    function Test-EhAdministrador { return $true }
    function Resolve-PlacaSessao { param($Placa) return [pscustomobject]@{ Name = $Placa.Nome; ifIndex = 7 } }
    function Get-ConfigIpv4Placa { param($Placa) return @{ Dhcp = $false; TemLeaseDhcp = $false; Gateway = '10.16.250.1'; GatewayMetrica = 256; Dns = @()
                                                           Enderecos = @(@{ Ip = '192.168.1.220'; Prefixo = 24; Origem = 'Manual' }, @{ Ip = '10.16.251.207'; Prefixo = 22; Origem = 'Manual' }) } }
    function Get-NetRoute { return @([pscustomobject]@{ NextHop = '10.16.250.1' }, [pscustomobject]@{ NextHop = '10.0.0.1' }) }
    function Get-IpsLocais { return @() }
    function Start-Sleep { param($Seconds) }
    $script:feitoRede = @()
    function Remove-NetIPAddress { param($InterfaceIndex, $IPAddress) $script:feitoRede += ('rm ' + $IPAddress) }
    function Remove-NetRoute { param($InterfaceIndex, $DestinationPrefix, $NextHop) $script:feitoRede += ('rmrota ' + $NextHop) }
    function Set-NetIPInterface { param($InterfaceIndex, $AddressFamily, $Dhcp) $script:feitoRede += 'dhcp' }
    function Set-DnsClientServerAddress { $script:feitoRede += 'dns' }
    function Invoke-RenovarDhcp { param($Placa) $script:feitoRede += 'renew' }

    $sessao = @{ Placa = 'Ethernet 3'; Antes = @{ Dhcp = $true; TemLeaseDhcp = $true; Enderecos = @() }
                 Adicionados = @(@{ Ip = '192.168.1.220'; Prefixo = 24; Para = 'fabrica' }); Devolvidos = @(@{ Ip = '10.16.251.207'; Prefixo = 22 })
                 Rota = @{ NextHop = '10.16.250.1'; Metrica = 35 } }
    $r = Reset-RedeLocalCameras -Gateway '10.16.248.1' -Mascara '255.255.252.0' -Placa @{ Nome = 'outra'; IfIndex = 9 } -Sessao $sessao
    Assert-Verdade $r.Ok 'ok'
    Assert-Igual 'rm 192.168.1.220|rm 10.16.251.207|rmrota 10.16.250.1|rmrota 10.0.0.1|dhcp|dns|renew' ($script:feitoRede -join '|') 'sequencia'
    Assert-Igual '192.168.1.220,10.16.251.207' ($r.Removidos -join ',') 'removidos'
    Assert-Igual '10.0.0.1' $r.RotaRemovida 'placa que volta ao DHCP perde toda rota estatica (sobra de antes inclusive)'
    Assert-Verdade $r.DhcpReligado 'dhcp religado'
    Assert-Igual 0 @($r.RotasHostRemovidas).Count 'sem rota de host no rastro'
    Assert-Verdade (($script:Linhas | Where-Object { $_ -match 'Placa: Ethernet 3' }).Count -gt 0) 'placa do rastro manda sobre a da sessao'

    # Placa estatica antes (o .207 era o IP fixo dela): nao religa DHCP, nao
    # renova, nao tira rota alheia nem o IP fixo.
    $script:feitoRede = @()
    $sessao.Antes = @{ Dhcp = $false; TemLeaseDhcp = $false; Enderecos = @(@{ Ip = '10.16.251.207'; Prefixo = 22; Origem = 'Manual' }) }
    $sessao.Devolvidos = @(); $sessao.Rota = $null
    $r = Reset-RedeLocalCameras -Gateway '10.16.248.1' -Mascara '255.255.252.0' -Sessao $sessao
    Assert-Igual 'rm 192.168.1.220' ($script:feitoRede -join '|') 'so tira o que pos'
    Assert-Falso $r.DhcpReligado 'estatica: dhcp intacto'
    Assert-Igual '' $r.RotaRemovida 'sem rota removida'

    # APIPA: religa DHCP mas nao renova (sem servidor DHCP).
    $script:feitoRede = @()
    $sessao.Antes = @{ Dhcp = $true; TemLeaseDhcp = $false; Enderecos = @() }
    $null = Reset-RedeLocalCameras -Gateway '10.16.248.1' -Mascara '255.255.252.0' -Sessao $sessao
    Assert-Igual 'rm 192.168.1.220|rm 10.16.251.207|rmrota 10.16.250.1|rmrota 10.0.0.1|dhcp|dns' ($script:feitoRede -join '|') 'sem renew (o .207 manual na rede sai; rotas estaticas saem com o DHCP de volta)'

    # Sem sessao: faixas pela mascara, TODAS as rotas padrao da placa, DHCP e renew.
    $script:feitoRede = @()
    $r = Reset-RedeLocalCameras -Gateway '10.16.248.1' -Mascara '255.255.252.0' -Placa @{ Nome = 'Ethernet'; IfIndex = 7 }
    Assert-Igual 'rm 192.168.1.220|rm 10.16.251.207|rmrota 10.16.250.1|rmrota 10.0.0.1|dhcp|dns|renew' ($script:feitoRede -join '|') 'sem sessao'
    # Sem sessao e sem placa: nada a fazer.
    Assert-Falso (Reset-RedeLocalCameras -Gateway '10.16.248.1').Ok 'sem placa nenhuma'

    # Sessao de fabrica (gateway vazio) ao encerrar: devolve pelo rastro.
    $script:feitoRede = @()
    $sessao.Antes = @{ Dhcp = $true; TemLeaseDhcp = $true; Enderecos = @() }
    $sessao.Devolvidos = @(@{ Ip = '10.16.251.207'; Prefixo = 22 }); $sessao.Rota = @{ NextHop = '10.16.250.1'; Metrica = 35 }
    $f = Get-SessaoFabrica
    $r = Reset-RedeLocalCameras -Gateway $f.Gateway -IpFabrica $f.IpFabrica -Mascara $f.Mascara -Placa $f.Placa -Sessao $sessao
    Assert-Verdade $r.Ok 'gateway vazio devolve'
    Assert-Igual 'rm 192.168.1.220|rm 10.16.251.207|rmrota 10.16.250.1|rmrota 10.0.0.1|dhcp|dns|renew' ($script:feitoRede -join '|') 'gateway vazio: pelo rastro'
}

T 'Reset tira as rotas de host do rastro ANTES dos IPs; sem rastro, varre as /32 on-link NetMgmt da placa' {
    function Test-EhAdministrador { return $true }
    function Resolve-PlacaSessao { param($Placa) return [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 8 } }
    function Get-ConfigIpv4Placa { param($Placa) return @{ Dhcp = $false; TemLeaseDhcp = $false; Gateway = ''; GatewayMetrica = 0; Dns = @()
                                                           Enderecos = @(@{ Ip = '10.16.251.254'; Prefixo = 32; Origem = 'Manual' }) } }
    function Get-NetRoute { param($InterfaceIndex, $DestinationPrefix, $AddressFamily)
        if ($DestinationPrefix) { return @() }
        return @([pscustomobject]@{ DestinationPrefix = '10.16.251.208/32'; NextHop = '0.0.0.0'; Protocol = 'NetMgmt' },
                 [pscustomobject]@{ DestinationPrefix = '10.16.251.254/32'; NextHop = '0.0.0.0'; Protocol = 'Local' },
                 [pscustomobject]@{ DestinationPrefix = '10.0.0.0/8'; NextHop = '0.0.0.0'; Protocol = 'NetMgmt' })
    }
    function Get-IpsLocais { return @() }
    function Start-Sleep { param($Seconds) }
    $script:feitoRede = @()
    function Remove-NetIPAddress { param($InterfaceIndex, $IPAddress) $script:feitoRede += ('rm ' + $IPAddress) }
    function Remove-NetRoute { param($InterfaceIndex, $DestinationPrefix, $NextHop) $script:feitoRede += ('rmrota ' + $DestinationPrefix + ' via ' + $NextHop) }
    function Set-NetIPInterface { $script:feitoRede += 'dhcp' }
    function Set-DnsClientServerAddress { $script:feitoRede += 'dns' }
    function Invoke-RenovarDhcp { $script:feitoRede += 'renew' }
    $sessao = @{ Placa = 'Ethernet'; IfIndex = 8; Antes = @{ Dhcp = $true; TemLeaseDhcp = $true; Enderecos = @() }
                 Adicionados = @(@{ Ip = '10.16.251.254'; Prefixo = 32; Para = 'temporario'; Camera = '10.16.251.208' })
                 Rotas = @(@{ Destino = '10.16.251.208/32'; NextHop = '0.0.0.0'; Para = 'temporario'; Camera = '10.16.251.208' })
                 Devolvidos = @(); Rota = $null; Dns = @() }
    $r = Reset-RedeLocalCameras -Gateway '10.16.248.1' -Mascara '255.255.252.0' -Sessao $sessao
    Assert-Igual 'rmrota 10.16.251.208/32 via 0.0.0.0|rm 10.16.251.254|dhcp|dns|renew' ($script:feitoRede -join '|') 'rota antes do IP'
    Assert-Igual '10.16.251.208/32' ($r.RotasHostRemovidas -join ',') 'RotasHostRemovidas'
    # Rastro antigo (1.1.1) sem Rotas e lido do disco: nada estoura.
    $script:feitoRede = @()
    $d = New-Temp
    try {
        $sessao.Remove('Rotas')
        Save-JsonAtomico -Caminho (Join-Path $d 's.json') -Objeto $sessao
        $r = Reset-RedeLocalCameras -Gateway '10.16.248.1' -Mascara '255.255.252.0' -Sessao (Read-JsonArquivo (Join-Path $d 's.json'))
        Assert-Igual 'rm 10.16.251.254|dhcp|dns|renew' ($script:feitoRede -join '|') 'sem Rotas no rastro'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    # Sem rastro: so a /32 on-link criada por NetMgmt sai (a Local e do proprio
    # IP; a /8 nao e de host); o .254 manual sai por estar na rede das cameras.
    $script:feitoRede = @()
    $r = Reset-RedeLocalCameras -Gateway '10.16.248.1' -Mascara '255.255.252.0' -Placa @{ Nome = 'Ethernet'; IfIndex = 8 }
    Assert-Igual 'rmrota 10.16.251.208/32 via 0.0.0.0|rm 10.16.251.254|dhcp|dns|renew' ($script:feitoRede -join '|') 'varredura sem rastro'
    Assert-Igual '10.16.251.208/32' ($r.RotasHostRemovidas -join ',') 'so a NetMgmt'
}

T 'Merge de sessoes: foto da primeira, IPs somados sem repetir, devolvidos de quem devolveu' {
    $a = @{ Quando = 'ontem'; Placa = 'Ethernet'; IfIndex = 7; Antes = @{ Dhcp = $true }; Mexida = $true
            Adicionados = @(@{ Ip = '192.168.1.220'; Prefixo = 24; Para = 'fabrica' }); Devolvidos = @(@{ Ip = '10.16.251.207'; Prefixo = 22 })
            Rota = @{ NextHop = '10.16.250.1'; Metrica = 35 }; Dns = @('8.8.8.8') }
    $b = @{ Quando = 'hoje'; Placa = 'Ethernet'; IfIndex = 7; Antes = @{ Dhcp = $false }; Mexida = $false
            Adicionados = @(@{ Ip = '192.168.1.220'; Prefixo = 24; Para = 'fabrica' }, @{ Ip = '192.168.0.50'; Prefixo = 24; Para = 'temporario'; Camera = '192.168.0.64' })
            Devolvidos = @(); Rota = $null; Dns = @() }
    $m = Merge-SessaoPlaca -Antiga $a -Nova $b
    Assert-Igual 'ontem|True|True' ($m.Quando + '|' + $m.Antes.Dhcp + '|' + $m.Mexida) 'foto e Mexida da primeira'
    Assert-Igual '192.168.1.220,192.168.0.50' (@($m.Adicionados | ForEach-Object { $_.Ip }) -join ',') 'sem repetir'
    Assert-Igual '192.168.0.64' @($m.Adicionados)[1].Camera 'camera do temporario'
    Assert-Igual '10.16.251.207|10.16.250.1|35|8.8.8.8' ($m.Devolvidos[0].Ip + '|' + $m.Rota.NextHop + '|' + $m.Rota.Metrica + '|' + ($m.Dns -join ',')) 'devolvidos da primeira'
    Assert-Igual 'hoje' (Merge-SessaoPlaca -Antiga $null -Nova $b).Quando 'sem antiga'
    Assert-Igual 'ontem' (Merge-SessaoPlaca -Antiga $a -Nova $null).Quando 'sem nova'
    $c = @{ Quando = 'hoje'; Placa = 'USB'; Adicionados = @(); Devolvidos = @(); Dns = @() }
    Assert-Igual 'USB' (Merge-SessaoPlaca -Antiga $a -Nova $c).Placa 'outra placa: a nova manda'
    # Rotas de host: somam sem repetir; rastro antigo sem Rotas nao estoura.
    $b.Rotas = @(@{ Destino = '10.16.251.208/32'; NextHop = '0.0.0.0'; Para = 'temporario'; Camera = '10.16.251.208' })
    Assert-Igual '10.16.251.208/32' (@((Merge-SessaoPlaca -Antiga $a -Nova $b).Rotas | ForEach-Object { $_.Destino }) -join ',') 'rota da nova'
    $a.Rotas = @(@{ Destino = '10.16.251.208/32'; NextHop = '0.0.0.0' }, @{ Destino = '10.1.1.1/32'; NextHop = '0.0.0.0' })
    Assert-Igual '10.16.251.208/32,10.1.1.1/32' (@((Merge-SessaoPlaca -Antiga $a -Nova $b).Rotas | ForEach-Object { $_.Destino }) -join ',') 'sem repetir'
    # Sobrevive ao disco (PSCustomObject do JSON).
    $d = New-Temp
    try {
        Save-JsonAtomico -Caminho (Join-Path $d 's.json') -Objeto $m
        $lido = Read-JsonArquivo (Join-Path $d 's.json')
        $m2 = Merge-SessaoPlaca -Antiga $lido -Nova $b
        Assert-Igual 2 @($m2.Adicionados).Count 'merge com o lido do disco'
        Assert-Igual 35 $m2.Rota.Metrica 'rota preservada'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# ------------------------------------------------ descoberta DHIP no motor

Write-Host ""
Write-Host "Descoberta DHIP: orquestracao, IP temporario, porta HTTP" -ForegroundColor Cyan

T 'Configuracao simulada com origem 192.168.0.64:8081 registra a porta para a origem e o destino' {
    $d = New-Temp
    try {
        $script:PortasHttp = $null
        $script:Linhas.Clear()
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.0.64'; Destino = '10.70.20.70'; Mac = ''; HttpPort = 8081 }
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro (Join-Path $d 'r.json') -Simular
        Assert-Verdade $r.Ok ('resultado: ' + $r.Erro)
        Assert-Igual 8081 (Get-CamPortaHttp '192.168.0.64') 'origem'
        Assert-Igual 8081 (Get-CamPortaHttp '10.70.20.70') 'destino (a camera leva a porta junto)'
        Assert-Verdade (($script:Linhas -join "`n") -match '=== camera em 192\.168\.0\.64:8081 -> 10.70.20\.70') 'log cita a porta'
        # Sem HttpPort no contexto: nada registrado.
        $ctx2 = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.71'; Mac = '' }
        $null = Invoke-ConfiguracaoCamera -Contexto $ctx2 -Padroes $padroes -Senha 's' -CaminhoRegistro (Join-Path $d 'r.json') -Simular
        Assert-Igual 80 (Get-CamPortaHttp '10.70.20.71') 'sem porta = 80'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; $script:PortasHttp = $null }
}

T 'Add-IpTemporarioPlaca -Simular escolhe o .220 da rede da camera e nao toca a placa' {
    function Get-IpsLocais { return @('10.16.251.207') }
    function Get-FaixasDaPlaca { return @(@{ Ip = '10.16.251.207'; Prefixo = 22; IfIndex = 15 }) }
    function Test-EhAdministrador { return $false }   # em simulacao nao importa
    $script:Linhas.Clear()
    $r = Add-IpTemporarioPlaca -IpCamera '192.168.0.64' -Mascara '255.255.255.0' -GatewayCamera '192.168.0.1' -Simular
    Assert-Verdade $r.Ok 'ok'
    Assert-Igual '192.168.0.220' $r.Ip 'o .220 da rede da camera'
    Assert-Verdade ($null -eq $r.Sessao) 'sem sessao em simulacao'
    Assert-Verdade (($script:Linhas -join "`n") -match 'adicionaria 192\.168\.0\.220/24 \(temporario, camera em 192\.168\.0\.64\)') 'log'
    Assert-Falso (($script:Linhas -join "`n") -match 'rota de host') 'camera fora de qualquer faixa do PC: sem rota'
    # Camera na faixa de OUTRA placa (o Wi-Fi): tambem a rota de host.
    $script:Linhas.Clear()
    $r = Add-IpTemporarioPlaca -IpCamera '10.16.251.208' -Mascara '255.255.252.0' -GatewayCamera '10.16.250.1' -Simular
    Assert-Verdade ($r.Ok -and $r.Ip -ne '10.16.251.207') ('ip: ' + $r.Ip)
    Assert-Verdade (($script:Linhas -join "`n") -match 'adicionaria a rota de host 10.16.251\.208/32') 'avisa a rota'
    # Camera no .220: pega outro.
    $r = Add-IpTemporarioPlaca -IpCamera '192.168.0.220' -Simular
    Assert-Verdade ($r.Ip -match '^192\.168\.0\.2[0-4]\d$' -and $r.Ip -ne '192.168.0.220') ('outro da faixa: ' + $r.Ip)
    # IP invalido.
    Assert-Falso (Add-IpTemporarioPlaca -IpCamera 'lixo' -Simular).Ok 'invalido'
}

# Cmdlets trocados por funcoes locais que so anotam: a camera .208 esta na
# faixa do Wi-Fi (ifIndex 15) e a placa escolhida e a Ethernet (8). E o caso
# da bancada de 01/10/2026.
T 'Add-IpTemporarioPlaca real: IP temporario + rota de host /32 na placa escolhida, os dois no rastro' {
    function Test-EhAdministrador { return $true }
    function Resolve-PlacaSessao { param($Placa) return [pscustomobject]@{ Name = 'Ethernet'; ifIndex = 8; MacAddress = 'D8-36-5F-00-00-08' } }
    function Get-IpsLocais { return @('10.16.251.207', '192.168.1.220') }
    function Get-FaixasDaPlaca { param([int]$IfIndex = 0) $t = @(@{ Ip = '10.16.251.207'; Prefixo = 22; IfIndex = 15 }, @{ Ip = '192.168.1.220'; Prefixo = 24; IfIndex = 8 }); if ($IfIndex -gt 0) { return @($t | Where-Object { $_.IfIndex -eq $IfIndex }) }; return $t }
    function Test-IpEmUso { param($Ip) return $false }
    function Get-ConfigIpv4Placa { param($Placa) return @{ Dhcp = $false; TemLeaseDhcp = $false; Enderecos = @(); Gateway = ''; GatewayMetrica = 0; Dns = @() } }
    function Start-Sleep { param($Seconds) }
    $script:feitoRede = @()
    function New-NetIPAddress { param($InterfaceIndex, $IPAddress, $PrefixLength) $script:feitoRede += ('ip ' + $IPAddress + '/' + $PrefixLength + ' if' + $InterfaceIndex) }
    function New-NetRoute { param($InterfaceIndex, $DestinationPrefix, $NextHop, $RouteMetric, $PolicyStore) $script:feitoRede += ('rota ' + $DestinationPrefix + ' via ' + $NextHop + ' m' + $RouteMetric + ' ' + $PolicyStore + ' if' + $InterfaceIndex) }
    $script:Linhas.Clear()
    $r = Add-IpTemporarioPlaca -IpCamera '10.16.251.208' -Mascara '255.255.252.0' -GatewayCamera '10.16.250.1' -Placa @{ Nome = 'Ethernet'; IfIndex = 8 }
    Assert-Verdade $r.Ok 'ok'
    Assert-Verdade ($r.Ip -match '^10.16.251\.2[0-4]\d$' -and $r.Ip -ne '10.16.251.207') ('IP temporario na rede da camera: ' + $r.Ip)
    Assert-Igual ('ip ' + $r.Ip + '/22 if8|rota 10.16.251.208/32 via 0.0.0.0 m1 ActiveStore if8') ($script:feitoRede -join '|') 'IP e depois a rota, na Ethernet'
    Assert-Igual ($r.Ip + '|temporario|10.16.251.208') ($r.Sessao.Adicionados[0].Ip + '|' + $r.Sessao.Adicionados[0].Para + '|' + $r.Sessao.Adicionados[0].Camera) 'IP no rastro'
    Assert-Igual '10.16.251.208/32|0.0.0.0|temporario|10.16.251.208' ($r.Sessao.Rotas[0].Destino + '|' + $r.Sessao.Rotas[0].NextHop + '|' + $r.Sessao.Rotas[0].Para + '|' + $r.Sessao.Rotas[0].Camera) 'rota no rastro'
    Assert-Verdade (($script:Linhas -join "`n") -match 'ADICIONADA rota de host 10.16.251\.208/32 on-link') 'log'
    # Rota que ja existia: conta como feita e entra no rastro.
    $script:feitoRede = @()
    function New-NetRoute { throw 'Instance MSFT_NetRoute already exists' }
    $r = Add-IpTemporarioPlaca -IpCamera '10.16.251.208' -Mascara '255.255.252.0' -Placa @{ Nome = 'Ethernet'; IfIndex = 8 }
    Assert-Verdade ($r.Ok -and @($r.Sessao.Rotas).Count -eq 1) 'ja existia = ok'
    # Camera fora de qualquer faixa do PC: so o IP, sem rota.
    $script:feitoRede = @()
    $r = Add-IpTemporarioPlaca -IpCamera '192.168.0.64' -Placa @{ Nome = 'Ethernet'; IfIndex = 8 }
    Assert-Igual 'ip 192.168.0.220/24 if8' ($script:feitoRede -join '|') 'sem rota'
    Assert-Igual 0 @($r.Sessao.Rotas).Count 'rastro sem rota'
}

# Rede trocada por funcoes locais: o broadcast "responde" duas cameras, uma de
# fabrica fora das faixas do PC (porta 8081) e uma inicializada alcancavel.
T 'Find-CamerasNaRede: broadcast acha a camera de fabrica, confirma por HTTP so a alcancavel e dispensa a varredura' {
    $script:PortasHttp = $null
    function Get-FaixasDaPlaca { return @(@{ Ip = '10.16.251.207'; Prefixo = 22 }) }
    function Get-IpsLocais { return @('10.16.251.207') }
    function Invoke-DescobertaDhip { param($Segundos)
        return @(
            (ConvertFrom-RespostaDhip -Json '{"mac":"aa:bb:cc:00:00:64","method":"client.notifyDevInfo","params":{"deviceInfo":{"DeviceClass":"IPC","DeviceType":"VIP-1230-B-G2","HttpPort":8081,"IPv4Address":{"DefaultGateway":"192.168.0.1","IPAddress":"192.168.0.64","SubnetMask":"255.255.255.0"},"SerialNo":"S64","Version":"2.8","Init":1}}}'),
            # Alcancavel e o broadcast diz "de fabrica" (bit 1): vai ao HTTP, que diz inicializada (Init=2). O HTTP manda.
            (ConvertFrom-RespostaDhip -Json '{"mac":"d8:36:5f:00:00:e3","method":"client.notifyDevInfo","params":{"deviceInfo":{"DeviceClass":"IPC","DeviceType":"VIP-1230-B-G2","HttpPort":80,"IPv4Address":{"DefaultGateway":"10.16.250.1","IPAddress":"10.16.250.51","SubnetMask":"255.255.255.0"},"SerialNo":"S51","Version":"2.8","Init":3209}}}'),
            (ConvertFrom-RespostaDhip -Json '{"mac":"d8:36:5f:00:00:e3","method":"client.notifyDevInfo","params":{"deviceInfo":{"DeviceClass":"IPC","DeviceType":"VIP-1230-B-G2","HttpPort":80,"IPv4Address":{"IPAddress":"10.16.250.51"},"Init":3209}}}'),
            # Alcancavel e ja inicializada pelo broadcast: nao vai ao HTTP.
            (ConvertFrom-RespostaDhip -Json '{"mac":"30:e1:f1:00:00:65","method":"client.notifyDevInfo","params":{"deviceInfo":{"DeviceClass":"IPC","DeviceType":"VIP-1230-D-G4","HttpPort":80,"IPv4Address":{"IPAddress":"10.16.250.102"},"Init":3210}}}')
        )
    }
    $script:probados = @()
    function Invoke-ProbeInitLote { param($Ips, $TimeoutSegProbe, $Paralelo, $Portas)
        $script:probados += $Ips
        $h = @{}; foreach ($ip in $Ips) { $h[$ip] = Read-RespostaInit '{"id":1,"params":{"Find":"BC","Init":2},"result":true}' }
        return $h
    }
    function Invoke-PingSweep { param($Ips, $TimeoutMs) return @() }
    function Get-VizinhosMac { param($Ips) return @{} }
    $script:Linhas.Clear()
    $a = @(Find-CamerasNaRede -IpFabrica '192.168.1.108' -GatewayDestino '10.70.20.1')
    Assert-Igual 3 $a.Count 'tres aparelhos (a repetida sai)'
    $fab = @($a | Where-Object { $_.Virgem })
    Assert-Igual 1 $fab.Count 'uma de fabrica (a .51 o HTTP desmentiu)'
    Assert-Igual '192.168.0.64|False|False|8081|VIP-1230-B-G2|255.255.255.0|192.168.0.1|broadcast DHIP' ($fab[0].Ip + '|' + $fab[0].Confirmado + '|' + $fab[0].Alcancavel + '|' + $fab[0].HttpPort + '|' + $fab[0].Modelo + '|' + $fab[0].Mascara + '|' + $fab[0].Gateway + '|' + $fab[0].Como) 'fora das faixas: nao confirmada'
    $ini = @($a | Where-Object { $_.Ip -eq '10.16.250.51' })[0]
    Assert-Igual 'True|True|2|D8365F0000E3' ([string]$ini.Confirmado + '|' + $ini.Alcancavel + '|' + $ini.Init + '|' + $ini.Mac) 'alcancavel com bit de fabrica: o HTTP manda (Init=2)'
    $ja = @($a | Where-Object { $_.Ip -eq '10.16.250.102' })[0]
    Assert-Igual 'False|True|2' ([string]$ja.Confirmado + '|' + $ja.Alcancavel + '|' + $ja.Init) 'ja inicializada pelo broadcast: nao vai ao HTTP'
    Assert-Igual '10.16.250.51' ($script:probados -join ',') 'so a alcancavel com bit de fabrica foi ao HTTP'
    Assert-Igual 8081 (Get-CamPortaHttp '192.168.0.64') 'porta registrada'
    $log = $script:Linhas -join "`n"
    Assert-Falso ($log -match 'varrendo|pingados') 'sem varredura'
    Assert-Verdade ($log -match '192\.168\.0\.64:8081 +VIP-1230-B-G2 +DE FABRICA \(fora das faixas do PC\)') ('log: ' + $log)
    # Atalho no IP de fabrica nao roda quando ja ha camera de fabrica? Roda (ping), mas aqui nada responde.
    $script:PortasHttp = $null
}

T 'Find-CamerasNaRede: sem resposta ao broadcast cai no atalho e na varredura; -SemVarredura para antes' {
    function Get-FaixasDaPlaca { return @(@{ Ip = '192.168.1.220'; Prefixo = 24 }) }
    function Get-IpsLocais { return @('192.168.1.220') }
    function Invoke-DescobertaDhip { param($Segundos) return @() }
    function Invoke-ProbeInitLote { param($Ips, $TimeoutSegProbe, $Paralelo, $Portas) return @{} }
    $script:pingados = 0
    function Invoke-PingSweep { param($Ips, $TimeoutMs) $script:pingados += @($Ips).Count; return @() }
    function Get-VizinhosMac { param($Ips) return @{} }
    $script:Linhas.Clear()
    $a = @(Find-CamerasNaRede -IpFabrica '192.168.1.108' -GatewayDestino '10.70.20.1')
    Assert-Igual 0 $a.Count 'nada'
    $log = $script:Linhas -join "`n"
    Assert-Verdade ($log -match '0 resposta\(s\).*firewall') 'avisa do firewall'
    Assert-Verdade ($log -match 'procurando no IP de fabrica') 'atalho rodou'
    Assert-Verdade ($log -match 'varrendo por ping') 'varreu'
    Assert-Verdade ($script:pingados -gt 254) ('pingou as faixas: ' + $script:pingados)

    $script:pingados = 0
    $script:Linhas.Clear()
    $a = @(Find-CamerasNaRede -IpFabrica '192.168.1.108' -GatewayDestino '10.70.20.1' -SemVarredura)
    Assert-Igual 1 $script:pingados 'so o atalho pingou'
    Assert-Verdade (($script:Linhas -join "`n") -match 'sem varredura') 'parou antes'
}

T 'Find-CamerasNaRede -IfIndex: faixas e broadcast so pela placa escolhida; a camera na faixa do Wi-Fi fica "fora das faixas"' {
    $script:PortasHttp = $null
    $script:pedidos = @()
    function Get-FaixasDaPlaca { param([int]$IfIndex = 0) $script:pedidos += ('faixas ' + $IfIndex); if ($IfIndex -eq 8) { return @(@{ Ip = '192.168.1.220'; Prefixo = 24; IfIndex = 8 }) }; return @(@{ Ip = '10.16.251.207'; Prefixo = 22; IfIndex = 15 }, @{ Ip = '192.168.1.220'; Prefixo = 24; IfIndex = 8 }) }
    function Get-IpsLocais { return @('10.16.251.207', '192.168.1.220') }
    function Invoke-DescobertaDhip { param($Segundos, $Interfaces, $IfIndex) $script:pedidos += ('dhip ' + $IfIndex)
        return @((ConvertFrom-RespostaDhip -Json '{"mac":"d8:36:5f:00:00:f4","method":"client.notifyDevInfo","params":{"deviceInfo":{"DeviceClass":"IPC","DeviceType":"VIP-1230-D-G4","HttpPort":80,"IPv4Address":{"DefaultGateway":"10.16.250.1","IPAddress":"10.16.251.208","SubnetMask":"255.255.252.0"},"Init":1}}}')) }
    function Invoke-ProbeInitLote { param($Ips, $TimeoutSegProbe, $Paralelo, $Portas) $script:pedidos += ('probe ' + ($Ips -join ',')); $h = @{}; foreach ($ip in $Ips) { $h[$ip] = Read-RespostaInit '{"id":1,"params":{"Find":"BC","Init":1},"result":true}' }; return $h }
    function Invoke-PingSweep { param($Ips, $TimeoutMs) return @() }
    function Get-VizinhosMac { param($Ips) return @{} }
    $a = @(Find-CamerasNaRede -IpFabrica '192.168.1.108' -GatewayDestino '10.16.250.1' -IfIndex 8 -Silencioso)
    Assert-Igual 'faixas 8|dhip 8' ($script:pedidos -join '|') 'tudo pela placa 8; nada foi ao HTTP (nao alcancavel)'
    Assert-Igual 'True|False|False' ([string]$a[0].Virgem + '|' + $a[0].Alcancavel + '|' + $a[0].Confirmado) 'de fabrica pelo broadcast, fora das faixas da placa escolhida'
    # Sem -IfIndex (0): todas as placas, e a camera "parece" alcancavel pelo Wi-Fi.
    $script:pedidos = @()
    $a = @(Find-CamerasNaRede -IpFabrica '192.168.1.108' -GatewayDestino '10.16.250.1' -Silencioso)
    Assert-Igual 'faixas 0|dhip 0|probe 10.16.251.208' ($script:pedidos -join '|') 'ifIndex 0 = todas'
    Assert-Verdade ($a[0].Alcancavel) 'alcancavel por todas as placas'
    $script:PortasHttp = $null
}

# ------------------------------------------------------------- versao

Write-Host ""
Write-Host "Versao do painel" -ForegroundColor Cyan

T 'VERSAO.txt do repo e uma versao valida e Get-VersaoPainel a le' {
    $v = Get-VersaoPainel -Pasta $raiz
    Assert-Verdade ($null -ne (ConvertTo-VersaoPainel $v)) ('versao: ' + $v)
    Assert-Verdade ($v -match '^\d+\.\d+\.\d+$') 'tres numeros'
    Assert-Igual '0.0.0' (Get-VersaoPainel -Pasta (Join-Path $env:TEMP 'nao-existe-mesmo-9')) 'sem arquivo'
    $d = New-Temp
    try {
        $null = New-Item -ItemType Directory -Force -Path $d
        [IO.File]::WriteAllText((Join-Path $d 'VERSAO.txt'), "  2.0.1`r`n")
        Assert-Igual '2.0.1' (Get-VersaoPainel -Pasta $d) 'com espaco e quebra'
        [IO.File]::WriteAllText((Join-Path $d 'VERSAO.txt'), 'lixo')
        Assert-Igual '0.0.0' (Get-VersaoPainel -Pasta $d) 'conteudo invalido'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'ConvertTo-VersaoPainel e Compare-Versao' {
    Assert-Igual '1.2.3' ([string](ConvertTo-VersaoPainel 'v1.2.3')) 'com v'
    Assert-Igual '1.2.3.4' ([string](ConvertTo-VersaoPainel '1.2.3.4')) 'quatro numeros'
    Assert-Verdade ($null -eq (ConvertTo-VersaoPainel '1')) 'um numero so'
    Assert-Verdade ($null -eq (ConvertTo-VersaoPainel '1.2.3-beta')) 'sufixo'
    Assert-Verdade ($null -eq (ConvertTo-VersaoPainel '')) 'vazio'
    Assert-Igual -1 (Compare-Versao '1.1.0' '1.2.0') 'menor'
    Assert-Igual 1 (Compare-Versao 'v1.10.0' '1.9.9') 'numerico, nao alfabetico'
    Assert-Igual 0 (Compare-Versao '1.1.0' 'v1.1.0') 'igual com v'
    Assert-Igual 1 (Compare-Versao '1.1.0' 'lixo') 'invalido conta como 0.0'
    Assert-Igual -1 (Compare-Versao '1.1' '1.1.0') '1.1 < 1.1.0 (como [version])'
}

# ------------------------------------------------- atualizacao pelo GitHub

Write-Host ""
Write-Host "Atualizacao pelo GitHub Releases" -ForegroundColor Cyan

T 'ConvertFrom-ReleaseGitHub le o release: versao da tag, asset do instalador, sha256, tamanho, notas' {
    $json = [IO.File]::ReadAllText((Join-Path $fix 'release-github.json'), [Text.Encoding]::UTF8)
    $r = ConvertFrom-ReleaseGitHub -Json $json
    Assert-Verdade ($null -ne $r) 'leu'
    Assert-Igual '1.2.0|v1.2.0|2009198' ($r.Versao + '|' + $r.Tag + '|' + $r.Tamanho) 'versao e tamanho'
    Assert-Igual 'https://github.com/xyron-robotics/ConfigurarCameras/releases/download/v1.2.0/ConfigurarCameras-1.2.0-instalador.exe' $r.Url 'url do exe'
    Assert-Verdade ($r.Sha256Url -match '\.exe\.sha256$') 'url do sha256'
    Assert-Verdade ($r.Notas -match 'O que mudou') 'notas'
    Assert-Igual '2026-10-15T12:05:00Z' $r.Publicado 'publicado'
    Assert-Verdade ($r.Pagina -match '/releases/tag/v1\.2\.0$') 'pagina'
    Assert-Igual 1 (Compare-Versao $r.Versao '1.1.0') 'mais nova que a 1.1.0'
}

T 'ConvertFrom-ReleaseGitHub devolve nulo sem o asset do instalador, em rascunho, erro da API e lixo' {
    $json = [IO.File]::ReadAllText((Join-Path $fix 'release-github.json'), [Text.Encoding]::UTF8)
    $o = $json | ConvertFrom-Json
    $o.assets = @($o.assets | Where-Object { $_.name -notlike '*.exe' })
    Assert-Verdade ($null -eq (ConvertFrom-ReleaseGitHub -Json ($o | ConvertTo-Json -Depth 10))) 'sem exe'
    $o = $json | ConvertFrom-Json; $o.draft = $true
    Assert-Verdade ($null -eq (ConvertFrom-ReleaseGitHub -Json ($o | ConvertTo-Json -Depth 10))) 'rascunho'
    $o = $json | ConvertFrom-Json; $o.tag_name = 'latest'
    Assert-Verdade ($null -eq (ConvertFrom-ReleaseGitHub -Json ($o | ConvertTo-Json -Depth 10))) 'tag sem versao'
    $o = $json | ConvertFrom-Json; $o.assets = @()
    Assert-Verdade ($null -eq (ConvertFrom-ReleaseGitHub -Json ($o | ConvertTo-Json -Depth 10))) 'sem assets'
    Assert-Verdade ($null -eq (ConvertFrom-ReleaseGitHub -Json '{"message":"Not Found","documentation_url":"https://docs.github.com"}')) 'erro da API'
    Assert-Verdade ($null -eq (ConvertFrom-ReleaseGitHub -Json '<html>proxy</html>')) 'lixo'
    Assert-Verdade ($null -eq (ConvertFrom-ReleaseGitHub -Json '')) 'vazio'
    # Sem o .sha256: Sha256Url vazio, mas o release vale.
    $o = $json | ConvertFrom-Json; $o.assets = @($o.assets | Where-Object { $_.name -like '*.exe' })
    $r = ConvertFrom-ReleaseGitHub -Json ($o | ConvertTo-Json -Depth 10)
    Assert-Igual '1.2.0|' ($r.Versao + '|' + $r.Sha256Url) 'sem sha256'
}

T 'Get-HashDoSha256 e Test-DeveChecarAtualizacao' {
    Assert-Igual '423b40e303415b1db1941e4cd6d86101e31760ccc71107781d42e012252d0cc2' (Get-HashDoSha256 "423B40E303415B1DB1941E4CD6D86101E31760CCC71107781D42E012252D0CC2  ConfigurarCameras-1.1.0-instalador.exe`n") 'sha256sum em maiusculas'
    Assert-Igual '' (Get-HashDoSha256 'abc  arquivo.exe') 'curto'
    Assert-Igual '' (Get-HashDoSha256 '') 'vazio'
    $agora = [datetime]'2026-10-02 09:00:00'
    Assert-Verdade (Test-DeveChecarAtualizacao -UltimaChecagem '' -Agora $agora) 'nunca checou'
    Assert-Verdade (Test-DeveChecarAtualizacao -UltimaChecagem 'lixo' -Agora $agora) 'registro ilegivel'
    Assert-Verdade (Test-DeveChecarAtualizacao -UltimaChecagem '2026-10-01 08:59:00' -Agora $agora) 'ha mais de 24 h'
    Assert-Falso (Test-DeveChecarAtualizacao -UltimaChecagem '2026-10-01 09:01:00' -Agora $agora) 'ha menos de 24 h'
    Assert-Verdade (Test-DeveChecarAtualizacao -UltimaChecagem '2026-10-02 07:00:00' -Agora $agora -Horas 1) '-Horas'
}

# ----------------------------------------- instancia unica e auto-encerrar

Write-Host ""
Write-Host "Instancia unica e auto-encerrar" -ForegroundColor Cyan

T 'Read-LockPainel: ausente, corrompido e sem porta/pid dao nulo; valido devolve porta e pid' {
    $d = New-Temp
    $arq = Join-Path $d 'painel.json'
    try {
        $null = New-Item -ItemType Directory -Force -Path $d
        Assert-Verdade ($null -eq (Read-LockPainel -Caminho $arq)) 'ausente'
        [IO.File]::WriteAllText($arq, '{ quebrado')
        Assert-Verdade ($null -eq (Read-LockPainel -Caminho $arq)) 'corrompido'
        [IO.File]::WriteAllText($arq, '{"porta":"x","pid":12}')
        Assert-Verdade ($null -eq (Read-LockPainel -Caminho $arq)) 'porta invalida'
        [IO.File]::WriteAllText($arq, '{"porta":51234,"pid":0}')
        Assert-Verdade ($null -eq (Read-LockPainel -Caminho $arq)) 'pid zero'
        [IO.File]::WriteAllText($arq, '{"porta":51234,"pid":4321,"inicio":"2026-10-01 09:00:00"}')
        $l = Read-LockPainel -Caminho $arq
        Assert-Igual '51234|4321|2026-10-01 09:00:00' ([string]$l.Porta + '|' + $l.Pid + '|' + $l.Inicio) 'valido'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'Test-PainelOcioso: so com a pagina sumida ha 180 s E nada em curso' {
    $agora = [datetime]'2026-10-01 10:00:00'
    $velho = $agora.AddSeconds(-181)
    $novo = $agora.AddSeconds(-30)
    Assert-Verdade (Test-PainelOcioso -Fase 'fila' -UltimoPoll $velho -Agora $agora) 'fila parada, pagina sumida'
    Assert-Verdade (Test-PainelOcioso -Fase 'ocioso' -UltimoPoll $velho -Agora $agora) 'ocioso'
    Assert-Falso (Test-PainelOcioso -Fase 'fila' -UltimoPoll $novo -Agora $agora) 'pagina viva'
    Assert-Falso (Test-PainelOcioso -Fase 'configurando' -UltimoPoll $velho -Agora $agora) 'configurando'
    Assert-Falso (Test-PainelOcioso -Fase 'decisao' -UltimoPoll $velho -Agora $agora) 'decisao'
    Assert-Falso (Test-PainelOcioso -Fase 'escolher' -UltimoPoll $velho -Agora $agora) 'escolher'
    Assert-Falso (Test-PainelOcioso -Fase 'fila' -VigiaLigado $true -UltimoPoll $velho -Agora $agora) 'vigia ligado'
    Assert-Falso (Test-PainelOcioso -Fase 'fila' -Ocupado $true -UltimoPoll $velho -Agora $agora) 'worker ocupado'
    Assert-Falso (Test-PainelOcioso -Fase 'fila' -Comandos 1 -UltimoPoll $velho -Agora $agora) 'comando na fila'
    Assert-Falso (Test-PainelOcioso -Fase 'fila' -Atualizando $true -UltimoPoll $velho -Agora $agora) 'atualizando'
    Assert-Falso (Test-PainelOcioso -Fase 'fila' -UltimoPoll $velho -Agora $agora -LimiteSeg 0) 'limite 0 desliga'
    Assert-Verdade (Test-PainelOcioso -Fase 'fila' -UltimoPoll $novo -Agora $agora -LimiteSeg 10) 'limite menor'
}

T 'Test-Internet: resposta do NCSI = ok; qualquer outra coisa = sem' {
    function curl.exe { $global:LASTEXITCODE = 0; return 'Microsoft Connect Test' }
    Assert-Igual 'ok' (Test-Internet) 'NCSI'
    function curl.exe { $global:LASTEXITCODE = 0; return '<html>portal cativo</html>' }
    Assert-Igual 'sem' (Test-Internet) 'portal cativo'
    function curl.exe { $global:LASTEXITCODE = 6; return '' }
    Assert-Igual 'sem' (Test-Internet) 'sem DNS'
}

# ------------------------------------------- camera que voltou de fabrica

Write-Host ""
Write-Host "Camera que voltou de fabrica (botao fisico ou tela dela)" -ForegroundColor Cyan

# O reset pelo painel saiu na 1.2.0 (nunca fez reset completo em firmware
# real). Registros antigos ainda podem ter Status 'Resetada': a fila tolera.
T 'Registro antigo com Status Resetada: a fila trata o IP como livre; o relatorio mostra' {
    $reg = New-Registro
    $e = New-EntradaRegistro -Mac 'aa:bb:cc:00:00:07' -Ip '10.70.20.57'
    $e.Status = 'Resetada'; $e.Modelo = 'VIP-1230-D-G3'
    Set-CameraRegistro $reg $e
    $f = @(New-FilaDeFaixa -Inicio '10.70.20.56' -Fim '10.70.20.58' -Registro $reg -Mascara '255.255.255.0' -Gateway '10.70.20.1')
    Assert-Igual 'pendente' ($f | Where-Object { $_.Ip -eq '10.70.20.57' }).Estado 'IP da resetada e livre'
    Assert-Verdade ((ConvertTo-RelatorioCsv -Registro $reg) -match 'Resetada') 'relatorio mostra Resetada'
}

# A camera que falhou nao ficou instalada: a posicao volta para a fila (o
# ping na hora de usar pula se ela ficou no IP). So Instalada ocupa.
T 'Fila: Falhou no registro nao ocupa a posicao; Instalada ocupa' {
    $reg = New-Registro
    $a = New-EntradaRegistro -Mac 'aa:bb:cc:00:00:56' -Ip '10.70.20.56'; $a.Status = 'Falhou'
    $b = New-EntradaRegistro -Mac 'aa:bb:cc:00:00:57' -Ip '10.70.20.57'; $b.Status = 'Instalada'
    Set-CameraRegistro $reg $a; Set-CameraRegistro $reg $b
    $f = @(New-FilaDeFaixa -Inicio '10.70.20.56' -Fim '10.70.20.58' -Registro $reg -Mascara '255.255.255.0' -Gateway '10.70.20.1')
    Assert-Igual 'pendente|pulada|pendente' (($f | ForEach-Object { $_.Estado }) -join '|') 'estados'
    Assert-Verdade (($f[1].Motivo) -match 'Instalada') ('motivo: ' + $f[1].Motivo)
}

T 'Camera ja no registro que reaparece de fabrica: entrada substituida, com aviso no log' {
    $d = New-Temp
    $arq = Join-Path $d 'registro.json'
    try {
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.80'; Mac = 'D8:36:5F:00:00:80' }
        $r = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $padroes -Senha 's' -CaminhoRegistro $arq -Simular
        Assert-Verdade $r.Ok 'primeira instalacao'
        # Mesma camera (MAC), de fabrica de novo, para outro IP.
        $ctx2 = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.81'; Mac = '' }
        function Get-EstadoCamera { param($IpOrigem, $Destino) return 'fabrica' }
        function Initialize-Cam { param($Ip, $Senha, $Email, [switch]$Simular) return $true }
        function New-CamSessao { param($Ip, $Senha) return [pscustomobject]@{ Ok = $true; Session = 1 } }
        function Get-CamInfoRpc { param($Sessao) return [pscustomobject]@{ Ok = $true; Modelo = 'VIP'; Serial = 'S'; Firmware = 'f'; Mac = 'D8365F000080' } }
        function Get-CamEncode { param($Sessao) return [pscustomobject]@{ Ok = $false; Erro = 'parar aqui' } }
        function Close-CamSessao { }
        function Test-IpLocal { param($Ip) return $false }
        $script:Linhas.Clear()
        $r2 = Invoke-ConfiguracaoCamera -Contexto $ctx2 -Padroes $padroes -Senha 's' -CaminhoRegistro $arq
        Assert-Verdade (($script:Linhas -join "`n") -match 'ja estava no registro em 10.70.20\.80 \(Instalada\); voltou de fabrica, a entrada sera substituida') 'aviso'
        $e = Find-CameraRegistro (Read-Registro $arq) 'D8365F000080'
        Assert-Igual '10.70.20.81' $e.Ip 'entrada substituida (IP novo)'
        Assert-Igual 1 @((Read-Registro $arq).Cameras).Count 'uma entrada so'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

T 'Aplicado no registro leva so o que a camera recebeu: sem placa, fila nem etapa' {
    $d = New-Temp
    try {
        $s = ConvertTo-SessaoTeste @{ Etapa = 7; Placa = @{ Nome = 'Ethernet'; IfIndex = 8 }; Fila = @{ Inicio = '10.70.20.50'; Fim = '10.70.20.60' } }
        $ctx = [pscustomobject]@{ IpOrigem = '192.168.1.108'; Destino = '10.70.20.55'; Mac = '' }
        $null = Invoke-ConfiguracaoCamera -Contexto $ctx -Padroes $s -Senha 's' -CaminhoRegistro (Join-Path $d 'r.json') -Simular
        $txt = [IO.File]::ReadAllText((Join-Path $d 'r.json'))
        Assert-Falso ($txt -match '"Placa"|"Fila"|"IfIndex"|"Quando"') 'sem placa/fila/ifIndex no registro'
        $ap = @((Read-Registro (Join-Path $d 'r.json')).Cameras)[0].Aplicado
        Assert-Igual '255.255.255.0|10.70.20.1|20' ($ap.Mascara + '|' + $ap.Gateway + '|' + $ap.Encoder.Principal.Fps) 'o que foi aplicado'
    } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
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
