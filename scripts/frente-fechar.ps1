<#
.SYNOPSIS
    Fecha (integra) uma frente: rebase de wt/<nome> sobre o branch da raiz e
    fast-forward na raiz. SO LOCAL: nunca faz fetch nem push. Dry-run por padrao;
    -Apply executa; -Remove tambem apaga o worktree.
.DESCRIPTION
    Regime de paralelismo (porta do Connect_VPS, que veio do Liro). Historico
    linear: nada de merge commit. Este script e o unico caminho de um worktree
    ate o branch da linha.

    Diferenca deliberada da origem: aqui NAO ha fetch nem push. O repo do GitHub
    e publico e o push so acontece na release (tag), com aprovacao explicita do
    usuario (docs/plans/2026-11-cameras-em-paralelo.md, secao 9).

    Ordem (com -Apply):
      0. guarda de linha: a frente nasceu de uma linha (branch.wt/<nome>.frenteLinha,
         gravado pelo frente-abrir); a raiz tem que estar NELA. -Force ignora.
      1. guardas: worktree limpo, raiz limpa, com -Remove o cwd nao pode estar
         dentro do worktree.
      2. git -C <wt> rebase <branch da raiz>   (conflito => --abort + instrucao, exit 1)
      3. git -C <raiz> merge --ff-only wt/<nome>
      4. com -Remove: git worktree remove + git branch -d wt/<nome>

    Sem -Remove o worktree continua e wt/<nome> == ponta do branch da linha.
.PARAMETER Frente
    Nome da frente aberta por frente-abrir.ps1.
.PARAMETER Apply
    Executa. Sem ele, so imprime o que faria.
.PARAMETER Remove
    Implica -Apply. Depois de integrar, remove o worktree e o branch wt/<nome>.
.PARAMETER Force
    Ignora a guarda de linha.
.EXAMPLE
    .\scripts\frente-fechar.ps1 -Frente motor            # dry-run
    .\scripts\frente-fechar.ps1 -Frente motor -Apply     # integra, worktree fica
    .\scripts\frente-fechar.ps1 -Frente motor -Remove    # integra e apaga o worktree
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Frente,

    [switch]$Apply,
    [switch]$Remove,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
if ($Remove) { $Apply = $true }
$mode = if ($Apply) { "APPLY" } else { "DRY-RUN" }

if ($Frente -notmatch '^[A-Za-z0-9._-]{1,40}$') {
    throw "[frente-fechar] nome de frente invalido '$Frente'"
}

function Normalize-Path([string]$p) {
    return ($p -replace '/', '\').TrimEnd('\').ToLowerInvariant()
}

function Git-Run([string]$dir, [string[]]$gitArgs) {
    # Executa e FALHA alto: qualquer exit != 0 vira excecao com stderr.
    $out = & git -C $dir @gitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "[frente-fechar] git $($gitArgs -join ' ') (em $dir) falhou: $($out -join "`n")"
    }
    return ($out | Out-String).Trim()
}

function Git-Try([string]$dir, [string[]]$gitArgs) {
    # Executa e devolve $null em falha (para sondas).
    $out = & git -C $dir @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($out | Out-String).Trim()
}

function Step([string]$msg) { Write-Host "[$mode] $msg" }

# --- raiz PRINCIPAL, mesmo rodando de dentro de um worktree ---
$commonDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $commonDir) { throw "[frente-fechar] nao estou dentro de um repo git" }
$commonDir = ($commonDir -replace '/', '\').TrimEnd('\')
$raiz = Split-Path -Parent $commonDir

$wtDir = Join-Path $raiz ".claude\worktrees\$Frente"
$branch = "wt/$Frente"

$registered = git -C $raiz worktree list --porcelain |
    Where-Object { $_ -like "worktree *" } |
    ForEach-Object { $_.Substring(9) }
$found = $registered | Where-Object { (Normalize-Path $_) -eq (Normalize-Path $wtDir) } | Select-Object -First 1
if (-not $found) {
    $frentes = ($registered | Where-Object { (Normalize-Path $_) -like "*\.claude\worktrees\*" } |
        ForEach-Object { Split-Path -Leaf $_ }) -join ", "
    throw "[frente-fechar] worktree da frente '$Frente' nao existe ($wtDir). Frentes abertas: $frentes"
}
$wtDir = ($found -replace '/', '\').TrimEnd('\')   # exatamente como o git registrou
if ($null -eq (Git-Try $raiz @("rev-parse", "--verify", "--quiet", "refs/heads/$branch"))) {
    throw "[frente-fechar] branch $branch nao existe (worktree em outro branch?). Confira: git -C `"$wtDir`" branch --show-current"
}

$linhaRaiz = Git-Run $raiz @("rev-parse", "--abbrev-ref", "HEAD")
if (-not $linhaRaiz -or $linhaRaiz -eq "HEAD") {
    throw "[frente-fechar] raiz em HEAD destacado; faca checkout de main na raiz"
}

# ================= 0. GUARDA DE LINHA =================
$linha = Git-Try $raiz @("config", "--get", "branch.$branch.frenteLinha")
if (-not $Force) {
    if (-not $linha) {
        throw "[frente-fechar] frente '$Frente' sem linha registrada. Se a raiz ($linhaRaiz) E a linha desta frente: git -C `"$raiz`" config branch.$branch.frenteLinha $linhaRaiz  e rode de novo. -Force integra em $linhaRaiz sem checar. Nada foi feito."
    }
    if ($linha -ne $linhaRaiz) {
        throw "[frente-fechar] frente '$Frente' nasceu da linha '$linha', mas a raiz esta em '$linhaRaiz'. Volte a raiz para '$linha', ou -Force para integrar em $linhaRaiz mesmo. Nada foi feito."
    }
}

Write-Host "[frente-fechar] frente=$Frente  worktree=$wtDir"
Write-Host "                $branch  ->  $linhaRaiz (raiz $raiz; frenteLinha=$linha; sem push)"
Write-Host ""

# ================= 1. GUARDAS =================
$wtDirty = Git-Run $wtDir @("status", "--porcelain")
if ($wtDirty) {
    Write-Host $wtDirty
    throw "[frente-fechar] worktree SUJO. Commite POR PATH no worktree (git add <arquivos da frente> && git commit) e rode de novo. Nada foi feito."
}

$raizDirty = Git-Run $raiz @("status", "--porcelain")
if ($raizDirty) {
    Write-Host $raizDirty
    throw "[frente-fechar] RAIZ suja: trabalho fora do regime (a raiz nao edita). Quem deixou isso precisa leva-lo para o seu worktree antes do fast-forward. Nada foi feito."
}

if ($Remove) {
    $cwdTop = git rev-parse --path-format=absolute --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $cwdTop -and (Normalize-Path $cwdTop) -eq (Normalize-Path $wtDir)) {
        throw "[frente-fechar] -Remove com o cwd DENTRO do worktree da frente. Saia primeiro (ExitWorktree keep, ou cd para a raiz) e rode de novo. Nada foi feito."
    }
}

# ================= 2. REBASE =================
$toIntegrate = [int](Git-Run $wtDir @("rev-list", "--count", "$linhaRaiz..$branch"))
$wtBehind    = [int](Git-Run $wtDir @("rev-list", "--count", "$branch..$linhaRaiz"))
$tipBefore   = Git-Run $raiz @("rev-parse", "--short", $linhaRaiz)

if ($toIntegrate -eq 0) {
    Step "nada a integrar: $branch nao tem commit fora de $linhaRaiz (worktree $wtBehind atras)"
} else {
    Step "commits a integrar ($toIntegrate):"
    (Git-Run $wtDir @("log", "--oneline", "$linhaRaiz..$branch")) -split "`r?`n" | ForEach-Object { Write-Host "    $_" }
}

if ($wtBehind -gt 0) {
    Step "rebase: git -C worktree rebase $linhaRaiz  ($wtBehind commit(s) novos embaixo)"
    if ($Apply) {
        $rb = & git -C $wtDir rebase $linhaRaiz 2>&1
        if ($LASTEXITCODE -ne 0) {
            & git -C $wtDir rebase --abort 2>&1 | Out-Null
            Write-Host ($rb | Out-String)
            throw "[frente-fechar] CONFLITO no rebase de $branch sobre ${linhaRaiz}: abortado, worktree como estava. Resolva no worktree (git rebase $linhaRaiz, resolver, git rebase --continue) e rode de novo. Raiz intocada."
        }
    }
} else {
    Step "rebase desnecessario: $branch ja esta em cima de $linhaRaiz"
}

# ================= 3. FAST-FORWARD NA RAIZ =================
if ($toIntegrate -gt 0) {
    Step "fast-forward: git -C raiz merge --ff-only $branch"
    if ($Apply) { Git-Run $raiz @("merge", "--ff-only", $branch) | Out-Null }
}
Step "push: nunca por este script (so na release, com aprovacao)"

# ================= 4. REMOVE =================
if ($Remove) {
    Step "remove: git worktree remove `"$wtDir`" && git branch -d $branch"
    if ($Apply) {
        Git-Run $raiz @("worktree", "remove", $wtDir) | Out-Null
        Git-Run $raiz @("branch", "-d", $branch) | Out-Null
        # `worktree remove` as vezes deixa o diretorio vazio para tras (medido no Liro)
        if ((Test-Path $wtDir) -and -not (Get-ChildItem $wtDir -Force)) { Remove-Item $wtDir }
    }
}

# ================= RESUMO =================
Write-Host ""
$tipAfter = Git-Run $raiz @("rev-parse", "--short", $linhaRaiz)
Write-Host "[frente-fechar] $mode concluido" -ForegroundColor Green
Write-Host "  integrados : $toIntegrate commit(s) de $branch"
Write-Host "  $linhaRaiz : $tipBefore -> $tipAfter (local; origin intocado)"
if ($Remove) {
    Write-Host "  worktree   : removido ($wtDir)"
} else {
    Write-Host "  worktree   : mantido ($wtDir); $branch == $linhaRaiz"
}
$rest = git -C $raiz worktree list --porcelain | Where-Object { $_ -like "worktree *" } | ForEach-Object { Split-Path -Leaf $_.Substring(9) }
Write-Host "  worktrees  : $($rest -join ', ')"
if (-not $Apply) { Write-Host ""; Write-Host "Nada foi alterado (dry-run). Repita com -Apply (ou -Remove)." -ForegroundColor Yellow }
