# Frente ui: Taste Skill, guidelines em JS e verificação visual (F2b, F3 e F4 do plano de UI)

**Status:** Concluído · **Frente:** `ui`

F2b, F3 e F4 do plano de UI estão feitas (Tasks 1 a 9); a Onda 2 do mapa `docs/plans/2026-11-cameras-em-paralelo.md` pode começar.

**Origem:** plano de UI `declarative-wobbling-rain.md` (fora do repo, aprovado). F1 (tema) está em 07b83c4 e F2 (guidelines em HTML e CSS) em 0d0581a. Este arquivo traz o que falta, e a partir daqui ele é a fonte. Os números de linha do plano de origem andaram com F1 e F2: localize pelo nome da função ou do seletor.

**Goal:** terminar a revisão de UI do painel. Sistema de movimento, escala e contraste da Taste Skill (F2b), guidelines em JS (F3) e verificação visual de ponta a ponta em claro e escuro, com Playwright, o checker da Taste Skill e uma nova passada da `web-design-guidelines` (F4). O fechamento desta frente é o ponto de rebase da Onda 2 do mapa `docs/plans/2026-11-cameras-em-paralelo.md`.

**Non-Goals:**
- servidor (`Servidor-Painel.ps1`), motor e orquestrador. Se uma Task precisar mexer no servidor, devolva `BLOQUEADO`;
- bancada com N cartões (F6 do mapa, Onda 3);
- mobile;
- herói, fotos, efeitos, "uma seção por tela", fontes web (a CSP barra), voz de marca: a Taste Skill é de marketing e só entra a parte de sistema, movimento, formulário e copy.

**Touched:** `fonte/web/www/app.css`, `fonte/web/www/index.html`, `fonte/web/www/app.js`, `docs/plans/2026-11-17-frente-ui-plan.md` (só a Task 10).

**Safety:**
- Painel só em simulação, com pasta de dados própria e porta fixa, rodando do **worktree**:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-ui
  ```

  - sem `-PastaDados`, a instância única lê o `painel.json` de `%ProgramData%` e pode reabrir o painel instalado;
  - porta 8765 ocupada: use 8766 e diga no commit;
  - o painel fecha sozinho com 180 s sem página; ao terminar, encerre o processo que você subiu.
- Há 3 câmeras de fábrica ligadas na bancada. Se o painel simulado mostrar qualquer câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`, pare e devolva `BLOQUEADO`: a simulação estaria tocando rede real.
- Capturas de tela ficam no scratchpad ou em `.playwright-mcp/` (ignorado). Nenhuma entra no repo.
- **Nunca** rodar `gate.mjs --start` nem `start.mjs` da Taste Skill neste repo. O Stop hook dela não faz nada sem `.taste-skill/`; não crie essa pasta.
- Textos em pt-BR, caixa de frase. A regra "Title Case" da skill é do inglês e não se aplica.

**Decisões (do plano de origem):**
- Corpo continua em 15 px: console denso a 1366×768. Os 16 px da skill valem para marketing.
- Botão e campo com 38 px de altura. É painel de mouse: dispensa 44/48.
- `confirm()` nativo vale como confirmação de ação destrutiva.
- Re-render da `#fita` e foco em `montarPasso` a cada poll: só mexer se a verificação da Task 8 mostrar defeito.
- Âmbar significa "agora".

## Task 1: Taste Skill, movimento e estados de controle

**Files:** `fonte/web/www/app.css`

- Invoque a skill `design-taste-frontend` antes de editar e use só a parte de sistema, movimento e formulário.
- Itens 1 a 5 do plano de origem:
  1. tokens em `:root`: `--m-in:150ms; --m-out:120ms; --m-press:90ms; --ease:cubic-bezier(.2,.8,.2,1)`;
  2. botões: `transition` em background-color, border-color e color (120 ms) e transform (90 ms); `:active { transform: translateY(1px) scale(.985) }`; hover do acento por `color-mix(in oklab, var(--acento) 86%, var(--texto))` no lugar de `filter: brightness`; sem lift;
  3. disabled sem `opacity:.5`: `color: var(--apoio)`, `background: var(--sup-2)` e borda tracejada, como `input:disabled`;
  4. `prefers-reduced-motion: reduce`: o botão não se move, o press vira um tom mais fundo, e o pulso da etapa atual para. Fora do reduce, o pulso vai de 1.6 s para 3.2 s;
  5. campo: `transition` de border-color e box-shadow em 120 ms; `:focus-visible` instantâneo (duração 0).

**Validation:** a régua; `Select-String` em `app.css` sem `opacity: *\.5` em seletor de disabled e com o bloco `prefers-reduced-motion`.

## Task 2: escalas, tipografia e altura

**Files:** `fonte/web/www/app.css`

- Itens 6 a 8:
  - espaço `--s-1..--s-6` = 4/8/12/16/24/32 px; paddings de `.passo`, `.bancada`, `.secao` e `.ferramenta` em `--s-4`/`--s-5`;
  - raio `--r-sm:4px` (controle, fita, etapas) e `--r-md:8px` (cartões); somem os `3px` fixos;
  - piso de 13 px em selo, fita, `.sit-detalhe` e `passo-botao`; log mono em 12.5 px; `label { font-weight: 500 }`; textos de ajuda com `max-width: 64ch`;
  - botão e campo com 38 px, alinhados em `.linha-campos`.

**Validation:** a régua; `Select-String 'border-radius: *3px'` em `app.css` sem resultado.

## Task 3: contraste, hierarquia e detalhes

**Files:** `fonte/web/www/app.css`, `fonte/web/www/index.html`

- Itens 9 a 15:
  - contraste: calcule `--apoio` sobre `--fundo` e `--sup` nos dois temas (fórmula WCAG; anote os números no commit). Abaixo de 4.5:1, texto de instrução (`.explica`, `.apoio` de parágrafo) passa a `--texto`. "Selecionado" ganha contorno em `--texto` ou marca, além da borda âmbar;
  - âmbar = "agora": a barra lateral de 6 px fica só em passo atual, bancada e etapa em curso; `.painel-sem-fila` usa `--linha`;
  - no máximo dois níveis de caixa: `.passo-escolha` e `fieldset` perdem o fundo próprio;
  - `--linha` = `color-mix(in oklab, var(--texto) 12%, transparent)`;
  - links em texto: sublinhado em `--linha`, `text-underline-offset: 3px`, `currentColor` no hover;
  - `tr:hover td { background: var(--sup-2) }`;
  - `scroll-margin-top` maior que a altura da `.faixa-simular` (sticky) em `.passo`, `.bancada`, `.secao` e nos campos.

**Validation:** a régua; contrastes calculados no corpo do commit, todos ≥ 4.5:1 para texto.

## Task 4: copy

**Files:** `fonte/web/www/app.js`, `fonte/web/www/index.html`

- Item 16: NBSP entre número e unidade (fps, kbps); botão com verbo e objeto onde hoje é genérico ("Avançar" fica, é do passo a passo); sem "simplesmente", "realmente" nem "!".
- Antes de trocar texto, `git grep` pelo texto antigo em `fonte/`: teste ou servidor que procure a string muda junto só se estiver no Touched; senão `BLOQUEADO`.
- O item 17 (um botão acento por vista) é conferido na Task 8.

**Validation:** a régua; `Select-String '!"'` e `'simplesmente|realmente'` nos dois arquivos sem resultado de texto de UI.

## Task 5: Intl para data e número

**Files:** `fonte/web/www/app.js`

- `Intl.DateTimeFormat('pt-BR')` no lugar de `dataCurta` e de `toLocaleTimeString`, e na data do registro. O timestamp do log continua a hora fixa do servidor.
- `Intl.NumberFormat('pt-BR')` em fps, kbps e na contagem da prévia.

**Validation:** a régua; `Select-String 'toLocaleTimeString'` em `app.js` sem resultado.

## Task 6: live regions, foco e estado vazio

**Files:** `fonte/web/www/app.js`, `fonte/web/www/index.html`

- `aria-live="polite"` em `#trabalho-texto`, `#vigia-texto`, `#resultado-ferramenta` e `#camera-avisos`.
- `#encerrado` e `#atualizando` com `tabindex="-1"` e foco ao aparecer.
- Em `desenharPlacas`, o texto "Nenhuma placa…" é sobrescrito logo depois de escrito. Corrigir para o estado vazio aparecer.

**Validation:** a régua; os quatro ids com `aria-live` em `index.html`.

## Task 7: confirmação e formulário sujo

**Files:** `fonte/web/www/app.js`

- "Montar fila" em Opções troca a fila atual: `confirm()` quando já houver fila com posições, com texto que diga quantas posições se perdem.
- `beforeunload` quando alguma seção estiver `sujo`.

**Validation:** a régua.

## Task 8: verificação visual com Playwright

**Files:** `fonte/web/www/app.css`, `fonte/web/www/index.html`, `fonte/web/www/app.js` (só correções do que a verificação achar)

- Suba o painel como na Safety. `browser_navigate` para `http://127.0.0.1:8765/`, navegação comum, sem forjar header. Janela 1366×768.
- Para {Sistema com `emulate_media` light e dark, Claro forçado, Escuro forçado} × telas: passo a passo 1 a 7; Painel (sem fila, com fila, bancada em trabalho, falha em simulação); Ferramentas; Opções (todas as seções e o seletor de tema); log aberto. Uma captura por combinação.
- Conferir: contraste; `select` legível no escuro; anel de foco visível no Tab; nenhum flash ao recarregar com tema forçado; `theme-color`; `browser_console_messages` sem erro nem violação de CSP; um botão acento por vista visível (item 17).
- Recarregar: o tema persiste. Encerrar e subir em outra porta (8766) com a mesma `-PastaDados`: o tema persiste.
- Defeito achado: corrija nos três arquivos e repita a combinação afetada. Sem defeito: commit vazio com a prova.

**Validation:** a régua; no corpo do commit, a lista de combinações vistas, os defeitos e as correções, e o caminho das capturas (fora do repo).

## Task 9: checker da Taste Skill e nova passada das guidelines

**Files:** `fonte/web/www/app.css`, `fonte/web/www/index.html`, `fonte/web/www/app.js` (só correções)

- Com o painel em simulação:

  ```
  node ~/.claude/skills/design-taste-frontend/scripts/consistency.mjs http://127.0.0.1:8765/ --widths 1366 --profile <scratchpad>/tc-cons --quick
  ```

  - valem só os ids básicos: `a11y-name`, `field-label`, `heading-order`, `tabindex`, `focus-ring`, `focus-visible`, `focus-hidden`, `lang`, `contrast`, `text-contrast`, `button-styles`, `button-shape`, `nesting`, `heading-scale`;
  - ignorar os de marketing: hero, one-section, moment, nav;
  - `perf.mjs` também, pela mesma URL, com `--runs 3`.
- Rodar a skill `web-design-guidelines` sobre os três arquivos: zero achados, ou cada exceção justificada no commit.

**Validation:** a régua; `Select-String '\.\.\.'` em `index.html` e `app.js` sem texto de UI; nenhuma cor `#rrggbb` em `app.css` fora de `:root`; saída resumida do checker e da skill no corpo do commit.

## Task 10: fechar o plano

**Files:** `docs/plans/2026-11-17-frente-ui-plan.md`

- `**Status:**` passa a `Concluído`, com uma linha dizendo que F2b, F3 e F4 do plano de UI estão feitas e que a Onda 2 do mapa pode começar. Não editar o mapa: três frentes correm ao mesmo tempo, e o mapa só muda na raiz, depois que elas fecham.

**Validation:** a régua inteira verde; `git diff --check` limpo.
