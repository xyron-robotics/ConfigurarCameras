# Frente responsivo: layout responsivo de 900 a 1920 px (1.3.1, 1 de 2)

**Status:** Concluído · **Frente:** `responsivo`

Frente 1 da onda 1 do mapa `docs/plans/2026-11-26-versao-131-mapa.md`. Sem dependência. A frente `registro-controle` depende desta.

**Goal:** sem scroll horizontal da página nem texto cortado sem reticências de 900 a 1920 px, nos dois temas, com o conteúdo centrado na janela cheia e medidas fluidas com mínimo e máximo, todas por token.

**Non-Goals:**
- mobile (abaixo de 900, a página rola na horizontal, sem elemento escondido);
- mudar fluxo ou texto além do necessário para caber;
- o MENOR do `topo.js` `.disabled` (pendência da frente 5);
- os achados da frente `registro-controle`.

**Touched:** `fonte/web/www/tokens.css`, `telas.css`, `componentes.css`, `topo.js`, `tela-painel.js`, `textos.js`, `fonte/Testes-Front.ps1`, `docs/design/2026-11-ux/medir-responsivo.js` (novo, prova, fora do instalador), este plano.

## Achados da auditoria (26/11)

Medição com `medir-pagina.js`, que mede scroll horizontal, texto cortado e elementos fora da tela. O script é injetado por `addInitScript`, por causa da CSP. Larguras: 1920, 1600, 1440, 1366, 1280, 1152, 1024, 900 e 800.

- **GRAVE 1, topo pede no mínimo 969 px.**
  - Sintoma: abaixo de ~970 a página rola na horizontal e "Encerrar o painel" sai da tela; a 800 sai também o chip Simulação.
  - Causa: `telas.css:18-40`, grade de 5 colunas `auto` com gap 24 e padding 24; chips (349 px) e botão (141 px) com `nowrap`.
  - 1b: a marca quebra em 2 linhas a 1024.
- **GRAVE 2, tabela Registro rola na horizontal em toda largura, até a 1920.**
  - Sintoma: a tabela pede no mínimo 1269 px para 1190 de área útil; Data fica escondida e Local se espreme em 115 px e 5 linhas.
  - Causa: `tela-painel.js:499`, Rack/porta em `td.mono` com `nowrap`; Encoder e Data com `nowrap`.
- **GRAVE 3, selects Resolução e Bitrate cortam texto sem reticências de 1920 a 1152.**
  - Sintoma: "1920 × 1080 (testac", "4096 (recomendad".
  - Causa: `componentes.css:294`, dois streams lado a lado, com 2 colunas cada, em 720 px; cada select fica com 162 px.
- **MENOR 4, tabela Fila agora rola a 900 e 800, e Modelo quebra a 1024.** Causa: Estado com 220 px fixos; serial e MAC com `nowrap` (`tela-painel.js:393-394`).
- **MENOR 5, popover dos chips colado na borda da janela,** e não no container centrado (`componentes.css:~77`).
- **MENOR 6, passo a passo (720) colado à esquerda do container de 1240,** com o chip Simulação isolado à direita (`telas.css:53-54`).
- **MENOR 7, Sessão descentrada de 1440 a 1920.**
- **MENOR 8, Local e Rack estreitos** (`--grade-local` 2fr/1fr/1fr em 720).
- **Geral:**
  - um único máximo (1240), nenhuma largura mínima e nenhum `clamp()`;
  - um único `@media` (1100); a quebra 1600 está declarada e não é usada;
  - o tema escuro tem a mesma geometria;
  - não auditados: o estado "em curso" e a faixa de atualização.

## Decisões

- **R1. Faixa suportada a partir de 900 px.**
  - É a meia tela de um monitor de 1920 (~960), o caso estreito real.
  - Abaixo de 900: `min-inline-size` no `body`, e a página rola na horizontal de forma limpa.
- **R2. Topo abaixo de 1100.**
  - Chips só com ícone e ponto de estado; o rótulo vai para `aria-label`, e o popover segue com o detalhe completo.
  - "Encerrar o painel" vira botão de ícone, com `aria-label` e `title`.
  - O gap do topo cai para `--esp-3`, e a marca fica `nowrap`.
- **R3. `.form-streams` sempre empilhado** (`--grade-1`), em toda largura.
- **R4. Tabela Registro.**
  - Rack/porta sai de mono e de `nowrap`, porque é texto livre.
  - Local ganha mínimo por token (~18ch), e Data vai em 2 linhas (data/hora).
  - Painel até `--conteudo-largo` (~1440) a partir da quebra 1600; a tabela cabe sem rolar a 1600 e a 1920.
  - Abaixo disso, rola só a `.tabela-rolagem`, nunca a página, com a coluna IP fixa (`sticky`).
- **R5. Centralização.**
  - `.inicio` e `.sessao-tela` centrados (`margin-inline: auto`) na largura da coluna.
  - Popover alinhado ao container: `inset-inline-end: max(var(--esp-5), calc((100vw - var(--conteudo-max)) / 2 + var(--esp-5)))`.
- **R6. Medidas fluidas só por token.**
  - `--margem-pagina` com `clamp()` no padding lateral de `main` e do topo.
  - Linha `quebras:` de `tokens.css`: entra `900px`; sai `760px` se nenhum `@media` a usar.
- **R7. Fila agora.**
  - Modelo com `nowrap`, reticências e `title`.
  - Estado com mínimo, não fixo.
  - Abaixo de 1100, serial e MAC em 2 linhas.
- **R8. `--grade-local` em 2 linhas:** Local inteiro na primeira; Rack e Andar embaixo.

**Safety (as duas frentes):**
- Painel só em simulação, do worktree:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -SimularCameras 3 -SimularEscala 1 -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-131`
  - Porta ocupada: use 8766 e anote no commit. Encerre o processo que você subiu.
- Câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`: `BLOQUEADO`.
- Capturas em `.playwright-mcp/` (ignorado), nunca no repo.
- Sem push, tag nem release.
- Codificação:
  - `Servidor-Painel.ps1` e o `.iss` em UTF-8 **com BOM**;
  - `Testes-*.ps1` em ASCII, com acento por `[char]`;
  - `www` em UTF-8 sem BOM, com CRLF.
- Textos em pt-BR, em caixa de frase, só em `textos.js`; medidas só em `tokens.css`.

**Régua de toda Task:** o bloco `### Validação` do `CLAUDE.md`, com a saída colada no corpo do commit.

## Task 0: trazer os planos para o repo

**Files:** `docs/plans/2026-11-26-versao-131-mapa.md`, `docs/plans/2026-11-26-frente-responsivo-plan.md`, `docs/plans/2026-11-26-frente-registro-controle-plan.md`, `CLAUDE.md` (a linha "O mapa do trabalho em curso é …")

- Mapa: `Context` + `Mapa da 1.3.1`.
- Frente `responsivo`: a seção "Frente `responsivo`" inteira, com `Safety` e `Régua`.
- Frente `registro-controle`: a seção dela inteira, com `Safety` e `Régua` copiados, cabeçalho `**Status:** Ativo · **Frente:** \`registro-controle\``, `## Task N:` numeradas de 1.
- `CLAUDE.md` passa a apontar o mapa da 1.3.1.
- Devolve ao maestro o caminho do plano `responsivo`.

**Validation:** os três arquivos existem; `Grep "^## Task "` em cada plano de frente; `git diff --check`.

## Task 1: guarda de overflow (RED antes)

**Files:** `fonte/Testes-Front.ps1`, `docs/design/2026-11-ux/medir-responsivo.js` (novo)

**Skills:** `mattpocock-skills:tdd`.

- **Regra estática `corte` no `Testes-Front.ps1`.** Todo `white-space: nowrap` em `componentes.css` ou `telas.css` vem com `text-overflow: ellipsis` na mesma regra, ou com um seletor de uma lista nomeada de curtos (chip, botão, número, mono de IP/MAC). Mesmo padrão das regras da frente 1: pasta plantada que falha (RED), depois o `www` real.
  - Se o `www` de hoje falhar (`td.mono` de Rack/porta), a regra entra com essa exceção anotada, que a Task 3 remove.
- **`medir-responsivo.js`.** Versão versionada do `medir-pagina.js` da auditoria.
  - Devolve um JSON: `scrollHorizontal`, `cortados[]` (texto com `scrollWidth > clientWidth` e sem ellipsis) e `foraDaTela[]`.
  - O cabeçalho explica como rodar pelo Playwright MCP (`addInitScript`, por causa da CSP).
  - Rodar a linha de base antes de qualquer conserto (9 larguras × Painel, Sessão, passo a passo, Ferramentas) e colar o resumo no commit.

**Validation:** a régua; o RED da regra `corte` colado; a linha de base da medição no commit.

## Task 2: topo (GRAVE 1, R1, R2, R6)

**Files:** `tokens.css`, `telas.css`, `componentes.css`, `topo.js`, `textos.js`

**Skills:** `design-taste-frontend` (`references/system.md`), `web-design-guidelines`.

- R2 no `@media (max-width: 1100px)`; R1 (`min-inline-size` no body, por token); R6 (`--margem-pagina`, quebra 900 na linha `quebras:`).
- Rótulos dos chips continuam acessíveis: `aria-label` com o mesmo texto do rótulo visível de hoje, vindo de `textos.js`.

**Validation:** a régua. Medição: topo sem scroll nem item fora da tela de 900 a 1920, nos dois temas. O popover abre e fecha pelo teclado a 1024.

## Task 3: tabelas (GRAVE 2, MENOR 4; R4, R7)

**Files:** `tela-painel.js`, `componentes.css`, `telas.css`, `tokens.css`, `fonte/Testes-Front.ps1` (tirar a exceção da Task 1, se houver)

- R4 e R7.
- `--conteudo-largo` vale só para o Painel; Início e Sessão seguem com 1240.

**Validation:** a régua. Medição:
- Registro sem rolar a 1600 e a 1920;
- de 900 a 1440, rola só a tabela, com o IP fixo;
- Fila agora sem rolar de 900 para cima, com 3 câmeras e no estado "em curso" (falha forçada `POST /api/simular`).

## Task 4: formulários e centralização (GRAVE 3, MENOR 5–8; R3, R5, R8)

**Files:** `componentes.css`, `telas.css`, `tokens.css`

**Validation:** a régua. Medição: Resolução e Bitrate sem corte em toda largura. Captura a 1920 e a 1366 mostrando o passo a passo, a Sessão e o popover centrados.

## Task 5: verificação e fechamento

**Files:** este plano no repo (`**Status:** Concluído`), o mapa

- `medir-responsivo.js` nas 9 larguras × 4 telas × 2 temas, mais a faixa de atualização (forçada no `browser_evaluate`) e o estado "em curso".
- Esperado: `scrollHorizontal` falso e `cortados` vazio de 900 para cima. A tabela antes/depois vai no commit.
- Console sem erro.

**Validation:** a régua, com a medição completa colada.
