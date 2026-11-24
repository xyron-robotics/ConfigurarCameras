# Frente redesenho-navegacao: casca nova, passo a passo, Conferir e Sessão (fase B, 3 de 5)

**Status:** Ativo · **Frente:** `redesenho-navegacao`

Frente 3 do mapa `docs/plans/2026-11-20-frente-redesenho-mapa.md`. Depende da frente 2 fechada. Especificação: `docs/design/2026-11-ux/direcao.md`, seções 2.1, 2.2, 3.1, 3.5, 5.1, 5.2, 5.6, 5.8, 5.9, 6 e 7.2. Código de partida: `docs/design/2026-11-ux/prototipo/` (`app.js`, `rotas.js`, `estado.js`, `componentes.js`, `topo.js`, `formularios.js`, `tela-inicio.js`, `tela-sessao.js`).

**Goal:**
- Casca nova: topo fixo com símbolo, abas Painel, Sessão e Ferramentas, chips de placa, internet e simulação com popover, e "Encerrar o painel" no topo. Rotas por hash, com o voltar do navegador funcionando.
- Passo a passo de 6 passos, Conferir (que confere a fila contra o registro e oferece a faixa seguinte) e Sessão, uma seção por tela.
- Diálogo de confirmação próprio no lugar do `confirm()`, nas telas desta frente.
- "Opções" passa a se chamar "Sessão" na tela, no `CONTEXT.md` e no `LEIA-ME.md` (decisão do usuário).

**Non-Goals:**
- Conteúdo do Painel e de Ferramentas: continuam o `legado-*.js`, montados nas rotas `#/painel` e `#/ferramentas` da casca nova (frentes 4 e 5).
- A caixa do broadcast (sai da área do vigia na frente 4).
- Faixas e estados globais (Abrindo, conexão perdida, Encerrado, atualização): frente 5.
- Servidor, motor, orquestrador, coordenador, contrato das rotas.

**Touched:**
- `fonte/web/www/**`;
- `instalador/ConfigurarCameras.iss`;
- `fonte/Testes-Motor.ps1` (só o teste "Front paralelo", Task 4);
- `CONTEXT.md`, `LEIA-ME.md` (Task 4);
- este plano e o mapa (Task 5).

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
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -SimularCameras 3 -SimularEscala 1 -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-nav`
  - sem `-PastaDados`, a instância única lê o `painel.json` de `%ProgramData%` e pode reabrir o painel instalado;
  - porta 8765 ocupada: use 8766 e anote no commit. Ao terminar, encerre o processo que você subiu;
  - sessão salva: rode o passo a passo uma vez e reabra a página com a mesma `-PastaDados`;
  - câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`: pare e devolva `BLOQUEADO`.
- Playwright pelo MCP (`browser_*`), a 1366×768. Capturas em `.playwright-mcp/` (ignorado pelo git), nunca no repo.
- Taste Skill: **nunca** `gate.mjs --start` nem `start.mjs`; não crie `.taste-skill/`; `consistency.mjs`, `perf.mjs` e `shoot.mjs` só com `--profile <scratchpad>/...`.
- Sem push, tag nem release.
- Codificação: `Servidor-Painel.ps1` e o `.iss` em UTF-8 **com BOM**; `Testes-*.ps1` em ASCII, acento por `[char]`; arquivos do `www` em UTF-8 sem BOM, CRLF.
- Skill ou ferramenta MCP indisponível: `BLOQUEADO` dizendo qual.

**Régua de toda Task:** o bloco `### Validação` do `CLAUDE.md`, com o `Testes-Front.ps1` (zero violações no `www` real). A contagem de testes se lê na saída.

## Decisões

- **N1. Telas novas recebem o modelo.** Toda tela desta frente recebe o `modelo` de `estado.derivar` e um `ctx` com `api`, `rotas` e `confirmar`, sem `fetch` e sem ler o estado bruto (direção 7.2, costuras). O `legado-*.js` que fica (Painel e Ferramentas) ainda lê o estado bruto até a frente que o troca.
- **N2. `estado.js` cresce com o uso.** Entra o que as telas desta frente consomem: placa (regra da direção 5.9), simulação, sessão, senha definida e o conflito da fila com o registro. Contagens, etapa real e falha entram na frente 4, quando o Painel novo as usa. Parte do `estado.js` do protótipo, que já lê o formato real do `/api/estado`.
- **N3. Sem mudança de comportamento no servidor.** Mudar placa ou faixas em Sessão continua devolvendo e preparando a placa como hoje (`LEIA-ME.md`, seção da sessão); a tela só passa a dizer isso junto do botão.
- **N4. Texto velho vira proibido.** Os rótulos da coluna "Substitui" do glossário da direção (seção 6) que esta frente troca entram nos proibidos do teste "Front paralelo" de `fonte/Testes-Motor.ps1` (mapa, ajuste 7).

## Herdado da frente 2 (24/11)

Exceções do `consistency.mjs` e achados MENOR da revisão da frente 2 (commits `9d84268` e `008110c`) que a casca e as telas desta frente resolvem. Cada um vale para a Task indicada:

- **Task 1, escala dos títulos (`heading-scale`):** o título da tela vira o `h1` da página; o nome no topo deixa de ser `h1`. Os tamanhos continuam os da direção 4.3.
- **Task 1, `theme-color` do escuro:** a meta do `index.html` ainda diz `#23272A` (superfície antiga); passa a acompanhar `--superficie` do escuro (`#212427`).
- **Task 2, mono no Conferir:** IP e MAC do Conferir em mono (direção 4.3). O `.resumo-secao dd` do Resumo de hoje perdeu a família mono e o nó não tem `.mono`; o Conferir não repete isso.
- **Task 2, estilos de botão (`button-styles`):** a trilha de número, palavra e ícone (`UI-10`) não conta como terceiro estilo de botão ao lado do primário e do secundário.
- **Task 3, contraste do texto corrido (`text-contrast`):** em Sessão, texto corrido longo usa `--texto`, não `--apoio` (decisão do usuário na frente 2, opção A: os tokens da direção 4.2 ficam; o texto que o checker cobra passa a `--texto`).
- **Task 3, rótulo de campo (`field-label`):** o campo "Outro valor" de quadros por segundo e bitrate tem rótulo visível, não só `aria-label`. A frente 4 herda isso no painel lateral do encoder.

## Task 1: casca nova (topo, rotas, componentes, diálogo)

**Files:** `fonte/web/www/app.js`, `rotas.js`, `estado.js`, `componentes.js`, `topo.js` (novos ou trocados), `textos.js`, `constantes.js`, `componentes.css`, `telas.css`, `legado-*.js`, `instalador/ConfigurarCameras.iss`

**Skills:** `mattpocock-skills:codebase-design` (`estado.js` como módulo profundo; aplique o teste da deleção e registre no commit), `frontend-design`.

- `rotas.js`: rotas da direção 2.1 (`#/inicio/<passo>`, `#/conferir`, `#/painel`, `#/painel/registro`, `#/sessao/<secao>`, `#/ferramentas`); ao trocar de tela, foco no título e rolagem no topo (`UX-06`).
- `componentes.js`: botão (direção 5.1), campo (5.2), aviso junto do controle e no `aria-live` (5.6), chip e popover (5.9) e `confirmar(opcoes) -> Promise<boolean>` com `<dialog>` e `showModal()` (5.8).
- `topo.js`: topo fixo de `--topo-altura`, com símbolo, nome, as três abas, os chips e "Encerrar o painel" (diálogo "Encerrar o painel?"). A barra colorida e a faixa de simulação de hoje saem: a simulação é chip neutro (`UI-08`), e a falha forçada aparece no popover dele (`UX-08`).
- `app.js`: ciclo de consulta (`CONSULTA_MS`), `estado.derivar`, montagem da tela da rota. O menu lateral de hoje sai; Painel e Ferramentas do `legado-*.js` se montam nas rotas deles.
- `.iss`: `Source:` dos módulos novos, na ordem da direção 7.3.

**Validation:** a régua. Playwright: cada aba abre pela URL e pelo clique; voltar do navegador volta de tela; Encerrar o painel pede o diálogo, Esc cancela, o foco inicial fica em Cancelar; chips neutros em simulação. Console sem erro. `consistency.mjs` (`--profile` e `--out` no scratchpad) nos dois temas, numa tela da casca: `heading-scale` sem FAIL; a meta `theme-color` do escuro igual à `--superficie` do escuro.

## Task 2: passo a passo de 6 passos e Conferir

**Files:** `fonte/web/www/tela-inicio.js`, `formularios.js` (novos), `textos.js`, `constantes.js`, `estado.js`, `componentes.css`, `telas.css`, `legado-*.js`, `instalador/ConfigurarCameras.iss`

**Skills:** `design-taste-frontend` (`references/system.md`, formulários e acesso), `frontend-design` (escrita).

- `formularios.js`: uma definição por seção (`senha`, `placa`, `rede`, `camera`, `fila`), usada pelo passo a passo, por Sessão e, na frente 4, pelo painel lateral (`UX-37`).
- Os 6 passos da direção 2.2, com a trilha de número, palavra e ícone (`UI-10`) e o rodapé fixo com Voltar e Avançar ou Começar (`UX-20`):
  - Senha: em simulação, "Senha não usada em simulação" (`UX-07`);
  - Placa: a sugerida marcada; a placa que leva à internet ganha a nota na própria linha, sem `confirm()` (`UX-17`); erro de leitura com "Ler as placas de novo" (`UX-31`);
  - Rede: faixa de fábrica num `<details>` recolhido com o resumo e "Alterar";
  - Câmera: um valor de bitrate, o recomendado selecionado, "Outro valor" abre o campo (`UX-18`); explicação em uma frase e um `<details>` "Por que isso importa" (`UI-12`);
  - Fila: prévia com quantas posições a faixa tem e quantas já estão no registro (`/api/registro`, no cliente);
  - Conferir: uma linha por seção com "Alterar a <seção>".
- Com sessão salva, o painel abre em Conferir, com a linha da senha no topo. Se a fila toda já está no registro, a linha da Fila diz isso e oferece "Usar a faixa seguinte (<primeiro> a <último>)" (`UX-16`, `UX-27`).
- Saem o passo a passo de 7 passos, o Resumo e o "Usar essa sessão / Revisar" do `legado-*.js`.

**Validation:** a régua. Playwright, nos dois temas: cenário 1 (primeira abertura até o Painel) e cenário 2a (sessão salva com a última fila instalada até o Painel) contados como na direção 2.3; os números de telas, cliques, campos e rolagens vão no corpo do commit, lado a lado com os da direção. Console sem erro. `consistency.mjs` nos dois temas, num passo e no Conferir: `button-styles`, `text-contrast`, `field-label` e `heading-scale` PASS; IP e MAC do Conferir com família mono no estilo computado.

## Task 3: Sessão

**Files:** `fonte/web/www/tela-sessao.js` (novo), `formularios.js`, `textos.js`, `constantes.js`, `marca.js`, `componentes.css`, `telas.css`, `legado-*.js`, `instalador/ConfigurarCameras.iss`

**Skills:** `design-taste-frontend` (`references/system.md`, formulários), `frontend-design`.

- Direção 3.5: seções Senha, Placa, Rede, Câmera, Fila à esquerda e, separada, Painel; a escolhida à direita, na rota `#/sessao/<secao>`.
- "Salvar alterações" em toda seção, que confirma com "Alterações salvas" junto do botão e no `aria-live` (`UX-14`, `UI-19`). Erro embaixo do campo, ao salvar, com `aria-invalid` e `aria-describedby`; o erro do servidor vira erro no formulário, sem `confirm()`.
- Seção Painel: Tema (Sistema, Claro, Escuro), versão com "Procurar atualização", "Refazer o passo a passo" (diálogo) e o bloco "Sobre" com a logo inteira. "Encerrar o painel" fica só no topo.
- A tela de Opções do `legado-*.js` sai.

**Validation:** a régua. Playwright: cada seção abre pela rota; salvar mostra "Alterações salvas"; um campo inválido mostra o erro embaixo dele; trocar o tema vale na hora e depois de recarregar. Console sem erro. `consistency.mjs` nos dois temas, nas seções Câmera e Painel: `text-contrast`, `field-label`, `button-styles` e `heading-scale` PASS.

## Task 4: escrita, documentos e o teste de textos

**Files:** `fonte/web/www/textos.js`, `fonte/Testes-Motor.ps1`, `CONTEXT.md`, `LEIA-ME.md`

**Skills:** `frontend-design` (escrita), `mattpocock-skills:domain-modeling` (a entrada Sessão e o termo Opções no `CONTEXT.md`).

- Textos das telas desta frente pelo glossário e pelas regras da direção 6: verbo mais objeto, plural certo, nada de "ifIndex", "DHIP" ou "broadcast" na tela principal; mensagem do servidor conhecida traduzida por `traduzirServidor`, a desconhecida como "O painel recusou a ação." com o original em "Detalhe técnico".
- `Testes-Motor.ps1`, teste "Front paralelo": N4. Os exigidos continuam todos.
- `CONTEXT.md`: Sessão "editada em Sessão"; a entrada **Opções** passa a **Sessão (tela)** com "antes chamada Opções"; passo a passo de 6 passos com Conferir.
- `LEIA-ME.md`: passo a passo, Conferir, Sessão no lugar de Opções (inclusive na tabela de sintomas), Encerrar o painel no topo.

**Validation:** a régua. `grep` por "Opções" no `www`, no `CONTEXT.md` e no `LEIA-ME.md` só acha a menção "antes chamada Opções".

## Task 5: fechar o plano

**Files:** este plano, `docs/plans/2026-11-20-frente-redesenho-mapa.md`

- `**Status:** Concluído (<data>)` com uma linha de fechamento; no mapa, a linha da frente 3 com "feita em <data>".

**Validation:** a régua inteira verde; `git diff --check` limpo.
