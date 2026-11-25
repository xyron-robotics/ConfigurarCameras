<#
    Testes-Front.ps1
    Teste estatico que guarda a arquitetura do front (direcao.md, secao 7.4):
    nenhum valor local solto, texto de UI num lugar so, CSS em camadas, todo
    arquivo do www servido e instalado. PowerShell 5.1, sem Node.

    A interface e uma funcao so:
        Test-Front -Www <pasta> -Iss <arquivo .iss> -Servidor <Servidor-Painel.ps1>
    que devolve a lista de violacoes { regra, arquivo, linha, trecho }. As 11
    regras ficam atras dela:
      hex, medida, numero-solto-css, numero-solto-js, estilo-inline,
      id-no-css, camada, texto-fora, import, servido, legado.
    A regra legado (nenhum legado-*.js no www nem import de um) e a lista dos
    24 arquivos da direcao 7.3 entraram na Task 2 do plano
    docs/plans/2026-11-20-frente-redesenho-5-verificacao-plan.md.

    Os testes montam, numa pasta de $env:TEMP (apagada no fim), um www minimo
    limpo, um .iss e um servidor minimos. A pasta limpa sozinha espera zero
    violacoes; cada caso planta UMA violacao e espera exatamente aquela regra.
    A assercao "www real com zero violacoes" entra na Task 5 do plano
    docs/plans/2026-11-20-frente-redesenho-1-arquitetura-plan.md (decisao R4);
    ate la o www real so e medido e a contagem sai na tela.

    Uso:
        .\Testes-Front.ps1
    Sai com codigo 1 se algum teste falhar.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$raiz = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($raiz)) { $raiz = (Get-Location).Path }

# ------------------------------------------------------------------ Test-Front

# Por dentro: leitura de cada tipo de arquivo (comentario e string apagados com
# espaco, para o indice e a linha continuarem os mesmos) e uma passada por regra.

$script:OrdemCamadas = @('tokens', 'base', 'componentes', 'telas')
$script:ReHex = '(?<![&\w])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![\w-])'
$script:ReMedida = '(?<![\w#.]|[\w-]-)-?(?:\d+\.?\d*|\.\d+)(?:px|rem|em|ms|s|vh|vw|%)(?![\w-])'
$script:ReNumeroCss = '(?<![\w#.]|[\w-]-)-?(?:\d+\.?\d*|\.\d+)(?![\w%.])'
$script:ReNumeroJs = '(?<![\w$.])(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|(?:\d[\d_]*)?\.?\d[\d_]*(?:[eE][+-]?\d+)?)n?(?![\w$])'
$script:ReAcento = '[\u00C0-\u024F]'
$script:RePalavraMaiuscula = '^[A-Z\u00C0-\u00DE][a-z\u00DF-\u00FF]'
$script:ReLegado = '^legado-[^/\\]*\.js$'
# Os 24 arquivos do www (direcao.md, secao 7.3), na ordem da lista.
$script:ArquivosWww = @('index.html', 'tokens.css', 'base.css', 'componentes.css', 'telas.css',
    'app.js', 'api.js', 'estado.js', 'rotas.js', 'textos.js', 'formato.js', 'constantes.js', 'dom.js',
    'icones.js', 'componentes.js', 'formularios.js', 'tela-inicio.js', 'tela-painel.js', 'tela-sessao.js',
    'tela-ferramentas.js', 'topo.js', 'marca.js', 'logo.png', 'simbolo.png')

function Hide-Trecho {
    param([string]$Texto)
    return [regex]::Replace($Texto, '[^\r\n]', ' ')
}

# Troca cada casamento de $Padrao por espacos, preservando quebras de linha.
function Hide-Padrao {
    param([string]$Texto, [string]$Padrao)
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    foreach ($m in [regex]::Matches($Texto, $Padrao)) {
        [void]$sb.Append($Texto.Substring($pos, $m.Index - $pos))
        [void]$sb.Append((Hide-Trecho $m.Value))
        $pos = $m.Index + $m.Length
    }
    [void]$sb.Append($Texto.Substring($pos))
    return $sb.ToString()
}

function Get-NumeroLinha {
    param([string]$Texto, [int]$Indice)
    return [regex]::Matches($Texto.Substring(0, $Indice), "`n").Count + 1
}

# JS: SemComentario (strings ficam), Codigo (strings e comentarios apagados) e a
# lista de literais de string com o indice. Regex literal nao e reconhecido.
function Read-Js {
    param([string]$Texto)
    $padrao = '//[^\r\n]*|/\*[\s\S]*?\*/|''(?:[^''\\\r\n]|\\.)*''|"(?:[^"\\\r\n]|\\.)*"|`(?:[^`\\]|\\[\s\S])*`'
    $semCom = New-Object System.Text.StringBuilder
    $codigo = New-Object System.Text.StringBuilder
    $strings = @()
    $pos = 0
    foreach ($m in [regex]::Matches($Texto, $padrao)) {
        $antes = $Texto.Substring($pos, $m.Index - $pos)
        [void]$semCom.Append($antes); [void]$codigo.Append($antes)
        $branco = Hide-Trecho $m.Value
        if ($m.Value.StartsWith('/')) {
            [void]$semCom.Append($branco)
        } else {
            [void]$semCom.Append($m.Value)
            $strings += @{ Indice = $m.Index; Valor = $m.Value.Substring(1, $m.Value.Length - 2) }
        }
        [void]$codigo.Append($branco)
        $pos = $m.Index + $m.Length
    }
    $resto = $Texto.Substring($pos)
    [void]$semCom.Append($resto); [void]$codigo.Append($resto)
    return @{ SemComentario = $semCom.ToString(); Codigo = $codigo.ToString(); Strings = $strings }
}

function Test-Front {
    param(
        [Parameter(Mandatory = $true)][string]$Www,
        [Parameter(Mandatory = $true)][string]$Iss,
        [Parameter(Mandatory = $true)][string]$Servidor
    )
    $v = New-Object System.Collections.ArrayList
    $add = {
        param($Regra, $Arquivo, $Linha, $Trecho)
        $t = ([string]$Trecho).Trim()
        if ($t.Length -gt 120) { $t = $t.Substring(0, 120) }
        [void]$v.Add([pscustomobject]@{ regra = $Regra; arquivo = $Arquivo; linha = [int]$Linha; trecho = $t })
    }
    # Uma violacao por casamento de $Padrao em cada linha de $Texto (o texto ja
    # processado); $Original da o trecho. $Filtro decide se o casamento conta.
    $porLinha = {
        param($Regra, $Arquivo, $Texto, $Original, $Padrao, $Filtro)
        $linhas = $Texto -split "`n"
        $orig = $Original -split "`n"
        for ($n = 0; $n -lt $linhas.Count; $n++) {
            foreach ($m in [regex]::Matches($linhas[$n], $Padrao)) {
                if ($Filtro -and -not (& $Filtro $m $linhas[$n])) { continue }
                & $add $Regra $Arquivo ($n + 1) $orig[$n]
            }
        }
    }
    $enc = [Text.Encoding]::UTF8
    $todos = @(Get-ChildItem -LiteralPath $Www -File -Recurse)
    $planos = @($todos | Where-Object { $_.DirectoryName.TrimEnd('\') -eq (Get-Item -LiteralPath $Www).FullName.TrimEnd('\') })
    $nomes = @($planos | ForEach-Object { $_.Name })

    # ---- legado: a ponte da fase B saiu (frente redesenho-verificacao, Task 2, V1)
    foreach ($f in $planos) {
        if ($f.Name -match $script:ReLegado) { & $add 'legado' $f.Name 0 'arquivo legado-*.js no www' }
    }

    # ---- quebras e ordem das camadas, de tokens.css
    $quebras = @()
    $caminhoTokens = Join-Path $Www 'tokens.css'
    if (Test-Path -LiteralPath $caminhoTokens) {
        $tok = [IO.File]::ReadAllText($caminhoTokens, $enc)
        $mq = [regex]::Match($tok, 'quebras:\s*([^*]+?)\s*\*/')
        if ($mq.Success) { $quebras = @($mq.Groups[1].Value -split '\s+' | Where-Object { $_ }) }
    }

    $medidaPermitida = {
        param($m, $linha)
        $txt = $m.Value
        if ($txt -eq '100%') { return $false }
        $num = [regex]::Match($txt, '-?(?:\d+\.?\d*|\.\d+)').Value
        if ([double]::Parse($num, [Globalization.CultureInfo]::InvariantCulture) -eq 0) { return $false }
        if ($linha -match '@media' -and $quebras -contains $txt) { return $false }
        return $true
    }

    foreach ($f in $planos) {
        $nome = $f.Name
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -notin @('.css', '.js', '.html')) { continue }
        $texto = [IO.File]::ReadAllText($f.FullName, $enc)

        if ($ext -eq '.css') {
            $semCom = Hide-Padrao $texto '/\*[\s\S]*?\*/'
            $limpo = Hide-Padrao $semCom '"(?:[^"\\\r\n]|\\.)*"|''(?:[^''\\\r\n]|\\.)*''|url\([^)]*\)'
            $camada = [IO.Path]::GetFileNameWithoutExtension($nome)

            # camada
            if ($script:OrdemCamadas -notcontains $camada -or
                $semCom -notmatch ('@layer\s+' + [regex]::Escape($camada) + '\s*\{')) {
                & $add 'camada' $nome 1 ('sem @layer ' + $camada + ' { }')
            }
            if ($nome -eq 'tokens.css' -and
                $semCom.TrimStart() -notmatch ('^@layer\s+' + ($script:OrdemCamadas -join '\s*,\s*') + '\s*;')) {
                & $add 'camada' $nome 1 ('primeira regra sem @layer ' + ($script:OrdemCamadas -join ', ') + ';')
            }

            # id-no-css: seletor e o que vem antes de cada '{'
            foreach ($p in [regex]::Matches($limpo, '[^{};]+(?=\{)')) {
                foreach ($m in [regex]::Matches($p.Value, '#-?[A-Za-z_][\w-]*')) {
                    $n = Get-NumeroLinha $limpo ($p.Index + $m.Index)
                    & $add 'id-no-css' $nome $n (($texto -split "`n")[$n - 1])
                }
            }

            if ($nome -ne 'tokens.css') {
                & $porLinha 'hex' $nome $semCom $texto $script:ReHex $null
                & $porLinha 'medida' $nome $limpo $texto $script:ReMedida $medidaPermitida
                $semHex = Hide-Padrao $limpo $script:ReHex
                $semHex = Hide-Padrao $semHex $script:ReMedida
                & $porLinha 'numero-solto-css' $nome $semHex $texto $script:ReNumeroCss {
                    param($m, $linha)
                    # O sinal e operador (calc(x * -1)), como no JS: conta o literal.
                    $x = [Math]::Abs([double]::Parse($m.Value, [Globalization.CultureInfo]::InvariantCulture))
                    return ($x -ne 0 -and $x -ne 1)
                }
            }
        }

        if ($ext -eq '.js') {
            $js = Read-Js $texto
            & $porLinha 'hex' $nome $js.SemComentario $texto $script:ReHex $null
            & $porLinha 'medida' $nome $js.SemComentario $texto $script:ReMedida $medidaPermitida
            if ($nome -ne 'constantes.js') {
                & $porLinha 'numero-solto-js' $nome $js.Codigo $texto $script:ReNumeroJs {
                    param($m, $linha)
                    $s = ($m.Value -replace '_', '').TrimEnd('n')
                    if ($s -match '^0[xX]') { $x = [Convert]::ToInt64($s.Substring(2), 16) }
                    elseif ($s -match '^0[bB]') { $x = [Convert]::ToInt64($s.Substring(2), 2) }
                    elseif ($s -match '^0[oO]') { $x = [Convert]::ToInt64($s.Substring(2), 8) }
                    else { $x = [double]::Parse($s, [Globalization.CultureInfo]::InvariantCulture) }
                    return ($x -gt 2)
                }
            }
            & $porLinha 'estilo-inline' $nome $js.SemComentario $texto '\.style\b(?!\s*\.\s*setProperty\s*\(\s*[''"`]--)' $null
            if ($nome -ne 'textos.js') {
                foreach ($s in $js.Strings) {
                    $val = [regex]::Replace($s.Valor, '\$\{[^}]*\}', ' ')
                    $maiusculas = @($val -split '\s+' | Where-Object { $_ -cmatch $script:RePalavraMaiuscula }).Count
                    if ($val -cmatch $script:ReAcento -or $maiusculas -ge 2) {
                        $n = Get-NumeroLinha $texto $s.Indice
                        & $add 'texto-fora' $nome $n (($texto -split "`n")[$n - 1])
                    }
                }
            }
            $reImport = @('\bimport\s*\(?\s*([''"])(?<esp>[^''"]+)\1',
                          '\b(?:import|export)\b[^;''"()]*?\bfrom\s*([''"])(?<esp>[^''"]+)\1')
            foreach ($re in $reImport) {
                foreach ($m in [regex]::Matches($js.SemComentario, $re)) {
                    $esp = ($m.Groups['esp'].Value -replace '[?#].*$', '') -replace '^\./', '' -replace '^/', ''
                    if ($esp -match $script:ReLegado) {
                        $n = Get-NumeroLinha $texto $m.Index
                        & $add 'legado' $nome $n (($texto -split "`n")[$n - 1])
                    } elseif ($esp -match '[/\\]' -or $nomes -notcontains $esp) {
                        $n = Get-NumeroLinha $texto $m.Index
                        & $add 'import' $nome $n (($texto -split "`n")[$n - 1])
                    }
                }
            }
        }

        if ($ext -eq '.html') {
            $semCom = Hide-Padrao $texto '<!--[\s\S]*?-->'
            $orig = $texto -split "`n"
            $linhasHtml = $semCom -split "`n"
            for ($n = 0; $n -lt $linhasHtml.Count; $n++) {
                if ($linhasHtml[$n] -match 'theme-color') { continue }
                foreach ($m in [regex]::Matches($linhasHtml[$n], $script:ReHex)) { & $add 'hex' $nome ($n + 1) $orig[$n] }
            }
            & $porLinha 'medida' $nome $semCom $texto $script:ReMedida $medidaPermitida
            foreach ($re in @('(?i)<[a-z][^>]*\sstyle\s*=', '(?i)<style\b', '(?i)<script\b(?![^>]*\ssrc\s*=)[^>]*>',
                              '(?i)<[a-z][^>]*\son[a-z]+\s*=')) {
                foreach ($m in [regex]::Matches($semCom, $re)) {
                    $n = Get-NumeroLinha $semCom $m.Index
                    & $add 'estilo-inline' $nome $n $orig[$n - 1]
                }
            }
            # texto-fora: texto e atributos de texto no <body>, fora de <noscript>
            $mb = [regex]::Match($semCom, '(?is)<body\b[^>]*>(.*?)</body>')
            if ($mb.Success) {
                $corpo = $mb.Groups[1].Value
                $ini = $mb.Groups[1].Index
                $corpo = Hide-Padrao $corpo '(?is)<noscript\b.*?</noscript>|<script\b.*?</script>'
                foreach ($m in [regex]::Matches($corpo, '(?i)\s(?:aria-label|title|placeholder|alt)\s*=\s*(?:"[^"]*[A-Za-z\u00C0-\u024F][^"]*"|''[^'']*[A-Za-z\u00C0-\u024F][^'']*'')')) {
                    $n = Get-NumeroLinha $semCom ($ini + $m.Index)
                    & $add 'texto-fora' $nome $n $orig[$n - 1]
                }
                $semTags = Hide-Padrao $corpo '<[^>]*>'
                $vistas = @{}
                foreach ($m in [regex]::Matches($semTags, '\S+')) {
                    $n = Get-NumeroLinha $semCom ($ini + $m.Index)
                    if ($vistas.ContainsKey($n)) { continue }
                    $vistas[$n] = $true
                    & $add 'texto-fora' $nome $n $orig[$n - 1]
                }
            }
            # import: script, link, img e source que apontam para arquivo local inexistente
            foreach ($m in [regex]::Matches($semCom, '(?i)<(?:script|link|img|source)\b[^>]*?\s(?:src|href)\s*=\s*["'']([^"'']+)["'']')) {
                $alvo = $m.Groups[1].Value
                if ($alvo -match '^(#|data:|//)' -or $alvo -match ':') { continue }
                $esp = ($alvo -replace '[?#].*$', '') -replace '^\./', '' -replace '^/', ''
                if ($esp -match '[/\\]' -or $nomes -notcontains $esp) {
                    $n = Get-NumeroLinha $semCom $m.Index
                    & $add 'import' $nome $n $orig[$n - 1]
                }
            }
        }
    }

    # ---- servido: www x .iss x $tipos do servidor
    $issLinhas = [IO.File]::ReadAllLines($Iss, $enc)
    $issNome = Split-Path $Iss -Leaf
    $noIss = @()
    for ($n = 0; $n -lt $issLinhas.Count; $n++) {
        $m = [regex]::Match($issLinhas[$n], '^Source:\s*"[^"]*\\web\\www\\([^"]+)"')
        if (-not $m.Success) { continue }
        $arq = $m.Groups[1].Value
        $noIss += $arq
        if ($nomes -notcontains $arq) { & $add 'servido' $issNome ($n + 1) $issLinhas[$n] }
    }
    $srv = [IO.File]::ReadAllText($Servidor, $enc)
    $mt = [regex]::Match($srv, '(?m)^\s*\$tipos\s*=\s*@\{([^\r\n]*)\}')
    $tipos = @()
    if ($mt.Success) { $tipos = @([regex]::Matches($mt.Groups[1].Value, '''(\.[^'']+)''\s*=') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() }) }
    foreach ($f in $todos) {
        $rel = $f.FullName.Substring((Get-Item -LiteralPath $Www).FullName.TrimEnd('\').Length + 1)
        if ($rel -match '\\') { & $add 'servido' $rel 0 'subpasta do www nao e servida'; continue }
        if ($noIss -notcontains $rel) { & $add 'servido' $rel 0 'sem Source: no .iss' }
        if ($tipos -notcontains $f.Extension.ToLowerInvariant()) {
            & $add 'servido' $rel 0 ('extensao ' + $f.Extension + ' sem entrada em $tipos do servidor')
        }
    }

    return $v.ToArray()
}

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

function Format-Violacoes {
    param($Lista)
    if (@($Lista).Count -eq 0) { return '(nenhuma)' }
    return ((@($Lista) | ForEach-Object { $_.regra + ' ' + $_.arquivo + ':' + $_.linha + ' [' + $_.trecho + ']' }) -join ' | ')
}

# ------------------------------------------------------------------ fixture

# Acentos em ASCII: o arquivo de teste e ASCII (regra do plano).
$cc = [char]0x00E7; $at = [char]0x00E3; $ec = [char]0x00EA
$textoAcento = 'Configura' + $cc + $at + 'o das c' + $ec + 'meras'
$sessaoAcento = 'Sess' + $at + 'o'

$script:SemBom = New-Object System.Text.UTF8Encoding $false

function Join-Linhas { param([string[]]$L) return ($L -join "`r`n") + "`r`n" }

# Www minimo limpo. Tem de proposito o que parece violacao e nao e: hex e texto em
# comentario, hash de rota, var(--espaco-2), nth-child(2n+1), calc(x * -1), 100%, identificador
# h2, numeros 0 a 2 no JS, 'Content-Type', hex das metas theme-color.
function Get-WwwLimpo {
    return [ordered]@{
        'tokens.css' = Join-Linhas @(
            '@layer tokens, base, componentes, telas;',
            '/* Tokens do painel.',
            '   quebras: 1100px 1600px */',
            '@layer tokens {',
            '  :root { --fundo: #FFFFFF; --texto: #1A1A1A; --espaco-2: 8px; --raio: 4px; --peso-forte: 600; --duracao: 150ms; }',
            '  [data-tema=escuro] { --fundo: #101418; }',
            '}')
        'base.css' = Join-Linhas @(
            '@layer base {',
            '  body { margin: 0; background: var(--fundo); color: var(--texto); }',
            '}')
        'componentes.css' = Join-Linhas @(
            '/* #123456 e 12px em comentario nao contam */',
            '@layer componentes {',
            '  .botao { padding: var(--espaco-2); border-radius: var(--raio); flex: 1; font-weight: var(--peso-forte); width: 100%; }',
            '  .lista > li:nth-child(2n+1) { opacity: 1; }',
            '  .coluna-2 { gap: var(--espaco-2); margin-inline-start: calc(var(--raio) * -1); }',
            '}')
        'telas.css' = Join-Linhas @(
            '@layer telas {',
            '  @media (max-width: 1100px) {',
            '    .grade { display: grid; }',
            '  }',
            '}')
        'constantes.js' = Join-Linhas @(
            'export const CONSULTA_MS = 1500;',
            'export const HTTP_CONFLITO = 409;')
        'textos.js' = Join-Linhas @(
            'const TEXTOS = {',
            ("  titulo: '" + $textoAcento + "',"),
            "  encerrar: 'Encerrar O Painel',",
            '};',
            'export function t(chave) { return TEXTOS[chave] ?? chave; }')
        'app.js' = Join-Linhas @(
            "// Ponto de entrada. '#123456', 12px e 'Texto Em Comentario' aqui nao contam.",
            "import { CONSULTA_MS } from './constantes.js';",
            "import { t } from './textos.js';",
            '',
            "const raiz = document.querySelector('[data-raiz]');",
            "raiz.textContent = t('titulo');",
            "raiz.style.setProperty('--largura', '0');",
            "location.hash = '#/painel';",
            'const itens = [0, 1, 2].map((n) => n * 2);',
            'const rotulo = `${itens.length} itens`;',
            "const cabecalho = { 'Content-Type': 'application/json' };",
            "const h2 = raiz.querySelector('h2');",
            "setInterval(() => raiz.setAttribute('data-n', rotulo + h2 + cabecalho), CONSULTA_MS);")
        'index.html' = Join-Linhas @(
            '<!doctype html>',
            '<html lang="pt-BR">',
            '<head>',
            '  <meta charset="utf-8">',
            '  <meta name="theme-color" content="#F4F6F8" media="(prefers-color-scheme: light)">',
            '  <meta name="theme-color" content="#101418" media="(prefers-color-scheme: dark)">',
            ('  <title>Configurar c' + $ec + 'meras</title>'),
            '  <link rel="stylesheet" href="/tokens.css">',
            '  <link rel="stylesheet" href="/base.css">',
            '  <link rel="stylesheet" href="/componentes.css">',
            '  <link rel="stylesheet" href="/telas.css">',
            '  <script type="module" src="/app.js"></script>',
            '</head>',
            '<body>',
            '  <!-- ponto de montagem; <p>Texto Comentado</p> nao conta -->',
            '  <div data-raiz></div>',
            '  <noscript><p>O painel precisa de JavaScript ligado.</p></noscript>',
            '</body>',
            '</html>')
    }
}

$script:TiposLimpos = @('.html', '.js', '.css', '.svg')

# Monta www + .iss + servidor numa pasta nova. -Mudar troca o conteudo de arquivos
# do www (valor $null tira o arquivo); -SemSource tira nomes do .iss; -SourceExtra
# poe nomes no .iss; -Tipos troca a lista de $tipos do servidor.
function New-FixtureFront {
    param(
        [string]$Pasta,
        [hashtable]$Mudar = @{},
        [string[]]$SemSource = @(),
        [string[]]$SourceExtra = @(),
        [string[]]$Tipos = $script:TiposLimpos
    )
    $www = Join-Path $Pasta 'www'
    New-Item -ItemType Directory -Path $www -Force | Out-Null
    $arquivos = Get-WwwLimpo
    foreach ($k in $Mudar.Keys) { $arquivos[$k] = $Mudar[$k] }
    $nomes = @()
    foreach ($k in $arquivos.Keys) {
        if ($null -eq $arquivos[$k]) { continue }
        [IO.File]::WriteAllText((Join-Path $www $k), [string]$arquivos[$k], $script:SemBom)
        $nomes += $k
    }
    $iss = @('[Files]')
    foreach ($n in (@($nomes) + @($SourceExtra))) {
        if ($SemSource -contains $n) { continue }
        $iss += ('Source: "{#Raiz}\fonte\web\www\' + $n + '"; DestDir: "{app}\web\www"; Flags: ignoreversion')
    }
    $iss += 'Source: "{#Raiz}\fonte\web\Servidor-Painel.ps1"; DestDir: "{app}\web"; Flags: ignoreversion'
    $caminhoIss = Join-Path $Pasta 'front.iss'
    [IO.File]::WriteAllText($caminhoIss, (Join-Linhas $iss), $script:SemBom)
    $pares = @($Tipos | ForEach-Object { "'" + $_ + "' = 'tipo'" }) -join '; '
    $caminhoSrv = Join-Path $Pasta 'Servidor.ps1'
    [IO.File]::WriteAllText($caminhoSrv, (Join-Linhas @('$www = ''x''', ('$tipos = @{ ' + $pares + ' }'))), $script:SemBom)
    return @{ Www = $www; Iss = $caminhoIss; Servidor = $caminhoSrv }
}

# Troca a linha N (1-based) de um texto da fixture, ou insere antes dela com -Inserir.
function Edit-Linha {
    param([string]$Arquivo, [int]$N, [string]$Linha, [switch]$Inserir)
    $l = New-Object System.Collections.ArrayList
    $l.AddRange(@(((Get-WwwLimpo)[$Arquivo]).TrimEnd("`r", "`n") -split "`r`n"))
    if ($Inserir) { $l.Insert($N - 1, $Linha) } else { $l[$N - 1] = $Linha }
    return Join-Linhas ([string[]]$l.ToArray())
}

# ------------------------------------------------------------------ casos

# Cada caso planta uma violacao e diz a regra, o arquivo e a linha esperados.
$casos = @(
    @{ Nome = 'hex em .css fora de tokens.css'; Regra = 'hex'; Arquivo = 'base.css'; Linha = 2
       Mudar = @{ 'base.css' = (Edit-Linha 'base.css' 2 '  body { margin: 0; color: #123456; }') } }
    @{ Nome = 'hex em .js'; Regra = 'hex'; Arquivo = 'app.js'; Linha = 7
       Mudar = @{ 'app.js' = (Edit-Linha 'app.js' 7 "raiz.setAttribute('data-cor', '#ABCDEF');") } }
    @{ Nome = 'hex no index.html fora das metas theme-color'; Regra = 'hex'; Arquivo = 'index.html'; Linha = 16
       Mudar = @{ 'index.html' = (Edit-Linha 'index.html' 16 '  <div data-raiz data-cor="#abc"></div>') } }
    @{ Nome = 'medida em .css fora de tokens.css'; Regra = 'medida'; Arquivo = 'componentes.css'; Linha = 5
       Mudar = @{ 'componentes.css' = (Edit-Linha 'componentes.css' 5 '  .coluna-2 { gap: 12px; }') } }
    @{ Nome = 'medida em @media fora das quebras'; Regra = 'medida'; Arquivo = 'telas.css'; Linha = 2
       Mudar = @{ 'telas.css' = (Edit-Linha 'telas.css' 2 '  @media (max-width: 900px) {') } }
    @{ Nome = 'medida em .js'; Regra = 'medida'; Arquivo = 'app.js'; Linha = 7
       Mudar = @{ 'app.js' = (Edit-Linha 'app.js' 7 "raiz.style.setProperty('--largura', '240px');") } }
    @{ Nome = 'numero sem unidade em .css fora de tokens.css'; Regra = 'numero-solto-css'; Arquivo = 'componentes.css'; Linha = 5
       Mudar = @{ 'componentes.css' = (Edit-Linha 'componentes.css' 5 '  .coluna-2 { flex: 2; }') } }
    @{ Nome = 'numero maior que 2 em .js fora de constantes.js'; Regra = 'numero-solto-js'; Arquivo = 'app.js'; Linha = 4
       Mudar = @{ 'app.js' = (Edit-Linha 'app.js' 4 'const TENTATIVAS = 5;') } }
    @{ Nome = '.style. em .js'; Regra = 'estilo-inline'; Arquivo = 'app.js'; Linha = 7
       Mudar = @{ 'app.js' = (Edit-Linha 'app.js' 7 "raiz.style.color = 'red';") } }
    @{ Nome = 'style= no html'; Regra = 'estilo-inline'; Arquivo = 'index.html'; Linha = 16
       Mudar = @{ 'index.html' = (Edit-Linha 'index.html' 16 '  <div data-raiz style="color: red"></div>') } }
    @{ Nome = '<style> no html'; Regra = 'estilo-inline'; Arquivo = 'index.html'; Linha = 12
       Mudar = @{ 'index.html' = (Edit-Linha 'index.html' 12 '  <style>.a { color: red; }</style>' -Inserir) } }
    @{ Nome = '<script> sem src no html'; Regra = 'estilo-inline'; Arquivo = 'index.html'; Linha = 12
       Mudar = @{ 'index.html' = (Edit-Linha 'index.html' 12 '  <script>window.x = true;</script>' -Inserir) } }
    @{ Nome = 'atributo on* no html'; Regra = 'estilo-inline'; Arquivo = 'index.html'; Linha = 16
       Mudar = @{ 'index.html' = (Edit-Linha 'index.html' 16 '  <div data-raiz onclick="ir()"></div>') } }
    @{ Nome = 'seletor de id no .css'; Regra = 'id-no-css'; Arquivo = 'telas.css'; Linha = 5
       Mudar = @{ 'telas.css' = (Edit-Linha 'telas.css' 5 '  #painel { display: grid; }' -Inserir) } }
    @{ Nome = '.css sem o @layer do seu nome'; Regra = 'camada'; Arquivo = 'base.css'; Linha = 1
       Mudar = @{ 'base.css' = (Edit-Linha 'base.css' 1 '@layer componentes {') } }
    @{ Nome = 'tokens.css sem a ordem das camadas na primeira regra'; Regra = 'camada'; Arquivo = 'tokens.css'; Linha = 1
       Mudar = @{ 'tokens.css' = (Edit-Linha 'tokens.css' 1 '@layer base, tokens, componentes, telas;') } }
    @{ Nome = 'texto com acento em .js fora de textos.js'; Regra = 'texto-fora'; Arquivo = 'app.js'; Linha = 4
       Mudar = @{ 'app.js' = (Edit-Linha 'app.js' 4 ("raiz.title = '" + $sessaoAcento + "';")) } }
    @{ Nome = 'texto com duas palavras em maiuscula em .js'; Regra = 'texto-fora'; Arquivo = 'app.js'; Linha = 4
       Mudar = @{ 'app.js' = (Edit-Linha 'app.js' 4 "raiz.title = 'Encerrar Painel';") } }
    @{ Nome = 'texto no <body> fora do <noscript>'; Regra = 'texto-fora'; Arquivo = 'index.html'; Linha = 16
       Mudar = @{ 'index.html' = (Edit-Linha 'index.html' 16 '  <div data-raiz>Carregando</div>') } }
    @{ Nome = 'texto em aria-label no <body>'; Regra = 'texto-fora'; Arquivo = 'index.html'; Linha = 16
       Mudar = @{ 'index.html' = (Edit-Linha 'index.html' 16 '  <div data-raiz aria-label="Painel"></div>') } }
    @{ Nome = 'import de arquivo que nao existe'; Regra = 'import'; Arquivo = 'app.js'; Linha = 4
       Mudar = @{ 'app.js' = (Edit-Linha 'app.js' 4 "import { nada } from './nao-existe.js';") } }
    @{ Nome = 'script do index.html que nao existe'; Regra = 'import'; Arquivo = 'index.html'; Linha = 12
       Mudar = @{ 'index.html' = (Edit-Linha 'index.html' 12 '  <script type="module" src="/fantasma.js"></script>') } }
    @{ Nome = 'arquivo do www sem Source: no .iss'; Regra = 'servido'; Arquivo = 'extra.js'; Linha = 0
       Mudar = @{ 'extra.js' = (Join-Linhas @('export const A = 1;')) }; SemSource = @('extra.js') }
    @{ Nome = 'Source: do www sem arquivo'; Regra = 'servido'; Arquivo = 'front.iss'; Linha = 10
       SourceExtra = @('fantasma.js') }
    @{ Nome = 'extensao sem entrada em $tipos'; Regra = 'servido'; Arquivo = 'logo.png'; Linha = 0
       Mudar = @{ 'logo.png' = 'png' } }
    @{ Nome = 'arquivo legado-*.js no www'; Regra = 'legado'; Arquivo = 'legado-x.js'; Linha = 0
       Mudar = @{ 'legado-x.js' = (Join-Linhas @('export const A = 1;')) } }
    @{ Nome = 'import de um legado-*.js'; Regra = 'legado'; Arquivo = 'app.js'; Linha = 4
       Mudar = @{ 'app.js' = (Edit-Linha 'app.js' 4 "import { nada } from './legado-x.js';") } }
)

# ------------------------------------------------------------------ testes

$tmpRaiz = Join-Path $env:TEMP ('testes-front-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRaiz -Force | Out-Null

try {
    T 'pasta limpa: zero violacoes' {
        $f = New-FixtureFront -Pasta (Join-Path $tmpRaiz 'limpa')
        $v = @(Test-Front -Www $f.Www -Iss $f.Iss -Servidor $f.Servidor)
        Assert-Igual 0 $v.Count ('violacoes na pasta limpa: ' + (Format-Violacoes $v))
    }

    $i = 0
    foreach ($c in $casos) {
        $i++
        $script:casoAtual = $c
        $script:pastaCaso = Join-Path $tmpRaiz ('caso-' + $i)
        T ($c.Regra + ': ' + $c.Nome) {
            $c = $script:casoAtual
            $p = @{ Pasta = $script:pastaCaso }
            if ($c.Mudar) { $p.Mudar = $c.Mudar }
            if ($c.SemSource) { $p.SemSource = $c.SemSource }
            if ($c.SourceExtra) { $p.SourceExtra = $c.SourceExtra }
            $f = New-FixtureFront @p
            $v = @(Test-Front -Www $f.Www -Iss $f.Iss -Servidor $f.Servidor)
            $lista = Format-Violacoes $v
            Assert-Igual 1 $v.Count ('violacoes: ' + $lista)
            Assert-Igual $c.Regra $v[0].regra ('regra: ' + $lista)
            Assert-Igual $c.Arquivo $v[0].arquivo ('arquivo: ' + $lista)
            Assert-Igual $c.Linha $v[0].linha ('linha: ' + $lista)
        }
    }

    T 'as 11 regras tem caso plantado' {
        $regras = @('hex', 'medida', 'numero-solto-css', 'numero-solto-js', 'estilo-inline',
                    'id-no-css', 'camada', 'texto-fora', 'import', 'servido', 'legado')
        $cobertas = @($casos | ForEach-Object { $_.Regra } | Sort-Object -Unique)
        $faltam = @($regras | Where-Object { $cobertas -notcontains $_ })
        Assert-Igual '' ($faltam -join ', ') 'regras sem caso'
    }
} finally {
    Remove-Item -LiteralPath $tmpRaiz -Recurse -Force -ErrorAction SilentlyContinue
}

# O www real, o .iss real e o servidor real: zero violacoes (R4). Arquivo que falta e falha, nao pulo.
T 'www real: zero violacoes' {
    $wwwReal = Join-Path $raiz 'web\www'
    $issReal = Join-Path (Split-Path $raiz -Parent) 'instalador\ConfigurarCameras.iss'
    $srvReal = Join-Path $raiz 'web\Servidor-Painel.ps1'
    foreach ($p in @($wwwReal, $issReal, $srvReal)) {
        if (-not (Test-Path -LiteralPath $p)) { throw ('nao achei ' + $p) }
    }
    $real = @(Test-Front -Www $wwwReal -Iss $issReal -Servidor $srvReal)
    Assert-Igual 0 $real.Count ('violacoes no www real: ' + (Format-Violacoes $real))
}

# O www real tem os 24 arquivos da direcao 7.3, nem um a mais nem um a menos.
T 'www real: os 24 arquivos da direcao 7.3, nos dois sentidos' {
    Assert-Igual 24 $script:ArquivosWww.Count 'tamanho da lista da direcao'
    $wwwReal = (Get-Item -LiteralPath (Join-Path $raiz 'web\www')).FullName.TrimEnd('\')
    $reais = @(Get-ChildItem -LiteralPath $wwwReal -File -Recurse | ForEach-Object { $_.FullName.Substring($wwwReal.Length + 1) })
    $sobram = @($reais | Where-Object { $script:ArquivosWww -notcontains $_ } | Sort-Object)
    $faltam = @($script:ArquivosWww | Where-Object { $reais -notcontains $_ })
    Assert-Igual '' ($sobram -join ', ') 'no www e fora da lista'
    Assert-Igual '' ($faltam -join ', ') 'na lista e fora do www'
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
