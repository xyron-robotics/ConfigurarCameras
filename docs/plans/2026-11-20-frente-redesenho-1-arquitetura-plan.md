# Frente redesenho-arquitetura: o front em módulos, tokens e textos, sem mudança visual (fase B, 1 de 5)

**Status:** Draft · **Frente:** `redesenho-arquitetura`

Frente 1 do mapa `docs/plans/2026-11-20-frente-redesenho-mapa.md`. Especificação: `docs/design/2026-11-ux/direcao.md`, seção 7 (arquitetura do front). Código de partida dos módulos de base: `docs/design/2026-11-ux/prototipo/`.

**Goal:**
- O front de hoje (`fonte/web/www/app.js`, `app.css`, `index.html`) passa para a arquitetura da direção 7: quatro CSS com `@layer`, ES modules planos, `textos.js`, `constantes.js`, `api.js` como único `fetch`.
- `tokens.css` com os valores visuais **de hoje**: a frente 2 troca valores, não nomes.
- `fonte/Testes-Front.ps1` guarda a regra (direção 7.4) e entra na régua, no CI e no instalador.
- O painel fica igual na tela, provado por captura antes e depois.

**Non-Goals:**
- Mudar cor, tipo, layout, texto ou fluxo: frentes 2 a 5.
- Servidor: nenhuma linha muda nesta frente (o `.png` no `$tipos` é da frente 2).
- Motor, orquestrador, coordenador e contrato das rotas.
- Dividir a lógica de hoje nas telas novas (ver Decisões, R1).

**Touched:**
- `fonte/web/www/**`;
- `fonte/Testes-Front.ps1` (novo);
- `fonte/Testes-Motor.ps1` (só o teste "Front paralelo", Task 4);
- `instalador/ConfigurarCameras.iss`, `instalador/Gerar-Instalador.ps1` (só a lista de testes), `.github/workflows/release.yml`;
- `CLAUDE.md` (só a régua, Task 2);
- este plano e o mapa (Task 6).

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
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -SimularCameras 3 -SimularEscala 1 -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-arq`
  - sem `-PastaDados`, a instância única lê o `painel.json` de `%ProgramData%` e pode reabrir o painel instalado;
  - porta 8765 ocupada: use 8766 e anote no commit. Ao terminar, encerre o processo que você subiu;
  - falha forçada: `POST /api/simular` com `{ "ligado": true, "falharEm": { "2": "encoder" } }` (chave é o número da câmera);
  - câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`: pare e devolva `BLOQUEADO`.
- Playwright pelo MCP (`browser_*`), a 1366×768. Capturas em `.playwright-mcp/` (ignorado pelo git), nunca no repo.
- Taste Skill: **nunca** `gate.mjs --start` nem `start.mjs`; não crie `.taste-skill/`; `consistency.mjs`, `perf.mjs` e `shoot.mjs` só com `--profile <scratchpad>/...`.
- Sem push, tag nem release.
- Codificação: `Servidor-Painel.ps1` e o `.iss` em UTF-8 **com BOM**; `Testes-*.ps1` em ASCII, acento por `[char]`; arquivos do `www` em UTF-8 sem BOM, CRLF, como os de hoje.
- Skill ou ferramenta MCP indisponível: `BLOQUEADO` dizendo qual.

**Régua de toda Task:** o bloco `### Validação` do `CLAUDE.md`. Depois da Task 2 ele inclui o `Testes-Front.ps1`. A contagem de testes se lê na saída.

## Restrições técnicas (medidas em 19/11)

- **CSP** (`Servidor-Painel.ps1`, `Send-Resposta` dos estáticos): `default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:`. Sem `style=`, sem `<style>`, sem script inline, sem CDN. `<script type="module" src>` passa.
- **Servidor:** serve só arquivos planos de `www\` (`Get-ChildItem -LiteralPath $www -File`), com `$tipos` para html, js, css e svg. Por isso os módulos ficam planos.
- **Instalador:** cada arquivo do `www` tem `Source:` próprio no `.iss`; o `Gerar-Instalador.ps1` recusa curinga e "senha" no nome.
- **Testes de UI que já existem** em `fonte/Testes-Motor.ps1`: "Tema: data-tema entra so no <html>…" (lê o `index.html` real e exige `<html lang="pt-BR">`) e "Front paralelo…" (proibidos e exigidos em `app.js` e `index.html`).
- **O front de hoje:** `app.js` com 1782 linhas em seções (avisos, navegação, estado, painel, cartões, ferramentas, sessão, placas, resumo, passo a passo, registro, senha, ligações, tema), estado mutável em variáveis de módulo e `document.getElementById` sobre a marcação do `index.html` (450 linhas, com os textos); `app.css` com 532 linhas e seletores de id.

## Decisões

- **R1. Código de transição `legado-*.js`.** O que não é módulo de base sai do `app.js` para módulos `legado-*.js`, sem reescrever o comportamento. Quantos módulos a fronteira pedir, sem `import` circular, com o estado mutável compartilhado num só deles. Cada um abre com o comentário `// Transicao: sai nas frentes 3 a 5 do redesenho.` *Porquê:* as frentes 3, 4 e 5 trocam essa lógica pelo código do protótipo; dividi-la em telas agora seria trabalho jogado fora (mapa, ajuste 1).
- **R2. Nome de token pelo papel da direção.** Valor de hoje com papel que existe na direção 4.2 (`--fundo`, `--superficie`, `--texto`, `--apoio`, `--acao`, `--foco`, `--sucesso`, `--falha`, `--atencao`…) recebe esse nome. Valor de hoje sem papel na direção recebe nome próprio e o comentário `/* legado: sai na frente 2 */`. *Porquê:* a frente 2 troca valores sem caçar uso.
- **R3. Módulos de base vêm do protótipo.** `dom.js`, `api.js` (`criarApi` e `transporteFetch`), `formato.js`, `constantes.js` e o mecanismo de `textos.js` (`t(chave, dados)`, plurais com `Intl.PluralRules`) partem dos arquivos de mesmo nome em `docs/design/2026-11-ux/prototipo/`, cortados ao que o front de hoje usa. As chaves de `textos.js` são os textos de hoje, sem mudar uma letra.
- **R4. A asserção "www real com zero violações" entra quando o www cumpre** (Task 5). Até lá o `Testes-Front.ps1` prova cada regra numa pasta plantada. Não é afrouxar: a regra nasce inteira e a asserção do www real entra no primeiro commit em que pode ficar verde.

## Task 1: linha de base de paridade

**Files:** nenhum no repo (commit vazio com a prova)

**Skills:** nenhuma.

- Com o painel em simulação (Safety), capture pelo Playwright, a 1366×768, em `.playwright-mcp/paridade/antes/`:
  1. `passo-senha-claro`: sessão nova, passo 1;
  2. `passo-camera-escuro`;
  3. `resumo-claro`;
  4. `painel-vigia-desligado-escuro`;
  5. `painel-decisao-claro` e 6. `painel-decisao-escuro`: falha forçada na câmera 2, parada em decisão;
  7. `painel-concluida-claro`: as 3 câmeras instaladas;
  8. `opcoes-escuro`: topo da tela de Opções;
  9. `ferramentas-claro`;
  10. `encerrado-claro`.
- Para cada captura, anote o passo a passo que a reproduz (cliques, comando de simulação) e as áreas que mudam sozinhas (hora, log, contador). A Task 3 e a 4 refazem os mesmos passos.

**Validation:** as 10 capturas existem. O corpo do commit (`--allow-empty`) traz a lista, o passo a passo de cada uma e as áreas que mudam sozinhas.

## Task 2: `Testes-Front.ps1` com as regras da direção 7.4

**Files:** `fonte/Testes-Front.ps1`, `.github/workflows/release.yml`, `instalador/Gerar-Instalador.ps1`, `CLAUDE.md`

**Skills:** `mattpocock-skills:codebase-design` (a função `Test-Front` é a interface; as regras ficam atrás dela), `mattpocock-skills:tdd`.

- No padrão de `fonte/Testes-Coordenador.ps1` (funções de teste e asserção, resumo "N passaram, M falharam", código de saída diferente de 0 em falha), PowerShell 5.1, sem Node.
- `Test-Front -Www <pasta> -Iss <arquivo> -Servidor <arquivo>` devolve a lista de violações `{ regra, arquivo, linha, trecho }`, com as 10 regras da direção 7.4: `hex`, `medida`, `numero-solto-css`, `numero-solto-js`, `estilo-inline`, `id-no-css`, `camada`, `texto-fora`, `import`, `servido`.
- **RED antes de GREEN, regra a regra:** uma pasta em `$env:TEMP` com uma pasta `www` mínima limpa mais **uma** violação plantada, um `.iss` e um servidor mínimos; o teste espera exatamente aquela regra. Mais a pasta limpa sozinha, esperando zero. Pastas apagadas no fim.
- Entradas do arquivo novo (regra do `CLAUDE.md`):
  - `release.yml`: passo "Testes do front" logo depois de "Testes do coordenador", no mesmo formato;
  - `Gerar-Instalador.ps1`: `'Testes-Front.ps1'` no fim da lista de testes;
  - `CLAUDE.md`, bloco `### Validação`: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Front.ps1` antes de `git diff --check`.

**Validation:** a régua, já com o `Testes-Front.ps1`, verde. Cada uma das 10 regras tem a pasta plantada que a faz falhar sozinha.

## Task 3: CSS em quatro camadas, com os valores de hoje

**Files:** `fonte/web/www/tokens.css`, `base.css`, `componentes.css`, `telas.css` (novos), `fonte/web/www/app.css` (sai), `fonte/web/www/index.html`, `fonte/web/www/app.js`, `instalador/ConfigurarCameras.iss`

**Skills:** `frontend-design` (especificidade controlada por `@layer`, sem id), `design-taste-frontend` (`references/system.md`, só a parte de tokens).

- Cada valor de `app.css` vira token em `tokens.css`, nomeado pela R2. Valor igual, papel igual, um token só.
- `tokens.css` começa com `@layer tokens, base, componentes, telas;`, tem `[data-tema=claro]`, `[data-tema=escuro]` e o comentário `/* quebras: <valores de hoje> */` que o teste lê. `base.css`, `componentes.css` e `telas.css` como na tabela da direção 7.1.
- Seletor de id vira classe ou atributo `data-`; a marcação e o JS ganham a classe onde o CSS precisa (`getElementById` no JS pode ficar).
- `index.html`: os quatro `<link rel="stylesheet">` na ordem da direção, no lugar do `app.css`.
- `.iss`: sai o `Source:` do `app.css`, entram os quatro, um por linha; em `[InstallDelete]`, `Type: files; Name: "{app}\web\www\app.css"`.
- **Paridade:** refaça as 10 capturas da Task 1 em `.playwright-mcp/paridade/depois-css/` e compare pixel a pixel com um script seu no scratchpad (`System.Drawing`, PowerShell 5.1). Diferença só nas áreas anotadas na Task 1; qualquer outra se corrige antes do commit.

**Validation:** a régua. `Test-Front` sobre o `www` real sem violação de `hex`, `medida`, `numero-solto-css`, `id-no-css` e `camada`. Paridade nas 10 capturas, com o resultado da comparação no corpo do commit.

## Task 4: ES modules, textos e constantes; `index.html` vira casca

**Files:** `fonte/web/www/app.js`, `api.js`, `dom.js`, `formato.js`, `constantes.js`, `textos.js`, `legado-*.js` (novos), `fonte/web/www/index.html`, `instalador/ConfigurarCameras.iss`, `fonte/Testes-Motor.ps1`

**Skills:** `mattpocock-skills:codebase-design` (`api.js` é a costura real, com dois adaptadores: o `fetch` daqui e o falso do protótipo; nada de costura com um adaptador só).

- Módulos de base pela R3. `api.js` é o único módulo com `fetch`; os comandos de hoje passam por ele, com o mesmo corpo e a mesma rota.
- O resto do `app.js` vai para `legado-*.js` pela R1. Na mudança:
  - todo texto de UI vai para `textos.js` (chaves por tela), sem mudar uma letra;
  - todo número com sentido (intervalo de consulta, trava, código HTTP, limite) vai para `constantes.js`, com nome;
  - a marcação do `index.html` passa a ser montada com `h()` de `dom.js`, sem `innerHTML` com dado do servidor.
- `app.js` vira o ponto de entrada (`<script type="module" src="/app.js">`): monta a marcação, liga os `legado-*.js` e o ciclo de consulta.
- `index.html` vira casca (direção 7.2, último item): `<html lang="pt-BR">`, `<title>`, as metas de hoje, os quatro CSS, o módulo, `<noscript>` e o ponto de montagem. Nenhum texto no `<body>` fora do `<noscript>`.
- `.iss`: um `Source:` por arquivo novo do `www`, na ordem da direção 7.3 para os que ela lista e depois os `legado-*.js`.
- `Testes-Motor.ps1`, teste "Front paralelo": lê todos os `.js` e `.html` do `www` no lugar de só `app.js` e `index.html`. Os mesmos proibidos e os mesmos exigidos, nenhum a menos.
- **Paridade:** as 10 capturas em `.playwright-mcp/paridade/depois-js/`, comparadas com as da Task 1 como na Task 3. Mais um passeio de comportamento: passo a passo até o Painel, ligar o vigia, falha forçada, "Tentar de novo", porta e canal digitados num cartão, Encerrar o painel. Console sem erro.

**Validation:** a régua. Paridade nas 10 capturas. Console sem erro no passeio. `Test-Front` sobre o `www` real sem violação de `numero-solto-js`, `estilo-inline`, `texto-fora`, `import` e `servido`.

## Task 5: a regra vale no `www` real

**Files:** `fonte/Testes-Front.ps1`, `fonte/web/www/**` (só o que ainda violar)

**Skills:** nenhuma.

- Entra no `Testes-Front.ps1` o teste que roda `Test-Front` sobre `fonte/web/www`, `instalador/ConfigurarCameras.iss` e `fonte/web/Servidor-Painel.ps1` reais e espera zero violações (R4).
- Violação que restar se corrige no `www`, dentro da R1 a R3. Corrigir no `www`, nunca abrir exceção na regra.

**Validation:** a régua com o teste novo verde.

## Task 6: fechar o plano

**Files:** este plano, `docs/plans/2026-11-20-frente-redesenho-mapa.md`

- `**Status:** Concluído (<data>)` e uma linha de fechamento: o que entrou, o que ficou para a frente 2.
- No mapa, a linha da frente 1 com "feita em <data>"; se a frente 1 é a primeira a fechar, o Status do mapa passa a Ativo.

**Validation:** a régua inteira verde; `git diff --check` limpo.
