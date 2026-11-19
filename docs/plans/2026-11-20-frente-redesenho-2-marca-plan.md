# Frente redesenho-marca: o sistema visual SmartSeg sobre o layout de hoje (fase B, 2 de 5)

**Status:** Draft · **Frente:** `redesenho-marca`

Frente 2 do mapa `docs/plans/2026-11-20-frente-redesenho-mapa.md`. Depende da frente 1 fechada (tokens, camadas, módulos e `fonte/Testes-Front.ps1`). Especificação: `docs/design/2026-11-ux/direcao.md`, seções 4 (sistema visual) e 8 (servidor). Código de partida: `docs/design/2026-11-ux/prototipo/tokens.css`, `icones.js`, `marca.js`, `logo.png`, `simbolo.png`.

**Goal:**
- O painel, ainda com o layout de hoje, ganha o sistema visual da direção 4: tokens de marca e semânticos nos dois temas, tipo, espaço, raio, sombra, movimento e ícones.
- Logo, símbolo e favicon da SmartSeg; no escuro, a logo oficial sobre a placa clara.
- O servidor serve `.png` com o tipo certo.
- Cada cor com um significado só (direção 4.2, regras de uso).

**Non-Goals:**
- Layout, navegação, fluxo e textos: frentes 3 a 5. Onde o layout de hoje não tem o lugar que a direção pede (topo fixo, chips), a marca vai no lugar mais próximo que já existe, e a frente 3 a move.
- A variante clara derivada da logo (decisão do usuário: não entra).
- Logo em vetor.
- Servidor além da entrada `.png` em `$tipos`.

**Touched:**
- `fonte/web/www/**`;
- `fonte/web/Servidor-Painel.ps1` (só a linha do `$tipos`, Task 2);
- `instalador/ConfigurarCameras.iss`;
- este plano e o mapa (Task 4).

**Pedidos do usuário (19/11, do plano `docs/plans/2026-11-19-frente-ux-plan.md`). Valem para toda Task, e cada executor os aplica:**
1. **Bonita e boa de usar.** UI **e** UX: fluxo do operador, clareza de estado, recuperação de erro, densidade certa para console de bancada. Não é polimento de regra.
2. **Skills de verdade.** Cada Task diz quais skills invocar. Invoque-as (Skill tool), leia as referências que elas apontam e cite no commit o que aplicou e o que descartou, com o porquê. Skill de marketing entra só na parte de sistema, formulário, acesso, movimento e escrita.
3. **Marca Grupo SmartSeg.**
   - Logo oficial em `docs/design/2026-11-ux/marca/` (PNG de 2302 px; não há vetorial).
   - Cores medidas na logo: azul petróleo `#407A94` / `#5489A1`, grafite `#565758`, cinza `#848688`.
   - O azul vira a cor de ação e de identidade. O âmbar sai como acento de marca e fica só como semântica de atenção (direção 4.1).
   - Logo nítida nos dois temas. No escuro, a logo oficial sobre uma placa clara (decisão do usuário, Task 6 da frente `ux`); a variante derivada não entra.
4. **Front organizado e fácil de mudar.**
   - Nenhum valor visual solto: cor, espaço, raio, tipo, sombra e duração só por token.
   - Textos de UI num lugar só.
   - Constantes nomeadas.
   - Módulos com fronteira clara (`codebase-design`).
   - A direção define essa arquitetura, e a fase B a implementa com um teste que a guarda.
5. **Uma direção defendida, sem cardápio.** A direção está aprovada. Escolha que ela não cobre e que muda o que o operador vê: `BLOQUEADO` com a pergunta pronta.
6. **Repo público.**
   - Só dados fictícios: MAC `AA:00:00:00:00:0x`, serial `SIM-x`, IPs `192.0.2.x` e `192.168.1.108`, obra "Obra exemplo".
   - A logo e as cores do SmartSeg são material público da empresa do usuário e podem entrar.
   - Nada de senha, IP, MAC ou obra reais. Antes do commit, `git diff --cached` revisado para isso.

**Safety:**
- Painel só em simulação, rodando do worktree da frente, com pasta de dados própria:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -SimularCameras 3 -SimularEscala 1 -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-marca`
  - sem `-PastaDados`, a instância única lê o `painel.json` de `%ProgramData%` e pode reabrir o painel instalado;
  - porta 8765 ocupada: use 8766 e anote no commit. Ao terminar, encerre o processo que você subiu;
  - falha forçada: `POST /api/simular` com `{ "ligado": true, "falharEm": { "2": "encoder" } }` (chave é o número da câmera);
  - câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`: pare e devolva `BLOQUEADO`.
- Playwright pelo MCP (`browser_*`), a 1366×768. Capturas em `.playwright-mcp/` (ignorado pelo git), nunca no repo.
- Taste Skill: **nunca** `gate.mjs --start` nem `start.mjs`; não crie `.taste-skill/`; `consistency.mjs`, `perf.mjs` e `shoot.mjs` só com `--profile <scratchpad>/...`.
- Sem push, tag nem release.
- Codificação: `Servidor-Painel.ps1` e o `.iss` em UTF-8 **com BOM** (há teste para o servidor); `Testes-*.ps1` em ASCII, acento por `[char]`; arquivos do `www` em UTF-8 sem BOM, CRLF.
- Skill ou ferramenta MCP indisponível: `BLOQUEADO` dizendo qual.

**Régua de toda Task:** o bloco `### Validação` do `CLAUDE.md`, com o `Testes-Front.ps1` da frente 1 (zero violações no `www` real). A contagem de testes se lê na saída.

## Decisões

- **M1. Tokens da direção, valores da direção.** Os primitivos (4.1), os semânticos nos dois temas com os contrastes medidos (4.2), o tipo (4.3) e espaço, raio, sombra, movimento e medidas (4.4) entram como estão no `tokens.css` do protótipo. Onde um nome de token da frente 1 já é o da direção, só o valor muda. Os tokens marcados `/* legado: sai na frente 2 */` somem: cada uso passa a um token da direção, pelo significado (âmbar só atenção, vermelho só falha que pede você, cinza para todo o resto, inclusive simulação).
- **M2. Arquivos da marca idênticos aos do protótipo.** `logo.png` (336 px de largura) e `simbolo.png` (64 px) se copiam de `docs/design/2026-11-ux/prototipo/`, com o mesmo hash. Nada se redesenha.
- **M3. Uma entrada no servidor.** `'.png' = 'image/png'` no `$tipos` de `Servidor-Painel.ps1` (direção 8). A rota `GET /favicon.ico` que devolve 204 fica.

## Task 1: tokens de marca e semânticos

**Files:** `fonte/web/www/tokens.css`, `base.css`, `componentes.css`, `telas.css`, `fonte/web/www/legado-*.js` (só onde o JS escolhe classe por cor)

**Skills:** `design-taste-frontend` (`references/system.md`: tokens, acento único, contraste, raio por nível), `frontend-design`.

- Aplique a M1. Família de sistema e mono só para IP, MAC, serial e log (4.3); seis tamanhos de tipo, piso de 13 px, corpo entre 14 e 15 px; pesos 400 e 600.
- Sombra só no que flutua; o resto da hierarquia sai de tipo, espaço e fundo (4.4).
- Durações por token e zeradas com `prefers-reduced-motion: reduce`; sem pulso nem animação em laço (`UI-15`).
- Estado nunca só por cor: onde o layout de hoje mostra estado só pela cor, entra a palavra que já existe no texto ou o ícone da Task 3.

**Validation:** a régua. `consistency.mjs` sobre o painel em simulação nos dois temas, sem falha em `contrast`, `text-contrast`, `focus-ring`, `focus-visible` e `button-styles`. Capturas das 10 telas da linha de base da frente 1 (lista na Task 1 do plano da frente 1) nos dois temas, em `.playwright-mcp/marca/`.

## Task 2: logo, símbolo, favicon e o `.png` servido

**Files:** `fonte/web/www/logo.png`, `simbolo.png`, `marca.js` (novos), `fonte/web/www/index.html`, `fonte/web/www/textos.js`, `fonte/web/www/legado-*.js`, `fonte/web/www/componentes.css`, `fonte/web/Servidor-Painel.ps1`, `instalador/ConfigurarCameras.iss`

**Skills:** `frontend-design`.

- M2 e M3. `marca.js` parte do protótipo (`logo()`, `simbolo()`, texto alternativo em `textos.js`).
- Onde (direção 4.6), no layout de hoje: o símbolo a 28 px de altura ao lado de "Configurar câmeras" no cabeçalho que existe; a logo inteira a 168 px de largura no passo a passo e na tela de encerrado. No tema escuro, a logo sobre a placa clara (`--logo-placa`, `--raio-bloco`, `--esp-3`).
- Favicon: `<link rel="icon" type="image/png" href="/simbolo.png">` no `index.html`.
- `.iss`: um `Source:` para `logo.png`, `simbolo.png` e `marca.js`, na ordem da direção 7.3.

**Validation:** a régua (inclui o teste de BOM do servidor e a regra `servido`). Com o painel em simulação, `GET /logo.png` e `GET /simbolo.png` respondem 200 com `Content-Type: image/png`. Hash dos dois PNG igual ao do protótipo. Logo nítida nos dois temas, em captura.

## Task 3: ícones

**Files:** `fonte/web/www/icones.js` (novo), `fonte/web/www/legado-*.js`, `fonte/web/www/textos.js`, `fonte/web/www/componentes.css`, `instalador/ConfigurarCameras.iss`

**Skills:** `frontend-design`.

- `icones.js` parte do protótipo: SVG montado a partir dos caminhos do Lucide, com o aviso da licença ISC no cabeçalho, traço de 1,5 px a 16 e 20 px (direção 4.5).
- Todo glifo de texto usado como ícone sai (o ⚙ e os outros, `UI-16`) e entra o ícone equivalente, com nome acessível ou `aria-hidden` quando há palavra ao lado.
- `.iss`: `Source:` do `icones.js`.

**Validation:** a régua. Nenhum glifo de texto como ícone no `www` (busca no corpo do commit). Console sem erro.

## Task 4: verificação e fechar o plano

**Files:** este plano, `docs/plans/2026-11-20-frente-redesenho-mapa.md`

**Skills:** `design-taste-frontend` (`consistency.mjs`).

- Painel em simulação, nos dois temas, as 10 telas da linha de base: capturas em `.playwright-mcp/marca/final/`, console sem erro.
- `consistency.mjs` com os ids básicos (`a11y-name`, `field-label`, `heading-order`, `tabindex`, `focus-ring`, `focus-visible`, `focus-hidden`, `lang`, `contrast`, `text-contrast`, `button-styles`, `button-shape`, `nesting`, `heading-scale`): sem falha, ou cada exceção no corpo do commit com o porquê e a frente que a resolve.
- `**Status:** Concluído (<data>)` com uma linha de fechamento; no mapa, a linha da frente 2 com "feita em <data>".

**Validation:** a régua inteira verde; `git diff --check` limpo.
