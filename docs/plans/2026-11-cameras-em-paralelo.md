# Plano: várias câmeras de fábrica no mesmo switch, configuradas em paralelo

**Status:** Ativo (aprovado em 17/11; Q1–Q8 respondidas na seção 6; P0 feita, ver seção 6.1)

Pedido do usuário: "a próxima versão [...] consiga operar qualquer tipo de câmera que for instalada em um switch de maneira paralela. [...] o vigia deve conseguir montar a fila e configurar elas de maneira que uma câmera conectada não atrapalhe a outra."

**Este arquivo é o mapa.** As frentes são executadas pelo `/regime:maestro`, cada uma pelo seu plano de frente:

| Frente | Plano de frente | Conteúdo | Onda |
|---|---|---|---|
| `motor` | `docs/plans/2026-11-17-frente-motor-plan.md` | F1 e depois F2 | 0 e 1 |
| `orquestrador` | `docs/plans/2026-11-17-frente-orquestrador-plan.md` | F3 | 0 |
| `ui` | `docs/plans/2026-11-17-frente-ui-plan.md` | F2b, F3 e F4 do plano de UI | 0 |
| `servidor` | `docs/plans/2026-11-18-frente-servidor-plan.md` | F4 e o mínimo da F5 (3 câmeras simuladas) | 2 |
| F5 a F8 | a escrever (F5 depois da `servidor`) | resto da simulação, UI paralela, docs, bancada | 2 a 4 |

Se um plano de frente divergir deste mapa, vale o plano de frente. Os números de linha valem para `main` em 0d0581a e vão andar: localize pelo nome da função, não pela linha.

Vocabulário: o de `CONTEXT.md`. Termos novos estão em "Termos novos" e entram no glossário na frente F7.

---

## 1. Contexto (estado medido)

### 1.1 Evidência da bancada (prints do usuário, novembro)

Duas câmeras de fábrica ligadas no mesmo switch, fila de 3 posições, vigia ligado. Aqui são A e B; os MACs reais ficam fora do repo, que é público.

- **Print 1:** a posição "câmera 1" falhou na etapa encoder com "MAC lido (B) nao e o da camera escolhida (A). Nada foi alterado.". A frase de apoio diz que a câmera "já está inicializada com a senha desta sessão". O vigia mostra "Em pausa até você resolver a câmera atual." A fila inteira fica parada.
- **Print 2:** "Câmera já inicializada em 192.168.1.108 (MAC B): o vigia não mexe nela." O vigia diz "Observando 192.168.1.108. Ligue a câmera 1 de 3". A câmera A, que continua de fábrica, nunca mais é vista. A placa aparece com 8 ou mais IPs de faixas diversas.

Origem de cada mensagem no código:

| Mensagem | Onde nasce |
|---|---|
| "MAC lido (...) nao e o da camera escolhida" | `fonte/Motor-Cameras.ps1:3816`, dentro de `Invoke-ConfiguracaoCamera` |
| "A câmera já está inicializada com a senha desta sessão..." | `fonte/web/www/app.js:629` (`textoDaFalha`, etapa encoder) |
| "Em pausa até você resolver a câmera atual." | `fonte/web/www/app.js:691` (`desenharVigia`, fase escolher/decisao) |
| "Câmera já inicializada em ... o vigia não mexe nela" | `fonte/web/Servidor-Painel.ps1:542` (`Add-AvisoJaInicializada`) |
| "Tire a câmera anterior e ligue a ..." | `fonte/web/www/app.js:~697`: o fluxo pressupõe uma câmera por vez |

### 1.2 Causa: tudo endereça a câmera pelo IP, e N câmeras de fábrica dividem o mesmo IP

As câmeras saem de fábrica no mesmo IP (`IpFabrica` da Sessão, 192.168.1.108). Com duas ou mais no switch, todas respondem ARP para o mesmo endereço. A tabela de vizinhos do Windows fica com o MAC de quem respondeu por último, e esse MAC troca no meio de uma configuração.

- O HTTP sai por IP: `Invoke-CamHttpJson` (Motor ~1583) monta a URL em `ConvertTo-UrlCam` (~975). `Get-CamInitStatus` (~459), `Initialize-Cam` (~1617), `New-CamSessao` (~2425), `Wait-CamOnline` (~1557) e `Get-EstadoCamera` (~3656) também falam com o IP.
- `Get-VizinhosMac` (~629) devolve um MAC por IP, o que estiver no ARP naquele instante.
- `$script:PortasHttp` (`Set-CamPortaHttp`, ~960) usa o IP como chave, então duas câmeras de fábrica no mesmo IP se sobrescrevem.
- No broadcast, `Find-CamerasNaRede` (~1215-1250) deduplica o DHIP por MAC (certo). Depois confirma por HTTP com `Invoke-ProbeInitLote`, cujas respostas usam o IP como chave (`$respostas[$u.Ip]`). As duas câmeras recebem a resposta HTTP de quem estava no ARP: o "Init confirmado" de uma vai parar na outra.
- O atalho no IP de fábrica (~1256-1285) pega o MAC do ARP e devolve uma câmera só.
- **Print 1 explicado:** `Initialize-Cam` roda anônimo e por IP (Motor 3786-3793) **antes** da conferência de MAC (3813-3817). A inicialização foi para B; o login também caiu em B, já com a senha da sessão. A trava pegou a troca, mas tarde, e a frase "Nada foi alterado" é falsa nesse caso.
- **Print 2 explicado:** sem broadcast, o tique do vigia (Servidor 563-575) faz ping e `Get-CamInitStatus` no IP de fábrica. Quem responde é B, já inicializada. O tique chama `Add-AvisoJaInicializada` e retorna. A câmera A, de fábrica, fica escondida atrás do mesmo IP, e o vigia fica cego para sempre: esse `return` sai antes de `SemSucesso` contar, então o vigia nunca desliga sozinho.
- Os IPs a mais na placa do print 2 provavelmente se somam de IPs do PC de sessões anteriores no rastro e de IPs temporários de câmeras vistas no broadcast (`Add-IpTemporarioPlaca`, Motor ~1070, só removidos ao restaurar). **Não confirmado:** a P0 mede isso no log.

### 1.3 O painel é serial por construção

- Há um worker só (`Servidor-Painel.ps1` 231-1137), e o estado `$W` (237-276) cabe uma câmera: `Atual`, `Camera`, `Falha`, `Escolha`, `Etapa`, `Progresso`, `CameraDoVigia`.
- O vigia só age com `Fase -eq 'fila'` (`Test-VezDoVigia`, 520-522). Uma falha põe a fase em `decisao` (`Invoke-Configurar`, 596-628) e pausa a fila inteira.
- `Invoke-Conectada` recusa trabalho com a fase em decisao/configurando/escolher (683).
- `Add-Comando` (~1316) recusa comando com `$E.Ocupado`.
- `Publicar` (337-360) publica uma câmera, e `app.js` (`desenharFila` 512+, `desenharVigia` 658+) desenha uma.
- Porta e canal somam 1 por câmera instalada (`Step-Rotulo`, só para câmera do vigia). Isso pressupõe que a ordem de ligação é a ordem física.

### 1.4 O que quebra se rodar duas configurações ao mesmo tempo

- **Registro com escrita perdida:** `Invoke-ConfiguracaoCamera` lê o registro uma vez (Motor ~3730) e o `$salvar` (~3756-3769) grava a cópia inteira. Duas configurações simultâneas apagam a entrada uma da outra.
- **`Save-JsonAtomico` (~3281):** o `.tmp` tem nome fixo (`$Caminho + '.tmp'`), então dois gravadores colidem.
- **`Write-Log` (~47):** faz `Add-Content` no arquivo e engole o erro. Vindo de vários runspaces, perde linhas em silêncio.
- **Progresso:** `$script:ProgressoSink` é um só por runspace (~75), e o servidor grava num `$W.Etapa` só (364-372).
- **Placa:** `New-NetIPAddress`, a rota de host e o rastro `placa-sessao.json` (`Merge-SessaoPlaca` + `Save-JsonAtomico`) não são seguros sob concorrência.
- **Firmware:** chamadas concorrentes contra a **mesma** câmera derrubam a conexão (`API-INTELBRAS.md:285-286`, cabeçalho do motor 38-39). Contra câmeras **diferentes**, em IPs diferentes, não há limite conhecido.

### 1.5 "Qualquer tipo de câmera": quanto é Intelbras/Dahua

- **Só Intelbras/Dahua (protocolo):**
  - login RPC2 com desafio MD5;
  - `/OutsideCmd` DevInit, com envelope RPAC-256 (RSA + AES);
  - descoberta DHIP na UDP 37810;
  - tabelas `Encode`/`Network` do `configManager`;
  - catálogo de encoder;
  - códigos de erro do login (`Get-ClassificacaoErroLogin`);
  - OUIs conhecidos;
  - reset.
- **Genérico (independe da marca):** placa escolhida e preparo, fila, posição, registro por MAC, Sessão, relatório, ping/ARP, painel e vigia como laço.
- **Fora da família Dahua:** a ativação de fábrica não tem padrão. ONVIF cobre encoder e rede depois que a câmera já tem senha, mas a primeira senha é proprietária de cada marca (Hikvision SADP, Axis VAPIX etc.). "Qualquer marca" significa um adaptador por marca, e não um protocolo único.

### 1.6 Testes que já existem

- `fonte/Testes-Motor.ps1`: arcabouço próprio (`T`, `Assert-*`, `Get-Fixture`, `New-Temp`). Carrega o motor por dot-source e cobre a configuração simulada com `-Simular`/`-FalharEm` (~940+).
- `fonte/Testes-Descoberta.ps1`: descoberta.
- Fixtures em `fonte/testes/`: tem DHIP real de uma G4.
- O CI (`.github/workflows/release.yml` 28-34) e o `instalador/Gerar-Instalador.ps1:41` rodam os dois arquivos de teste pelo nome. Arquivo de teste novo precisa entrar nos dois.
- O instalador lista arquivo por arquivo (`instalador/ConfigurarCameras.iss:50+`).

---

## 2. Decisões defendidas

### D1. Cada câmera passa a ser identificada pelo MAC, de ponta a ponta; o IP é só o endereço do momento

- **Porquê:** o MAC é a única coisa que distingue duas câmeras de fábrica, e o registro já usa o MAC como chave.
- **Na prática:** a câmera nasce do DHIP com MAC, serial e modelo. Contexto sem MAC não entra na fila paralela: o caminho "informado por IP" continua para a retomada manual, de uma por vez.
- **Descartada:** continuar por IP e detectar a troca depois (é o que existe hoje: a trava pega tarde, depois do DevInit).

### D2. Portão do IP de fábrica: uma câmera por vez sai do IP de fábrica, presa pelo MAC

- **Como funciona:** antes de qualquer HTTP para o IP de fábrica, o coordenador fixa um vizinho estático na placa escolhida: `IpFabrica -> MAC` (`New-NetNeighbor -State Permanent -PolicyStore ActiveStore`, depois de remover a entrada dinâmica). Só então começa o primeiro passo.
  - Quadros unicast do PC vão só para aquele MAC: o switch encaminha pelo MAC de destino.
  - As outras câmeras de fábrica no mesmo IP não recebem nada.
- **O que roda dentro do portão:** inicialização, encoder e gravação da rede (as etapas atuais até `rede`). Ao gravar a rede, a câmera reinicia já no IP de destino, que é único. O portão solta o vizinho e passa para a próxima câmera.
- **Rastro:** o vizinho estático entra no rastro `placa-sessao.json`. ActiveStore some no reboot, e o encerrar/restaurar remove (ADR 0002).
- **Porquê:** é ARP padrão, sem engenharia reversa, e funciona com qualquer switch não gerenciado. O ganho de paralelismo está na espera do boot e na conferência, que dominam o tempo (`EsperaBootSeg` 120).
- **Confirmada na P0 (17/11):** com 3 câmeras de fábrica no mesmo IP, cada uma presa pelo MAC respondeu 20 de 20 com a própria chave pública (seção 6.1).
- **Descartada:**
  1. Mudar o IP pelo MAC via DHIP (`DHDiscover.setConfig`, à moda do ConfigTool): não está documentado em `API-INTELBRAS.md` nem implementado. A P0 pode sondar isso, mas o plano não depende disso.
  2. VLAN por porta: exige switch gerenciado.
  3. Pedir ao operador que ligue uma por vez: é o estado atual, que o usuário quer eliminar.

### D3. Ordem das etapas mantida (inicializada, encoder, rede, conferida); o paralelo cobre a conferência

- **Porquê:**
  - a retomada (`Get-PlanoRetomada`), o registro (`Etapa`) e os textos de falha dependem dessa ordem, e mudar mexe em semântica já validada na bancada;
  - o portão leva menos de 1 min por câmera, e a conferência leva de 1 a 2 min.
- **Descartada:** inverter para inicializada, rede, encoder, conferida. Tiraria o encoder do portão, mas mudaria a retomada. O usuário manteve a ordem (Q7).

### D4. Coordenador único e jobs por câmera num RunspacePool

- **Coordenador:** o worker atual vira coordenador. É o único dono de `sessao.json`, da placa (IP temporário, vizinho estático, rastro), do estado publicado e do log em arquivo.
- **Jobs:** cada câmera roda num job do pool. O pool não tem limite próprio (Q2): o teto natural é o número de posições pendentes da fila. O portão tem sempre 1 vaga.
- **Ida e volta:** o job carrega o motor e chama `Invoke-ConfiguracaoCamera`. A volta acontece por uma fila de eventos (`ConcurrentQueue`) com `{mac, tipo: log|progresso|fim, ...}`. O laço do coordenador drena a fila a cada volta, processa comandos e faz o tique do vigia sem bloquear.
- **Porquê:** mantém a regra "uma chamada por câmera" (um job por MAC) e o painel continua respondendo enquanto câmeras configuram.
- **Descartada:** `Start-Job` (um processo por câmera, sem estado compartilhado, lento para subir) e threads soltas sem pool (sem limite).

### D5. Registro gravado por câmera, sob trava, com releitura e mescla por MAC

- **Como:** função nova `Update-RegistroCamera -Caminho -Entrada`. Pega um Mutex nomeado por hash do caminho, relê do disco, faz o upsert por MAC e grava com `Save-JsonAtomico`, agora com `.tmp` de nome único. O `$salvar` de `Invoke-ConfiguracaoCamera` passa a usá-la.
- **Porquê:** a entrada é por MAC, então a mescla é trivial. Fica síncrono e testável sem servidor, e vale também para `registro-simulado.json`.
- **Descartada:** mandar o registro para o coordenador por evento. A gravação ficaria assíncrona, e o motor perderia a garantia de "gravou antes de seguir", da qual a retomada depende.

### D6. Falha isolada por câmera: o vigia não pausa

- **Como:** a falha vira um cartão de decisão daquela câmera (Tentar de novo / Pular esta posição), e as outras seguem.
- **"Encerrar a fila":** para de admitir câmeras novas. Quem está no portão ou conferindo termina, porque abortar no meio da gravação de rede deixa a câmera num estado sem dono.
- **Senha recusada:** pausa só aquela câmera. Nunca se repete login recusado no mesmo MAC e na mesma geração da senha: a guarda que hoje é global (Servidor ~949) passa a valer por cartão.
- **Porquê:** é o pedido do usuário ("uma câmera conectada não atrapalhe a outra"). A recusa numa câmera não diz nada das outras: as de fábrica recebem a senha da Sessão na inicialização.
- **Revoga** a regra antiga "recusa da câmera para a fila", que vira "recusa da câmera para aquela câmera".

### D7. MAC trocado no portão é erro do portão, não falha da posição

- **Antes da inicialização:** o portão confere a tabela de vizinhos (`Get-NetNeighbor` = MAC escolhido). Se não bater, solta e devolve a câmera à espera. A posição continua pendente.
- **Conferência de MAC depois do login:** fica como defesa em profundidade. Se disparar, a posição volta a pendente e as duas câmeras voltam à avaliação, sem cartão de decisão.
- **Texto:** troca para "A câmera que respondeu não é a escolhida. A posição continua livre e as duas câmeras voltam para a fila."

### D8. O vigia só toca câmera de fábrica; câmera já inicializada nunca é tocada, e o aviso vem do registro (Q4)

- **Regra:** o vigia age só em câmera com `Init` de fábrica. Câmera inicializada não recebe login, nem inicialização, nem adoção.
- **Aviso pelo registro, por MAC (só leitura de arquivo):**
  - MAC no registro em `Em andamento`/`Falhou`: "Câmera da fila parada na etapa X. Retome em Ferramentas.";
  - MAC no registro em `Instalada`: nada;
  - MAC desconhecido: "Câmera já inicializada: não tocada.", uma vez por MAC.
- **Init desconhecido** (firmware sem o campo no DHIP): o portão consulta `DevInit.getStatus` anônimo, depois de preso pelo MAC, e só segue se for de fábrica.
- **Porquê:** com o portão (D2) e o DHIP obrigatório (D9), a inicializada não esconde mais a de fábrica (print 2), e a inicialização não cai mais na câmera errada (print 1). Câmera desta execução que falhou já tem cartão de decisão próprio (D6). Assim nenhuma senha é gasta às cegas.
- **Revogada:** a adoção com `MacsComSenhaDaSessao` e com um login de teste (versão Draft deste plano).

### D9. O DHIP na placa escolhida passa a ser obrigatório no modo paralelo (Q5)

- **Por quê:** sem DHIP, câmeras no mesmo IP são indistinguíveis. Isso vale mesmo com a caixa "qualquer faixa" desmarcada.
- **A caixa** passa a significar só "agir também em câmera de fábrica fora do IP de fábrica".
- **Sem resposta DHIP** (firewall barrando a UDP 37810): o painel cai para uma câmera por vez e avisa: "O broadcast não responde. Libere a porta UDP 37810 no firewall ou ligue uma câmera por vez."
- **MAC alternando no IP de fábrica:** dois `Get-VizinhosMac` seguidos diferentes. O painel avisa "Duas câmeras respondem em 192.168.1.108.".

### D10. Posição atribuída na entrada do portão, em ordem de chegada; o cartão mostra serial e MAC

- **Ordem:** a posição é a próxima livre no momento em que a câmera entra no portão. A ordem de espera é a ordem do primeiro aparecimento no DHIP: estável, mas não física. Nas palavras do usuário (Q3): conforme as câmeras são plugadas no switch, iniciam uma de cada vez, e a próxima que o vigia detectar vai para o próximo IP da fila.
- **Cartão:** mostra modelo, serial (impresso na etiqueta) e MAC. O relatório já leva o MAC e passa a levar o serial.
- **Porta e canal:** no modo paralelo deixam de somar 1 sozinhos. Ficam editáveis no cartão até a conferência terminar e vão para o registro.
- **Descartada:** confirmação do operador antes de cada câmera, porque trava o fluxo (Q3).
- **Atraso da P0:** a câmera recém-ligada responde ARP cerca de 1 min antes de responder DHIP. A ordem de chegada é a do DHIP, não a do cabo.

### D11. Fronteira multimarca: costura de adaptador, só Intelbras/Dahua nesta versão (Q1)

- **Interface interna documentada** (sem implementar outra marca): `Descobrir`, `ObterEstado`, `Inicializar`, `AjustarEncoder`, `GravarRede`, `Conferir`.
- **Esta versão:** a família DHIP (Intelbras, Dahua e OEMs).
- **Outras marcas:** aparelho de outra marca visto na rede aparece como "Marca não suportada: não tocada".

---

## 3. Termos novos (entram no `CONTEXT.md` em F7)

- **Portão do IP de fábrica:** etapa serial em que uma câmera, presa pelo MAC, sai do IP de fábrica.
- **Vizinho estático:** entrada ARP fixa `IpFabrica -> MAC` na placa escolhida, com rastro.
- **Conferência em paralelo:** a conferência roda ao mesmo tempo para várias câmeras, cada uma no seu destino.
- **Cartão da câmera:** o bloco da bancada de cada câmera em curso.

---

## 4. Riscos

| Risco | Efeito | Mitigação |
|---|---|---|
| Firmware detecta conflito de IP e muda de IP ou para de responder | Câmera some do IP de fábrica | P0: em cerca de 15 min nenhuma das 3 saiu de 192.168.1.108. Se uma cair para outro IP, o DHIP a acha por MAC |
| O vizinho estático não pega (já existe entrada dinâmica; `New-NetNeighbor` falha) | HTTP vai para a câmera errada | Remover a dinâmica antes e conferir com `Get-NetNeighbor` antes do primeiro passo (D7). Teste unitário com a função de rede falsificada |
| Vizinho estático esquecido depois de queda do painel | PC preso a um MAC antigo no IP de fábrica | ActiveStore (some no reboot), rastro em `placa-sessao.json` e limpeza no encerrar, no restaurar e na partida |
| Lockout (cerca de 5 senhas erradas) | Câmera bloqueada | Login recusado nunca se repete por MAC e geração. Câmera inicializada nunca recebe login do vigia (D8). Trocar a senha é recusado com câmera no portão ou conferindo |
| Concorrência em arquivos (registro, rastro, sessão, log) | Escrita perdida ou corrompida | D5 para o registro. Rastro e sessão só pelo coordenador. Log em arquivo só pelo coordenador; o job loga por evento |
| CPU e threads: cada job dispara `curl.exe` e o PS 5.1 pesa por runspace | Notebook lento, timeouts | Sem limite por escolha do usuário (Q2); o teto é o número de posições. O portão serializa a parte pesada. Conferência é quase toda espera (ping a cada 5 s). Medir CPU na F8; se pesar, o limite volta como decisão nova |
| Firmware antigo (G3, 2.800) não atende `Security.getEncryptInfo` no `/RPC2` | Chamada sem resposta útil | Medido na P0: atende no `/OutsideCmd`. Manter a alternância de endpoint que `Get-CamChavePublica` já faz |
| PoE do switch | Câmera reinicia por falta de energia | Fora do software. Avisar no LEIA-ME e no roteiro de bancada |
| Firmware antigo sem DHIP ou sem o campo `Init` | Não entra no modo paralelo | `Init<0` = desconhecido; confirmado por HTTP **depois** de preso. Sem DHIP, cai para uma por vez (D9) |
| IP temporário e IPs do PC acumulam na placa (print 2) | Placa poluída, rota ambígua | P0 mede a origem. A F2 remove o IP temporário quando a câmera sai do portão |
| Comando que mexe em tudo com câmeras em curso (nova fila, simular, salvar sessão, restaurar placa, atualizar, encerrar) | Estado inconsistente | Recusar enquanto houver câmera no portão ou conferindo, com texto claro. `Test-PainelOciosoAgora` passa a contar os jobs |
| Conflito com o plano de UI (mesmos arquivos) | Retrabalho e conflito de merge | Ondas abaixo: só F1, F3 e P0 correm junto com o plano de UI |
| `-Simular` hoje fabrica uma câmera sem MAC (Servidor ~712) | Simulação não exercita o paralelo | F5: N câmeras simuladas com MACs fictícios distintos |

---

## 5. Premissas

1. **P-1:** câmeras da família DHIP respondem ao `DHDiscover.search` com o MAC próprio, mesmo duplicadas no IP. Visto ao vivo com uma câmera em 01/10. Com duas, a P0 confirma.
2. **P-2:** o switch da bancada é não gerenciado e encaminha unicast pelo MAC de destino.
3. **P-3:** a gravação da rede faz a câmera reiniciar no destino, como hoje. Depois disso ela não volta ao IP de fábrica.
4. **P-4:** o painel roda como Administrador quando toca a placa, como hoje. Sem isso, nada de vizinho estático: o modo paralelo fica desligado com aviso.
5. **P-5:** a senha da sessão é uma só para todas as câmeras da fila, como hoje.
6. **P-6:** mobile fora do escopo. Textos de UI em pt-BR, em caixa de frase.
7. **P-7:** fixtures e documentos do repo usam MACs, seriais e IPs fictícios. Os da bancada do usuário nunca entram (o repo é público).

## 6. Decisões do usuário (Q1–Q8, respondidas em 17/11)

| Pergunta | Resposta | Efeito no plano |
|---|---|---|
| Q1. Marcas | Só Intelbras/Dahua (família DHIP) | D11. Outra marca aparece como "Marca não suportada: não tocada" |
| Q2. Câmeras ao mesmo tempo | Sem limite | O teto é o número de posições pendentes. Sem opção em Opções (sai a antiga F6 Task 4). O orquestrador guarda `Max` só para o modo de reserva: 0 = sem limite, 1 = uma por vez sem DHIP |
| Q3. Posição contra câmera física | Automática, por ordem de chegada | D10 |
| Q4. Câmera já inicializada no IP de fábrica | Não tocar; avisar pelo registro | D8 reescrita. Sai a adoção e sai `MacsComSenhaDaSessao` |
| Q5. DHIP | Obrigatório; sem resposta, uma por vez com aviso | D9 |
| Q6. Versão | 1.3.0 = plano de UI + paralelo, numa release só | Seção 9 |
| Q7. Ordem das etapas | Manter (inicializada, encoder, rede, conferida) | D3 |
| Q8. P0 | Sim, antes da F2 | Feita em 17/11 (6.1) |

### 6.1 Achados P0 (bancada, 17/11)

Três câmeras de fábrica (aqui A, B e C; os MACs reais ficam fora do repo) num switch isolado, sem uplink. A placa recebeu um IP temporário na faixa de fábrica só durante a prova. No fim ficou limpa: sem IP temporário, sem vizinho estático e com DHCP religado.

- **(a) DHIP:** lista as 3 com o mesmo IP (192.168.1.108), MACs distintos e `Init=1` (de fábrica). A câmera recém-resetada responde ARP cerca de 1 min antes de responder DHIP. Com a placa só em APIPA, o DHIP voltou vazio; com IP na faixa de fábrica, respondeu.
- **(b) Vizinho estático:** com a câmera presa pelo MAC, 20 de 20 chamadas `Security.getEncryptInfo` anônimas devolveram a mesma chave pública, distinta para A, B e C. A impressão da chave serve de identidade sem login. Sem prender, tudo foi para a vencedora do ARP (o print 2). Numa outra rodada o ARP trocou de dono no meio: parte das respostas veio de uma, parte de outra, parte não veio (o print 1). **D2 confirmada.**
- **Firmware antigo (G3, 2.800):** no `/RPC2` responde só `{ "NotifyMethod" : "1.2" }`. `Security.getEncryptInfo` e `DevInit.getStatus` funcionam no `/OutsideCmd`. A F2 usa os endpoints com a alternância que `Get-CamChavePublica` já tem.
- **(c) Conflito de IP:** em cerca de 15 min, nenhuma das 3 saiu de 192.168.1.108.
- **(d) IPs a mais na placa (print 2):** não medido. A F2 Task 6 trata pelo rastro.
- **(e) `DHDiscover.setConfig` por MAC:** não sondado (opcional). D2 não depende disso.

---

## 7. Frentes em ondas

Regras para o executor:
- **Execução:** pelo `/regime:maestro`, uma sessão por frente, cada uma no seu worktree (`scripts/frente-abrir.ps1`), integrando só local (`scripts/frente-fechar.ps1`, sem push). Régua e regras do repo: `CLAUDE.md`.
- **Commit:** uma Task, um commit. O corpo traz o quê, o porquê e a prova (saída do teste colada) e termina com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Testes:** cada Task roda o teste da sua frente. Ao fechar a frente, roda a régua inteira do `CLAUDE.md`.
- **Restrições:** sem push e sem release fora da seção 9. Sem painel nem rede real, exceto F8 com permissão.
- **Codificação:** `Servidor-Painel.ps1` continua UTF-8 com BOM (há teste para isso). Tabela `Encode` continua array.

**Dependência do plano de UI** (`~/.claude/plans/declarative-wobbling-rain.md`; F1 e F2 em `main`; F2b, F3 e F4 vão pela frente `ui`):
- o plano de UI mexe em `app.css`, `index.html`, `app.js` e eventualmente em `Servidor-Painel.ps1`;
- **ponto de rebase:** o fechamento da frente `ui` (F4 do plano de UI feita, Status dele em Concluído);
- até lá, só correm frentes que não tocam esses arquivos: F1, F2 e F3.

### Onda 0: em paralelo com o plano de UI

#### P0. Prova de bancada (sem código no repo) — FEITA em 17/11, achados na seção 6.1
- **Escopo:** medir com 2 a 3 câmeras de fábrica num switch isolado:
  - (a) o DHIP lista N câmeras com o mesmo IP e MACs distintos;
  - (b) o vizinho estático fixa o alvo: 20 `getStatus` seguidos respondem do MAC preso, conferido por login e `Get-CamInfoRpc` sem inicializar;
  - (c) o comportamento do firmware com conflito de IP (alguma sai de 192.168.1.108?);
  - (d) a origem dos IPs a mais na placa do print 2, no log e em `placa-sessao.json`;
  - (e) opcional: se `DHDiscover.setConfig` por MAC existe.
- **Arquivos:** script descartável no scratchpad; nada no repo.
- **Depende de:** permissão do usuário (Q8).
- **Paralela com:** tudo da Onda 0.
- **Pronto quando:** os achados de (a) a (d) estão anotados numa seção "Achados P0" deste plano (edição do plano, commit próprio). D2 está confirmada ou trocada.

#### F1. Motor: primitivas seguras para concorrência
- **Arquivos:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`.
- **Depende de:** nada (os commits do plano de UI no motor já estão em `main`).
- **Paralela com:** P0, F3 e o plano de UI.
- **Tasks:**
  1. **`Save-JsonAtomico` com `.tmp` de nome único** (`$Caminho + '.' + guid + '.tmp'`), mantendo `Replace` e `.bak`. Pronto: novo teste em que 2 runspaces gravam o mesmo arquivo 50 vezes cada sem exceção, e o arquivo final é JSON válido.
  2. **`Update-RegistroCamera -Caminho -Entrada`** com Mutex nomeado (hash do caminho, `WaitOne` com timeout de 30 s e erro claro), releitura, `Set-CameraRegistro` e gravação. Pronto: teste em que 2 runspaces fazem upsert de 25 MACs distintos cada, e o registro final tem 50 entradas.
  3. **O `$salvar` de `Invoke-ConfiguracaoCamera` passa a usar `Update-RegistroCamera`;** a leitura inicial continua para a retomada. Pronto: todos os testes de "configuração simulada" passam, mais um teste novo com duas `Invoke-ConfiguracaoCamera -Simular` concorrentes (MACs distintos) no mesmo arquivo terminando com as duas `Instalada`.
  4. **Log por runspace:** documentar e garantir que, sem `-Arquivo` em `Set-MotorLog`, `Write-Log` só chama o sink, e que o sink recebe o contexto. Pronto: teste de que, sem arquivo, nada é escrito em disco.
  5. **Porta HTTP explícita por contexto:** `Invoke-ConfiguracaoCamera` faz `Set-CamPortaHttp` a partir de `Contexto.HttpPort` no início do job, sem depender de estado deixado pela descoberta. Pronto: teste com `HttpPort=8080` no contexto simulado aparecendo na URL montada (`ConvertTo-UrlCam`).
  6. **Parâmetro `-AteEtapa` em `Invoke-ConfiguracaoCamera`** (padrão: vazio, que significa tudo). Para depois da etapa pedida com `Status='Em andamento'` e `Ok=$true`. Uma segunda chamada retoma pelo registro. Pronto: teste com `-AteEtapa rede` seguido de chamada sem o parâmetro terminando em `Instalada|conferida`, sem reinicializar.

#### F3. Orquestrador puro (arquivo novo, sem rede)
- **Arquivos (novos):** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`.
- **Arquivos (alterados):** `.github/workflows/release.yml` (passo de teste), `instalador/Gerar-Instalador.ps1:41` (lista de testes), `instalador/ConfigurarCameras.iss` (linha do arquivo novo).
- **Depende de:** nada.
- **Paralela com:** P0, F1 e o plano de UI.
- **Ideia:** máquina de estado pura. Recebe estado, evento ou tique e devolve o novo estado mais uma lista de ações (`prender`, `soltar`, `despachar`, `publicar`, `avisar`). Não chama rede, placa nem disco: o servidor executa as ações. É o módulo profundo que torna o paralelo testável.
- **Estado por MAC:** `{Mac, Serial, Modelo, IpOrigem, HttpPort, Indice, Fase: espera|portao|conferindo|decisao|feita|pulada, Etapa, Falha, GeracaoLogin}`, mais `Portao` (MAC ou nada), `Max` (0 = sem limite, Q2; 1 = uma por vez, reserva sem DHIP), `Admitindo` e `Avisados` (MACs já avisados, D8).
- **Tasks:**
  1. **Esqueleto e testes do esqueleto:** `New-EstadoParalelo`, `Get-Resumo`. Pronto: `Testes-Orquestrador.ps1` roda no CI e no `Gerar-Instalador`, e a linha nova no `.iss` existe.
  2. **`Step-Descoberta`:** recebe achados DHIP. Deduplica por MAC, ignora MAC de câmera feita, pulada ou em decisão, coloca as de fábrica em espera na ordem de chegada e marca "Marca não suportada" fora da família. Pronto: testes com duas câmeras no mesmo IP (as duas em espera), MAC repetido entre tiques (sem duplicar) e câmera feita reaparecendo (ignorada).
  3. **`Step-Admissao`:** com portão livre, vaga (`Max` 0 = sem limite), `Admitindo` e posição pendente, gera a ação `prender` e depois `despachar(AteEtapa=rede)` para a primeira em espera, atribuindo o índice (D10). Sem posição livre, a câmera fica em espera com o motivo "sem posição livre". Pronto: testes com Max=0 e 3 em espera (uma no portão, as outras aguardam só o portão), Max=1 (a segunda espera a primeira terminar a conferência), sem posição livre e com IP de destino ocupado (pula a posição, como hoje em `Invoke-Conectada`).
  4. **`Step-FimDoJob`:**
     - fim do portão com Ok: `soltar` e `despachar(conferência)`;
     - Ok da conferência: `feita`;
     - falha: `decisao` só daquele MAC, com `soltar` se estava no portão;
     - MAC trocado: volta para espera, posição pendente, sem decisão (D7).
     - Pronto: testes para cada ramo, com o caso do print 1 reproduzido (escolhido A, lido B) terminando com a posição pendente, A e B de volta à espera e o vigia sem pausa.
  5. **`Step-JaInicializada` (aviso, D8):** recebe as câmeras inicializadas vistas pelo DHIP e o registro (só dados, o servidor lê o arquivo). Nunca gera `prender` nem `despachar` para elas. Gera `avisar`, uma vez por MAC: registro `Em andamento`/`Falhou` → "Câmera da fila parada na etapa X. Retome em Ferramentas."; `Instalada` → nada; desconhecido → "Câmera já inicializada: não tocada.". `Init` desconhecido vai para espera com a marca `ConferirInit` (o portão consulta depois de prender). Pronto: testes de cada caso, do aviso único entre tiques e de que nenhuma ação de rede sai para câmera inicializada.
  6. **`Step-Decisao -Mac -Acao tentar|pular|encerrar`:**
     - `tentar` com login recusado na mesma geração é recusado;
     - `encerrar` zera `Admitindo` e deixa terminar quem está em curso.
     - Pronto: testes de cada ação e da guarda de lockout por cartão.
  7. **`Step-Comando` (guardas globais):** nova fila, simular, salvar sessão, trocar senha, restaurar placa e atualizar são recusados com câmera em portão ou conferindo, com o texto da recusa definido aqui. Pronto: tabela de testes comando × estado.

### Onda 1: depois da F1

#### F2. Motor: identidade por MAC e portão
- **Arquivos:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`, `fonte/Testes-Descoberta.ps1`, fixture nova `fonte/testes/dhip-duas-de-fabrica-mesmo-ip.json` (derivada da G4, com MACs e seriais fictícios).
- **Depende de:** F1 (mesmo arquivo; vai na mesma frente `motor`, depois da F1); P0 feita (6.1).
- **Achado P0 que pesa aqui:** a G3 (2.800) só atende chamada anônima no `/OutsideCmd`. Qualquer sonda nova por câmera presa (por exemplo, conferir o `Init` desconhecido) usa a alternância de `Get-CamChavePublica`, não `/RPC2` fixo.
- **Paralela com:** F3, se ainda estiver aberta, e com o plano de UI.
- **Tasks:**
  1. **`Set-VizinhoEstatico -IfIndex -Ip -Mac` e `Remove-VizinhoEstatico`** (remove a dinâmica, cria Permanent em ActiveStore, confere com `Get-NetNeighbor`; devolve `{Ok; Erro}`), com as chamadas de rede injetáveis para teste. Pronto: testes com funções falsas: entrada dinâmica pré-existente (remove e cria) e conferência que não bate (`Ok=$false`).
  2. **Rastro:** `New-SessaoPlaca`/`Merge-SessaoPlaca` passam a guardar `Vizinhos` (lista de `{Ip, Mac}`), e `Get-IpsARemover`/`Reset-RedeLocalCameras` os removem. Pronto: testes de mescla e de remoção na seção "IPs do PC na sessao e rastro da placa".
  3. **Descoberta sem atribuição cruzada:** em `Find-CamerasNaRede`, IP repetido entre achados DHIP de MACs distintos não vai ao `Invoke-ProbeInitLote`. Fica `Confirmado=$false`, `Init` do broadcast e um campo novo `IpDividido=$true`. Pronto: teste em `Testes-Descoberta` com a fixture nova (2 achados, os dois com `IpDividido`, nenhum confirmado por HTTP).
  4. **`Test-MacTrocandoNoIp -Ip`** (duas leituras de vizinho com intervalo curto, injetável), para o aviso da D9. Pronto: teste com leituras falsas diferentes (verdadeiro) e iguais (falso).
  5. **Texto da trava de MAC (Motor ~3816):** sai o "Nada foi alterado". O resultado ganha `MacTrocado=$true` e `MacLido`. Pronto: teste simulado com `-Simular` e MAC falso forçando a troca (`FalharEm 'mac-trocado'`), devolvendo `MacTrocado`.
  6. **Remoção do IP temporário** que a câmera do portão usou (`Remove-IpTemporarioPlaca`) quando ela sai do IP de origem. O achado (d) da P0 não foi medido: a Task trata pelo rastro. Pronto: teste de rastro mostrando o IP fora depois da remoção.

### Onda 2: depois das frentes `ui` (F4 do plano de UI), `motor` e `orquestrador` fechadas

Os planos de frente da Onda 2 em diante se escrevem quando a Onda 0 fechar, a partir do `main` integrado.

#### F4. Servidor: coordenador e pool
- **Plano de frente:** `docs/plans/2026-11-18-frente-servidor-plan.md` (frente `servidor`). Ele manda onde divergir do texto abaixo: coordenador em arquivo próprio (`fonte/Coordenador-Cameras.ps1`, testado no CI); "câmera conectada" sem IP vira "procurar agora"; decisões R1–R8 (tentar com rede gravada retoma pela conferência sem portão; admissão percorre a espera; encerrar a fila ≠ encerrar o painel; falha ao prender e MAC trocado na conferência viram decisão; fase `ignorada`). O contrato da Task 4 abaixo ganha `aviso` por câmera, `paralelo.emCurso` e `filaItens`.
- **Arquivos:** `fonte/web/Servidor-Painel.ps1` (UTF-8 com BOM).
- **Depende de:** plano de UI Concluído (ponto de rebase), F1, F2, F3.
- **Paralela com:** F7.
- **Tasks:**
  1. **Carregar `Orquestrador-Cameras.ps1` e criar o RunspacePool** (sem limite próprio, Q2; o teto é o número de posições), com a fila de eventos. O job recebe o contexto, a senha (só em memória), o caminho do registro, `-AteEtapa` e um sink que enfileira `{mac, tipo, ...}`. Pronto: com `-Simular`, uma câmera passa por portão e conferência via pool, e `GET /api/estado` mostra a câmera; teste ponta a ponta em simulação descrito no corpo do commit.
  2. **Laço do coordenador:** comando, depois drenar eventos (log via `$adicionarLog` e arquivo, progresso por MAC), depois tique do vigia e admissão (`Step-*`), depois executar ações (`prender`/`soltar` via F2, `despachar` no pool), depois `Publicar`. `$E.Ocupado` passa a significar "há câmera em curso". `Add-Comando` deixa passar decisão, vigia e porta/canal por cartão. Pronto: com 3 câmeras simuladas, o painel responde a `GET /api/estado` em menos de 500 ms durante as conferências.
  3. **Vigia paralelo:** com o vigia ligado, o tique roda o DHIP na placa escolhida (D9) mesmo com fase de câmera em curso. `Test-VezDoVigia` deixa de exigir `Fase='fila'`, e `Add-AvisoJaInicializada` vira `Step-JaInicializada`. `SemSucesso` só conta tique que viu câmera e não pôde agir por motivo que exige o operador; sem DHIP, cai para uma por vez com o aviso. Pronto: em simulação, uma câmera em decisão não impede a admissão da seguinte.
  4. **Contrato do estado publicado** (é a base da F6; não mudar sem atualizar este plano):
     - `cameras: [{mac, serial, modelo, ipOrigem, indice, posicao, destino, porta, canal, fase, etapa, progresso:{atual,total}, trabalho, falha:{etapa, erro, recusa, loginRecusado, bloqueada, geracao}}]`;
     - `portao: mac|null`;
     - `paralelo: {max, admitindo, dhip: ok|sem-resposta}`;
     - os campos antigos `fase/atual/camera/falha` continuam derivados (primeira câmera em decisão ou em curso), para a UI atual seguir funcionando até a F6.
     - Pronto: teste do JSON publicado em simulação com 2 câmeras; a UI atual carrega sem erro no console.
  5. **Comandos por MAC:** `POST /api/decisao {mac, acao}`, `POST /api/camera {mac, porta, canal}` e guardas globais via `Step-Comando`. Pronto: chamadas em simulação conferidas no corpo do commit.
  6. **Encerrar e atualizar:** `Test-PainelOciosoAgora` conta os jobs. O encerrar espera os jobs ou recusa com texto, solta todos os vizinhos estáticos e restaura a placa (ADR 0002). Pronto: em simulação, o encerrar com conferência em curso recusa e, depois do fim, encerra limpo.

#### F5. Simulação com N câmeras
- **Arquivos:** `fonte/web/Servidor-Painel.ps1` e, se preciso, só o ramo `-Simular` de `fonte/Motor-Cameras.ps1`.
- **Depende de:** F4 (mesmo arquivo).
- **Paralela com:** F7.
- **Tasks:**
  1. **N câmeras simuladas:** o tique do vigia em simulação "faz aparecer" N câmeras de fábrica (padrão 3), com MACs fictícios distintos (`AA:00:00:00:00:0x`), serial `SIM-x` e atrasos por etapa (escala curta configurável). Pronto: `-Simular` mostra 3 cartões avançando juntos na conferência. *A frente `servidor` já entrega 3 câmeras fixas e uma espera simulada no job (portão e conferência); aqui fica o N configurável e os atrasos por etapa.*
  2. **`FalharEm` por câmera** (por exemplo, câmera 2 na rede), mais os casos `mac-trocado` e `ja-inicializada`. Pronto: com falha na câmera 2, as câmeras 1 e 3 terminam `feita`; o caso `mac-trocado` não abre decisão; o caso `ja-inicializada` só é avisado, nunca tocado.

### Onda 3: depois da F4 (contrato do estado)

#### F6. UI: bancada com N cartões
- **Arquivos:** `fonte/web/www/app.js`, `index.html`, `app.css`.
- **Depende de:** F4 (contrato) e o plano de UI Concluído; F5 ajuda a ver.
- **Paralela com:** F7.
- **Tasks:**
  1. **Cartão da câmera:** um por item de `cameras[]`, com modelo, serial, MAC, posição, destino, etapa e barra de progresso. "No portão" destacado; porta e canal editáveis até a conferência terminar. Respeitar o tema e as guidelines do plano de UI (`aria-live` por cartão, sem re-render que roube foco). Pronto: Playwright em `-Simular -Porta 8765` com 3 cartões, captura de tela clara e escura.
  2. **Decisão por cartão:** Tentar de novo / Pular esta posição no cartão. "Encerrar a fila" sai do cartão e vira um botão da fila. Tentar fica desabilitado com login recusado na mesma geração. Pronto: Playwright com falha forçada na câmera 2; as outras seguem.
  3. **Fita e vigia:**
     - a fita marca várias posições "agora" ao mesmo tempo;
     - o texto do vigia passa a ser "Observando 192.168.1.108 por broadcast. Ligue quantas câmeras quiser no switch: cada uma entra na próxima posição livre.";
     - saem "Tire a câmera anterior" e "Em pausa até você resolver a câmera atual";
     - avisos de DHIP sem resposta e de MAC alternando aparecem.
     - Pronto: Playwright confere os textos novos e a ausência dos antigos.
  - Sem opção "Câmeras ao mesmo tempo": o usuário escolheu sem limite (Q2).

#### F7. Documentação
- **Arquivos:** `CONTEXT.md` (termos da seção 3; revisar "Fila", "Vigia" e "Posição"), `LEIA-ME.md` (fluxo novo, PoE, firewall UDP 37810, Pendências), `fonte/API-INTELBRAS.md` (comportamento de IP duplicado e vizinho estático, achados P0), `docs/adr/0004-portao-do-ip-de-fabrica.md` (D2 e D4).
- **Depende de:** F4 (para descrever o real).
- **Paralela com:** F5 e F6.
- **Pronto quando:** `git grep -n "uma por vez"` só sobra onde for verdade (retomada manual, sem DHIP), e nenhum MAC ou IP real da bancada aparece (`git grep` com os valores dos prints, guardados fora do repo, sai vazio).

### Onda 4: validação real e release

#### F8. Bancada com 2 a 3 câmeras reais
- **Arquivos:** `fonte/testes/Conferir-Bancada.ps1` (novo, só leitura: lê `GET /api/estado` e o registro e confere os invariantes; não vai no instalador).
- **Depende de:** F4, F5, F6; permissão do usuário.
- **Pronto quando:** o roteiro (seção 8.3) passou, com a saída do `Conferir-Bancada.ps1` colada no commit.

---

## 8. Estratégia de validação

### 8.1 Unitários, sem hardware (régua de toda Task)
- **`Testes-Motor.ps1`:** concorrência de arquivo (F1), `-AteEtapa`, vizinho estático com funções falsas, rastro com `Vizinhos`, trava de MAC com `MacTrocado`.
- **`Testes-Descoberta.ps1`:** fixture de duas câmeras de fábrica no mesmo IP, sem confirmação cruzada.
- **`Testes-Orquestrador.ps1`:** todos os ramos da máquina de estado, incluindo o print 1 (MAC trocado), o print 2 (inicializada escondendo a de fábrica), falha isolada, lockout por cartão e guardas globais.
- **Contagem de testes:** não se escreve em documento. Conta-se ao vivo na saída.

### 8.2 Simulação (`Servidor-Painel.ps1 -Simular`)
- 3 câmeras simuladas em paralelo; falha forçada na 2; casos `mac-trocado` e `ja-inicializada`.
- Painel respondendo durante as conferências.
- Encerrar recusado com câmera em curso.
- Playwright (F6) com capturas clara e escura.

### 8.3 Roteiro de bancada (F8, com permissão; switch isolado, PoE suficiente)
1. Sessão pronta, placa escolhida preparada, fila de 3 posições, vigia ligado.
2. Ligar as 3 câmeras de fábrica de uma vez no switch.
3. Esperado:
   - as três aparecem em espera;
   - uma por vez no portão;
   - conferências sobrepostas;
   - as três `Instalada` no registro com MACs distintos e destinos distintos;
   - nenhum aviso "MAC lido";
   - sem vizinho estático sobrando (`Get-NetNeighbor -State Permanent` vazio para o IP de fábrica).
4. Repetir puxando o cabo de uma câmera durante a conferência dela. Esperado: só aquele cartão falha, e as outras terminam.
5. Reproduzir o print 2: inicializar uma câmera e deixá-la no IP de fábrica, depois ligar outra de fábrica. Esperado: a de fábrica é configurada, e a inicializada não é tocada (só o aviso do D8).
6. `Conferir-Bancada.ps1` sem violação. CPU do notebook anotada no commit.

Teste só da frente: o roteiro não junta prova de outras pendências do LEIA-ME (reset real, etc.).

## 9. Release (só com aprovação explícita do usuário)

1. Número conforme a Q6: `fonte/VERSAO.txt` para 1.3.0 (plano de UI + paralelo), num commit só.
2. Antes do push, `git ls-files | findstr /i senha` tem que sair vazio. Nunca subir o bundle de histórico. Push pelo credential helper do `gh` (conta ativa conferida).
3. Tag `v<versão>` igual ao `VERSAO.txt`. O `release.yml` roda os três arquivos de teste, gera o instalador e publica o `.exe` e o `.sha256`.
4. Depois da publicação: atualizar pelo painel numa máquina de bancada e conferir a versão.
5. Plano em Concluído.
