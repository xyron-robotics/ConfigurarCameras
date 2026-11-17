<#
.SYNOPSIS
    Abre uma frente de trabalho: worktree isolado em <raiz>\.claude\worktrees\<nome>,
    branch curto wt/<nome>, a partir do branch corrente da raiz.
.DESCRIPTION
    Regime de paralelismo (porta do Connect_VPS, que veio do Liro): a RAIZ so
    integra; toda edicao acontece num worktree por frente. Dois agentes na mesma
    arvore = escrita perdida em silencio, nao conflito de merge.

    Funciona de qualquer pasta do repo (raiz ou outro worktree): a raiz principal
    vem de `git rev-parse --git-common-dir`, nunca se cria worktree aninhado.
    Idempotente: worktree ja registrado => imprime o caminho e sai 0.

    Linha de origem: grava `branch.wt/<nome>.frenteLinha = <Base>`. O
    frente-fechar recusa integrar quando a raiz nao esta mais nessa linha.

    Este projeto nao tem venv: a regua roda no powershell.exe (5.1) direto do
    worktree.
.PARAMETER Frente
    Nome da frente: ^[A-Za-z0-9._-]{1,40}$ (vira o diretorio e o sufixo de wt/<nome>).
.PARAMETER Base
    Ref de partida. Padrao: branch corrente da raiz (main).
.EXAMPLE
    .\scripts\frente-abrir.ps1 -Frente motor
    # depois, como 1a acao do agente:  EnterWorktree path=<raiz>\.claude\worktrees\motor
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Frente,

    [string]$Base = ""
)

$ErrorActionPreference = "Stop"

if ($Frente -notmatch '^[A-Za-z0-9._-]{1,40}$') {
    throw "[frente-abrir] nome de frente invalido '$Frente' (use [A-Za-z0-9._-], ate 40 caracteres)"
}

function Normalize-Path([string]$p) {
    return ($p -replace '/', '\').TrimEnd('\').ToLowerInvariant()
}

# --- raiz PRINCIPAL, mesmo rodando de dentro de um worktree ---
# Canonico PELO GIT (nao Resolve-Path): o git resolve subst/junction para o
# caminho real e e esse caminho que ele registra em `worktree list`.
$commonDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $commonDir) {
    throw "[frente-abrir] nao estou dentro de um repo git"
}
$commonDir = ($commonDir -replace '/', '\').TrimEnd('\')   # <raiz>\.git
$raiz = Split-Path -Parent $commonDir

$wtDir = Join-Path $raiz ".claude\worktrees\$Frente"
$branch = "wt/$Frente"

# --- idempotente: ja registrado? ---
$registered = git -C $raiz worktree list --porcelain |
    Where-Object { $_ -like "worktree *" } |
    ForEach-Object { $_.Substring(9) }
$already = $registered | Where-Object { (Normalize-Path $_) -eq (Normalize-Path $wtDir) }
if ($already) {
    Write-Host "[frente-abrir] worktree ja existe: $wtDir" -ForegroundColor Yellow
    Write-Host "EnterWorktree path=$wtDir"
    exit 0
}

# --- branch sobrando sem worktree (sobra de um -Remove interrompido) ---
git -C $raiz rev-parse --verify --quiet "refs/heads/$branch" *> $null
if ($LASTEXITCODE -eq 0) {
    throw "[frente-abrir] branch $branch ja existe sem worktree (sobra de um -Remove interrompido). " +
          "Confira com 'git log $branch -3'; se nao tiver nada que preste: git branch -D $branch. Ou escolha outro nome."
}

# --- base: branch corrente da raiz ---
if (-not $Base) {
    $Base = (git -C $raiz rev-parse --abbrev-ref HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $Base -or $Base -eq "HEAD") {
        throw "[frente-abrir] raiz em HEAD destacado; passe -Base <ref> explicitamente"
    }
}

Write-Host "[frente-abrir] git worktree add `"$wtDir`" -b $branch $Base"
$addOut = & git -C $raiz worktree add --quiet $wtDir -b $branch $Base 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "[frente-abrir] git worktree add falhou (exit $LASTEXITCODE): $($addOut -join "`n")"
}

# --- linha de origem: o frente-fechar recusa integrar se a raiz mudou de linha ---
& git -C $raiz config "branch.$branch.frenteLinha" $Base 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Warning "[frente-abrir] nao gravei branch.$branch.frenteLinha=$Base; o frente-fechar vai pedir (ou -Force)"
}

Write-Host ""
Write-Host "[frente-abrir] pronto: $wtDir" -ForegroundColor Green
Write-Host "               branch $branch (base $Base; linha registrada em branch.$branch.frenteLinha)"
Write-Host ""
Write-Host "1a acao do agente, ANTES de qualquer edicao:"
Write-Host "EnterWorktree path=$wtDir"
Write-Host "Ao fechar (integra em $Base, so local, sem push):"
Write-Host "  .\scripts\frente-fechar.ps1 -Frente $Frente -Apply     (-Remove quando a frente acabar)"
