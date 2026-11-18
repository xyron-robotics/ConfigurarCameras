# Frente servidor: coordenador e pool (F4 do mapa)

**Status:** Concluído · **Frente:** `servidor`

Fechado em 18/11: o contrato publicado da Task 4 (`ConvertTo-EstadoPublicadoParalelo`) é o que a F6 consome, e a F5 restante (`FalharEm` por câmera, cenários `mac-trocado`/`ja-inicializada`, atrasos por etapa) segue no mapa.

Plano de frente da F4 de `docs/plans/2026-11-cameras-em-paralelo.md`, escrito sobre o `main` integrado depois das frentes `motor`, `orquestrador` e `ui` fecharem. Onde divergir do mapa, vale este plano (as divergências estão em "Decisões").

**Goal:** ligar o orquestrador ao painel. O worker do servidor vira coordenador: executa as ações dos `Step-*` (`prender`, `soltar`, `despachar`, `avisar`), roda um job por câmera num RunspacePool e publica o estado por câmera. Com 3 câmeras de fábrica simuladas, as três passam pelo portão uma por vez e conferem ao mesmo tempo, e o painel continua respondendo.

**Non-Goals:**
- UI com N cartões (F6). A UI atual só precisa carregar sem erro.
- `FalharEm` por câmera, cenários `mac-trocado`/`ja-inicializada` na simulação, atrasos por etapa (F5).
- Documentação de usuário e ADR (F7).
- Câmera real (F8).
- Mexer em `Motor-Cameras.ps1`.

**Touched:**
- `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1` (Task 1);
- `fonte/Coordenador-Cameras.ps1` (novo), `fonte/Testes-Coordenador.ps1` (novo);
- `fonte/web/Servidor-Painel.ps1`;
- `fonte/testes/Smoke-Paralelo.ps1` (novo; fora do CI e do instalador);
- `.github/workflows/release.yml`, `instalador/Gerar-Instalador.ps1`, `instalador/ConfigurarCameras.iss`, `CLAUDE.md` (régua);
- `fonte/Testes-Motor.ps1` (só os testes de texto do servidor, se a mudança os quebrar);
- este plano (Task 9).

**Safety:**
- Sem rede, placa ou câmera reais. As 3 câmeras de fábrica da bancada ficam reservadas para a F8 e têm de continuar de fábrica.
- Teste de placa só com as funções pequenas do motor trocadas por falsas (`Get-VizinhoPlaca`, `New-VizinhoPlaca`, `Remove-VizinhoPlaca`, como o `Testes-Motor.ps1` já faz).
- O servidor só sobe com `-Simular -SemElevar -SemNavegador -PastaDados <pasta temporária>`.
- Repo público: MAC `AA:00:00:00:00:0x`, serial `SIM-x`, IPs de documentação (192.0.2.x) ou 192.168.1.108. Antes de cada commit, `git diff --cached` sem dado real.
- Sem push e sem release.
- Codificação:
  - `Servidor-Painel.ps1` UTF-8 **com BOM** (há teste);
  - `Coordenador-Cameras.ps1` UTF-8 com BOM (tem acento, como o orquestrador);
  - `Testes-Coordenador.ps1` sem BOM e sem acento no código (padrão do `Testes-Orquestrador.ps1`).
- PowerShell 5.1 (`powershell.exe`).

**Régua de toda Task:** o bloco "Validação" do `CLAUDE.md`, mais `Testes-Coordenador.ps1` a partir da Task 2. A contagem de testes se lê na saída e não se escreve no plano.

## Decisões

Valem as do mapa (D1–D11, Q1–Q8). Desta frente:

**Do usuário (18/11):**
- **U1. O mínimo da F5 vem para cá.** O DHIP simulado devolve 3 câmeras de fábrica (`AA:00:00:00:00:01..03`, `SIM-1..3`, IP de fábrica, `Init=1`, marca Intelbras). O job em simulação espera um pouco (portão ~1 s, conferência ~4 s; parâmetro `EsperaSimuladaSeg` do coordenador) para a sobreposição ser visível. A F5 fica com `FalharEm` por câmera, os cenários `mac-trocado`/`ja-inicializada` e os atrasos por etapa.
- **U2. Coordenador num arquivo próprio.** A lógica fica em `fonte/Coordenador-Cameras.ps1`, com as dependências injetáveis `Prender`, `Soltar`, `Pingar`, `Descobrir`, `Despachar` e `Agora`, e é testada por `fonte/Testes-Coordenador.ps1` (no CI). O servidor só faz a fiação.
- **U3. "Câmera conectada" sem IP = "procurar agora"** (tique imediato do vigia, pelo orquestrador). A tela, as rotas e os comandos `escolher`/`cancelar-escolha` saem. Com IP (retomada de câmera já inicializada), continua serial e "uma por vez" (D1), e é recusada com câmera em curso.

**Técnicas (pontos em aberto do handoff da F4):**
- **R1. "Tentar de novo" com a rede já gravada retoma pela conferência, sem portão.** Se a última etapa feita é `rede`, o `tentar` põe `Retomar='conferencia'`. A admissão despacha direto a conferência (`AteEtapa` vazio, sem `prender`), sem ocupar o portão e dentro do `Max`. As outras falhas voltam pelo portão, como hoje, e a retomada do motor (`Get-PlanoRetomada`) acha a câmera na origem ou no destino. *Porquê:* pelo portão funcionaria (o motor acha a câmera no destino), mas prenderia um MAC ausente no IP de fábrica e seguraria as câmeras de fábrica durante o ping.
- **R2. O `despachar` não muda.** O servidor lê a câmera no estado. Ele precisa dela de qualquer jeito para montar o contexto (`IpOrigem`, `HttpPort`, `Serial`, `ConferirInit`).
- **R3. MAC lido desconhecido não entra na espera** (escolha do executor da F3, mantida). Se for de fábrica, o DHIP do próximo tique o traz pela regra normal (D8).
- **R4. A admissão percorre a espera em ordem de chegada.** Admite a primeira câmera que pode entrar: com posição reservada (tentar) ou, se for nova, com posição pendente. "Sem posição livre" só vale para câmera sem reserva. `Admitindo=$false` (encerrar a fila) barra só câmera sem reserva, porque a nova tentativa é do operador e o mapa diz "para de admitir câmeras novas".
- **R5. "Encerrar a fila" ≠ "encerrar o painel".**
  - Encerrar a fila = `Step-Decisao -Acao encerrar` / `POST /api/decisao {acao:'encerrar'}`. Passa sempre.
  - Encerrar o painel = `POST /api/encerrar`, comando `encerrar-painel` no `Step-Comando`. Recusado com câmera em curso.
  - Nenhum identificador novo usa "encerrar" sem complemento.
- **R6. Falha ao prender = decisão** daquela câmera (etapa `portao`), não volta à espera. *Porquê:* voltar à espera readmitiria a mesma câmera na volta seguinte, num laço de `New-NetNeighbor`. Desvia do texto da D7, que só cobre MAC trocado.
- **R7. MAC trocado na conferência = decisão comum.** A D7 (volta à espera, posição pendente) vale só no portão. Na conferência, a rede já foi gravada, e liberar a posição causaria conflito de IP.
- **R8. Fase nova `ignorada`.** Com `ConferirInit`, o job consulta a câmera presa. Se ela estiver inicializada: solta, a posição volta a pendente e sai um aviso único. *Porquê:* `pulada` confundiria com "pulada pelo operador".

**Estrutura:**
- **Fonte única das posições:** `Posicoes` do estado paralelo. `$W.Fila.Itens` deixa de existir como cópia, e `fila.itens` é publicado a partir do estado.
- **Ocupado:**
  - `$E.Ocupado` = comando bloqueante em execução;
  - `$E.EmCurso` = câmeras em `portao` + `conferindo`.
  - O listener recusa (409) os comandos guardados com `EmCurso>0`, com o texto de `Get-TextoRecusaComando`. O worker confere de novo com `Step-Comando` (corrida).

## Task 1: Orquestrador: ajustes que o coordenador consome

**Files:** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`

Escrever primeiro os testes que falham. Depois:
- **R1:**
  - no `Step-FimDoJob`, a falha guarda `Etapa` (a última feita) como hoje;
  - o `Step-Decisao tentar`, com `Etapa -eq 'rede'`, põe `Retomar='conferencia'` (campo novo, `''` em `New-CameraDoAchado`) e não limpa a reserva;
  - o `Step-Admissao` despacha cada câmera em espera com `Retomar='conferencia'` e posição reservada: `despachar` com `AteEtapa=''`, `Posicao` e `Destino`, fase `conferindo`, sem `prender`, sem ocupar o portão, dentro do `Max`. Pode despachar várias numa chamada, além de no máximo uma no portão.
- **R4:**
  - a admissão percorre a espera em ordem e escolhe a primeira que pode entrar no portão (reserva própria ou posição pendente);
  - "sem posição livre" só vai para câmera sem reserva;
  - `Admitindo=$false` barra só câmera sem reserva.
- **R7:** `MacTrocado` com a câmera em `conferindo` segue o ramo de falha (decisão). O ramo D7 fica só para o `portao`.
- **R8:** campo de resultado `NaoDeFabrica`. No portão: `soltar`, fase `ignorada` (entra em `Get-Resumo`), `Indice=0`, posição de volta a `pendente`, e `avisar` "Câmera já inicializada: não tocada." uma vez por MAC (`Avisados`).
- **`Step-Comando`:**
  - comandos novos guardados: `preparar-placa` ("preparar a placa de rede"), `ferramenta` ("usar as ferramentas"), `retomar` ("retomar uma câmera pelo IP"), `refazer-sessao` ("refazer a sessão") e `encerrar-painel` ("encerrar o painel");
  - o texto vem de uma função pura nova, `Get-TextoRecusaComando -Comando -EmCurso`, que o listener também usa.

**Validation:** testes novos verdes, mais o `Testes-Orquestrador.ps1` inteiro:
- falha na conferência → tentar → admissão despacha a conferência sem `prender`, com o portão ocupado por outra câmera, e a posição continua a mesma;
- primeira em espera sem posição e a de trás com reserva → a de trás entra;
- tentar depois de encerrar a fila → entra; câmera nova depois de encerrar → não entra;
- MAC trocado na conferência → decisão;
- `NaoDeFabrica` → `ignorada`, posição pendente, aviso único;
- tabela comando × estado com os comandos novos;
- `Get-TextoRecusaComando` com 1 e com N câmeras.

## Task 2: Coordenador: esqueleto, execução das ações, testes no CI

**Files:** `fonte/Coordenador-Cameras.ps1` (novo), `fonte/Testes-Coordenador.ps1` (novo), `.github/workflows/release.yml`, `instalador/Gerar-Instalador.ps1`, `instalador/ConfigurarCameras.iss`, `CLAUDE.md`

- **`New-Coordenador -Posicoes -Max -Deps`:** guarda o estado paralelo (`New-EstadoParalelo`), a tabela de jobs por MAC, a fila de eventos (`ConcurrentQueue`), os avisos globais e por câmera, porta/canal por câmera e a geração da senha usada em cada despacho.
- **`Invoke-AcoesCoordenador -Coord -Acoes`:** executa em ordem.
  - `prender`/`soltar` via `Deps`.
  - Se `prender` falha: não despacha e alimenta `Step-FimDoJob` com o resultado sintético `{Ok=$false; Falhou='portao'; Erro}` (R6).
  - `despachar` chama `Deps.Despachar`, que a Task 3 liga ao pool.
  - `avisar` com MAC de câmera do estado vai para o aviso daquela câmera; sem MAC, ou de câmera fora do estado, vai para o aviso global.
  - `publicar` marca o estado como sujo.
- **`New-DepsPlaca -IfIndex -CaminhoRastro -Simular`:**
  - `Prender` = `Set-VizinhoEstatico`, mais `Vizinhos` no rastro (`Merge-SessaoPlaca` + `Save-JsonAtomico`), mais o IP temporário se a origem estiver fora das faixas da placa (`Add-IpTemporarioPlaca`);
  - `Soltar` = `Remove-VizinhoEstatico`, mais o vizinho fora do rastro, mais `Remove-IpTemporarioPlaca`;
  - em `-Simular`, os dois só logam.
- **`ConvertTo-AchadoParalelo`:** item de `Find-CamerasNaRede` → `{Mac, Serial, Modelo, Ip, HttpPort, Init, Marca}`.
- **CI e instalador:**
  - `Testes-Coordenador.ps1` entra em `release.yml`, no `foreach` e no comentário do `Gerar-Instalador.ps1`, e na régua do `CLAUDE.md`;
  - `Coordenador-Cameras.ps1` entra no `.iss`, ao lado do orquestrador.

**Validation:** `Testes-Coordenador.ps1` verde com `Deps` falsas:
- ordem `prender` → `despachar`;
- `prender` falho → decisão na etapa `portao`, sem `despachar`;
- `soltar` no fim do portão;
- roteamento do `avisar`;
- `ConvertTo-AchadoParalelo` com a fixture `fonte/testes/dhip-duas-de-fabrica-mesmo-ip.json`;
- `New-DepsPlaca` com as funções pequenas do motor falsificadas: vizinho no rastro ao prender e fora ao soltar.

`Select-String` mostra o arquivo novo em `release.yml`, `Gerar-Instalador.ps1`, `.iss` e `CLAUDE.md`.

## Task 3: Pool e jobs

**Files:** `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`

- **`New-PoolCameras -Max`:** `RunspacePool` de 1 a N, com N = número de posições da fila (Q2: sem limite próprio).
- **`Start-JobCamera`:** recebe câmera (lida do estado, R2), ação, contexto, senha (só em memória), padrões, caminho do registro, `-Simular`, `FalharEm`, geração e `EsperaSimuladaSeg`.
  - O job faz dot-source do motor uma vez por runspace e chama `Set-MotorLog` sem arquivo, com um sink que enfileira `{Mac, Tipo='log', Texto, Cor}`. `Set-MotorProgresso` enfileira `{Mac, Tipo='progresso', Etapa, Atual, Total, Detalhe}`.
  - Com `ConferirInit`, no real, o job chama `Get-CamInitStatus` na origem antes do motor (a câmera já está presa). Se ela não for de fábrica, devolve `NaoDeFabrica=$true` sem chamar o motor.
  - Em simulação, o job espera `EsperaSimuladaSeg` antes de chamar o motor.
  - No `finally`, enfileira `{Mac, Tipo='fim', Resultado}`.
- **`New-ContextoJob`:** câmera do estado (`IpOrigem`, `HttpPort`, `Mac`, `Serial`), `Destino` da ação, Local/Rack/Andar da fila e porta/canal do cartão.
- **`Receive-EventosCoordenador`:** drena a fila de eventos.
  - `log` vai para o callback (o servidor manda para `$adicionarLog` e para o arquivo, com o MAC curto no prefixo).
  - `progresso` atualiza a câmera.
  - `fim` chama `Step-FimDoJob` com a geração do despacho, depois `EndInvoke`/`Dispose` e executa as ações.
  - Handle concluído sem `fim` (exceção) vira o resultado sintético `{Ok=$false; Falhou=<etapa do último progresso>; Erro='erro interno no job: ...'}`.

**Validation:** `Testes-Coordenador.ps1` com pool real e o motor em `-Simular`:
- 3 câmeras (`AA:00:00:00:00:01..03`) terminam `feita`;
- o registro temporário fica com 3 `Instalada`, com MACs e destinos distintos;
- nunca mais de 1 MAC preso ao mesmo tempo (contador no `Prender` falso);
- as conferências se sobrepõem (janelas de tempo pelos eventos, com `EsperaSimuladaSeg` curto);
- a senha `NaoPodeVazar#9` não aparece em nenhum evento;
- job que lança exceção → decisão daquela câmera, e as outras terminam.

## Task 4: Estado publicado (contrato da F6)

**Files:** `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`

- **`ConvertTo-EstadoPublicadoParalelo -Coord`:**
  - `cameras: [{mac, serial, modelo, ipOrigem, indice, posicao, destino, porta, canal, fase, etapa, progresso:{atual,total}, trabalho, aviso, falha:{etapa, erro, recusa, loginRecusado, bloqueada, geracao}}]`;
  - `portao: mac|null`;
  - `paralelo: {max, admitindo, dhip: 'ok'|'sem-resposta', emCurso}`;
  - `filaItens` a partir de `Posicoes`.
- **Campos legados derivados,** para a UI atual seguir até a F6:
  - `fase`: `configurando` com câmera em curso; `decisao` com câmera em decisão; `concluida` quando nenhuma posição está pendente ou reservada e não há câmera em curso; `encerrada` com `Admitindo=$false` e nada em curso; senão `fila`;
  - `atual`, `camera` e `falha`: da primeira câmera em decisão, senão da primeira em curso.
- Este contrato é a base da F6. Não mudar sem atualizar este plano e o mapa. Em relação ao mapa, acrescenta `aviso` por câmera, `paralelo.emCurso`, `filaItens` e a fase `ignorada` (R8).

**Validation:**
- teste do formato com 2 câmeras (uma conferindo, outra em decisão), passando por `ConvertTo-Json -Depth 12` e `ConvertFrom-Json`;
- tabela de derivação dos campos legados (ocioso, em curso, decisão, concluída, encerrada).

## Task 5: Servidor: laço do coordenador, em simulação

**Files:** `fonte/web/Servidor-Painel.ps1`, `fonte/testes/Smoke-Paralelo.ps1` (novo)

- **Carga:** o worker faz dot-source do orquestrador e do coordenador (mesmo caminho do motor).
- **Laço que não bloqueia:** a cada volta faz, em ordem:
  1. comando;
  2. `Receive-EventosCoordenador`;
  3. tique do vigia, quando for a vez, e admissão;
  4. `Invoke-AcoesCoordenador`;
  5. `Publicar`, se o estado está sujo ou a cada ~250 ms.
- **`Invoke-MontarFila`** cria o coordenador e o pool. `$W.Fila.Itens` sai, e `Publicar` junta o contrato da Task 4.
- **`-Simular`:** o DHIP simulado devolve as 3 câmeras (U1), e `Deps` são de simulação.
- **`$E.EmCurso`** é publicado. `Add-Comando` deixa passar `decisao`, `vigia` e `camera`.
- **`conectada` sem IP** = tique imediato (U3). As rotas `/api/escolher` e `/api/escolher/cancelar` e os comandos `escolher`/`cancelar-escolha` saem.
- **`Smoke-Paralelo.ps1`:**
  - sobe o servidor com `-Simular -SemElevar -SemNavegador -PastaDados <temp> -Porta <livre>`;
  - monta uma sessão e uma fila fictícias de 3 posições e liga o vigia;
  - consulta `GET /api/estado` a cada 100 ms, medindo a latência;
  - imprime as fases por câmera ao longo do tempo;
  - encerra o painel no fim.
  - Não entra no CI nem no instalador.

**Validation:**
- saída do `Smoke-Paralelo.ps1` colada no commit: 3 câmeras `feita`, pelo menos 2 `conferindo` ao mesmo tempo, latência máxima abaixo de 500 ms, processo encerrado;
- a UI atual carrega em `-Simular -Porta 8765` sem erro no console (Playwright, se a ferramenta estiver disponível; senão, dizer que não foi verificado);
- a régua.

## Task 6: Vigia paralelo no real (DHIP, reserva sem DHIP, avisos)

**Files:** `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`, `fonte/web/Servidor-Painel.ps1`

- **`Invoke-TiqueParalelo -Coord -Achados -Registro -DhipRespondeu -PingFabrica -MacArp`:**
  1. `Step-Descoberta`, depois `Step-JaInicializada` (o registro chega como dado, lido pelo servidor);
  2. se o DHIP ficou vazio e o IP de fábrica responde ao ping: `dhip='sem-resposta'`, `Max=1`, o aviso da D9 e um achado do ARP com `Init=-1` (entra com `ConferirInit`, e o portão confere);
  3. com o DHIP de volta: `Max=0`.
  - `Test-MacTrocandoNoIp` verdadeiro → aviso "Duas câmeras respondem em <IP de fábrica>.".
- **`Get-IpsOcupadosAdmissao`:** pinga só as próximas posições pendentes (`Deps.Pingar`) quando há câmera esperando e o portão está livre.
- **Servidor:**
  - o tique roda `Find-CamerasNaRede` na placa escolhida mesmo com câmera em curso;
  - `Test-VezDoVigia` deixa de exigir `Fase='fila'`;
  - `Add-AvisoJaInicializada` sai.
  - **`SemSucesso`:** só conta tique que viu câmera e não pôde agir por algo que exige o operador.
  - Real sem administrador: `Max=1`, `Deps` no-op e o aviso "Sem administrador: uma câmera por vez.".

**Validation:** `Testes-Coordenador.ps1` com `Deps` falsas:
- DHIP vazio e ping respondendo → `Max=1`, aviso e achado com `ConferirInit`; DHIP de volta → `Max=0`;
- câmera em decisão não impede a admissão da seguinte;
- inicializada desconhecida → aviso único e nenhuma `prender`/`despachar` (asserção sobre todas as ações);
- `SemSucesso` não sobe com câmera em curso.

## Task 7: Comandos por MAC e guardas globais

**Files:** `fonte/web/Servidor-Painel.ps1`, `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`, `fonte/Testes-Motor.ps1` (só os testes de texto de rotas), `fonte/testes/Smoke-Paralelo.ps1`

- **`POST /api/decisao {mac, acao}`** → `Step-Decisao` com a geração atual. `{acao:'encerrar'}` sem MAC = encerrar a fila. Sem MAC e com outra ação = decisão da retomada manual (o caminho serial antigo).
- **`POST /api/camera {mac, porta, canal}`:** porta e canal editáveis até a conferência terminar.
  - O coordenador guarda o valor do despacho.
  - Se mudou depois do despacho, no `feita` corrige o registro com `Update-RegistroCamera`.
- **Guardas:** no listener, 409 com `Get-TextoRecusaComando` quando `$E.EmCurso>0`, para:
  - `fila`, `simular`, `PUT /api/sessao`, `sessao-concluir`/`refazer`, `senha`;
  - `rede-preparar`/`restaurar`, `sondar`/`verificar`/`descobrir`;
  - `conectada` com IP, `atualizar`.
  - No worker, `Step-Comando` confere de novo.

**Validation:**
- `Testes-Coordenador`: correção de porta/canal no registro depois de editar na conferência; nada muda sem edição;
- teste de texto das rotas novas e da lista de guardas;
- smoke estendido, com `FalharEm 'conferida'` (uma câmera falha; o servidor zera `FalharEm` depois da falha):
  - a câmera vai para decisão e as outras terminam;
  - `POST /api/decisao {mac, acao:'tentar'}` → conferência sem portão (R1) → `feita`;
  - `POST /api/fila` com câmera em curso → 409 com o texto da recusa.

## Task 8: Encerrar o painel, atualizar e partida

**Files:** `fonte/web/Servidor-Painel.ps1`, `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`, `fonte/testes/Smoke-Paralelo.ps1`

- **`POST /api/encerrar`** (encerrar o painel, R5):
  - 409 com o texto de `encerrar-painel` se `EmCurso>0`;
  - senão, como hoje: antes do `Reset-RedeLocalCameras`, solta todos os vizinhos do rastro (`Remove-VizinhoEstatico`) e fecha o pool (`Close`/`Dispose`).
- **`Test-PainelOciosoAgora`:** `EmCurso>0` ou câmera em decisão → não ocioso.
- **`POST /api/atualizar`:** recusado com câmera em curso (`Step-Comando`).
- **Partida:** vizinhos que sobraram no rastro de uma execução anterior são removidos (função do coordenador com `Deps`).
- **Nomes:** `git grep -n -i "encerrar"` em `Servidor-Painel.ps1` e `Coordenador-Cameras.ps1` não mostra identificador novo ambíguo. Fila = `decisao`/`encerrar`; painel = `encerrar-painel`/`/api/encerrar`.

**Validation:**
- `Testes-Coordenador`: limpeza de vizinhos no encerrar e na partida, com `Deps` falsas;
- smoke: `POST /api/encerrar` durante a conferência → 409 com o texto; depois do fim → 200 e o processo sai.

## Task 9: Fechar o plano

**Files:** `docs/plans/2026-11-18-frente-servidor-plan.md`

- `**Status:**` passa a `Concluído`, com uma linha dizendo que o contrato publicado (Task 4) é o que a F6 consome e que a F5 restante está no mapa. Não editar o mapa: ele muda na raiz, depois que a frente fecha.

**Validation:** a régua inteira verde, mais o `Smoke-Paralelo.ps1` uma vez; `git diff --check` limpo.
