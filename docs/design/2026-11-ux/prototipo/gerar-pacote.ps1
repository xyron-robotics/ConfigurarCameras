# PROTOTIPO. Junta os ES modules desta pasta em pacote.js (script classico) para o index.html
# abrir por file://, onde o navegador bloqueia modulos. Gera tambem modulos.html, que carrega
# app.js como modulo, para conferir por http que os modulos sao a fonte de verdade.
# Contrato com os modulos: import numa linha so, so exports nomeados, sem import circular.
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File gerar-pacote.ps1
$ErrorActionPreference = 'Stop'
$pasta = $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding $false
$reImport = '^import\s*\{([^}]*)\}\s*from\s*''\./([\w-]+)\.js'';\s*$'
$reExport = '^export\s+((?:async\s+)?(?:function|const|let|class)\s+([\w$]+))'

$modulos = @{}
foreach ($arq in Get-ChildItem -Path $pasta -Filter '*.js' | Where-Object { $_.Name -ne 'pacote.js' }) {
    $nome = $arq.BaseName
    $texto = [System.IO.File]::ReadAllText($arq.FullName, $utf8) -replace "`r`n", "`n"
    $deps = New-Object System.Collections.Generic.List[string]
    $cabeca = New-Object System.Collections.Generic.List[string]
    $corpo = New-Object System.Collections.Generic.List[string]
    $exports = New-Object System.Collections.Generic.List[string]
    foreach ($linha in $texto.Split("`n")) {
        if ($linha -match '^import\b') {
            if ($linha -notmatch $reImport) { throw "$($arq.Name): import fora do contrato: $linha" }
            $origem = $Matches[2]
            $nomes = ($Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) |
                ForEach-Object { $_ -replace '^([\w$]+)\s+as\s+([\w$]+)$', '$1: $2' }
            $deps.Add($origem)
            $cabeca.Add("  const { $($nomes -join ', ') } = __m['$origem'];")
        } elseif ($linha -match '^export\b') {
            if ($linha -notmatch $reExport) { throw "$($arq.Name): export fora do contrato: $linha" }
            $exports.Add($Matches[2])
            $corpo.Add('  ' + ($linha -replace '^export\s+', ''))
        } elseif ($linha -eq '') {
            $corpo.Add('')
        } else {
            $corpo.Add('  ' + $linha)
        }
    }
    $modulos[$nome] = @{ deps = $deps; cabeca = $cabeca; corpo = $corpo; exports = $exports }
}

$ordem = New-Object System.Collections.Generic.List[string]
$visitando = @{}
function Visitar([string]$nome) {
    if ($ordem.Contains($nome)) { return }
    if (-not $modulos.ContainsKey($nome)) { throw "modulo ausente: $nome" }
    if ($visitando[$nome]) { throw "import circular em $nome" }
    $visitando[$nome] = $true
    foreach ($d in $modulos[$nome].deps) { Visitar $d }
    $ordem.Add($nome)
}
Visitar 'app'

$saida = New-Object System.Collections.Generic.List[string]
$saida.Add('// GERADO por gerar-pacote.ps1 a partir dos modulos desta pasta. Nao edite: edite o modulo e gere de novo.')
$saida.Add('(function () {')
$saida.Add("  'use strict';")
$saida.Add('  const __m = {};')
foreach ($nome in $ordem) {
    $m = $modulos[$nome]
    $saida.Add('')
    $saida.Add("  // ---- $nome.js")
    $saida.Add("  __m['$nome'] = (function () {")
    foreach ($l in $m.cabeca) { $saida.Add('  ' + $l) }
    foreach ($l in $m.corpo) { if ($l -eq '') { $saida.Add('') } else { $saida.Add('  ' + $l) } }
    $saida.Add("    return { $($m.exports -join ', ') };")
    $saida.Add('  })();')
}
$saida.Add('})();')
$js = (($saida | ForEach-Object { $_.TrimEnd() }) -join "`n") + "`n"
[System.IO.File]::WriteAllText((Join-Path $pasta 'pacote.js'), $js, $utf8)

$html = [System.IO.File]::ReadAllText((Join-Path $pasta 'index.html'), $utf8) -replace "`r`n", "`n"
$marca = '<script src="pacote.js" defer></script>'
if (-not $html.Contains($marca)) { throw 'index.html sem a tag do pacote' }
$html = $html.Replace($marca, '<script type="module" src="app.js"></script>')
$html = $html -replace '<title>([^<]*)</title>', '<title>$1 (modulos)</title>'
[System.IO.File]::WriteAllText((Join-Path $pasta 'modulos.html'), $html, $utf8)

"pacote.js: $($ordem.Count) modulos ($($ordem -join ', '))"
