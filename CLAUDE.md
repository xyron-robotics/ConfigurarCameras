# CLAUDE.md: ConfigurarCameras

Painel local (PowerShell 5.1 + navegador) que leva câmeras Intelbras/Dahua de fábrica a câmeras instaladas. Vocabulário em `CONTEXT.md`; uso e pendências em `LEIA-ME.md`; protocolo das câmeras em `fonte/API-INTELBRAS.md`.

## Comandos

```powershell
.\scripts\frente-abrir.ps1 -Frente <nome>            # worktree em .claude\worktrees\<nome>, branch wt/<nome>
.\scripts\frente-fechar.ps1 -Frente <nome> -Apply    # rebase + fast-forward em main, SÓ LOCAL (dry-run sem -Apply)
powershell.exe -File fonte\web\Servidor-Painel.ps1 -Simular -Porta 8765   # painel em simulação, sem hardware
```

### Validação

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Motor.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Descoberta.ps1
if (Test-Path fonte\Testes-Orquestrador.ps1) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Orquestrador.ps1 }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Coordenador.ps1
git diff --check
```

Os testes rodam no PowerShell 5.1 (`powershell.exe`), o mesmo do painel e do CI (`.github/workflows/release.yml`). A contagem de testes não mora aqui: rode e leia a saída.

## Regras para quem edita

- **Repo público.** Nunca entram MAC, serial, IP, senha ou nome de obra reais da bancada. Fixtures e documentos usam valores fictícios (MACs `AA:00:00:00:00:0x`, seriais `SIM-x`, câmeras A/B/C). Antes do commit, `git diff --cached` não pode ter dado real.
- **Sem push.** Nem `frente-fechar` faz push. O push só acontece na release por tag, com aprovação explícita do usuário.
- **Sem rede nem hardware reais** (placa de rede, câmeras, `New-NetIPAddress`, `New-NetNeighbor` de verdade) fora de Task de bancada marcada `[você]` no plano. Teste de rede usa funções injetáveis/falsas.
- `fonte/web/Servidor-Painel.ps1` é UTF-8 **com BOM** (há teste para isso). Os demais `.ps1` seguem a codificação que já têm.
- Arquivo de teste novo entra em `.github/workflows/release.yml` e em `instalador/Gerar-Instalador.ps1`; arquivo novo que vai para o usuário entra em `instalador/ConfigurarCameras.iss`.
- Textos de UI em pt-BR, em caixa de frase. Mobile fora do escopo.

## Planos

Planos em `docs/plans/`, com `**Status:**` Draft | Ativo | Concluído | Superado. Plano de frente para o `/regime:maestro` tem `**Frente:**` no cabeçalho e `## Task N:`. O mapa do trabalho em curso é `docs/plans/2026-11-cameras-em-paralelo.md`.
