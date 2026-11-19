# Frente ux: auditoria de UI e UX, direção visual SmartSeg, protótipo e planos do redesenho (fase A)

**Status:** Concluído (19/11) · **Frente:** `ux`

Fechamento: a fase B do redesenho está indexada em `docs/plans/2026-11-20-frente-redesenho-mapa.md` (cinco frentes sequenciais, planos em Draft).

**Goal:**
- Diagnosticar o painel como experiência do operador e como interface.
- Definir uma direção visual e de UX defendida, com a marca do Grupo SmartSeg.
- Provar a direção num protótipo navegável.
- Escrever os planos da fase B (implementação), em frentes.
- Nenhuma linha de `fonte/` muda nesta frente.

**Non-Goals:**
- Editar `fonte/` (front, servidor, motor, testes): isso é a fase B.
- Release, push ou tag.
- Mobile.
- Herói, fotos, efeitos de shader e "uma seção por tela": são de site de marketing.

**Touched:** `docs/design/2026-11-ux/**` (novo), `docs/plans/2026-11-19-frente-ux-plan.md` (só a Task 7), `docs/plans/2026-11-2*-frente-redesenho-*.md` (novos, Task 6).

**Pedidos do usuário (19/11). Valem para toda Task, e cada executor os aplica:**
1. **Bonita e boa de usar.** UI **e** UX: fluxo do operador, clareza de estado, recuperação de erro, densidade certa para console de bancada. Não é polimento de regra.
2. **Skills de verdade.** Cada Task diz quais skills invocar. Invoque-as (Skill tool), leia as referências que elas apontam e cite no commit o que aplicou e o que descartou, com o porquê. Skill de marketing entra só na parte de sistema, formulário, acesso, movimento e escrita.
3. **Marca Grupo SmartSeg.**
   - Logo oficial em `docs/design/2026-11-ux/marca/` (a Task 3 traz).
   - Cores medidas na logo: azul petróleo `#407A94` / `#5489A1`, grafite `#565758`, cinza `#848688`.
   - O azul vira a cor de ação e de identidade. O âmbar atual sai como acento de marca; se ficar, fica só como semântica de "agora" ou "atenção", e a direção decide.
   - Logo nítida nos dois temas, com variante clara no escuro.
4. **Front organizado e fácil de mudar.**
   - Nenhum valor visual solto: cor, espaço, raio, tipo, sombra e duração só por token.
   - Textos de UI num lugar só.
   - Constantes nomeadas.
   - Módulos com fronteira clara (`codebase-design`).
   - A direção define essa arquitetura, e a fase B a implementa com um teste que a guarda.
5. **Uma direção defendida, sem cardápio.** Pesquise o padrão (ferramentas de provisionamento e comissionamento de dispositivos, consoles de NVR e VMS, painéis operacionais) e proponha o ideal. Alternativa só para um trade-off real e nomeado.
6. **Repo público.**
   - Só dados fictícios: MAC `AA:00:00:00:00:0x`, serial `SIM-x`, IPs `192.0.2.x` e `192.168.1.108`, obra "Obra exemplo".
   - A logo e as cores do SmartSeg são material público da empresa do usuário e podem entrar.
   - Nada de senha, IP, MAC ou obra reais. Antes do commit, `git diff --cached` revisado para isso.

**Safety:**
- Painel só em simulação, rodando do worktree:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-ux`
  - Porta ocupada: use 8766 e anote no commit.
  - Ao terminar, encerre o processo que você subiu.
  - Câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`: pare e devolva BLOQUEADO.
- Taste Skill: **nunca** `gate.mjs --start` nem `start.mjs`. Não crie `.taste-skill/`. `consistency.mjs`, `perf.mjs` e `shoot.mjs` rodam sempre com `--profile <scratchpad>/...`.
- Capturas:
  - as de referência ficam em `docs/design/2026-11-ux/capturas/` (PNG, 1366×768, só simulação, no máximo 20 no total da frente, nome `<task>-<tela>-<tema>.png`);
  - o resto fica em `.playwright-mcp/`.
- Skill ou ferramenta MCP indisponível para você: BLOQUEADO dizendo qual, sem improvisar.

**Decisões já tomadas (19/11):**
- O redesenho vem antes da release 1.3.0.
- Front livre: navegação, fluxo, número de passos, layout e estrutura do código.
- Servidor só no mínimo para a tela: tipos de arquivo estático, faixa no HTML, dado que já existe exposto no `/api/estado`.
- Motor, orquestrador, coordenador e contrato das rotas intocados.
- Corpo continua legível a 1366×768 (piso de 13 px; corpo entre 14 e 15 px).
- `confirm()` nativo vale como confirmação de ação destrutiva, salvo se a direção defender um diálogo próprio.

**Restrições técnicas que a direção e o protótipo respeitam:**
- **CSP:** `default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:`. Sem `style=`, sem `<style>`, sem script inline, sem CDN. ES modules (`<script type="module" src>`) passam.
- **Servidor** (`Servidor-Painel.ps1:1614-1617`): serve só arquivos diretos de `www\` (sem subpasta), e `$tipos` só tem html, js, css e svg.
- **Instalador:** cada arquivo de `www` exige `Source:` próprio no `instalador/ConfigurarCameras.iss` e passa pela conferência do `Gerar-Instalador.ps1` (sem coringa, sem "senha" no nome).
- **Testes de UI existentes:** `Testes-Motor.ps1:2851-2873` (tema e strings proibidas ou exigidas).

## Task 1: linha de base e jornada do operador

**Files:** `docs/design/2026-11-ux/linha-de-base.md`, `docs/design/2026-11-ux/capturas/`

- **Antes de tudo:** confirme que você tem a Skill tool e o Playwright MCP (`browser_navigate`). Se faltar algum, devolva BLOQUEADO.
- Suba o painel como na Safety, com janela de 1366×768 e navegação comum.
- **Inventário:** toda tela e todo estado, cada um com seletor, função de render em `app.js` e propósito em uma linha. Telas e estados: passo a passo 1 a 7 (sessão nova e sessão salva com Usar/Revisar), Painel (sem fila, fila montada, vigia ligado, 3 câmeras em portão/conferindo/feita, falha na câmera 2 em decisão, fila concluída, fila encerrada), Ferramentas, Opções (todas as seções e o tema), log, faixa de simulação, tela de encerrado e de atualização.
- **Jornada:** rode 4 cenários e meça telas, cliques, campos e momentos de dúvida em cada um:
  1. primeira abertura até a 1ª câmera feita;
  2. sessão salva até 3 câmeras feitas;
  3. falha na câmera 2 e recuperação;
  4. encerrar.
  - Use `/api/simular` com `falharEm` para forçar as falhas.
- Capturas de referência dos estados principais, no claro e no escuro (até 10).

**Validation:** a régua. O `.md` tem a tabela do inventário e a tabela da jornada com os números. As capturas citadas existem.

## Task 2: auditoria de UX

**Files:** `docs/design/2026-11-ux/auditoria-ux.md`

- Leia `linha-de-base.md`, `CONTEXT.md` (vocabulário) e o fluxo em `LEIA-ME.md`.
- Método explícito:
  - as 10 heurísticas de Nielsen;
  - análise de tarefa sobre os 4 cenários da Task 1, olhando o que o operador precisa saber em cada momento, o que a tela mostra, o que esconde e o que pede à toa;
  - recuperação de erro;
  - estados vazio, carregando e erro;
  - arquitetura de informação (as 3 abas mais o passo a passo fazem sentido? as Opções duplicam o passo a passo?);
  - carga do vigia e dos cartões com N câmeras.
- Invoque `frontend-design` e aplique a seção de escrita: verbo no botão, erro que diz o conserto, vazio como convite, mesma ação com o mesmo nome.
- **Cada achado tem:** id `UX-nn`, severidade de 0 a 4 (Nielsen), evidência (captura ou passo da jornada), `arquivo:linha` quando houver, e impacto no operador.
- No fim, os 5 problemas de maior impacto, em ordem.

**Validation:** a régua. Todo achado tem severidade e evidência.

## Task 3: auditoria de UI e marca

**Files:** `docs/design/2026-11-ux/auditoria-ui.md`, `docs/design/2026-11-ux/marca/`, `docs/design/2026-11-ux/capturas/`

- Invoque `web-design-guidelines` sobre `fonte/web/www/app.css`, `index.html` e `app.js`, e registre os achados `arquivo:linha`.
- Invoque `design-taste-frontend`:
  - leia `references/system.md`, `motion.md` e `cards.md`;
  - aplique o checklist "One system" e o de teclado;
  - rode `consistency.mjs http://127.0.0.1:8765/ --widths 1366 --quick --profile <scratchpad>/tc` e `perf.mjs` (`--runs 3`).
- Invoque `frontend-design` e liste os "tells" de UI gerada presentes no painel.
- Crítica visual com as capturas: hierarquia, densidade, tipografia, cor, consistência de componentes, alinhamento, estados.
- Achados com id `UI-nn` e severidade alta, média ou baixa.
- **Marca:**
  - traga a logo oficial para `marca/`. Com resposta do usuário apontando um vetor oficial, use-o. Sem isso, use `http://gruposmartseg.com.br/wp-content/uploads/2023/09/Logo-Smartseg-Vetor.png` (o certificado HTTPS do site está vencido, então baixe por HTTP);
  - registre as cores medidas;
  - calcule o contraste WCAG de `#407A94` e `#5489A1` com texto branco e sobre o fundo claro e o escuro, e anote quais usos cada uma aguenta.

**Decisão do usuário:** você tem o arquivo vetorial oficial da logo do Grupo SmartSeg (SVG, AI, PDF ou EPS)? Se tiver, diga o caminho. Se não, o executor segue com o PNG de 2302 px do site.

**Validation:** a régua. A logo está em `marca/`. A tabela de contraste está no `.md`. Os ids `UI-nn` têm severidade.

## Task 4: direção defendida

**Files:** `docs/design/2026-11-ux/direcao.md`

- Leia `auditoria-ux.md`, `auditoria-ui.md` e a pasta `marca/`.
- Invoque `mattpocock-skills:research` para padrões de referência: ferramentas de provisionamento e comissionamento de câmeras (de fabricantes, sem copiar a interface de nenhuma), consoles de NVR e VMS, painéis operacionais de bancada. Cite as fontes.
- Invoque `frontend-design` (plano em duas passagens), `design-taste-frontend` (`references/system.md`, para tokens, formulário e acesso) e `codebase-design` (para a arquitetura do front).
- O `direcao.md` traz:
  1. **Princípios** (3 a 5), cada um amarrado a achados `UX-nn` e `UI-nn`.
  2. **Arquitetura de informação e fluxo novos:**
     - navegação e passos, com o porquê;
     - jornada dos 4 cenários refeita, com a contagem de telas e cliques antes e depois.
  3. **Layout por tela**, em ASCII a 1366×768: passo a passo (ou o que o substituir), Painel com N cartões, decisão, Ferramentas, Opções, estados vazio e erro.
  4. **Sistema visual:**
     - tokens primitivos da marca (`#407A94`, `#5489A1`, `#565758`, `#848688`) e tokens semânticos (ação, foco, sucesso, falha, atenção, "agora", superfícies) nos dois temas, com o contraste de cada par;
     - escala de tipo, espaço, raio, sombra e movimento;
     - logo: onde aparece, tamanho, variante clara no escuro, favicon.
  5. **Componentes:** botão (primário e secundário), campo, cartão da câmera, fita, aviso, faixa, tabela, cada um com seus estados.
  6. **Escrita:** regras e um glossário de rótulos, coerente com o `CONTEXT.md`.
  7. **Arquitetura do front.** Regra-mãe: "nenhum valor local solto".
     - **CSS:** `tokens.css` (primitivos, semânticos, tema), `base.css`, `componentes.css` e `telas.css`, ou outra divisão defendida, com `@layer`.
     - **JS:** ES modules por responsabilidade, por exemplo API e estado, roteamento, uma tela por módulo, componentes e `textos.js` com toda string de UI. Fronteiras e interfaces explícitas.
     - **Arquivos que a fase B precisa servir e instalar:** a lista de `$tipos` e `Source:`, e as linhas exatas que mudam no servidor e no `.iss`.
     - **Teste que guarda a regra:** por exemplo, um `fonte/Testes-Front.ps1` que falha com hex, px ou ms fora de `tokens.css`, e com string de UI fora de `textos.js`. Esse arquivo novo entra no `release.yml`, no `Gerar-Instalador` e na régua do `CLAUDE.md`.
  8. **Mudanças no servidor:** só as mínimas, uma por uma, com o porquê.
  9. **Mapa de resolução:** todo achado `UX-nn` e `UI-nn` com severidade 3 ou mais, ou alta, aparece resolvido, adiado com motivo ou recusado com motivo.

**Validation:** a régua. As 9 seções presentes. Nenhum achado grave fica sem destino no mapa de resolução.

## Task 5: protótipo navegável da direção

**Files:** `docs/design/2026-11-ux/prototipo/` (HTML, CSS, JS e a logo), `docs/design/2026-11-ux/capturas/`

- Invoque `mattpocock-skills:prototype` no ramo UI, **com uma direção só**, a do `direcao.md`. Invoque `frontend-design` para a execução visual.
- **Formato do protótipo:**
  - estático, abre por `file://` com um duplo clique;
  - estado fictício embutido no JS (sem fetch);
  - um seletor de cenário e de tema numa barra discreta.
- Use já a arquitetura da seção 7 da direção (tokens, textos, módulos) e as regras de CSP, para que a fase B aproveite o código.
- **Cobertura:** primeira configuração; Painel com 3 câmeras (portão, conferindo, feita); falha com decisão; fila concluída; Opções; Ferramentas. Tudo no claro e no escuro, com a logo nos dois.
- **Verificação:**
  - Playwright a 1366×768 com capturas de referência (até 10);
  - `consistency.mjs` contra o protótipo, servido por `http` local no scratchpad, sem falha nos ids básicos (`a11y-name`, `field-label`, `heading-order`, `tabindex`, `focus-ring`, `focus-visible`, `focus-hidden`, `lang`, `contrast`, `text-contrast`, `button-styles`, `button-shape`, `nesting`, `heading-scale`);
  - console sem erro.

**Validation:** a régua. O protótipo abre por `file://` sem erro no console. Os ids básicos do checker passam. As capturas citadas existem.

## Task 6: ajustes do usuário e planos da fase B

**Files:** `docs/design/2026-11-ux/direcao.md`, `docs/design/2026-11-ux/prototipo/`, `docs/design/2026-11-ux/capturas/`, `docs/plans/2026-11-2*-frente-redesenho-*.md`

**Decisão do usuário:** abra `docs/design/2026-11-ux/prototipo/index.html` no navegador (no worktree da frente `ux`) e percorra os cenários nos dois temas. Aprova a direção como está, ou quais ajustes?

- Aplique os ajustes pedidos na direção e no protótipo, com capturas novas só do que mudou.
- Invoque `writing-for-agents` e `codebase-design`. Escreva os planos da fase B em `docs/plans/`, com **Status: Draft**, no formato do maestro: `**Frente:**`, Goal, Non-Goals, Touched, Safety, `## Task N:` com Files e Validation.
  - Esqueleto esperado. Ajuste com justificativa, porque todas as frentes mexem nos mesmos arquivos e são sequenciais:
    1. **arquitetura do front:** módulos, tokens, `textos.js` e o teste que guarda a regra, sem mudança visual;
    2. **marca e sistema visual:** tokens de marca, logo, favicon, `$tipos` e `.iss`;
    3. **navegação e configuração:** passo a passo e Opções;
    4. **Painel e bancada:** fila, vigia, cartões e decisão;
    5. **Ferramentas, estados e verificação final:** Playwright nos dois temas, `consistency.mjs`, `web-design-guidelines` e o roteiro de duas filas.
  - Cada plano carrega no cabeçalho os "Pedidos do usuário" deste arquivo.
  - O bug do `salvarCartao` (`app.js:746`: uma recusa não limpa `k.enviado`) entra na frente 4.
  - A atualização de `Testes-Motor.ps1:2861-2873` entra onde as strings mudarem.
- Um índice `docs/plans/2026-11-2x-redesenho-mapa.md` lista as frentes em ordem, com "depende de".

**Validation:** a régua. Cada plano da fase B passa no formato do maestro (`**Frente:**`, `## Task N:`, Status Draft). O índice lista todas as frentes.

## Task 7: fechar o plano

**Files:** `docs/plans/2026-11-19-frente-ux-plan.md`

- `**Status:**` passa a `Concluído`, com uma linha apontando o índice da fase B.

**Validation:** a régua inteira verde; `git diff --check` limpo.
