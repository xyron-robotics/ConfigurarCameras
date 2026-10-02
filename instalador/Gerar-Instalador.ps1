<#
    Gerar-Instalador.ps1
    Gera o instalador do painel (Inno Setup 6) em instalador\saida\, com o
    .sha256 ao lado (formato sha256sum). E o mesmo script que o GitHub
    Actions roda no push de uma tag v* (.github\workflows\release.yml).

    Antes de compilar: roda Testes-Motor.ps1 e Testes-Descoberta.ps1 (aborta
    se algum falhar) e confere a lista [Files] do .iss: sem coringa, sem
    *.local.ps1, todo arquivo existente. A saida e ignorada pelo git.

    A versao vem de fonte\VERSAO.txt (ou -Versao, que passa /DVersao= ao
    ISCC: serve para gerar um instalador de teste com outro numero).

    Uso:
        .\Gerar-Instalador.ps1
        .\Gerar-Instalador.ps1 -Iscc 'D:\Inno Setup 6\ISCC.exe'
        .\Gerar-Instalador.ps1 -SemTestes     (so para depurar o .iss)
        .\Gerar-Instalador.ps1 -Versao 9.9.9  (instalador de teste da atualizacao)
#>
[CmdletBinding()]
param(
    [string]$Iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    [switch]$SemTestes,
    [string]$Versao = ''
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$iss  = Join-Path $PSScriptRoot 'ConfigurarCameras.iss'

if (-not (Test-Path -LiteralPath $Iscc)) {
    throw ("ISCC.exe nao encontrado em " + $Iscc + ". Instale o Inno Setup 6 (jrsoftware.org) ou passe -Iscc.")
}

if ([string]::IsNullOrWhiteSpace($Versao)) {
    $Versao = ([IO.File]::ReadAllText((Join-Path $raiz 'fonte\VERSAO.txt'))).Trim()
}
if ($Versao -notmatch '^\d+\.\d+\.\d+$') { throw ("versao invalida: '" + $Versao + "' (use x.y.z)") }

if (-not $SemTestes) {
    foreach ($t in @('Testes-Motor.ps1', 'Testes-Descoberta.ps1')) {
        Write-Host ("== " + $t) -ForegroundColor Cyan
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $raiz ('fonte\' + $t))
        if ($LASTEXITCODE -ne 0) { throw ($t + " falhou: instalador nao gerado.") }
    }
}

# Lista explicita de arquivos: a senha local nunca pode entrar no pacote.
$fontes = @(Select-String -Path $iss -Pattern '^Source:\s*"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value })
if ($fontes.Count -eq 0) { throw "nenhum Source: no [Files] do .iss" }
foreach ($f in $fontes) {
    if ($f -match '[\*\?]') { throw ("coringa no [Files] (" + $f + "): a lista tem que ser explicita") }
    if ($f -match '\.local\.ps1$' -or $f -match 'senha') { throw ("arquivo proibido no instalador: " + $f) }
    # Caminho relativo ao .iss: {#Raiz}\... e a raiz do repo; sem prefixo e a pasta instalador\.
    $caminho = Join-Path $PSScriptRoot ($f -replace '\{#Raiz\}', '..')
    if (-not (Test-Path -LiteralPath $caminho)) { throw ("arquivo do [Files] nao existe: " + $caminho) }
}
Write-Host ("[Files] conferido: " + $fontes.Count + " arquivos, nenhum *.local.ps1") -ForegroundColor Gray

& $Iscc /Q ("/DVersao=" + $Versao) $iss
if ($LASTEXITCODE -ne 0) { throw ("ISCC falhou com codigo " + $LASTEXITCODE) }

# O nome e exato (o painel baixa pelo nome do asset no release).
$exe = Join-Path $PSScriptRoot ('saida\ConfigurarCameras-' + $Versao + '-instalador.exe')
if (-not (Test-Path -LiteralPath $exe)) { throw ("o ISCC nao gerou " + $exe) }

$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
$sha = $exe + '.sha256'
[IO.File]::WriteAllText($sha, ($hash + '  ' + (Split-Path -Leaf $exe) + "`n"), (New-Object Text.UTF8Encoding($false)))

$tam = [math]::Round((Get-Item -LiteralPath $exe).Length / 1KB)
Write-Host ("Instalador " + $Versao + ": " + $exe + " (" + $tam + " KB)") -ForegroundColor Green
Write-Host ("SHA-256   : " + $hash + "  -> " + (Split-Path -Leaf $sha)) -ForegroundColor Gray
