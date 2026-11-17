# Frente motor: primitivas de concorrência (F1) e identidade por MAC com portão (F2)

**Status:** Ativo · **Frente:** `motor`

**Goal:** deixar o `Motor-Cameras.ps1` pronto para várias câmeras ao mesmo tempo, sem servidor nem UI. Gravação de arquivo e registro seguras entre runspaces, job com porta e etapa final explícitas, vizinho estático (o portão do IP de fábrica) com rastro, descoberta que não confunde duas câmeras no mesmo IP e trava de MAC que devolve dado em vez de texto.

**Non-Goals:**
- servidor, pool e coordenador (F4 do mapa);
- orquestrador (frente `orquestrador`);
- UI (frente `ui`);
- qualquer chamada real de rede, placa ou câmera.

**Touched:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`, `fonte/Testes-Descoberta.ps1`, `fonte/testes/dhip-duas-de-fabrica-mesmo-ip.json` (nova), `docs/plans/2026-11-17-frente-motor-plan.md` (só a Task 13).

**Safety:**
- Há 3 câmeras de fábrica ligadas no switch da bancada, e elas têm que continuar de fábrica até a F8. Nenhum teste chama `New-NetNeighbor`, `New-NetIPAddress`, `Remove-NetNeighbor`, `curl.exe` ou HTTP de verdade: tudo que toca rede ou placa é injetável e falso no teste.
- Repo público: fixture com MAC `AA:00:00:00:00:0x`, serial `SIM-x`, modelo genérico. Nunca valores da bancada.
- `Motor-Cameras.ps1` é UTF-8 com BOM; os dois arquivos de teste são sem BOM. Manter cada um como está.
- PowerShell 5.1 (`powershell.exe`), não `pwsh`.

**Decisões (do mapa `docs/plans/2026-11-cameras-em-paralelo.md`):**
- D1: a câmera é identificada pelo MAC, de ponta a ponta.
- D2: portão do IP de fábrica = vizinho estático `IpFabrica -> MAC` (`New-NetNeighbor -State Permanent -PolicyStore ActiveStore`), confirmado na P0 (seção 6.1 do mapa).
- D5: registro gravado por câmera sob Mutex nomeado, com releitura e mescla por MAC.
- D7: MAC trocado é erro do portão, não falha da posição.
- Achado P0: a G3 (firmware 2.800) só atende chamada anônima no `/OutsideCmd`. Sonda nova usa a alternância de `Get-CamChavePublica`, nunca `/RPC2` fixo.
- Localize pelo nome da função, não pela linha.

## Task 1: Save-JsonAtomico com .tmp de nome único

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- RED: teste novo em que 2 runspaces gravam o mesmo arquivo 50 vezes cada. Hoje o `.tmp` tem nome fixo, então o teste deve falhar com exceção ou JSON quebrado.
- GREEN: `.tmp` passa a ser `$Caminho + '.' + [guid]::NewGuid().ToString('N') + '.tmp'`, mantendo `Replace` e `.bak`. Se o `Replace` concorrente ainda falhar, tentar de novo com espera curta, com limite.

**Validation:** `Testes-Motor.ps1` verde, com o teste novo listado na saída; o arquivo final é JSON válido.

## Task 2: Update-RegistroCamera sob Mutex nomeado

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- `Update-RegistroCamera -Caminho -Entrada`: Mutex com nome derivado do hash do caminho (sem prefixo `Global`: o painel e os jobs rodam na mesma sessão), `WaitOne` de 30 s com erro claro em pt-BR, releitura do arquivo, `Set-CameraRegistro` (mescla por MAC) e `Save-JsonAtomico`. `ReleaseMutex` no `finally`.
- RED: 2 runspaces fazem upsert de 25 MACs distintos cada no mesmo registro.

**Validation:** `Testes-Motor.ps1` verde; o registro final tem 50 entradas.

## Task 3: Invoke-ConfiguracaoCamera grava pelo Update-RegistroCamera

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- O `$salvar` interno de `Invoke-ConfiguracaoCamera` passa a chamar `Update-RegistroCamera`. A leitura inicial do registro continua, para a retomada (`Get-PlanoRetomada`).
- Teste novo: duas `Invoke-ConfiguracaoCamera -Simular` concorrentes, MACs distintos, mesmo arquivo de registro.

**Validation:** todos os testes de "configuração simulada" continuam verdes; o teste novo termina com as duas câmeras `Instalada`.

## Task 4: log por runspace sem arquivo

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- Documentar no comentário de `Set-MotorLog`/`Write-Log` e garantir no código: sem `-Arquivo`, `Write-Log` só chama o sink, e o sink recebe o contexto (MAC) da câmera.

**Validation:** teste novo prova que, sem arquivo configurado, nada é escrito em disco e o sink recebe a linha com o MAC.

## Task 5: porta HTTP explícita por contexto

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- `Invoke-ConfiguracaoCamera` chama `Set-CamPortaHttp` a partir de `Contexto.HttpPort` logo no início do job, sem depender do estado deixado pela descoberta.

**Validation:** teste com `HttpPort=8080` no contexto simulado; a URL montada por `ConvertTo-UrlCam` leva `:8080`.

## Task 6: parâmetro -AteEtapa em Invoke-ConfiguracaoCamera

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- `-AteEtapa` (vazio = tudo, o comportamento de hoje). Para depois da etapa pedida com `Status='Em andamento'` e `Ok=$true`. Uma segunda chamada, sem o parâmetro, retoma pelo registro.

**Validation:** teste com `-AteEtapa rede` e depois sem o parâmetro termina em `Instalada` com etapa `conferida`, sem reinicializar a câmera (o simulado não registra um segundo DevInit).

## Task 7: Set-VizinhoEstatico e Remove-VizinhoEstatico

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- `Set-VizinhoEstatico -IfIndex -Ip -Mac`: remove a entrada dinâmica, cria `Permanent` em `ActiveStore`, confere com `Get-NetNeighbor`. Devolve `{Ok; Erro}`.
- `Remove-VizinhoEstatico -IfIndex -Ip`.
- As chamadas `Get/New/Remove-NetNeighbor` ficam em funções pequenas do motor, que o teste redefine com versões falsas. É o padrão que `Testes-Motor.ps1` já usa (ele redefine `Get-VizinhosMac` e `Invoke-ProbeInitLote`).

**Validation:** testes só com funções falsas: entrada dinâmica pré-existente (remove e cria); conferência que não bate (`Ok=$false` com erro em pt-BR); remoção. Nenhuma chamada real (conferir no teste que o falso foi o chamado).

## Task 8: rastro guarda os vizinhos estáticos

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- `New-SessaoPlaca`/`Merge-SessaoPlaca` ganham `Vizinhos` (lista de `{Ip, Mac}`). `Get-IpsARemover` e `Reset-RedeLocalCameras` removem os vizinhos do rastro, pelas funções injetáveis da Task 7.

**Validation:** testes de mescla e de remoção na seção "IPs do PC na sessao e rastro da placa" de `Testes-Motor.ps1`; rastro antigo, sem `Vizinhos`, continua lido sem erro.

## Task 9: descoberta sem atribuição cruzada

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Descoberta.ps1`, `fonte/testes/dhip-duas-de-fabrica-mesmo-ip.json`

- Fixture nova derivada da fixture G4 que já existe em `fonte/testes/`: dois achados DHIP no mesmo IP de fábrica, MACs `AA:00:00:00:00:01` e `AA:00:00:00:00:02`, seriais `SIM-1` e `SIM-2`, os dois de fábrica.
- Em `Find-CamerasNaRede`, IP repetido entre achados de MACs distintos não vai para `Invoke-ProbeInitLote`: fica `Confirmado=$false`, `Init` do broadcast e campo novo `IpDividido=$true`.

**Validation:** `Testes-Descoberta.ps1` verde; com a fixture nova saem 2 achados, os dois com `IpDividido`, nenhum confirmado por HTTP.

## Task 10: Test-MacTrocandoNoIp

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- `Test-MacTrocandoNoIp -Ip`: duas leituras de vizinho (`Get-VizinhosMac`) com intervalo curto; verdadeiro se o MAC mudou. Leitura injetável; o intervalo também, para o teste não dormir.

**Validation:** leituras falsas diferentes dão verdadeiro; iguais dão falso.

## Task 11: trava de MAC devolve MacTrocado

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- Na trava de MAC de `Invoke-ConfiguracaoCamera` (procure a mensagem "Nada foi alterado"), o texto deixa de dizer "Nada foi alterado". O resultado ganha `MacTrocado=$true` e `MacLido`.
- O simulado ganha `FalharEm 'mac-trocado'`.

**Validation:** teste com `-Simular -FalharEm 'mac-trocado'` devolve `MacTrocado=$true` e o `MacLido` falso; o registro não marca a posição como `Falhou`.

## Task 12: remoção do IP temporário da câmera do portão

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

- Quando a câmera do portão sai do IP de origem, o IP temporário que a placa ganhou para alcançá-la (`Add-IpTemporarioPlaca`) sai também. Função nova `Remove-IpTemporarioPlaca`, guiada pelo rastro, com `Remove-NetIPAddress` numa função que o teste redefine. O achado (d) da P0 não foi medido: tratar pelo rastro, sem suposição sobre a origem dos IPs a mais.

**Validation:** teste de rastro mostra o IP fora depois da remoção, com funções falsas.

## Task 13: fechar o plano

**Files:** `docs/plans/2026-11-17-frente-motor-plan.md`

- `**Status:**` passa a `Concluído`, com uma linha dizendo que F1 e F2 do mapa estão feitas. Não editar o mapa: três frentes correm ao mesmo tempo, e o mapa só muda na raiz, depois que elas fecham.

**Validation:** a régua inteira verde; `git diff --check` limpo.
