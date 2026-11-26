# Frente redesenho-verificacao: Ferramentas, estados globais e verificação final (fase B, 5 de 5)

**Status:** Concluído (26/11/2026), **sem a bancada real (Task 4 adiada)** · **Frente:** `redesenho-verificacao`

**Fechamento:** entraram a tela Ferramentas da direção 3.4, com o bloco "Resultado" (mono só em IP, MAC, serial e log), o texto corrido em `--texto` e o log do painel saindo do Painel (Task 1); os estados globais na faixa da casca (Abrindo, conexão perdida depois de 3 consultas sem resposta com o resto da tela `inert`, Encerrado sem pedido depois do fim, faixa de atualização), os 7 MENOR herdados da frente 4 e a recusa de porta e canal traduzida (H1 a H8), e o fim dos `legado-*.js`, guardado pela regra `legado` do `Testes-Front.ps1` com o `www` conferido contra a lista da direção 7.3 (Task 2); a verificação final em simulação, com o roteiro de duas filas nos dois temas, `consistency.mjs`, `perf.mjs` e `web-design-guidelines`, e os GRAVE achados (foco perdido em 4 fluxos, campo sob o rodapé fixo) corrigidos (Task 3). **A bancada com uma câmera de fábrica real (Task 4) foi adiada por decisão do usuário (26/11, commit `edbbb3b`): nenhum dos cinco pontos foi conferido no hardware.** Ela fica como pendência aberta, para antes ou logo depois da release 1.3.0, no mapa `docs/plans/2026-11-20-frente-redesenho-mapa.md` e nas Pendências do `LEIA-ME.md`. Os MENOR achados na verificação e nas Tasks 1 e 2 (Non-Goals) estão nos corpos dos commits `06208f2`, `543dd0e` e `8dfedec`.

Frente 5 do mapa `docs/plans/2026-11-20-frente-redesenho-mapa.md`. Depende da frente 4 fechada. Especificação: `docs/design/2026-11-ux/direcao.md`, seções 2.3 (jornada inteira), 3.4, 3.6, 5.7, 7.3 e 7.4. Código de partida: `docs/design/2026-11-ux/prototipo/tela-ferramentas.js`, `app.js`, `componentes.js`.

**Goal:**
- Ferramentas da direção 3.4, com o log do painel saindo do Painel para cá.
- Os estados globais da direção 3.6 e 5.7: Abrindo, conexão perdida, Encerrado e a faixa de atualização.
- O último `legado-*.js` apagado, e o `www` igual à lista da direção 7.3, guardado por teste.
- A fase B verificada de ponta a ponta:
  - nos dois temas, em simulação, com o roteiro de duas filas;
  - na bancada real, com uma câmera de fábrica.

**Non-Goals:**
- Release 1.3.0, tag, push e o `CHANGELOG` da release: vêm depois do mapa, com aprovação do usuário.
- Servidor, motor, orquestrador, coordenador.
- Achado novo de verificação que mude o que o operador vê além da direção: vai para o corpo do commit como pendência, sem conserto nesta frente.

**Touched:**
- `fonte/web/www/**`;
- `fonte/Testes-Front.ps1` (regra `legado` e a lista de arquivos, Task 2);
- `instalador/ConfigurarCameras.iss`;
- `LEIA-ME.md` (Ferramentas e estados, Task 1 e 2);
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
   - Na Task 4, de bancada, nenhum dado da câmera real (MAC, serial, IP de obra) entra em commit, captura versionada ou documento.

**Safety:**
- Tasks 1 a 3: painel só em simulação, rodando do worktree da frente, com pasta de dados própria:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -SimularCameras 3 -SimularEscala 1 -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-verif`
  - sem `-PastaDados`, a instância única lê o `painel.json` de `%ProgramData%` e pode reabrir o painel instalado;
  - porta 8765 ocupada: use 8766 e anote no commit. Ao terminar, encerre o processo que você subiu;
  - falha forçada: `POST /api/simular` com `{ "ligado": true, "falharEm": { "2": "encoder" } }` (chave é o número da câmera);
  - câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`: pare e devolva `BLOQUEADO`.
- Task 4: a única com rede e hardware reais, marcada `[você]`. O executor prepara e para no gesto físico; quem liga cabo, câmera e confirma o que vê é o usuário.
- Playwright pelo MCP (`browser_*`), a 1366×768. Capturas em `.playwright-mcp/` (ignorado pelo git), nunca no repo.
- Taste Skill: **nunca** `gate.mjs --start` nem `start.mjs`; não crie `.taste-skill/`; `consistency.mjs`, `perf.mjs` e `shoot.mjs` só com `--profile <scratchpad>/...`.
- Sem push, tag nem release.
- Codificação: `Servidor-Painel.ps1` e o `.iss` em UTF-8 **com BOM**; `Testes-*.ps1` em ASCII, acento por `[char]`; arquivos do `www` em UTF-8 sem BOM, CRLF.
- Skill ou ferramenta MCP indisponível: `BLOQUEADO` dizendo qual.

**Régua de toda Task:** o bloco `### Validação` do `CLAUDE.md`, com o `Testes-Front.ps1` (zero violações no `www` real). A contagem de testes se lê na saída.

## Decisões

- **V1. O fim do código de transição se guarda por teste.** A regra `legado` entra no `Testes-Front.ps1`: nenhum arquivo `legado-*.js` no `www` e nenhum `import` dele. Ela segue o padrão das outras regras da frente 1, com a pasta plantada que a faz falhar (RED), e o teste passa a conferir o `www` contra a lista da direção 7.3 (24 arquivos), nos dois sentidos.
- **V2. Encerrado para as consultas.** Na tela "Painel encerrado", o ciclo de `CONSULTA_MS` para e nenhum pedido sai depois dela (`UX-35`), provado pelo `browser_network_requests`.
- **V3. Conexão perdida depois de 3 consultas sem resposta**, com o número em `constantes.js`. O resto da tela fica `inert`, e a faixa diz a hora da última resposta.
- **V4. O roteiro de duas filas é a prova de ponta a ponta da simulação.** Cobre os cenários 1, 2b, 3 e 4a da direção 2.3 numa sessão só e roda nos dois temas.

## Herdado da frente 2 (24/11)

Exceção do `consistency.mjs` e achado MENOR da revisão da frente 2 (commits `9d84268` e `008110c`), ambos da Task 1:

- **Mono no resultado da sondagem:** o `.resultado dd` perdeu a família mono e o JS não põe `.mono` no `dd`, então serial, MAC e rede saem em fonte proporcional. No bloco "Resultado" novo, mono só em IP, MAC, serial e log (direção 4.3).
- **Contraste do texto corrido (`text-contrast`):** os parágrafos longos de Ferramentas em `--apoio` dão 6.74:1 no escuro e 6.33:1 no claro, abaixo dos 7:1. Texto corrido longo usa `--texto` (decisão do usuário na frente 2, opção A).

## Herdado da frente 4 (25/11)

Os 7 MENOR da revisão da frente 4 (commit `c9da6ab`) e a mensagem crua de recusa, todos para a Task 2 (decisão do usuário, 25/11). Cada item fecha com a prova no corpo do commit.

- **H1. Recusa de porta e canal de outra linha** (`tela-painel.js:128`): a confirmação aceita qualquer aviso novo com origem `camera` como recusa desta linha. Com duas linhas salvando juntas, a recusa de uma vira o erro da outra. A recusa casa pela câmera, por `cameras[].aviso`, que o `estado.derivar` já guarda.
- **H2. "Qualquer faixa" fica com o valor recusado** (`app.js:48`): `definirQualquerFaixa` grava `extras.qualquerFaixa` antes da resposta e não desfaz na recusa. Mesma regra da P2 da frente 4: vale o que o servidor publica, e a caixa volta a ele na recusa.
- **H3. Painel importa de outra tela** (`tela-painel.js:17`): `salvarParcial` vem de `tela-inicio.js`. Vai para `formularios.js` ou para o `ctx`, e as duas telas importam de lá.
- **H4. Seção vazia em `textos.js:293`**: o cabeçalho "painel (bancada da retomada manual)" sem chave embaixo sai.
- **H5. Estado local da linha sobrevive à fila nova** (`tela-painel.js:55`): rascunho, nota de erro e trava guardados pelo número da posição e nunca limpos. Limpam ao montar outra fila. Uma nota velha não aparece na linha de mesmo número da fila nova.
- **H6. Numeração das posições sem guarda** (`estado.js:167`, correção `25c68ab`): o `www` não tem teste unitário de JS, então o caso entra no roteiro Playwright da Task 2 e de novo no da Task 3. O caso usa um bruto montado no `browser_evaluate`, com uma faixa de 7 IPs (gateway, já no registro e IP que já responde no meio). Esperado: total 5, números 1..5, 1 pulada. Um executor de testes de JS no repo fica fora desta frente.
- **H7. Regra da posição usável repetida** (`estado.js:167` e `legado-painel.js:111`, mesmo regex `/operador|responde/` sobre o `Motivo`): com o `legado-painel.js` apagado, a regra fica só no `estado.js`. Quem mostra "câmera N de M" lê o número do `modelo`.
- **H8. Mensagem crua na recusa de porta e canal**: o erro junto dos campos mostra o texto do servidor (ex.: "Exceção ao chamar Replace… Acesso negado ao caminho"). Passa pelo `traduzirServidor` de `textos.js`. A recusa conhecida (registro só leitura ou em uso) ganha texto com o conserto. As outras dizem "O painel recusou a ação.", com o original em "Detalhe técnico". Só front. Se pedir mudança no servidor: `BLOQUEADO` com a pergunta.

## Task 1: Ferramentas

**Files:** `fonte/web/www/tela-ferramentas.js` (novo), `textos.js`, `constantes.js`, `componentes.css`, `telas.css`, `legado-*.js`, `instalador/ConfigurarCameras.iss`, `LEIA-ME.md`

**Skills:** `design-taste-frontend` (`references/system.md`, formulários e estados), `frontend-design` (escrita).

- Direção 3.4:
  - "Para diagnóstico. Nenhuma delas altera câmera.";
  - Sondar um IP, Verificar o registro, Procurar câmeras ("Só no uso real." em simulação) e Testar a internet;
  - um bloco "Resultado" com tabela ou texto, e o erro com o conserto.
- Log do painel: sai do Painel e entra em Ferramentas, num `<details>` fechado por padrão, linhas em mono, filtro "só avisos e erros".
- Ferramentas do `legado-*.js` saem.
- `LEIA-ME.md`: seção de Ferramentas e onde está o log.

**Validation:** a régua. Playwright: cada ferramenta roda em simulação e mostra o resultado; sondar um IP inválido mostra o erro embaixo do campo. Console sem erro.

## Task 2: estados globais e o fim do `legado-*.js`

**Files:** `fonte/web/www/app.js`, `componentes.js`, `estado.js`, `textos.js`, `constantes.js`, `marca.js`, `tela-painel.js`, `tela-inicio.js`, `formularios.js`, `componentes.css`, `telas.css`, `legado-*.js` (apagados), `fonte/Testes-Front.ps1`, `instalador/ConfigurarCameras.iss`, `LEIA-ME.md`

**Skills:** `mattpocock-skills:tdd` (RED da regra `legado`), `design-taste-frontend` (`references/system.md`, estados e movimento), `frontend-design` (escrita).

- Estados da direção 3.6 e 5.7, uma faixa de cada vez, por prioridade:
  - Abrindo: logo e "Abrindo o painel…", com o topo já na altura final (`UI-06`);
  - conexão perdida (V3);
  - Encerrado: logo, "Painel encerrado. Pode fechar esta janela." (V2);
  - faixa de atualização: "Versão 1.x.y disponível. [Atualizar o painel]", com o diálogo que diz que o painel fecha e reabre.
- O que ainda resta no `legado-*.js` sai. Os arquivos são apagados com `git rm` e saem do `.iss`, com `[InstallDelete]` para eles na instalação por cima.
- V1, RED antes: a regra `legado` falha na pasta plantada, depois passa no `www` real.
- `LEIA-ME.md`: tabela de sintomas com conexão perdida e painel encerrado.
- Herdado da frente 4: H1 a H8.

**Validation:** a régua, com a regra `legado` e a conferência dos 24 arquivos. Playwright:
- Abrindo, em captura com a rede lenta (`browser_evaluate` atrasando o 1º `/api/estado`);
- conexão perdida com o servidor parado: faixa, hora e tela `inert`;
- Encerrado: nenhum pedido sai em 10 s;
- H1: duas linhas salvando juntas, a recusa de uma não aparece na outra;
- H2: "Qualquer faixa" recusada volta ao valor publicado;
- H5: nota de erro na linha 2, montar outra fila, a linha 2 nova sem nota;
- H6: o caso da numeração com 7 IPs dá total 5, números 1..5, 1 pulada;
- H8: com o registro só leitura, a recusa de porta e canal mostra o texto traduzido, e o original fica em "Detalhe técnico".

Console sem erro, fora o erro de rede esperado na conexão perdida.

## Task 3: verificação final em simulação

**Files:** nenhum (Task de prova; `git commit --allow-empty` com a prova). Se a verificação achar defeito do que esta fase B entregou: conserto em `fonte/web/www/**` e no `.iss`, no mesmo commit, com o achado e a prova.

**Skills:** `web-design-guidelines` (sobre o `www` inteiro), `design-taste-frontend` (`consistency.mjs`, `perf.mjs`), `frontend-design`.

- **Roteiro de duas filas (V4)**, com `-SimularCameras 3`, nos dois temas:
  1. Primeira abertura, passo a passo inteiro, fila 1 de 3 posições.
  2. Vigia ligado, falha forçada na câmera 2 (`POST /api/simular`), "Tentar de novo", e a fila termina com 3 instaladas.
  3. Porta e canal salvos em uma linha, que aparecem no Registro. O caso H6 da numeração roda de novo aqui.
  4. Encerrar a fila (diálogo).
  5. Recarregar: abre em Conferir, a linha da Fila oferece "Usar a faixa seguinte".
  6. Fila 2, até concluir.
  7. Encerrar o painel (diálogo), tela de encerrado, nenhuma consulta depois.
- Jornada da direção 2.3 medida (telas, cliques, campos, rolagens por cenário), lado a lado com os números da direção, no corpo do commit.
- `consistency.mjs` com os ids básicos (`a11y-name`, `field-label`, `heading-order`, `tabindex`, `focus-ring`, `focus-visible`, `focus-hidden`, `lang`, `contrast`, `text-contrast`, `button-styles`, `button-shape`, `nesting`, `heading-scale`), nos dois temas.
- `perf.mjs --runs 3` sobre o Painel com 16 posições.
- `web-design-guidelines` sobre `fonte/web/www/`.
- Achados graves do mapa de resolução da direção (seção 9.1): cada um conferido na tela, com o resultado no corpo do commit.

**Validation:** a régua. Roteiro de duas filas completo nos dois temas, console sem erro; `consistency.mjs` sem falha, ou cada exceção no corpo do commit com o porquê; os resultados de `perf.mjs` e do `web-design-guidelines` resumidos no corpo do commit. Capturas em `.playwright-mcp/verificacao/`.

## Task 4: bancada com uma câmera de fábrica real `[você]`

**Files:** nenhum (Task de bancada; `git commit --allow-empty` com a prova, sem dado real).

- `[eu]`: abre o painel do worktree **sem** `-Simular`, com `-PastaDados <scratchpad>\painel-bancada`, e a placa escolhida no passo a passo.
- `[você]`: liga uma câmera Intelbras de fábrica no switch da bancada e diz o que o painel mostra em cada ponto:
  - chip "Placa pronta" depois de "Preparar a placa";
  - Conferir com a sessão;
  - a câmera entrando na fila e terminando "Instalada";
  - porta e canal salvos na linha e vistos no Registro;
  - "Encerrar o painel" devolve a placa ao DHCP.
- O executor para no primeiro `[você]` e devolve `FISICO` com uma instrução; cada retomada traz o que o usuário viu.

**Validation:** os cinco pontos acima confirmados pelo usuário, no corpo do commit, sem MAC, serial nem IP reais. A régua verde.

## Task 5: fechar o plano e o mapa

**Files:** este plano, `docs/plans/2026-11-20-frente-redesenho-mapa.md`

- `**Status:** Concluído (<data>)` neste plano, com uma linha de fechamento.
- No mapa: a linha da frente 5 com "feita em <data>", e o mapa em `**Status:** Concluído (<data>)`, com a release 1.3.0 como próximo passo, que pede a aprovação do usuário.

**Validation:** a régua inteira verde; `git diff --check` limpo.
