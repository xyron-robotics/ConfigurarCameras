# Frente orquestrador: máquina de estado pura do paralelo (F3)

**Status:** Ativo · **Frente:** `orquestrador`

**Goal:** criar `fonte/Orquestrador-Cameras.ps1`, uma máquina de estado pura que decide o paralelo. Recebe estado mais evento ou tique e devolve o novo estado e uma lista de ações (`prender`, `soltar`, `despachar`, `publicar`, `avisar`). Não chama rede, placa nem disco: quem executa as ações é o servidor, na F4 do mapa. Este é o módulo que torna o paralelo testável sem hardware.

**Non-Goals:**
- carregar o orquestrador no servidor, criar o pool e executar as ações (F4 do mapa);
- mexer em `Motor-Cameras.ps1` (frente `motor`) ou na UI (frente `ui`);
- ler ou gravar arquivo: o registro chega como dado no parâmetro.

**Touched:** `fonte/Orquestrador-Cameras.ps1` (novo), `fonte/Testes-Orquestrador.ps1` (novo), `.github/workflows/release.yml`, `instalador/Gerar-Instalador.ps1`, `instalador/ConfigurarCameras.iss`, `docs/plans/2026-11-17-frente-orquestrador-plan.md` (só a Task 8).

**Safety:**
- Nada de rede, placa, câmera ou disco no orquestrador nem nos testes dele. Há 3 câmeras de fábrica ligadas na bancada, e elas têm que continuar de fábrica.
- Repo público: testes com MAC `AA:00:00:00:00:0x`, serial `SIM-x`, IPs de documentação ou a faixa de fábrica 192.168.1.108.
- `Orquestrador-Cameras.ps1` leva texto em pt-BR com acento: UTF-8 **com BOM**, que é como o PowerShell 5.1 lê acento sem quebrar (é a codificação do `Motor-Cameras.ps1`). `Testes-Orquestrador.ps1` segue o padrão de `Testes-Motor.ps1`: sem BOM e sem acento no código.
- PowerShell 5.1 (`powershell.exe`).

**Decisões (do mapa `docs/plans/2026-11-cameras-em-paralelo.md`, seções 2 e 6):**
- Estado por MAC: `{Mac, Serial, Modelo, IpOrigem, HttpPort, Indice, Fase: espera|portao|conferindo|decisao|feita|pulada, Etapa, Falha, GeracaoLogin}`, mais `Portao` (MAC ou nada), `Max`, `Admitindo` e `Avisados`.
- Q2: sem limite de câmeras ao mesmo tempo. `Max` = 0 significa sem limite (padrão). `Max` = 1 é o modo de reserva, uma por vez, quando o DHIP não responde (Q5, D9).
- O portão tem sempre 1 vaga (D2). A ordem de espera é a do primeiro aparecimento no DHIP; a posição é atribuída na entrada do portão (D10, Q3).
- Q4/D8: câmera já inicializada nunca recebe ação de rede. Só aviso, guiado pelo registro.
- D6: falha isolada por câmera, o vigia não pausa. D7: MAC trocado volta para espera, sem decisão.
- Sai do Draft: não existe `MacsComSenhaDaSessao` nem adoção.
- Contrato de saída de todo `Step-*`: `@{ Estado = <novo estado>; Acoes = @(<ação>, ...) }`, com ação `@{ Tipo = 'prender'|'soltar'|'despachar'|'publicar'|'avisar'; Mac = ...; ... }`. `despachar` leva `AteEtapa` (`rede` no portão, vazio na conferência). `avisar` leva `Texto`. O estado de entrada nunca é mutado: o Step devolve cópia.

## Task 1: esqueleto, testes no CI e no instalador

**Files:** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`, `.github/workflows/release.yml`, `instalador/Gerar-Instalador.ps1`, `instalador/ConfigurarCameras.iss`

- `New-EstadoParalelo -Posicoes -Max` e `Get-Resumo` (contagem por fase, portão, admitindo).
- `Testes-Orquestrador.ps1` no estilo de `Testes-Motor.ps1` (mesmo jeito de contar e de sair com código diferente de 0 na falha), carregando o orquestrador por dot-source.
- `release.yml`: passo novo igual aos de `Testes-Motor.ps1` e `Testes-Descoberta.ps1`.
- `Gerar-Instalador.ps1`: o arquivo entra na lista de testes (`foreach ($t in @(...))`) e no comentário do topo.
- `.iss`: linha do `Orquestrador-Cameras.ps1`, igual à do `Motor-Cameras.ps1`. O arquivo de teste não vai para o usuário.

**Validation:** `Testes-Orquestrador.ps1` verde; `Select-String` mostra o arquivo novo em `release.yml`, `Gerar-Instalador.ps1` e `.iss`.

## Task 2: Step-Descoberta

**Files:** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`

- Recebe achados DHIP (`Mac, Serial, Modelo, Ip, HttpPort, Init, Marca`). Deduplica por MAC; ignora MAC em `feita`, `pulada`, `decisao` ou em curso; põe as de fábrica em `espera` na ordem de chegada; fora da família DHIP, `avisar` "Marca não suportada: não tocada." uma vez por MAC. Câmeras inicializadas vão para o Step da Task 5, não para a espera.

**Validation:** testes com duas câmeras de fábrica no mesmo IP (as duas em espera, ordem preservada), MAC repetido entre tiques (sem duplicar), câmera feita reaparecendo (ignorada), marca não suportada (um aviso só).

## Task 3: Step-Admissao

**Files:** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`

- Com portão livre, `Admitindo`, vaga (`Max` 0 = sem limite; senão, câmeras em `portao` + `conferindo` abaixo de `Max`) e posição pendente: para a primeira em espera, atribui o índice (D10), fase `portao`, ações `prender` e `despachar(AteEtapa=rede)`.
- Sem posição livre: a câmera fica em espera com o motivo "sem posição livre".
- IP de destino ocupado (dado de entrada): pula a posição, como `Invoke-Conectada` faz hoje no servidor.

**Validation:** testes com `Max`=0 e 3 em espera (uma no portão, as outras aguardam só o portão); `Max`=1 (a segunda espera a primeira terminar a conferência); sem posição livre; destino ocupado.

## Task 4: Step-FimDoJob

**Files:** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`

- Fim do portão com Ok: `soltar` e `despachar` (conferência), fase `conferindo`.
- Ok da conferência: `feita`.
- Falha: `decisao` só daquele MAC, com `soltar` se estava no portão; guarda `Falha` (etapa, erro, login recusado, geração).
- `MacTrocado` (resultado da frente `motor`): `soltar`; o MAC escolhido e o MAC lido voltam para espera; a posição volta a pendente; sem decisão (D7).

**Validation:** um teste por ramo, mais o print 1 reproduzido (escolhido A, lido B) terminando com a posição pendente, A e B em espera e `Admitindo` intacto.

## Task 5: Step-JaInicializada (aviso pelo registro)

**Files:** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`

- Recebe as câmeras inicializadas vistas pelo DHIP e o registro como dado (lista de `{Mac, Status, Etapa}`). Nunca gera `prender` nem `despachar` para elas.
- `avisar`, uma vez por MAC (guardado em `Avisados`):
  - registro `Em andamento` ou `Falhou`: "Câmera da fila parada na etapa X. Retome em Ferramentas.";
  - registro `Instalada`: nada;
  - desconhecida: "Câmera já inicializada: não tocada.".
- `Init` desconhecido (firmware sem o campo): vai para espera com `ConferirInit=$true`. O portão confere depois de prender.

**Validation:** um teste por caso; aviso único entre tiques; nenhuma ação `prender`/`despachar` sai para câmera inicializada (asserção sobre a lista inteira de ações).

## Task 6: Step-Decisao

**Files:** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`

- `Step-Decisao -Mac -Acao tentar|pular|encerrar`:
  - `tentar`: volta para espera com a mesma posição; recusado, com texto, se a falha foi login recusado na mesma `GeracaoLogin` (guarda de lockout por cartão);
  - `pular`: posição `pulada`, câmera sai;
  - `encerrar`: `Admitindo=$false`; quem está em curso termina.

**Validation:** teste de cada ação e da guarda de lockout (mesma geração recusa; geração nova aceita).

## Task 7: Step-Comando (guardas globais)

**Files:** `fonte/Orquestrador-Cameras.ps1`, `fonte/Testes-Orquestrador.ps1`

- Nova fila, simular, salvar sessão, trocar senha, restaurar placa e atualizar: recusados com câmera em `portao` ou `conferindo`. O texto da recusa em pt-BR é definido aqui (a F4 só o repassa). Decisão por MAC, vigia e porta/canal por cartão passam.

**Validation:** tabela de testes comando × estado (ocioso, só espera, portão, conferindo, decisão).

## Task 8: fechar o plano

**Files:** `docs/plans/2026-11-17-frente-orquestrador-plan.md`

- `**Status:**` passa a `Concluído`, com uma linha dizendo que a F3 do mapa está feita e o contrato de saída dos `Step-*` (o da seção Decisões) é o que a F4 consome. Não editar o mapa: três frentes correm ao mesmo tempo, e o mapa só muda na raiz, depois que elas fecham.

**Validation:** a régua inteira verde; `git diff --check` limpo.
