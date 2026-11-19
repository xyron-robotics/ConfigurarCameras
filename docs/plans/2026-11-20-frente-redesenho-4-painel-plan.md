# Frente redesenho-painel: fila, linha da câmera, "Pede você" e vigia (fase B, 4 de 5)

**Status:** Draft · **Frente:** `redesenho-painel`

Frente 4 do mapa `docs/plans/2026-11-20-frente-redesenho-mapa.md`. Depende da frente 3 fechada (casca, rotas, `componentes.js` com `confirmar`, `formularios.js`, `estado.js`). Especificação: `docs/design/2026-11-ux/direcao.md`, seções 2.3 (cenários 3, 3' e 4a), 3.2, 3.3, 3.6 (estados do Painel e modo de reserva), 5.3 a 5.7 e 6. Código de partida: `docs/design/2026-11-ux/prototipo/tela-painel.js`, `estado.js`, `componentes.js`, `formularios.js`.

**Goal:**
- O Painel da direção 3.2:
  - cabeçalho da fila com fita e legenda;
  - "Pede você" com a decisão;
  - tabela com Fila agora e Registro, uma linha por câmera;
  - porta e canal editáveis na linha da câmera instalada.
- Etapa mostrada é a etapa real do servidor.
- A falha nunca some da fita nem da contagem, e se anuncia sem roubar o foco (decisão do usuário).
- Painel lateral "Mudar o encoder" com o formulário de Câmera da sessão.
- Vigia: estados vazios, modo de reserva e a caixa "Aceitar câmera de fábrica de qualquer faixa" em Sessão > Rede.
- Corrige o bug do `salvarCartao`: hoje, quando o servidor recusa porta e canal, `k.enviado` fica com o valor recusado e o cartão não reenvia o mesmo valor.

**Non-Goals:**
- Ferramentas, o log e os estados globais (Abrindo, conexão perdida, Encerrado, atualização): frente 5.
- Servidor, motor, orquestrador, coordenador e o contrato de `/api/camera`, `/api/decidir`, `/api/vigia`, `/api/fila`. Se o bug do `salvarCartao` pedir mudança no servidor: `BLOQUEADO` com a pergunta.

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
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -SimularCameras 3 -SimularEscala 1 -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-painel`
  - sem `-PastaDados`, a instância única lê o `painel.json` de `%ProgramData%` e pode reabrir o painel instalado;
  - porta 8765 ocupada: use 8766 e anote no commit. Ao terminar, encerre o processo que você subiu;
  - falha forçada: `POST /api/simular` com `{ "ligado": true, "falharEm": { "2": "encoder" } }` (chave é o número da câmera). Para a fila longa da direção 3.2, `-SimularCameras 16`;
  - câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`: pare e devolva `BLOQUEADO`.
- Playwright pelo MCP (`browser_*`), a 1366×768. Capturas em `.playwright-mcp/` (ignorado pelo git), nunca no repo.
- Taste Skill: **nunca** `gate.mjs --start` nem `start.mjs`; não crie `.taste-skill/`; `consistency.mjs`, `perf.mjs` e `shoot.mjs` só com `--profile <scratchpad>/...`.
- Sem push, tag nem release.
- Codificação: `Servidor-Painel.ps1` e o `.iss` em UTF-8 **com BOM**; `Testes-*.ps1` em ASCII, acento por `[char]`; arquivos do `www` em UTF-8 sem BOM, CRLF.
- Skill ou ferramenta MCP indisponível: `BLOQUEADO` dizendo qual.

**Régua de toda Task:** o bloco `### Validação` do `CLAUDE.md`, com o `Testes-Front.ps1` (zero violações no `www` real). A contagem de testes se lê na saída.

## Decisões

- **P1. O estado do Painel sai do `estado.derivar`.**
  - O que entra no módulo: contagens por estado, etapa real ("2 de 4: encoder"), fração da etapa para a fita, falhas abertas, a próxima posição, o grupo "Na espera do portão" e o modo de reserva.
  - A tela só desenha o `modelo`.
  - Cada regra nova do módulo ganha um caso no roteiro Playwright da Task, porque o `www` não tem teste unitário de JS: o seam é a interface `derivar(bruto) -> modelo`.
- **P2. Porta e canal: o que vale é o que o servidor publica.**
  - A linha guarda o valor enviado só até a próxima resposta do `/api/estado`.
  - Na recusa, a linha volta ao valor publicado, o erro aparece junto dos campos (direção 5.6), e um novo envio do mesmo valor é aceito.
  - Isto corrige o `salvarCartao` de `fonte/web/www/app.js` (hoje em `legado-*.js` depois da frente 1), que grava `k.enviado` antes da resposta e nunca o limpa.
- **P3. Foco fica onde está** (decisão do usuário). A falha nova é anunciada em `aria-live="assertive"`, marca a linha e entra no "Pede você". O atalho "Ir para o que pede você" leva o foco ao bloco. O `focarDecisao` sai.
- **P4. "Por broadcast" sai da tela.** A direção 6, regra 5, tira "broadcast" da tela principal. O exigido `'por broadcast'` do teste "Front paralelo" troca pelo texto do vigia paralelo da direção 3.6 ("Esperando câmeras de fábrica"), que guarda o mesmo comportamento: a tela do vigia é a do modo paralelo. É troca de texto guardado, com a mesma força; os outros exigidos e proibidos continuam.

## Task 1: tabela e linha da câmera, com o bug do `salvarCartao`

**Files:** `fonte/web/www/tela-painel.js` (novo), `estado.js`, `componentes.js`, `formato.js`, `textos.js`, `constantes.js`, `componentes.css`, `telas.css`, `legado-*.js`, `instalador/ConfigurarCameras.iss`

**Skills:** `mattpocock-skills:tdd` (RED do bug antes do conserto), `mattpocock-skills:codebase-design` (P1), `design-taste-frontend` (`references/system.md`, tabela e estados).

- **RED primeiro.** Com o painel em simulação e uma câmera instalada, um roteiro Playwright:
  1. envia porta e canal que o servidor recusa;
  2. volta o campo ao valor recusado e sai do campo;
  3. mostra que hoje nenhum `POST /api/camera` sai, pelo `browser_network_requests`.

  Valor que o servidor recusa: leia a validação de `/api/camera` em `Servidor-Painel.ps1` e no coordenador; não invente. Saída do RED no corpo do commit.
- Tabela da direção 5.4, com abas internas "Fila agora" e "Registro":
  - cabeçalho fixo;
  - colunas de máquina em mono e `nowrap` (`UX-33`);
  - "Lendo o registro…" e "Não deu para ler o registro. [Ler de novo]" sem dado velho (`UX-32`);
  - no Registro, "Rack / porta" e "Canal" em texto.
- Linha da câmera da direção 5.3:
  - estado com ícone e palavra, nunca só cor;
  - etapa real com a mini barra de 4 (`UX-04`);
  - porta e canal só na câmera com posição (`UX-03`);
  - "Retomar esta câmera" na já inicializada;
  - linha recém-instalada com `--acao-fraco` por um ciclo.
- P2 aplicada. O mesmo roteiro do RED fica verde.
- O cartão da câmera do `legado-*.js` sai.

**Validation:** a régua. O roteiro do RED verde, com a saída no corpo do commit. Playwright com `-SimularCameras 16`: a tabela mostra a etapa igual à do `/api/estado` em três consultas seguidas; porta e canal salvos aparecem no Registro. Console sem erro.

## Task 2: cabeçalho da fila, fita, estados vazios e vigia

**Files:** `fonte/web/www/tela-painel.js`, `estado.js`, `tela-sessao.js`, `formularios.js`, `componentes.js`, `textos.js`, `constantes.js`, `componentes.css`, `telas.css`, `legado-*.js`

**Skills:** `design-taste-frontend` (`references/system.md`), `frontend-design` (escrita), `dataviz` (a fita como gráfico de estado: legenda, forma além da cor).

- Cabeçalho da fila da direção 3.2:
  - nome e faixa;
  - chip "Vigia ligado" com o token "agora", sem pulso (`UI-15`);
  - "Desligar o vigia", "Montar outra fila" e "Encerrar a fila", esta com o diálogo.
- Fita e legenda da direção 5.5:
  - a falha mais alta e com "!";
  - plural certo (`UX-40`);
  - a fita com `aria-hidden` e uma frase para leitor de tela;
  - clicar numa casa rola a tabela até a linha.
- Estados do Painel da direção 3.6: vigia desligado, vigia ligado sem câmera ("Esperando câmeras de fábrica", com o IP observado e a hora), sem fila, fila encerrada.
- Modo sequencial: "Sem vigia: uma câmera por vez" leva a "Configurar a câmera 3" com "Ligue a câmera 3 no switch".
- Faixa do modo de reserva (direção 3.6 e 5.7), com a instrução da porta UDP 37810.
- Broadcast (direção 3.2): a caixa sai da área do vigia e vai para Sessão > Rede como "Aceitar câmera de fábrica de qualquer faixa", com o risco escrito embaixo, sem `title`. Ligada, o cabeçalho da fila mostra o chip de atenção "Qualquer faixa" (`UX-10`, `UI-11`).

**Validation:** a régua. Playwright: os quatro estados vazios e a faixa de reserva em captura (a reserva forçada pelo que a simulação oferece; se ela não oferece, o estado vem do `estado.derivar` com um bruto montado no `browser_evaluate`, e o corpo do commit diz isso). A contagem da legenda bate com a tabela. Console sem erro.

## Task 3: "Pede você", decisão e painel lateral do encoder

**Files:** `fonte/web/www/tela-painel.js`, `estado.js`, `componentes.js`, `formularios.js`, `textos.js`, `constantes.js`, `componentes.css`, `telas.css`, `legado-*.js`

**Skills:** `design-taste-frontend` (`references/system.md`, acesso e movimento), `frontend-design` (escrita), `web-design-guidelines` (foco, `aria-live`, diálogo).

- Bloco "Pede você" da direção 3.2 e 3.3. Por falha, mostra:
  - o que houve e o conserto;
  - "Tentar de novo" e "Mudar o encoder";
  - "Pular esta posição", que abre o diálogo "Pular a câmera 9?";
  - "Detalhe técnico" com o texto cru em mono.

  Os botões de decisão só existem no DOM da linha em falha e no bloco (`UX-13`). A trava de decisão usa a constante de `constantes.js`.
- Senha recusada: "Tentar de novo" desabilitado, com o motivo visível embaixo (`UI-14`).
- Painel lateral "Mudar o encoder da câmera N":
  - reusa o formulário de Câmera de `formularios.js` (`UX-37`);
  - diz que o valor vale para a sessão inteira;
  - "Salvar e tentar de novo" salva a sessão e decide "tentar de novo";
  - o conteúdo atrás fica `inert`.
- P3: anúncio, atalho "Ir para o que pede você", `focarDecisao` fora.
- Mensagem do servidor: `traduzirServidor` de `textos.js` para as conhecidas, "O painel recusou a ação." com o original em "Detalhe técnico" para as outras.

**Validation:** a régua. Playwright com a falha forçada na câmera 2:
- digitando no campo de porta de outra câmera, o foco fica no campo quando a falha surge;
- o anúncio chega ao `aria-live`;
- "Mudar o encoder" com outro bitrate salva e a câmera termina instalada;
- de novo com falha, "Pular" pede o diálogo, Esc cancela, e confirmar marca a posição como pulada.

Console sem erro.

## Task 4: escrita, documentos e o teste de textos

**Files:** `fonte/web/www/textos.js`, `fonte/Testes-Motor.ps1`, `CONTEXT.md`, `LEIA-ME.md`

**Skills:** `frontend-design` (escrita), `mattpocock-skills:domain-modeling` (linha da câmera no `CONTEXT.md`).

- Textos do Painel pelo glossário da direção 6.
- `Testes-Motor.ps1`, teste "Front paralelo":
  - P4;
  - os rótulos da coluna "Substitui" que esta frente troca entram nos proibidos ("Sem posição", "Ligar vigia", "Câmera conectada", "Atualizar registro").
- `CONTEXT.md`: **Cartão da câmera** passa a **Linha da câmera**, com "antes chamada cartão da câmera"; Decisão sem foco automático.
- `LEIA-ME.md`: a seção da bancada (fila, vigia, porta e canal na linha, Pede você, Mudar o encoder, broadcast em Sessão > Rede).

**Validation:** a régua. Playwright, nos dois temas: os cenários 3, 3' e 4a da direção 2.3 contados (telas, cliques, campos, rolagens), lado a lado com os números da direção no corpo do commit. `grep` por "cartão" no `www` sem resultado.

## Task 5: fechar o plano

**Files:** este plano, `docs/plans/2026-11-20-frente-redesenho-mapa.md`

- `**Status:** Concluído (<data>)` com uma linha de fechamento; no mapa, a linha da frente 4 com "feita em <data>".

**Validation:** a régua inteira verde; `git diff --check` limpo.
