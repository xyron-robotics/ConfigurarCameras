# Frente simulacao: conferência segura e simulação com N câmeras (F5 do mapa)

**Status:** Concluído (18/11) · **Frente:** `simulacao`

Herança da frente `servidor` (seção 0 do mapa) fechada aqui: conferência no real partindo do IP de fábrica (alto, Task 0/S1), câmera começando durante o download da atualização (médio, Task 3/S4 c), janela de ~250 ms do 409 do encerrar (baixo, Task 3/S4 a e b) e `escolher` nas guardas do listener mais `$VersaoPainel` (menor, Task 4). Seguem com outras frentes: porta e canal do cartão (F6) e a prova real de DHIP, ping, ARP e modo sem Administrador (F8).

Plano de frente da F5 de `docs/plans/2026-11-cameras-em-paralelo.md`, escrito sobre o `main` em e76f4e9 (frentes `motor`, `orquestrador`, `ui` e `servidor` fechadas). Além das Tasks 1 e 2 da F5 no mapa, leva os itens da herança da frente `servidor` (seção 0 do mapa) que são da F5. Onde divergir do mapa, vale este plano (as divergências estão em "Decisões").

**Goal:** a conferência no real nunca fala com a câmera errada; a simulação mostra N câmeras com progresso etapa por etapa e reproduz, por câmera, falha numa etapa, MAC trocado e câmera já inicializada; encerrar o painel e atualizar não cortam câmera em curso.

**Non-Goals:**
- UI: os restos de `escolher` em `app.js`, porta/canal do cartão (`POST /api/camera` na UI) e os N cartões são da F6.
- Documentação de usuário, glossário e ADR (F7).
- Câmera real (F8).
- Mexer em `Orquestrador-Cameras.ps1`: as regras D7, D8 e R1 já existem; esta frente só as exercita.

**Touched:**
- `fonte/Motor-Cameras.ps1`: fora do ramo `-Simular` só na Task 0 (`-SoConferencia`); na Task 1, só o ramo `-Simular`;
- `fonte/Testes-Motor.ps1`;
- `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`;
- `fonte/web/Servidor-Painel.ps1`;
- `fonte/testes/Smoke-Paralelo.ps1` (fora do CI e do instalador);
- este plano (Task 5).

**Safety:**
- Sem rede, placa ou câmera reais. Teste do caminho real do motor só com as funções de rede trocadas por falsas dentro do teste (padrão do `Testes-Motor.ps1`: `Test-IpEmUso`, `Get-CamInitStatus`, `Initialize-Cam`, `New-CamSessao`, `Get-CamInfoRpc`, `Wait-CamOnline`...).
- O servidor só sobe com `-Simular -SemElevar -SemNavegador -SemAtualizacao -PastaDados <pasta temporária>`.
- Repo público: MAC `AA:00:00:00:00:0x`, serial `SIM-x`, IPs de documentação (192.0.2.x), 192.168.1.108 ou os da rede fictícia que o `Testes-Motor.ps1` já usa. Antes de cada commit, `git diff --cached` sem dado real.
- Sem push e sem release.
- Codificação: `Servidor-Painel.ps1` e `Coordenador-Cameras.ps1` UTF-8 **com BOM**; `Motor-Cameras.ps1`, `Testes-*.ps1` e `Smoke-Paralelo.ps1` como já estão. PowerShell 5.1 (`powershell.exe`).

**Régua de toda Task:** o bloco "Validação" do `CLAUDE.md` (Motor, Descoberta, Orquestrador, Coordenador, `git diff --check`). A contagem de testes se lê na saída e não se escreve no plano.

## Medição da herança (18/11, na escrita deste plano)

Pergunta da seção 0 do mapa: a conferência no real pode falar com a câmera errada? **Sim, pela leitura do código.** O caminho:

1. `New-ContextoJob` (coordenador) monta o contexto da conferência com `IpOrigem` = o IP de onde a câmera veio (o de fábrica). O despacho da conferência (`AteEtapa` vazio) sai em dois pontos do orquestrador: depois do portão e na retomada R1 (`Retomar='conferencia'`).
2. `Invoke-ConfiguracaoCamera`, no real, chama `Get-EstadoCamera -IpOrigem <fábrica> -Destino <destino>`, que pinga e consulta **a origem primeiro**.
3. Com N câmeras no switch, o IP de fábrica quase sempre responde: a câmera presa no portão (vizinho estático) ou qualquer outra de fábrica em espera (ARP comum). Quem responde é a câmera B, não a A que está sendo conferida.
4. Se B ainda é de fábrica (`Init=1`): estado `fabrica`, `Get-PlanoRetomada` manda configurar do zero na origem, o registro de A é descartado (`$ent = $null`) e **`Initialize-Cam` vai para B**, sem autenticação e antes da trava de MAC. Depois o login lê o MAC de B e devolve `MacTrocado`; na conferência isso vira decisão (R7). Dano: A cai numa decisão falsa, e B fica inicializada com a nossa senha. No tique seguinte o DHIP vê B com `Init≠1`, e pela D8 ela nunca mais é tocada: só sai com reset físico.
5. Se B já foi inicializada pelo próprio portão: estado `inicializada`, o plano volta para depois do `encoder`, o login vai para B e a trava de MAC pega. Nada é gravado em B, mas A cai numa decisão falsa.
6. Só quando nada responde no IP de fábrica (uma câmera sozinha no switch) o motor chega ao estado `destino` e confere certo. Os testes de hoje não pegam o defeito: no `-Simular` o motor não chama `Get-EstadoCamera`.

A Task 0 reproduz isso num teste, que precisa falhar antes do conserto (saída colada no commit).

## Decisões

Valem as do mapa (D1–D11, Q1–Q8) e as da frente `servidor` (U1–U3, R1–R8). Desta frente:

- **S1. A conferência despachada pelo coordenador parte do destino e nunca toca a origem.** `Invoke-ConfiguracaoCamera` ganha `-SoConferencia`: exige no registro a entrada do MAC do contexto com `Etapa='rede'` e `Status≠'Instalada'`, pula o `Get-EstadoCamera` e começa com `feita='rede'` e `ipCam=destino`. A trava de MAC que já existe na conferência (`quem responde em <destino> e outro aparelho`) continua valendo. Com o destino mudo, a falha fica em `conferida`, sem cair para a origem. Sem a entrada certa no registro, falha `conferida` com texto claro e sem tocar na rede. `-SoConferencia` junto com `-AteEtapa` estoura. O coordenador passa `-SoConferencia` em todo despacho com `AteEtapa` vazio. A retomada manual pelo IP (caminho serial) não muda. *Porquê:* "travar pelo MAC" no IP de fábrica não serve. A câmera já saiu de lá, e o vizinho estático desse IP pertence ao portão, que está prendendo outra câmera.
- **S2. Cenários de simulação por câmera num mapa só.** `POST /api/simular {ligado, falharEm}` passa a aceitar `falharEm` como texto (o comportamento de hoje: o primeiro despacho que alcança a etapa leva a falha) ou como mapa `{ "<n>": "<valor>" }`. `n` é o número da câmera simulada (1..N, a de MAC `AA:00:00:00:00:<n em hex, 2 dígitos>`), e o valor é uma etapa (`inicializada`, `encoder`, `rede`, `conferida`), `mac-trocado` ou `ja-inicializada`.
  - Etapa e `mac-trocado` valem uma vez por câmera: o despacho daquela câmera que alcança o valor leva a falha e a desarma, e o "Tentar de novo" passa.
  - `mac-trocado` é falha de portão: a câmera volta à espera sem decisão (D7) e entra de novo na admissão seguinte.
  - `ja-inicializada` não é falha de job: a câmera `n` aparece no DHIP simulado com `Init=0` e fora do registro, e por isso só gera o aviso da D8, sem nunca ser presa nem despachada.
  - Hoje `mac-trocado` como texto não faz nada: `Use-FalharEmCoordenador` não acha o valor entre as etapas. Esta frente corrige: no texto, ele vale para o primeiro portão.
- **S3. N e ritmo por parâmetro do servidor.**
  - `-SimularCameras <n>` (padrão 3, de 1 a 16) diz quantas câmeras de fábrica o DHIP simulado devolve.
  - `-SimularEscala <x>` (padrão 1; 0 = sem espera) multiplica os atrasos.
  - O atraso passa a ser por etapa, no ramo `-Simular` do motor. O parâmetro novo `-EsperaSimuladaMs` é uma tabela etapa → ms, com padrão `inicializada 400, encoder 400, rede 400, conferida 3000`, tudo × escala. Ele substitui a espera única antes do motor (`EsperaSimuladaSeg`), e assim o progresso anda etapa por etapa no estado publicado.
  - Sem tela nova: a simulação continua sem UI (desde a 1.2.0).
- **S4. Encerrar e atualizar não cortam câmera em curso.**
  - (a) O worker atualiza `$E.EmCurso` logo depois de cada `Invoke-AcoesCoordenador` e de cada `Receive-EventosCoordenador`, e não só no `Publicar`. A janela do 409 cai de ~250 ms para quase zero.
  - (b) Com `$E.Parar`, o worker não roda o tique nem a admissão e não executa `despachar`. Executa só `prender`/`soltar`/`avisar`, e com log, porque o `despachar` de uma conferência pendente fica no registro como "Em andamento". Ele espera os jobs em curso drenando eventos até um teto de 180 s (conferência: `Wait-CamOnline` de 120 s, mais login), e só então fecha o pool. O thread principal espera o worker até esse teto, e não mais 30 s fixos.
  - (c) Durante a atualização (pedido feito, ou estado `baixando`, `verificando` ou `instalando`), o worker recusa ligar o vigia, montar fila, `conectada` e `decisao tentar`, com o texto "Aguarde a atualização terminar.", e não admite câmera. O atualizador só põe `Parar` com `EmCurso=0`. Senão, publica `erro` com "Uma câmera começou durante o download. Atualize de novo quando ela terminar." e apaga o instalador baixado.
  - *Porquê (b):* com (a) e (c), câmera começando depois do 409 vira caso raro. Esperar em vez de cortar cobre o resto sem mudar o contrato do `POST /api/encerrar` (200/409), que a UI atual e a F6 usam.

## Task 0: Conferência parte do destino (herança, alto)

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`, `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`

1. **Reproduzir antes de consertar.** Teste novo no `Testes-Motor.ps1`, no padrão dos testes "Configuracao real (stubs)":
   - registro com a câmera A (`AA:00:00:00:00:01`) com `Etapa='rede'`, `Status='Em andamento'` e `Ip=<destino>`, e contexto da conferência como o coordenador monta hoje (`IpOrigem='192.168.1.108'`, `Destino`, `Mac` de A);
   - funções falsas que **anotam o IP de cada chamada**: `Test-IpEmUso` (responde nos dois IPs), `Get-CamInitStatus` (192.168.1.108 → `Init=1`, câmera B; destino → `Init=0`), `Initialize-Cam`, `New-CamSessao` (devolve o IP na sessão), `Get-CamInfoRpc` (MAC pelo IP da sessão: B `AA:00:00:00:00:02` na origem, A no destino; `IpAtual`, `Mascara` e `Gateway` certos no destino), `Wait-CamOnline`, `Get-CamEncode`, `Close-CamSessao`, `Start-Sleep` (não dorme);
   - variante com B já inicializada (`Init=0` na origem).
   - Rodar contra o código de hoje e colar no corpo do commit a falha esperada: `Initialize-Cam` chamado em 192.168.1.108 e `MacTrocado`; na variante, login em 192.168.1.108 e `MacTrocado`.
2. **Motor:** `-SoConferencia` como na S1. Uma linha de log identifica o modo ("conferência a partir do destino <IP>; a origem não é consultada").
3. **Coordenador:** o `ScriptJobCamera` passa `-SoConferencia:($AteEtapa -eq '')` ao motor.

**Validation:**
- os testes do passo 1, agora com `-SoConferencia` (o contexto do teste, como o coordenador vai mandar): nenhuma chamada anotada em 192.168.1.108; `Ok`, registro `Instalada` com o MAC de A; vale para as duas variantes;
- destino respondendo com o MAC de B → falha `conferida` com "outro aparelho", e nenhuma chamada na origem;
- destino mudo (`Wait-CamOnline` falso) → falha `conferida`, e nenhuma chamada na origem;
- sem entrada no registro, ou entrada com `Etapa='encoder'` → falha `conferida` sem nenhuma chamada de rede;
- `-SoConferencia -AteEtapa 'rede'` estoura;
- `Testes-Coordenador.ps1` (pool real, motor em `-Simular`): o log da conferência traz a linha do modo e o do portão não; as 3 câmeras terminam `feita` como antes;
- a régua.

## Task 1: N câmeras simuladas e atraso por etapa

**Files:** `fonte/web/Servidor-Painel.ps1`, `fonte/Coordenador-Cameras.ps1`, `fonte/Motor-Cameras.ps1` (só o ramo `-Simular`), `fonte/Testes-Coordenador.ps1`, `fonte/Testes-Motor.ps1`, `fonte/testes/Smoke-Paralelo.ps1`

- **Servidor:** parâmetros `-SimularCameras` e `-SimularEscala` (S3), validados (1..16; escala ≥ 0). O `$DescobrirAchados` em simulação gera N achados com MAC `AA:00:00:00:00:{0:X2}`, serial `SIM-<n>`, modelo `SIM-IPC`, IP de fábrica e `Init=1`.
- **Motor (ramo `-Simular`):** `-EsperaSimuladaMs` (tabela etapa → ms, vazia = sem espera). Depois de cada `Write-Progresso` de etapa, dorme o tempo daquela etapa. Fora de `-Simular`, o parâmetro é ignorado.
- **Coordenador:** `Trabalho.EsperaSimuladaSeg` vira `Trabalho.EsperaSimuladaMs` (tabela × escala). O job passa a tabela ao motor e deixa de dormir antes dele.
- **Smoke:** parâmetro `-Cameras` (padrão 3), repassado como `-SimularCameras`; a saída imprime a etapa por câmera ao longo do tempo.

**Validation:**
- `Testes-Motor`: com `-Simular` e `-EsperaSimuladaMs @{ encoder = 300 }`, o tempo da chamada fica ≥ 300 ms e os eventos de progresso vêm na ordem das etapas; sem a tabela, a chamada não espera;
- `Testes-Coordenador`: 5 câmeras, escala curta, todas `feita`, nunca mais de 1 MAC preso, conferências sobrepostas;
- `Smoke-Paralelo.ps1 -Cameras 5`, saída colada no commit: 5 `feita`, pelo menos 2 `conferindo` ao mesmo tempo, etapas `inicializada`/`encoder`/`rede` visíveis no portão, latência máxima abaixo de 500 ms;
- a régua.

## Task 2: Cenários por câmera (falha, MAC trocado, já inicializada)

**Files:** `fonte/web/Servidor-Painel.ps1`, `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`, `fonte/Testes-Motor.ps1` (só os testes de texto de rotas, se a mudança os quebrar), `fonte/testes/Smoke-Paralelo.ps1`

- **Servidor:** `POST /api/simular` e o comando `simular` aceitam `falharEm` texto ou mapa (S2). `$W.FalharEm` guarda o que veio. O número da câmera vira MAC. `ja-inicializada` vai para o `$DescobrirAchados` (`Init=0` para aquela câmera) e não para o coordenador. O log diz o cenário armado por câmera.
- **Coordenador:** `Trabalho.FalharEm` aceita texto ou tabela MAC → valor. `Use-FalharEmCoordenador -Coord -AteEtapa -Mac`: com tabela, só o MAC do despacho, uma vez. `mac-trocado` alcança só o portão. Com texto, mantém o comportamento de hoje, mais o `mac-trocado` no primeiro portão.
- **Servidor:** o "esquecer `$W.FalharEm`" depois do consumo (hoje no laço) passa a valer por entrada da tabela.
- **Smoke:** parâmetro `-Cenario` com `basico` (padrão), `falha-rede-2`, `mac-trocado-2` e `ja-inicializada-3`. Cada um sobe um servidor próprio, arma o `falharEm` antes de ligar o vigia, imprime as fases por câmera e confere o esperado no fim (sai com código ≠ 0 se não bater).

**Validation:**
- `Testes-Coordenador`:
  - tabela com a câmera 2 em `rede` → só o despacho da 2 leva a falha, uma vez;
  - `mac-trocado` na tabela → só o portão daquela câmera;
  - texto `mac-trocado` → primeiro portão;
  - texto de etapa → como hoje.
- smoke, saída dos três cenários colada no commit:
  - `falha-rede-2`: 1 e 3 `feita`, 2 em decisão; `POST /api/decisao {mac, acao:'tentar'}` → 2 `feita`;
  - `mac-trocado-2`: a 2 volta à espera sem decisão e termina `feita`, sem aviso "MAC lido" para as outras;
  - `ja-inicializada-3`: 1 e 2 `feita`, a 3 nunca aparece em `portao` nem em `conferindo`, e o aviso da D8 sai uma vez só.
- a régua.

## Task 3: Encerrar e atualizar sem cortar câmera (herança, médio e baixo)

**Files:** `fonte/web/Servidor-Painel.ps1`, `fonte/Coordenador-Cameras.ps1`, `fonte/Testes-Coordenador.ps1`, `fonte/Testes-Motor.ps1` (só os testes de texto do servidor), `fonte/testes/Smoke-Paralelo.ps1`

- **S4 (a):** `$E.EmCurso` atualizado pelo worker logo depois do despacho e da drenagem de eventos.
- **S4 (b), no coordenador:**
  - `Invoke-AcoesCoordenador -SemDespacho` pula o `despachar`, com log por câmera;
  - `Wait-JobsCoordenador -Coord -LimiteSeg -Log` drena eventos e executa as ações (sem despacho) até não haver job ou estourar o teto, e devolve quantos jobs sobraram.
- **S4 (b), no servidor:** fora do `while (-not $E.Parar)`, antes do `Close-PoolCameras`, chama `Wait-JobsCoordenador` com 180 s. O `WaitOne` do worker no thread principal passa para o teto + margem.
- **S4 (c):**
  - função pura `Test-AtualizacaoEmCurso -Pedido -Estado` no coordenador;
  - o worker recusa os comandos da S4 (c) e pula a admissão enquanto ela for verdadeira;
  - o atualizador confere `$E.EmCurso` antes do `Parar`.

**Validation:**
- `Testes-Coordenador`:
  - `Wait-JobsCoordenador` com pool real e escala curta: um job de portão em curso termina, o `soltar` acontece, o `despachar` da conferência é pulado com log, e devolve 0;
  - com teto menor que o job, devolve 1;
  - tabela de `Test-AtualizacaoEmCurso`.
- testes de texto: o servidor chama `Wait-JobsCoordenador` antes do `Close-PoolCameras`, e o atualizador confere `EmCurso` antes do `Parar`;
- smoke, cenário `encerrar` (sobe com escala 1): `POST /api/encerrar` durante a conferência → 409 com o texto; depois do fim → 200, e o processo sai em menos de 10 s;
- a régua.

## Task 4: Menores da herança

**Files:** `fonte/web/Servidor-Painel.ps1`

- tirar `'escolher'` das três guardas do listener (troca de placa/faixas no `PUT /api/sessao`, `POST /api/sessao/refazer` e `POST /api/atualizar`). A fase não existe mais no estado publicado;
- `$VersaoPainel = Get-VersaoPainel`.
- O `'escolher'` em `app.js` é da F6; o teste de `Test-PainelOcioso -Fase 'escolher'` no `Testes-Motor.ps1` fica (função do motor, fase qualquer).

**Validation:** `git grep -n "'escolher'" fonte/web/Servidor-Painel.ps1` vazio; o teste de BOM do servidor verde; a régua.

## Task 5: Fechar o plano

**Files:** `docs/plans/2026-11-18-frente-simulacao-plan.md`

- `**Status:**` passa a `Concluído`, com uma linha dizendo quais itens da herança (seção 0 do mapa) esta frente fechou. Não editar o mapa: ele muda na raiz, depois que a frente fecha.

**Validation:** a régua inteira verde, mais o `Smoke-Paralelo.ps1` com todos os cenários uma vez; `git diff --check` limpo.
