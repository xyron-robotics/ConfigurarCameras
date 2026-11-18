# Frente ui-paralela: bancada com N cartões (F6 do mapa)

**Status:** Concluído (18/11) · **Frente:** `ui-paralela`

Fechamento: o item alto da herança (porta e canal não chegavam à câmera) fechou na Task 1 (`feita` aceita porta e canal, gravados no registro) e nos cartões (Tasks 2 e 3: porta e canal digitados no cartão de cada câmera); os dois menores da revisão da `simulacao` (S4 b, `-SemDespacho:$E.Parar` no laço do worker, e o ".." no log do atualizador) fecharam na Task 1; `falharEmCameras` está registrado nas Decisões.

Plano de frente da F6 de `docs/plans/2026-11-cameras-em-paralelo.md`, escrito sobre o `main` em eece536 (frentes `motor`, `orquestrador`, `ui`, `servidor` e `simulacao` fechadas). Leva o item alto da herança da frente `servidor` (seção 0 do mapa: porta e canal não chegam à câmera) e dois menores da revisão da frente `simulacao`. Roda em paralelo com a frente `docs` (F7), que só mexe em documentação e cita os textos fixados em C4. Onde divergir do mapa, vale este plano.

**Goal:** a bancada mostra um cartão por câmera; porta e canal são digitados no cartão e chegam ao registro, inclusive depois de a câmera instalada; a decisão é por cartão; a fita e o vigia falam do modo paralelo.

**Non-Goals:**
- Documentação de usuário, glossário e ADR (F7).
- Câmera real (F8).
- Mudar ordem das etapas, portão, admissão ou o formato do estado publicado (`ConvertTo-EstadoPublicadoParalelo`).
- Mobile.

**Touched:**
- `fonte/web/www/app.js`, `fonte/web/www/index.html`, `fonte/web/www/app.css` (Tasks 2 a 4);
- `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1` (só a Task 1);
- `fonte/web/Servidor-Painel.ps1` (só a Task 1);
- `fonte/Testes-Motor.ps1` (Task 4: teste de texto do front, junto do teste de tema que já lê o `index.html` real);
- este plano (Task 5).

**Safety:**
- Painel só em simulação, com pasta de dados própria e porta fixa, rodando do **worktree**:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -SimularCameras 3 -SimularEscala 5 -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-f6
  ```

  - sem `-PastaDados`, a instância única lê o `painel.json` de `%ProgramData%` e pode reabrir o painel instalado;
  - porta 8765 ocupada: use 8766 e diga no commit;
  - o painel fecha sozinho com 180 s sem página; ao terminar, encerre o processo que você subiu.
- Se o painel simulado mostrar câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`, pare e devolva `BLOQUEADO`: a simulação estaria tocando rede real.
- Playwright pelo MCP (`browser_*`). Capturas no scratchpad ou em `.playwright-mcp/` (ignorado), nunca no repo.
- **Nunca** rodar `gate.mjs --start` nem `start.mjs` da Taste Skill neste repo; não criar `.taste-skill/`.
- Repo público: MAC `AA:00:00:00:00:0x`, serial `SIM-x`, IPs de documentação ou os da rede fictícia dos testes. Antes de cada commit, `git diff --cached` sem dado real.
- Sem push e sem release.
- Codificação: `Servidor-Painel.ps1` e `Coordenador-Cameras.ps1` UTF-8 **com BOM**; `app.js`, `index.html`, `app.css` e `Testes-*.ps1` como já estão. PowerShell 5.1 (`powershell.exe`).

**Régua de toda Task:** o bloco "Validação" do `CLAUDE.md` (Motor, Descoberta, Orquestrador, Coordenador, `git diff --check`). A contagem de testes se lê na saída e não se escreve no plano.

## Estado medido (18/11, na escrita deste plano)

- O servidor já publica `cameras[]` (`mac, serial, modelo, ipOrigem, indice, posicao, destino, porta, canal, fase, etapa, progresso{atual,total}, trabalho, aviso, falha{etapa,erro,recusa,loginRecusado,bloqueada,geracao}`), `portao` (MAC ou null) e `paralelo{max, admitindo, dhip: ok|sem-resposta, emCurso}`. `fila.itens` vem de `filaItens` (`Posicao, Ip, Estado, Motivo, Mac`, chaves em Pascal case). Fases por câmera: `espera|portao|conferindo|decisao|feita|pulada|ignorada` (`Orquestrador-Cameras.ps1`).
- `POST /api/decisao {mac, acao}` (tentar, pular, encerrar; sem `mac`, vale para a primeira em decisão) e `POST /api/camera {mac, porta, canal}` existem e passam com o worker ocupado. A recusa do `/api/camera` volta como aviso global (`avisoN`), não no HTTP (responde 202).
- O front não usa nada disso. `desenharFila` (`app.js`) desenha uma câmera só, pelos campos legados `fase/atual/camera/falha/trabalho/etapa/progresso`, em cinco subblocos (`#bancada-pronta|trabalho|escolha|decisao|fim`). `/api/decisao` sai sem `mac`, e `/api/camera` nunca é chamado.
- **Item alto da herança, confirmado:** porta e canal do formulário do vigia (`W.Vigia.Porta/Canal`) só são publicados em `vigia{}` e logados; nada os copia para `Coord.PortaCanal`. `Set-PortaCanalCoordenador` recusa câmera `feita`. Resultado: no modo vigia o registro sai com porta e canal vazios. O caminho serial ("Câmera conectada", `Invoke-Conectada`) manda os dele.
- Restos de `escolher` no front: `/api/escolher`, `/api/escolher/cancelar`, `#bancada-escolha`, `#escolha-lista`, `#escolha-texto` e os mapas de origem de aviso. O servidor não tem mais essa fase.
- Textos do modo serial em `app.js`: "Tire a câmera anterior e ligue a…", "Em pausa até você resolver a câmera atual.", "Porta e canal somam 1 a cada câmera instalada…", e a trava do "Atualizar" com "Termine a câmera atual…" lendo `fase`.
- Retomada manual pelo IP (`W.Manual`) não entra em `cameras[]`: só aparece nos campos legados (o `Publicar` os sobrescreve).
- Não há Playwright no repo; a frente `ui` usou o MCP (`docs/plans/2026-11-17-frente-ui-plan.md`, Safety e Task 8).

## Decisões

Valem as do mapa (D1–D11, Q1–Q8), as da frente `ui` e as das frentes `servidor` (U1–U3, R1–R8) e `simulacao` (S1–S4). Desta frente:

- **C1. Porta e canal só no cartão.** Saem do formulário do vigia os campos porta e canal e o texto "somam 1". O `POST /api/vigia` continua aceitando os campos (o servidor não muda), a UI só deixa de mandar. *Porquê:* com várias câmeras ao mesmo tempo, a ordem de chegada é a do DHIP, não a do cabo (D10); somar 1 por chegada grava porta errada. Quem identifica a câmera é o operador, pelo serial e pelo MAC da etiqueta. O caminho serial ("Câmera conectada" e a retomada manual) continua com porta e canal no próprio formulário.
- **C2. Editável até a fila fechar** (decisão do usuário, 18/11). A câmera `feita` aceita porta e canal, gravados direto no registro (`Sync-PortaCanalRegistro`). A `pulada` continua recusada. *Porquê:* a conferência pode terminar em segundos; o operador não pode correr contra o relógio para não perder porta e canal.
- **C3. Cartão por MAC, atualizado no lugar.** Cada câmera tem um nó com chave no MAC, criado uma vez e atualizado campo a campo; sem `replaceChildren` nos cartões. Campo com foco ou com texto não salvo nunca é sobrescrito pelo polling. Cada cartão tem uma linha de estado com `aria-live="polite"` que só muda quando a fase muda (o progresso não é anunciado). Câmera que sai de `cameras[]` tem o cartão removido.
- **C4. Textos fixos (contrato com a frente `docs`).** Mudar algum exige atualizar este plano:
  - palavra do estado por fase: `espera` "Na espera", `portao` "No portão", `conferindo` "Conferindo", `decisao` "Falhou", `feita` "Instalada", `pulada` "Pulada", `ignorada` "Já inicializada: não tocada";
  - campos "Porta" e "Canal", com a confirmação "Salvo";
  - botões "Tentar de novo" e "Pular esta posição" no cartão; "Encerrar a fila" como botão da fila;
  - texto do vigia ligado: "Observando <IP> por broadcast. Ligue quantas câmeras quiser no switch: cada uma entra na próxima posição livre. Digite porta e canal no cartão de cada câmera, pelo serial da etiqueta.";
  - sem DHIP (`paralelo.dhip = 'sem-resposta'`): "Sem broadcast: uma câmera por vez." no bloco do vigia.
- **C5. Um acento por vista** (decisão da frente `ui`): só o "Tentar de novo" do primeiro cartão em decisão é `btn acento`; os outros são `btn`.
- **C6. Ordem dos cartões:** pela posição; câmeras sem posição (`posicao = 0`) no fim, na ordem de `cameras[]`. Cartões de `feita` e `pulada` ficam compactos (sem etapas nem barra), mas a `feita` mantém Porta e Canal.
- **C7. Bloco legado só para a retomada manual.** O bloco de câmera única (`#bancada-trabalho`, `#bancada-decisao`) só aparece quando `cameras[]` está vazio e a fase legada é `configurando` ou `decisao` (retomada pelo IP, `W.Manual`). Ali a decisão sai sem `mac`, como hoje.
- **Contrato registrado:** o estado publicado tem também `falharEmCameras` (mapa `n → valor` da simulação, ou `null`; `falharEm` continua texto). Veio do commit d050aa3 (frente `simulacao`) e não estava no mapa. A UI não o usa.

## Task 1: Servidor e coordenador (porta/canal depois de instalada, menores da revisão)

**Files:** `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`, `fonte/web/Servidor-Painel.ps1`

1. **Teste antes do código** em `Testes-Coordenador.ps1`, no padrão dos testes de `Set-PortaCanalCoordenador` e `Sync-PortaCanalRegistro` que já existem (registro em pasta temporária):
   - câmera `feita` no registro com porta/canal vazios; `Set-PortaCanalCoordenador -Porta 7 -Canal 8` → `Ok`, e o registro relido tem porta `7` e canal `8`;
   - segunda edição na mesma `feita` (porta `9`) → registro com `9`;
   - câmera `pulada` → recusa com o texto de hoje, registro intocado;
   - `feita` que não está no registro → `Ok=$false` ou aviso da câmera (o comportamento de `Sync-PortaCanalRegistro`), sem exceção.
   Rodar contra o código de hoje e colar no corpo do commit a falha esperada (`feita` recusada).
2. **Coordenador:** em `Set-PortaCanalCoordenador`, `feita` deixa de ser recusada: grava em `PortaCanal` e chama `Sync-PortaCanalRegistro`. Se a sincronização falhar, devolve `Ok=$false` com o texto do aviso. A docstring passa a dizer "editáveis até a fila fechar; `pulada` recusada".
3. **Servidor, menores da revisão da `simulacao`:**
   - no laço do worker, o `Receive-EventosCoordenador` que roda antes do `if ($E.Parar) { continue }` passa a receber `-SemDespacho:$E.Parar` (S4 b: com `Parar`, nenhum `despachar`);
   - a mensagem "Uma câmera começou durante o download. Atualize de novo quando ela terminar." não sai mais com ".." no log (o log acrescenta ". Nada foi instalado."): acertar a junção.

**Validation:**
- os testes do passo 1 verdes (RED antes, colado no commit);
- `Smoke-Paralelo.ps1 -Cenario basico` e `-Cenario encerrar` com SMOKE OK;
- o teste de BOM do servidor verde;
- a régua.

## Task 2: Cartão da câmera

**Files:** `fonte/web/www/app.js`, `fonte/web/www/index.html`, `fonte/web/www/app.css`

1. Container novo de cartões dentro de `#bancada` (lista com `aria-label="Câmeras em curso"`). Um cartão por item de `cameras[]` (C3, C6), com:
   - cabeçalho: "Câmera N" (posição) ou "Sem posição"; modelo, serial e MAC com `translate="no"`; destino;
   - a palavra do estado (C4) na linha `aria-live`, com cor e palavra (nunca só cor); "No portão" destacado em âmbar (âmbar = "agora", decisão da frente `ui`);
   - etapa atual, `<progress>` com `progresso` e o texto de `trabalho` (só em `portao` e `conferindo`);
   - o `aviso` da câmera, se houver;
   - campos "Porta" e "Canal" (C2: em toda fase menos `pulada` e `ignorada`). Salvam com Enter ou ao sair do campo, se o valor mudou, via `POST /api/camera {mac, porta, canal}`, e mostram "Salvo" quando o valor publicado alcança o digitado. Recusa chega pelo aviso global, como hoje.
2. Tokens e regras da frente `ui`: `--s-*`, `--r-*`, `light-dark()`, corpo 15 px, botão/campo 38 px, `prefers-reduced-motion`, NBSP entre número e unidade.
3. C7: o bloco legado de câmera única só para a retomada manual. O subbloco `pronta` ("Câmera conectada") continua para o caminho sem vigia.

**Validation:**
- Playwright (painel da Safety, 3 câmeras, escala 5): três cartões aparecem e avançam ao mesmo tempo na conferência, cada um com serial e MAC próprios;
- porta/canal digitados num cartão em `conferindo` e noutro já `Instalada`; depois, `GET /api/registro` mostra os dois valores nas câmeras certas;
- com o foco num campo Porta e texto digitado sem salvar, três ciclos de polling não apagam o texto nem tiram o foco (`document.activeElement` conferido);
- capturas clara e escura em 1366×768 (escuro e claro forçados pelo seletor de tema); console sem erro nem violação de CSP;
- a régua.

## Task 3: Decisão por cartão

**Files:** `fonte/web/www/app.js`, `fonte/web/www/index.html`, `fonte/web/www/app.css`

1. Cartão em `decisao` mostra `falha.etapa` e `falha.erro` e os botões "Tentar de novo" e "Pular esta posição" (C4, C5), que mandam `POST /api/decisao {mac, acao}`.
2. "Tentar de novo" desabilitado com `falha.loginRecusado` e `falha.geracao === senhaGeracao`, como hoje; o foco vai a ele só na primeira vez que aquele cartão entra em decisão.
3. Os `confirm()` falam da câmera do cartão ("Pular a câmera N (serial …)? Ela fica como está agora, registrada como Falhou e fora das instaladas. As outras seguem.").
4. "Encerrar a fila" sai do bloco de decisão e vira botão da fila (`btn discreto`, com o `confirm()` de hoje adaptado: "As câmeras em curso terminam antes; as pendentes ficam sem câmera."), visível enquanto a fila está aberta. Manda `POST /api/decisao {acao: 'encerrar'}` sem `mac`.
5. `aplicarOcupado` trava só os botões do cartão que mandou o comando, não os dos outros cartões.

**Validation:**
- Playwright: `POST /api/simular {"ligado": true, "falharEm": {"2": "rede"}}` antes de ligar o vigia; só a câmera 2 cai em "Falhou"; as câmeras 1 e 3 terminam "Instalada" sem esperar a 2; "Tentar de novo" na 2 a leva a "Instalada";
- segunda rodada com `{"3": "encoder"}`: "Pular esta posição" na 3 (aceitando o `confirm`) a deixa "Pulada", e a fita marca a posição como pulada;
- só um botão acento na vista com duas câmeras em decisão (`{"1": "rede", "2": "rede"}`);
- a régua.

## Task 4: Fita, vigia e restos do modo serial

**Files:** `fonte/web/www/app.js`, `fonte/web/www/index.html`, `fonte/web/www/app.css`, `fonte/Testes-Motor.ps1`

1. **Fita:** "agora" em toda posição cujo `cameras[].indice` tem câmera em `portao`, `conferindo` ou `decisao` (várias ao mesmo tempo); "próxima" na primeira pendente sem câmera. Estado em palavra, como hoje.
2. **Vigia:** os textos do C4; saem "Tire a câmera anterior…", "Em pausa até você resolver a câmera atual." e "Porta e canal somam 1…"; saem os campos porta e canal do formulário do vigia (C1). Com `paralelo.dhip = 'sem-resposta'`, a linha "Sem broadcast: uma câmera por vez." aparece no bloco do vigia enquanto durar. O aviso de MAC alternando ("Duas câmeras respondem em …") continua pelo aviso global, no slot do vigia.
3. **Atualizar:** a trava do botão passa a usar `paralelo.emCurso > 0` (ou fase legada `configurando`/`decisao` da retomada manual), com o texto "Espere as câmeras em curso terminarem antes de atualizar."
4. **Restos de `escolher`:** sai todo o código e marcação (`/api/escolher`, `/api/escolher/cancelar`, `#bancada-escolha`, `#escolha-lista`, `#escolha-texto`, entradas nos mapas de origem de aviso e no anúncio de fase).
5. **Teste novo** em `Testes-Motor.ps1`, junto do teste de tema que lê o `index.html` real: lê `web\www\app.js` e `web\www\index.html` reais e confere que não contêm "Tire a câmera anterior", "Em pausa até você resolver", "somam 1", "/api/escolher" nem `bancada-escolha`, e que o `app.js` contém "/api/camera" e "por broadcast".

**Validation:**
- o teste do passo 5 verde (e vermelho antes do passo 2, colado no commit);
- Playwright: com o vigia ligado, o texto do C4 aparece e os antigos não; com duas câmeras em conferência, duas posições "agora" na fita; o botão "Atualizar" travado com câmera em curso e livre depois;
- a régua.

## Task 5: Fechar o plano

**Files:** `docs/plans/2026-11-18-frente-ui-paralela-plan.md`

- `**Status:**` passa a `Concluído`, com uma linha: item alto da herança (porta e canal) fechado na Task 1 e nos cartões; os dois menores da revisão da `simulacao` fechados; `falharEmCameras` registrado nas Decisões. Não editar o mapa: ele muda na raiz, depois que a frente fecha.

**Validation:**
- a régua inteira verde;
- `Smoke-Paralelo.ps1` nos cenários `basico`, `falha-rede-2` e `encerrar` com SMOKE OK;
- matriz de capturas {Sistema claro e escuro via `emulate_media`, Claro forçado, Escuro forçado} × {bancada com 3 cartões em curso, bancada com uma câmera em decisão} em 1366×768, sem texto cortado, contraste ok e anel de foco visível no Tab;
- `git diff --check` limpo.
