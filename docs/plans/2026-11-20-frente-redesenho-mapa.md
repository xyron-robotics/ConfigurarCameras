# Mapa da fase B do redesenho do painel

**Status:** Ativo

Índice das frentes que implementam a direção aprovada (`docs/design/2026-11-ux/direcao.md`) a partir do protótipo (`docs/design/2026-11-ux/prototipo/`). Escrito na Task 6 da frente `ux` (`docs/plans/2026-11-19-frente-ux-plan.md`), em 19/11. O redesenho vem antes da release 1.3.0; a release não faz parte deste mapa.

## Frentes, em ordem

Todas são **sequenciais**: cada uma mexe em `fonte/web/www/**` e no `instalador/ConfigurarCameras.iss`, e as frentes 2 a 5 dependem do teste `fonte/Testes-Front.ps1` que a frente 1 cria. Nenhuma roda em paralelo com outra. Cada frente abre com `.\scripts\frente-abrir.ps1 -Frente <nome>` depois de a anterior fechar (`frente-fechar -Apply`).

| # | Frente (`-Frente`) | Plano | Escopo | Depende de |
|---|---|---|---|---|
| 1 | `redesenho-arquitetura` | `docs/plans/2026-11-20-frente-redesenho-1-arquitetura-plan.md` | O front de hoje em módulos, tokens com os valores de hoje, `textos.js`, `constantes.js` e o `Testes-Front.ps1`. Sem mudança visual, provada por captura. Feita em 24/11/2026 | frente `ux` fechada |
| 2 | `redesenho-marca` | `docs/plans/2026-11-20-frente-redesenho-2-marca-plan.md` | Sistema visual da direção (seção 4) sobre o layout de hoje: tokens de marca e semânticos, tipo, ícones, logo, símbolo, favicon, `.png` no `$tipos`, `.iss`. Feita em 24/11/2026 | 1 |
| 3 | `redesenho-navegacao` | `docs/plans/2026-11-20-frente-redesenho-3-navegacao-plan.md` | Casca nova (topo, abas, chips, rotas, diálogo), passo a passo de 6 passos, Conferir e Sessão (antes "Opções"). Feita em 24/11/2026 | 2 |
| 4 | `redesenho-painel` | `docs/plans/2026-11-20-frente-redesenho-4-painel-plan.md` | Painel: fila, fita, tabela, linha da câmera, "Pede você", painel lateral do encoder, vigia, registro. Bug do `salvarCartao` | 3 |
| 5 | `redesenho-verificacao` | `docs/plans/2026-11-20-frente-redesenho-5-verificacao-plan.md` | Ferramentas, estados globais, saída do código de transição e verificação final (Playwright nos dois temas, `consistency.mjs`, `web-design-guidelines`, roteiro de duas filas, bancada) | 4 |

Paralela com: nenhuma (sobreposição de arquivo em todas).

## Ajustes ao esqueleto da Task 6 da frente `ux`, com o porquê

1. **Código de transição `legado-*.js` (estrangulamento).** A frente 1 não divide o `app.js` de hoje (1782 linhas, estado mutável compartilhado) em telas novas: move o que não é base para módulos `legado-*.js`, já sem texto, número, `fetch` nem valor visual soltos. As frentes 3, 4 e 5 trocam o legado tela a tela pelo código do protótipo, e a 5 apaga o último `legado-*.js`. *Porquê:* dividir em telas um código que as frentes 3 e 4 reescrevem seria trabalho jogado fora. O que a frente 1 cria e fica (tokens, camadas, `api.js`, `dom.js`, `textos.js`, `constantes.js`, `formato.js`, o teste) é o que o resto usa. Entre uma frente e outra o painel funciona inteiro e pode ir para release.
2. **A frente 1 tira a linha de base de paridade antes de mexer.** Sem mudança visual só se prova comparando capturas do antes e do depois.
3. **O diálogo de confirmação próprio (direção 5.8) nasce na frente 3**, que tem o primeiro uso (Encerrar o painel no topo). A frente 4 o reusa para Pular e Encerrar a fila.
4. **A caixa do broadcast vai para Sessão > Rede na frente 4**, e não na 3, porque sai da área do vigia, que só a frente 4 refaz.
5. **A faixa do modo de reserva fica na frente 4** (é do vigia). As outras faixas e estados globais (Abrindo, conexão perdida, Encerrado, atualização) ficam na 5, como no esqueleto.
6. **A frente 5 tem uma Task de bancada `[você]`** com uma câmera de fábrica real. Os estados reais da placa (chip em alarme, preparar, restaurar o DHCP) e a senha real não se reproduzem em simulação.
7. **Os rótulos que a direção substitui viram textos proibidos** no teste "Front paralelo" de `fonte/Testes-Motor.ps1`, na frente que migra cada um (coluna "Substitui" do glossário, direção seção 6). Assim o texto velho não volta.
8. **Nomes dos arquivos:** data 20 e `frente-redesenho-` no nome para caber no `Touched` da frente `ux` (`docs/plans/2026-11-2*-frente-redesenho-*.md`).

## Decisões do usuário que a fase B carrega (Task 6 da frente `ux`, 19/11)

- Protótipo aprovado como está.
- Opções passa a se chamar Sessão.
- No tema escuro, a logo oficial sobre uma placa clara, em definitivo. A variante derivada (`marca/logo-smartseg-escuro.png`) não entra no `www`.
- Sem foco automático na falha: anúncio `aria-live`, a linha da câmera e o bloco "Pede você".
- Sem logo vetorial: os arquivos servidos derivam do PNG de 2302 px por redução (`prototipo/logo.png`, `prototipo/simbolo.png`).

## Ajuste de 23/11: frente 2 em paralelo com a frente 1

**Decisão do usuário (23/11):** acelerar a fase B abrindo a frente 2 antes de a frente 1 fechar ("paralelo agressivo"). Vale só para o par 1 e 2; as frentes 3 a 5 seguem sequenciais.

- **Base:** o worktree `redesenho-marca` nasce do commit da frente 1 com `Plano: docs/plans/2026-11-20-frente-redesenho-1-arquitetura-plan.md` e `Plano-Task: 3` (CSS em quatro camadas, `Testes-Front.ps1`), com `branch.wt/redesenho-marca.frenteLinha = main`, e recebe por `cherry-pick` o commit deste ajuste (o plano da frente 2 `Ativo`).
- **Abertura, na raiz, depois da Task 3 da frente 1:**
  ```powershell
  $t3 = git log wt/redesenho-arquitetura -1 --format=%H --all-match --grep "^Plano-Task: 3$" --grep "^Plano: docs/plans/2026-11-20-frente-redesenho-1-arquitetura-plan.md$"
  $aj = git log main -1 --format=%H -- docs/plans/2026-11-20-frente-redesenho-2-marca-plan.md
  .\scripts\frente-abrir.ps1 -Frente redesenho-marca -Base $t3
  git config branch.wt/redesenho-marca.frenteLinha main
  git -C .claude\worktrees\redesenho-marca cherry-pick $aj
  ```
  Depois, em outra sessão na raiz: `/regime:maestro docs/plans/2026-11-20-frente-redesenho-2-marca-plan.md`.
- **Sobreposição:** a Task 1 da frente 2 só mexe nos quatro CSS; a frente 1, nas Tasks 4 a 6, mexe em JS, `index.html`, `.iss`, `Testes-Motor.ps1` e, na Task 5, no que ainda violar. Porta 8765 para a frente 1, 8766 para a frente 2.
- **Ponto de espera:** a Task 2 da frente 2 devolve `BLOQUEADO` até a frente 1 estar `Concluído` no `main`; então `git rebase main` e a frente 2 segue sequencial.
- **Ordem de fechar:** a frente 1 fecha primeiro, sempre. A frente 2 não fecha antes, porque a guarda da Task 2 impede.
