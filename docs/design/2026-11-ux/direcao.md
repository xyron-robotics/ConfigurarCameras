# Direção do redesenho do painel

Frente `ux`, Task 4. Entrada: `linha-de-base.md` (Task 1), `auditoria-ux.md` (Task 2, achados `UX-nn`), `auditoria-ui.md` (Task 3, achados `UI-nn`) e `marca/`. Saída: uma direção só, defendida. Há alternativa apenas onde existe um trade-off com nome. O protótipo (Task 5) e a fase B constroem a partir daqui.

Dados de exemplo fictícios: IPs `192.0.2.x` e `192.168.1.108` (IP de fábrica), MACs `AA:00:00:00:00:0x`, seriais `SIM-x`, "Obra exemplo".

Decisão do usuário (Task 3): não há arquivo vetorial da logo. A direção usa o PNG oficial de 2302 px (`marca/logo-smartseg.png`) e recortes dele. Nada é redesenhado em vetor.

## Conceito: console de bancada

O painel deixa de ser um site com menu lateral e cartões e passa a ser um **console de bancada**: uma linha por posição da fila, o resultado e a falha na própria linha, cor só para o que é anormal, e uma única área que diz "isto pede você". O passo a passo fica para a primeira vez. A volta do segundo dia cai direto na conferência.

Fiz o plano em duas passagens, como pede a `frontend-design`. A primeira foi "painel com marca": cartões azuis e logo grande no topo. Revisei contra os padrões genéricos e mudei três coisas. Os cartões viraram tabela porque eram o kit SaaS (padrão 4 da skill) e o `UX-22`. A linha de contagem com pontos médios ("7 instaladas · 1 falha · …") virou legenda colada na fita, porque era o padrão 5 (template chrome). E a logo grande no topo virou símbolo no topo mais logo inteira nas telas de abertura e fim, porque custava 26 px de altura em toda tela (trade-off nomeado na seção 4.6). A ousadia fica num lugar só: a **fita da fila**, larga, uma casa por posição, que funciona como a régua física da bancada.

## Pesquisa: padrões de referência

Feita com a skill `mattpocock-skills:research` por um agente em segundo plano, só com fontes primárias (manuais e documentação dos fabricantes, normas, design systems). Nenhuma interface foi copiada. O que se aproveita é o padrão de comportamento.

| Padrão | Fonte (lida) | Onde entra |
|---|---|---|
| Tabela densa por dispositivo. Dispositivo não inicializado com estado próprio. Resultado por linha, com ícone e detalhe. Lote de IPs a partir de um IP inicial. "Repetir as operações com falha" | Intelbras IP Utility, manual 03-22: https://backend.intelbras.com/sites/default/files/2022-05/Manual_IP_Utility_03-22_0.pdf | Tabela da fila (5.4), estado "Na espera" separado, falha na linha |
| [Simulate] mostra os IPs antes de aplicar. Coluna Result por linha. Paralelo até 16 ou sequencial | Hanwha Wisenet Device Manager, guia 2020: https://www.hanwhavision.com/wp-content/uploads/2021/09/Wisenet-Device-Manager-UserGuide_EN_201027.pdf | Prévia da fila com conflito do registro (2.2), coluna Estado |
| Lista com estado. Senha só para quem não tem. "Cancelar o restante se uma falhar". Painel de tarefas | AXIS Device Manager: https://help.axis.com/en/axis-device-manager | Falha não para a fila; o resto segue (já é o comportamento do coordenador) |
| Alarme com estados Novo, Em andamento, Em espera, Fechado. Reconhecer quer dizer "vou agir". Evento não é alarme | Milestone XProtect 2024R1, alarmes: https://doc.milestonesys.com/2024R1/en-US/feature_flags/ff_managealarms/sc_workingwithalarms.htm | Bloco "Pede você": só falha que espera decisão |
| Estado Online, Offline, Warning. Visão de problemas de saúde. Prioridade, o mais grave e mais novo primeiro | Genetec Security Center 5.14: https://techdocs.genetec.com/r/en-US/Security-Center-User-Guide-5.14/System-status-task-columns | Ordem do "Pede você"; chips de placa e internet |
| Contagem de saúde por estado | HikCentral: https://enpinfo.hikvision.com/hkwsen/unzip/20230830144955_12918_doc/GUID-0A6A7D5B-197E-4312-9ECA-19DC0BF01165.html | Legenda da fita com contagem por estado |
| Alarme só para o que pede ação do operador. Estado não é alarme. Reduzir alarme permanente. Cerca de 3 prioridades. Cada alarme tem uma resposta definida | HSE CHIS6: https://www.hse.gov.uk/pubns/chis6.pdf | Princípio 2; fim da barra vermelha permanente (`UX-01`) |
| Fundo neutro, cor seletiva só para o anormal, um significado por cor | ASM Consortium, artigo sobre fundos cinza (URL da Honeywell no relatório) | Princípio 2; tokens semânticos (4.2) |
| Pelo menos 2 de cor, forma e símbolo. 3:1. Três níveis de atenção. Nenhum indicador sem ação | Carbon, status indicator: https://carbondesignsystem.com/patterns/status-indicator-pattern/ ; Atlassian Lozenge; WCAG 1.4.1 | Estado sempre com ícone e palavra (5.3, 5.4) |
| Assistente para uso raro ou novato, caminho rápido para quem repete, estado salvo | NN/g, Wizards: https://www.nngroup.com/articles/wizards/ | Passo a passo só na primeira vez; volta pela Conferência (2.1) |
| Conferir respostas com "Alterar" por resposta | GOV.UK Design System, Check answers | Tela Conferir (3.1) |
| Diálogo de confirmação só para consequência séria, botões com verbo | NN/g, Confirmation dialogs: https://www.nngroup.com/articles/confirmation-dialog/ ; Carbon danger modal (título igual ao botão) | Diálogo próprio (5.8) |
| `confirm()` pode ser suprimido pelo navegador e devolver `false` sem aviso; prefira `<dialog>` | MDN, `Window.confirm()` | Diálogo próprio no lugar dos 10 `confirm()` (`UX-19`) |

Lido só em parte ou de segunda mão: Hikvision SADP (uma página só, manual não aberto: https://enpinfo.hikvision.com/unzip/20201102205526_84041_doc/GUID-E5BD58D7-364D-40DB-A6ED-4A176E9436CA.html), IEC 62682 (só o resumo), ISA-18.2 (via exida, secundária). Não confirmado e **não usado como base**: Dahua ConfigTool, UniFi Protect, Nx Witness, texto da ISA-101, Primer, Fluent.

Lacuna: nenhuma ferramenta de fabricante documenta um botão "tentar de novo" por item. O IP Utility repete as operações com falha em lote. O "Tentar de novo" por linha do painel já existe e fica, porque a falha de uma câmera depende de algo físico daquela câmera. O lote não ajuda a bancada.

Relatório completo do agente (fora do repo, só como rastro): `pesquisa-padroes.md` no scratchpad da sessão. O que dele vale está nesta seção.

## 1. Princípios

**P1. A falha mora onde a câmera mora, com o conserto ao lado.** A falha aparece na linha da posição, na fita e no bloco "Pede você", com o texto do conserto e o botão que conserta, sem ir a outra tela. Resolve `UX-02`, `UX-25`, `UX-26`, `UX-13`, `UX-29`, `UI-11`.

**P2. Cor só para o que é anormal; o normal é cinza.** Fundo neutro, um azul para ação, e vermelho e âmbar só quando há algo a fazer, com ícone e palavra junto. Estado normal (placa ainda não preparada antes de começar, simulação) não acende nada. Resolve `UX-01`, `UX-15`, `UI-01`, `UI-08`, `UI-09`, `UI-10`, `UI-13`.

**P3. Uma tela inteira para 16 câmeras.** Uma linha de 36 px por posição numa tabela que rola por dentro. O cabeçalho da fila e o "Pede você" ficam sempre à vista. Nada de cartão por câmera. Resolve `UX-22`, `UX-06`, `UX-24`, `UI-03`, `UI-06`.

**P4. Primeira vez guiada, segunda vez direta.** O passo a passo existe para a sessão nova. Com sessão salva, o painel abre na Conferência, que já confere a fila contra o registro e oferece a faixa seguinte. Navegação no topo, sempre à vista, inclusive Encerrar. Resolve `UX-16`, `UX-12`, `UX-20`, `UX-21`, `UX-36`, `UX-38`.

**P5. Uma palavra por coisa, um valor por token.** O mesmo nome para a mesma ação em todo o fluxo, todo texto em `textos.js`, todo valor visual em `tokens.css`, com um teste que guarda as duas regras. Resolve `UX-14`, `UX-39`, `UX-40`, `UX-09`, `UX-37`, `UI-04`, `UI-05`, `UI-07`, `UI-14`.

## 2. Arquitetura de informação e fluxo novos

### 2.1 Navegação

```
Topo fixo (56 px), em toda tela depois do passo a passo:
[símbolo] Configurar câmeras   Painel  Sessão  Ferramentas     (placa) (internet) (simulação)   [Encerrar o painel]
```

- **Menu lateral sai.** Ele ocupava 1257 px de altura, empurrava Opções para 1304 px (`UX-12`) e dava a Ferramentas o mesmo peso de Painel (`UX-38`). Três abas no topo cabem a 1366 px e ficam sempre à vista.
- **Opções passa a se chamar Sessão.** A tela edita a sessão (`CONTEXT.md`: Sessão); "Opções atrás da engrenagem" era nome de contêiner. O que não é da sessão (tema, versão, refazer o passo a passo) vai para o último bloco dela, "Painel" (`UX-36`). Decisão do usuário (Task 6): renome aprovado. A fase B (frente `redesenho-navegacao`) atualiza o `CONTEXT.md` e o `LEIA-ME.md`. Trade-off nomeado: quem já usa a 1.2 procura "Opções". Por isso a aba tem o texto escrito, sem ícone de engrenagem (`UI-16`).
- **Sessão é uma tela por seção**, não uma página de 2847 px: lista de seções à esquerda (Senha, Placa, Rede, Câmera, Fila, Painel) e a seção escolhida à direita, com rota própria (`#/sessao/camera`).
- **Encerrar o painel** fica no topo, como botão secundário: 2 cliques, 0 rolagem (`UX-12`).
- **Chips de placa, internet e simulação** substituem a barra colorida. São neutros no estado normal e acendem só quando pedem ação. O detalhe (IPs, faixas, ifIndex) abre num popover sob demanda, com as ações Preparar a placa e Restaurar o DHCP (`UX-01`, `UI-09`).
- **Log sai do Painel** e vai para Ferramentas (`UX-24`). O "Detalhe técnico" de uma falha leva ao trecho do log.
- **Rotas:** `#/inicio/<passo>`, `#/conferir`, `#/painel`, `#/painel/registro`, `#/sessao/<secao>`, `#/ferramentas`. Toda tela tem endereço, e o voltar do navegador funciona.

### 2.2 Passos

Seis passos no lugar de sete. Faixa de fábrica entra em Rede, recolhida por padrão, porque o IP de fábrica quase nunca muda.

1. **Senha.** Duas vezes, botão "Salvar a senha". Em simulação o passo diz "Senha não usada em simulação" e segue (`UX-07`).
2. **Placa.** A sugerida já vem marcada. Escolher a placa que leva à internet mostra uma nota na própria linha ("Esta placa leva o PC à internet; o painel vai pôr as faixas nela e devolver o DHCP ao encerrar"), sem `confirm()` (`UX-17`). Se a leitura falhar, aparece erro com "Ler as placas de novo" no lugar de "Lendo…" eterno (`UX-31`).
3. **Rede.** Máscara, gateway, DNS e IP do PC na rede definitiva. "Faixa de fábrica" fica num `<details>` com o resumo "IP de fábrica 192.168.1.108, IP do PC 192.168.1.220" e um "Alterar".
4. **Câmera.** E-mail de recuperação e encoder dos dois streams. Mostra um valor de bitrate só: o recomendado vem selecionado, e "Outro valor" abre o campo (`UX-18`). A explicação longa vira uma frase de uma linha acima do primeiro campo e um `<details>` "Por que isso importa" (`UI-12`).
5. **Fila.** Primeiro e último IP, local, rack, andar. A prévia diz quantas posições a faixa tem e **quantas já estão no registro**. Se a faixa toda já foi instalada, aparece "Usar a faixa seguinte (192.0.2.13 a 192.0.2.15)" (`UX-16`).
6. **Conferir.** Uma linha por seção, com "Alterar a placa", "Alterar a rede"… (GOV.UK). "Começar" fica num rodapé fixo, sempre à vista (`UX-20`).

**Com sessão salva**, o painel abre direto em **Conferir**, com a linha da senha no topo (real: campo de senha ali mesmo; simulação: "não usada"). A fila é conferida contra `/api/registro` no cliente: se todas as posições já estão instaladas, a linha da Fila diz isso e oferece "Usar a faixa seguinte". Isso some com o "Usar essa sessão / Revisar" do passo 1 e com o aviso cru do servidor (`UX-16`, `UX-27`).

**No Painel**, um começo só: o vigia. Com o vigia desligado, o estado vazio tem "Ligar o vigia" como primário e um link "Sem vigia: uma câmera por vez" para o modo sequencial (`UX-21`, `UX-03`). Montar outra fila abre a seção Fila num painel lateral, sem sair do Painel, e volta com "Fila montada: 3 posições, de 192.0.2.13 a 192.0.2.15" (`UX-11`).

### 2.3 Jornada dos 4 cenários, antes e depois

"Antes" vem da `linha-de-base.md`, medido em simulação a 1366×768. "Depois" é contado sobre os layouts da seção 3 e vai ser medido no protótipo (Task 5) e na fase B. Um clique de diálogo de confirmação conta como clique.

| Cenário | Telas antes | Telas depois | Cliques antes | Cliques depois | Campos antes / depois | Rolagens antes / depois |
|---|---|---|---|---|---|---|
| 1. Primeira abertura até a 1ª instalada (uso real) | 8 | 7 | 9 | 7 | 7 / 7 | 1 / 0 |
| 2a. Sessão salva, última fila já instalada, até 3 instaladas | 5 | 2 | 6 | 3 | 2 / 0 | 0 / 0 |
| 2b. Sessão salva com fila livre, até 3 instaladas | 3 | 2 | 3 | 2 | 0 / 0 | 0 / 0 |
| 3. Falha na câmera 2, "Tentar de novo" | 3 | 2 | 4 | 3 | 0 / 0 | 0 / 0 |
| 3'. Falha por valor recusado, mudar o encoder | 5 ou mais, estimado (Painel, Opções, Painel) | 2 (fica no Painel) | 7 ou mais, estimado | 5 | 1 / 1 | 2 ou mais / 0 |
| 4a. Encerrar a fila | 1 | 1 | 2 | 2 | 0 / 0 | 0 / 0 |
| 4b. Encerrar o painel | 2 | 2 | 3 | 2 | 0 / 0 | 2 / 0 |

Cliques depois, um por um:
- **1:** Salvar a senha, Avançar (placa), Avançar (rede), Avançar (câmera), Montar a fila, Começar, Ligar o vigia. Antes havia o `confirm()` da placa e o Câmera conectada como começo.
- **2a:** Usar a faixa seguinte, Começar, Ligar o vigia. Antes: Usar essa sessão, Começar, link do aviso, 2 campos, Montar fila, Painel no menu, Ligar vigia.
- **2b:** Começar, Ligar o vigia.
- **3:** Começar, Ligar o vigia, Tentar de novo.
- **3':** Começar, Ligar o vigia, Mudar o encoder (abre o painel lateral com a seção Câmera), escolher o valor, Salvar e tentar de novo. O "antes" é estimativa de leitura de código (`UX-25`): não foi medido na Task 1.
- **4a:** Encerrar a fila, Encerrar a fila (diálogo). Texto do fim: "Fila encerrada: 1 instalada, 2 sem câmera" (`UX-34`).
- **4b:** Encerrar o painel (topo), Encerrar o painel (diálogo).

Momentos de dúvida da linha de base que deixam de existir pelo desenho: cenário 1, os 6 (`UX-17`, `UX-18`, `UX-20`, `UX-06`, `UX-01`, `UX-21`); 2a, os 4 (`UX-16`, `UX-11`, `UX-33`); 2b, os 5 (`UX-07`, `UX-01`, `UX-03`, `UX-04`, campos sem posição); 3, os 5 (`UX-02`, `UX-40`, `UX-25`, `UX-26`, `UX-08`); 4, os 5 (`UX-34`, `UX-12`, `UX-35`). O protótipo conta de novo.

## 3. Layout por tela (1366×768)

Área útil no Edge a 1366×768: cerca de 1366×650. Largura de conteúdo: 1240 px máximo, margens de 24 px. As medidas em px aqui são do desenho. No código elas são tokens.

### 3.1 Passo a passo e Conferir

```
+------------------------------------------------------------------------------------------------+
| [logo SmartSeg 168x86]                                                  (simulação)             |
|                                                                                                |
|  Configurar câmeras                                                                            |
|  1 Senha  ✓   2 Placa  ✓   3 Rede  ✓   4 Câmera  ●   5 Fila   6 Conferir                       |
|  ----------------------------------------------------------------------------------------      |
|  Câmera                                                                                        |
|  E-mail de recuperação e encoder dos dois streams. Vale para todas as câmeras da sessão.       |
|                                                                                                |
|  E-mail de recuperação                                                                         |
|  [ tecnico@exemplo.example                    ]                                                |
|  Único jeito de recuperar a senha do admin.                                                    |
|                                                                                                |
|  Stream principal                       Stream secundário                                      |
|  Resolução [1080p      v]               Resolução [D1        v]                                |
|  Bitrate   [4096 (recomendado) v]       Bitrate   [512 (recomendado) v]                        |
|  FPS [15]   Codec [H.265 v]             FPS [15]   Codec [H.265 v]                             |
|  > Por que isso importa                                                                        |
|                                                                                                |
+------------------------------------------------------------------------------------------------+
| [Voltar]                                                                        [Avançar]      |  <- rodapé fixo
+------------------------------------------------------------------------------------------------+
```

- Coluna única de 720 px, alinhada à esquerda sob a logo. A trilha de passos usa número, palavra e ícone (✓ feito, ● atual): o estado não depende só da cor e o rótulo não quebra (`UI-10`).
- O rodapé fixo deixa Avançar e Começar sempre à vista (`UX-20`).

```
Conferir (sessão salva ou passo 6)
+------------------------------------------------------------------------------------------------+
| [logo SmartSeg 168x86]                                                  (simulação)             |
|  Conferir a sessão                                                                             |
|  Confira antes de começar. Cada linha abre a seção para alterar.                               |
|  +------------------------------------------------------------------------------------------+  |
|  | Senha     [••••••••]  [Salvar a senha]   (real)  /  Não usada em simulação  (simulação)   |  |
|  | Placa     Ethernet 2, cabo ligado                                      Alterar a placa    |  |
|  | Rede      192.0.2.0/24, gateway 192.0.2.1, PC em 192.0.2.250           Alterar a rede     |  |
|  | Câmera    H.265, 1080p 4096 kbps, D1 512 kbps, e-mail tecnico@...      Alterar a câmera   |  |
|  | Fila      ⚠ As 3 posições de 192.0.2.10 a 192.0.2.12 já estão no registro.               |  |
|  |           [Usar a faixa seguinte: 192.0.2.13 a 192.0.2.15]   Alterar a fila               |  |
|  +------------------------------------------------------------------------------------------+  |
+------------------------------------------------------------------------------------------------+
|                                               Prepara a placa e abre o Painel.   [Começar]     |
+------------------------------------------------------------------------------------------------+
```

### 3.2 Painel com N câmeras (16 posições, vigia ligado)

```
+------------------------------------------------------------------------------------------------+
| [S] Configurar câmeras   Painel  Sessão  Ferramentas    (✓ Placa pronta) (✓ Internet) [Encerrar o painel]
+------------------------------------------------------------------------------------------------+
| Fila Obra exemplo, rack 2, 2º andar                          (● Vigia ligado)  [Desligar o vigia]|
| 192.0.2.10 a 192.0.2.25                                  [Montar outra fila] [Encerrar a fila]   |
| [■][■][■][■][■][■][■][▣][!][▣][▣][┆][ ][ ][ ][ ]                                               |
|  10  11  12  13  14  15  16  17  18  19  20  21  22  23  24  25                                 |
|  ■ 7 instaladas   ! 1 pede você   ▣ 3 em curso   ┆ próxima   □ 5 aguardando                     |
+------------------------------------------------------------------------------------------------+
| Pede você (1)                                                                                  |
| ! Câmera 9 (192.0.2.18) falhou no encoder: a câmera recusou o bitrate 4096.                    |
|   Mude o bitrate do stream principal e tente de novo.                                          |
|   [Mudar o encoder]  [Tentar de novo]  Pular esta posição          > Detalhe técnico          |
+------------------------------------------------------------------------------------------------+
| (Fila agora | Registro)                                                                        |
| Pos.  Estado                    IP de destino   Modelo        Serial   MAC                Porta Canal
| 1     ✓ Instalada               192.0.2.10      VIP 3230 B    SIM-1    AA:00:00:00:00:01  [3 ] [1 ]
| ...                                                                                            |
| 8     ▣ 2 de 4: encoder ▰▰▱▱    192.0.2.17      VIP 3230 B    SIM-8    AA:00:00:00:00:08  [10] [8 ]
| 9     ! Falhou no encoder       192.0.2.18      VIP 3230 B    SIM-9    AA:00:00:00:00:09  [11] [9 ]
| 10    ▣ 4 de 4: conferindo      192.0.2.19      ...                                            |
| 12    ┆ Próxima                 192.0.2.21                                                      |
| 13    Aguardando                192.0.2.22                                                      |
|   (rola por dentro; cabeçalho fixo)                                                            |
| Na espera do portão (1)                                                                        |
| -     ◷ Na espera               -               VIP 3230 B    SIM-17   AA:00:00:00:00:11       |
+------------------------------------------------------------------------------------------------+
```

- Alturas: topo 56, cabeçalho da fila com fita e legenda 128, "Pede você" com uma falha 104, tabela com o resto (cerca de 9 linhas de 36 px visíveis a 650 px; sem falha, cerca de 12). Antes: 16 câmeras eram cerca de 5 telas de cartões (`UX-22`).
- A tabela é a fonte acessível do estado: a fita tem `aria-hidden` e uma frase resumida para leitor de tela.
- A etapa mostrada é a etapa real do servidor ("2 de 4: encoder") e o texto da linha descreve a mesma etapa (`UX-04`).
- Porta e Canal só aparecem quando a câmera tem posição (`UX-03`, momento 2b.5).
- Botões de decisão só existem no DOM das linhas em falha (`UX-13`).
- "Vigia ligado" usa o token "agora" (azul-500) com o ícone de ponto, sem pulso (`UI-15`).
- Broadcast: a caixa sai da área do vigia e vai para Sessão > Rede, como "Aceitar câmera de fábrica de qualquer faixa", com o risco escrito embaixo dela, sem `title`. Ligada, o cabeçalho da fila mostra o chip de atenção "Qualquer faixa" (`UX-10`, `UI-11`).

### 3.3 Decisão (falha aberta) e painel lateral do encoder

```
+-------------------------------------------------------------+----------------------------------+
| (Painel como em 3.2, com conteúdo inerte atrás)             | Mudar o encoder da câmera 9      |
|                                                             | O novo valor vale para a sessão  |
|                                                             | inteira, não só para esta câmera.|
|                                                             |                                  |
|                                                             | Stream principal                 |
|                                                             | Bitrate [2048 v]                 |
|                                                             | ...                              |
|                                                             |                                  |
|                                                             | [Cancelar] [Salvar e tentar de novo]
+-------------------------------------------------------------+----------------------------------+
```

- O painel lateral reusa o formulário de Câmera de `formularios.js` (uma definição só, `UX-37`). Ele diz que muda a sessão, porque o encoder é um padrão global da sessão (`CONTEXT.md`: Sessão).
- "Pular esta posição" abre o diálogo: título "Pular a câmera 9?", texto "A posição 192.0.2.18 fica registrada como falha e a fila segue para a próxima.", botões "Pular a câmera 9" e "Cancelar" (`UX-39`, `UX-19`).
- Falha por senha recusada: "Tentar de novo" fica desabilitado com o motivo visível embaixo ("Repetir a senha recusada bloqueia o admin. Troque a senha em Sessão > Senha."). O motivo não fica só num `title` (`UI-14`, `UI-11`).
- Foco: ao surgir uma falha, o foco **não** salta sozinho (o operador pode estar digitando porta e canal). Um anúncio `aria-live` avisa, e um atalho "Ir para o que pede você" fica no topo do Painel. Muda o `focarDecisao` atual, que roubava o foco. Decisão do usuário (Task 6): aprovado. A falha se anuncia pelo `aria-live`, na linha da câmera e no bloco "Pede você", sem mover o foco.

### 3.4 Ferramentas

```
+------------------------------------------------------------------------------------------------+
| [S] Configurar câmeras   Painel  Sessão  Ferramentas   ...                                     |
+------------------------------------------------------------------------------------------------+
| Ferramentas                                                                                    |
| Para diagnóstico. Nenhuma delas altera câmera.                                                 |
|                                                                                                |
| Sondar um IP            [192.0.2.18      ] [Sondar o IP]                                       |
| Verificar o registro    Faz login em cada câmera instalada e confere IP e MAC. [Verificar o registro]
| Procurar câmeras        Só no uso real.                                   [Procurar câmeras]   |
| Testar a internet       Ethernet 2 e Wi-Fi.                               [Testar a internet]  |
|                                                                                                |
| Resultado                                                                                      |
| +--------------------------------------------------------------------------------------------+ |
| | (tabela ou texto do último resultado; erro com o conserto)                                 | |
| +--------------------------------------------------------------------------------------------+ |
| > Log do painel (fechado por padrão; linhas em mono, filtro "só avisos e erros")               |
+------------------------------------------------------------------------------------------------+
```

### 3.5 Sessão (antes "Opções")

```
+------------------------------------------------------------------------------------------------+
| [S] Configurar câmeras   Painel  Sessão  Ferramentas   ...                                     |
+------------------------------------------------------------------------------------------------+
| Sessão                      | Câmera                                                           |
|  Senha                      | E-mail de recuperação e encoder dos dois streams.                |
|  Placa                      | (mesmo formulário do passo 4)                                    |
|  Rede                       |                                                                  |
| >Câmera                     |                                                                  |
|  Fila                       |                                                                  |
|  ------                     |                                                                  |
|  Painel                     |                                    [Salvar alterações]           |
+------------------------------------------------------------------------------------------------+
Seção Painel: Tema (Sistema, Claro, Escuro), Versão 1.x.y com "Procurar atualização", "Refazer o passo a passo"
e o bloco "Sobre" com a logo inteira. "Encerrar o painel" está no topo e não se repete aqui.
```

- Uma seção por vez, nada de rolagem longa. "Salvar alterações" tem o mesmo nome em toda seção e confirma com "Alterações salvas", junto do botão e no `aria-live` (`UX-14`, `UI-19`).
- Erro de campo embaixo do campo, ao salvar, com `aria-invalid` e `aria-describedby` (system.md, formulários).

### 3.6 Estados vazio, carregando e erro

```
Abrindo (até o 1º /api/estado)          Vigia desligado, sem câmera             Vigia ligado, sem câmera
+---------------------------+           +-------------------------------+       +---------------------------------+
| [logo]                    |           | Ligue o vigia para configurar |       | Esperando câmeras de fábrica    |
| Abrindo o painel…         |           | cada câmera de fábrica que    |       | Observando 192.168.1.108 desde  |
| (topo já com a altura     |           | aparecer no switch.           |       | 14:02. A primeira costuma levar |
|  final: sem salto, UI-06) |           | [Ligar o vigia]               |       | cerca de 1 minuto depois de     |
+---------------------------+           | Sem vigia: uma câmera por vez |       | ligada.                         |
                                        +-------------------------------+       +---------------------------------+

Sem fila                                 Modo de reserva (atenção)
+-------------------------------+        +---------------------------------------------------------------+
| Nenhuma fila montada.         |        | ⚠ O broadcast não respondeu: o vigia está no modo de reserva. |
| [Montar a fila]               |        | Ligue uma câmera de fábrica por vez no switch. Para voltar ao |
+-------------------------------+        | modo normal, libere a porta UDP 37810 no firewall do Windows. |
                                         +---------------------------------------------------------------+

Conexão perdida (alarme, depois de 3 consultas sem resposta)
+------------------------------------------------------------------------------------------------+
| ✕ O painel parou de responder. Veja se a janela do servidor ainda está aberta e recarregue.    |
|   [Recarregar a página]                                     Última resposta às 14:07:31         |
+------------------------------------------------------------------------------------------------+
(o resto da tela fica inerte: atributo inert, nada clicável que não vá funcionar)

Encerrado                                 Fila encerrada
+-------------------------------+         +--------------------------------------------------+
| [logo]                        |         | Fila encerrada: 1 instalada, 2 sem câmera.       |
| Painel encerrado.             |         | O vigia foi desligado.  [Montar outra fila]       |
| Pode fechar esta janela.      |         +--------------------------------------------------+
| (consultas paradas: UX-35)    |
+-------------------------------+
```

- Registro: "Lendo o registro…" enquanto busca. Em erro, a tabela antiga sai e vem "Não deu para ler o registro. [Ler de novo]" (`UX-32`). Colunas com largura mínima e `white-space: nowrap` em IP, MAC e serial (`UX-33`).
- Faixa de atualização: faixa informativa (azul neutro) sob o topo, "Versão 1.x.y disponível. [Atualizar o painel]". O botão abre diálogo que diz que o painel fecha e reabre.

## 4. Sistema visual

### 4.1 Tokens primitivos da marca

| Token | Valor | Papel |
|---|---|---|
| `--marca-azul-700` | `#407A94` | Preenchimento do botão primário. Cor da marca |
| `--marca-azul-500` | `#5489A1` | "Agora": em curso, vigia ligado, progresso |
| `--marca-grafite` | `#565758` | Texto de apoio no tema claro |
| `--marca-cinza` | `#848688` | Ícone neutro no tema escuro (4.69 sobre `#191C1E`, Task 3); no claro, só decorativo (3.65 sobre branco) |

Derivados (fora da paleta oficial, escolhidos para contraste e documentados): `--azul-800` `#35687F` (hover do primário), `--azul-link` `#2F6A83` (link e foco no claro), `--azul-claro` `#7FB2C9` (link e foco no escuro).

O âmbar sai da marca do painel. Ele existe só como token semântico de atenção (`UI-01`, `UX-15`).

### 4.2 Tokens semânticos, nos dois temas, com contraste (WCAG 2.x)

Contrastes medidos com a fórmula de luminância relativa do WCAG. Texto pede 4.5:1. Componente e ícone pedem 3:1.

| Token | Claro | Contraste (claro) | Escuro | Contraste (escuro) |
|---|---|---|---|---|
| `--fundo` | `#EEF0F1` | n/a | `#17191B` | n/a |
| `--superficie` | `#FFFFFF` | n/a | `#212427` | n/a |
| `--superficie-2` (cabeçalho de tabela, chip) | `#F6F7F8` | n/a | `#2A2E31` | n/a |
| `--linha` (divisória, decorativa) | `#D5D9DC` | 1.42 sobre branco (decorativa, isenta) | `#3A3F43` | decorativa |
| `--linha-forte` (borda de campo, só sobre superfície) | `#8A9096` | 3.23 branco, 3.01 sup-2 | `#7A8187` | 3.95 sup, 3.47 sup-2 |
| `--texto` | `#232526` | 15.39 branco, 13.47 fundo | `#E6E8EA` | 14.35 sup, 12.70 fundo, 11.15 sup-2 |
| `--apoio` | `#565758` (grafite da marca) | 7.24 branco, 6.33 fundo, 6.75 sup-2 | `#A7ABAE` | 7.62 fundo, 6.74 sup, 5.92 sup-2 |
| `--acao` (fundo do primário) | `#407A94` | rótulo branco 4.74; 3.61 contra o fundo | `#407A94` | rótulo branco 4.74; 3.29 contra sup |
| `--acao-hover` | `#35687F` | rótulo branco 6.11 | `#35687F` | rótulo branco 6.11 |
| `--acao-texto` (link, aba ativa, botão secundário) | `#2F6A83` | 5.98 branco, 5.23 fundo, 5.58 sup-2 | `#7FB2C9` | 6.77 sup, 7.65 fundo, 5.94 sup-2 |
| `--foco` (anel de 2 px) | `#2F6A83` | 5.98 branco, 5.23 fundo | `#7FB2C9` | 6.77 sup, 7.65 fundo |
| `--acao-fraco` (linha selecionada) | `#E3EEF3` | texto 13.04, apoio 6.13, acao-texto 5.07 | `#1F3440` | texto 10.53, apoio 5.59, acao-texto 5.61 |
| `--agora` (em curso, vigia ligado) | `#5489A1` | 3.84 branco, 3.58 sup-2, 3.36 fundo (só ícone e preenchimento) | `#5489A1` | 4.06 sup, 4.59 fundo |
| `--sucesso` | `#1E7A46` | 5.35 branco, 4.68 fundo, 4.98 sup-2 | `#5CC08A` | 6.95 sup, 7.86 fundo, 6.10 sup-2 |
| `--falha` (texto e ícone) | `#B42318` | 6.57 branco, 5.75 sobre falha-fundo | `#FF8A80` | 6.83 sup, 6.60 sobre falha-fundo |
| `--falha-fundo` | `#FDECEA` | texto 13.46, apoio 6.33 | `#3A1F1D` | texto 12.27, apoio 6.51 |
| `--perigo` (fundo do botão destrutivo no diálogo) | `#B42318` | rótulo branco 6.57 | `#B42318` | rótulo branco 6.57 (2.37 contra sup: o rótulo identifica o botão) |
| `--atencao` (texto e ícone) | `#8A5A00` | 5.93 branco, 5.42 sobre atencao-fundo, 5.18 fundo | `#F2C063` | 9.28 sup, 8.53 sobre atencao-fundo |
| `--atencao-fundo` | `#FFF4DB` | texto 14.09, apoio 6.63 | `#33290F` | texto 11.67, apoio 6.20 |

Regras de uso:
- **Um significado por cor.** Azul-700 é ação. Azul-500 é "agora". Verde é concluído. Vermelho é falha que pede você. Âmbar é atenção: o operador precisa saber, mas nada quebrou. Cinza é todo o resto, inclusive simulação, "aguardando" e "pulada".
- O primário fica só sobre `--superficie` ou `--fundo`. Sobre `--superficie-2` no escuro ele tem 2.89 e não passa no 3:1.
- Estado nunca só por cor: sempre ícone mais palavra (Carbon, WCAG 1.4.1).
- A faixa de simulação vira chip neutro "Simulação" com ícone, no topo (`UI-08`). A falha forçada aparece no popover do chip e na linha da câmera (`UX-08`).

### 4.3 Tipo

- **Família:** `"Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif`. Mono: `"Cascadia Mono", Consolas, monospace`, só para IP, MAC, serial e log (`UI-07`). Por quê: o painel roda no Windows do técnico. A fonte do sistema não pede download nem regra extra de CSP, não pesa no instalador e já tem números tabulares (`font-variant-numeric: tabular-nums` na tabela e na fita).
- **Escala** (px, razão perto de 1,2 a partir de 14): `--tipo-meta` 13, `--tipo-corpo` 14, `--tipo-leitura` 15, `--tipo-subtitulo` 17, `--tipo-titulo` 21, `--tipo-numero` 28. O piso de 13 vale para 1366×768 (decisão do plano). No lugar de 11 tamanhos, 6 (`UI-04`).
- **Peso:** 400 e 600. Rótulo de campo em 13 com peso 600, nunca caixa alta (system.md, formulários).
- **Entrelinha:** `--entrelinha-corpo` 1.45, `--entrelinha-titulo` 1.25. Medida de texto: no máximo 72 caracteres.

### 4.4 Espaço, raio, sombra, movimento

- **Espaço** (base 4): `--esp-1` 4, `--esp-2` 8, `--esp-3` 12, `--esp-4` 16, `--esp-5` 24, `--esp-6` 32, `--esp-7` 48. O resto é derivado com `calc()` de token. Nenhum literal (`UI-05`).
- **Raio por nível:** `--raio-controle` 6 (botão, campo, chip retangular, casa da fita), `--raio-bloco` 10 (bloco, painel lateral, diálogo), `--raio-selo` 999 (chip e selo).
- **Sombra:** só no que flutua. `--sombra-sobreposta` em diálogo, popover e painel lateral. Bloco no chão não tem sombra: a hierarquia sai de tipo, espaço e um fundo de diferença (`UI-03`).
- **Movimento:** `--dur-rapida` 90 ms (hover, press), `--dur-media` 150 ms (popover, chip), `--dur-lenta` 240 ms (painel lateral, diálogo), uma curva `--curva` `cubic-bezier(.2,0,0,1)`. Sem pulso nem loop (`UI-15`). Com `prefers-reduced-motion: reduce`, todas as durações vão a 0 pelos tokens.
- **Medidas fixas de layout** (tokens também): `--topo-altura` 56, `--linha-tabela` 36, `--fita-altura` 28, `--conteudo-max` 1240, `--coluna-form` 720, `--lateral-largura` 440, `--logo-largura` 168, `--simbolo-altura` 28, `--traco` 1 (linha fina), `--foco-espessura` 2.
- **Quebras** (`@media`): `--bp-estreito` 1100 e `--bp-largo` 1600, declaradas num comentário de `tokens.css` que o teste lê (seção 7.4), porque `@media` não aceita `var()`.

### 4.5 Ícones

Um conjunto só, em traço de 1,5 px a 16 e 20 px, montado como SVG por `icones.js` a partir dos caminhos do Lucide (licença ISC, aviso no cabeçalho do arquivo). Ícones: concluído, falha, atenção, informação, espera, agora (ponto), placa, internet, simulação, fechar, abrir/recolher, mais ações. Sem glifo de texto como ícone (`UI-16`).

### 4.6 Logo

- **Onde:** a logo inteira (`logo.png`) aparece no passo a passo e na Conferência (alto à esquerda, 168 px de largura, cerca de 86 px de altura, acima do piso de 160 px da Task 3), na tela Abrindo, na tela Encerrado e no bloco "Sobre" de Sessão > Painel. No topo fixo vai só o **símbolo** (os dois paralelogramos azuis), recortado do PNG oficial, a 28 px de altura, ao lado do texto "Configurar câmeras".
- **Trade-off nomeado:** a logo inteira no topo, a 160 px de largura, pede 82 px de altura: 26 px a mais em toda tela de trabalho, cerca de uma linha de tabela a menos. O símbolo no topo mantém a marca à vista sem esse custo.
- **Tema escuro:** a logo oficial sobre uma placa clara (`--superficie` do claro, `--raio-bloco`, `--esp-3` de respiro), sem alterar a arte. Decisão do usuário (Task 6): é a solução definitiva. A variante derivada da Task 3 (`marca/logo-smartseg-escuro.png`, grafite trocado por claro) fica só como registro da auditoria e **não** entra na fase B nem no `www`.
- **Favicon:** `simbolo.png` (recorte 64×64 do símbolo, fundo transparente) via `<link rel="icon" type="image/png" href="/simbolo.png">`. A rota `GET /favicon.ico` que devolve 204 fica como está.
- **Arquivos servidos:** derivados do PNG de 2302 px por redução (nada redesenhado, conforme a decisão do usuário): `logo.png` a 336 px de largura (2× de 168) e `simbolo.png` a 64 px. Sem SVG da marca: redesenhar o símbolo em vetor criaria uma arte não oficial.

## 5. Componentes

Cada componente usa só tokens semânticos. Estados: repouso, hover, foco, pressionado, desabilitado, e os específicos de cada um.

### 5.1 Botão

| Tipo | Repouso | Hover / pressionado | Foco | Desabilitado | Ocupado |
|---|---|---|---|---|---|
| Primário (1 por área) | fundo `--acao`, rótulo branco 600 | `--acao-hover`, pressionado desce 1 px | anel 2 px `--foco`, deslocado 2 px | fundo `--superficie-2`, texto `--apoio`, motivo visível embaixo (não só `title`) | rótulo vira "Salvando…" com o mesmo verbo, largura fixa, `aria-busy` |
| Secundário | contorno `--linha-forte`, texto `--acao-texto` | fundo `--acao-fraco` | igual | igual ao primário | igual |
| Discreto (link de ação) | texto `--acao-texto`, sublinhado no hover | sublinhado | anel | `--apoio` | n/a |
| Destrutivo (só no diálogo) | fundo `--perigo`, rótulo branco | escurece por `color-mix` de token | anel | n/a | igual |

Uma só cara para desabilitado (`UI-14`). Rótulo sempre verbo mais objeto (seção 6).

### 5.2 Campo

Rótulo visível acima (13, 600), campo com borda `--linha-forte` sobre `--superficie`, ajuda em `--apoio` embaixo. Estados: foco (anel `--foco`), erro (borda e mensagem em `--falha` com ícone, `aria-invalid`, `aria-describedby`, a mensagem diz o conserto), desabilitado, somente leitura. Placeholder só como exemplo de formato, nunca como rótulo, sempre "ex.: 192.0.2.10" (`UI-18`). IP, MAC e serial em mono.

### 5.3 Linha da câmera (substitui o cartão da câmera)

O "cartão da câmera" do `CONTEXT.md` vira **linha da câmera**: o mesmo conceito, na tabela.

| Estado (`CONTEXT.md`) | Ícone | Palavra | Cor | Ações na linha |
|---|---|---|---|---|
| Na espera | espera | Na espera | `--apoio` | nenhuma (grupo "Na espera do portão") |
| No portão | agora | "1 de 4: senha" … "3 de 4: rede", mini barra de 4 | `--agora` | nenhuma |
| Conferindo | agora | "4 de 4: conferindo" | `--agora` | nenhuma |
| Falhou | falha | "Falhou no encoder" | `--falha`, fundo `--falha-fundo` na linha | as da seção 3.3, também no "Pede você" |
| Instalada | concluído | Instalada | `--sucesso` (só o ícone; texto `--texto`) | Porta e Canal editáveis |
| Pulada | traço | Pulada | `--apoio` | nenhuma |
| Já inicializada: não tocada | informação | Já inicializada, não tocada | `--atencao` | "Retomar esta câmera" (abre o fluxo de retomada) |

Hover da linha: `--superficie-2`. Linha recém-instalada: fundo `--acao-fraco` por 1 ciclo de consulta, sem animação. Sem estado que só mude a cor.

### 5.4 Tabela

Cabeçalho fixo em `--superficie-2`, linhas de `--linha-tabela`, divisória `--linha`, números tabulares, colunas de máquina em mono e `nowrap` (`UX-33`). Estados: carregando ("Lendo o registro…" na própria área), vazia (convite à ação), erro (mensagem com o conserto e "Ler de novo", sem dado velho). A mesma tabela serve à Fila agora e ao Registro. O Registro troca as colunas Porta/Canal editáveis por "Rack / porta" e "Canal" em texto (`UX-14`).

### 5.5 Fita

Uma casa por posição, largura igual, altura `--fita-altura`, números da posição embaixo (até 24 casas; acima disso, número a cada 5).

| Estado | Desenho |
|---|---|
| Instalada | preenchida em `--apoio` |
| Em curso | contorno `--agora`, preenchida até a fração da etapa (1/4 … 4/4) |
| Falhou | preenchida em `--falha`, com "!" branco, 4 px mais alta que as outras (forma, além da cor) |
| Próxima | contorno tracejado `--acao-texto` |
| Aguardando | só contorno `--linha-forte` |
| Pulada | contorno `--linha` com um traço no meio |

Legenda embaixo com ícone e contagem por estado ("7 instaladas", "1 pede você"), plural certo (`UX-40`). A falha nunca some da fita nem da contagem (`UX-02`). Clicar numa casa rola a tabela até a linha.

### 5.6 Aviso (resposta a uma ação)

Aparece **junto do controle que o gerou**: embaixo do formulário ou do botão, nunca num aviso global sem origem (`UX-27`). Tipos: sucesso (ícone e `--sucesso`, some quando o operador age de novo), erro (fica até ser resolvido ou fechado, diz o conserto), atenção. Tudo também em `aria-live="polite"`, erro em `assertive`. Nada some sozinho em 4 s (`UI-19`, `UX-27`).

### 5.7 Faixa (estado do painel inteiro)

Logo abaixo do topo, largura total, uma de cada vez por prioridade: conexão perdida (alarme, `--falha-fundo`), modo de reserva (atenção), atualização disponível (informação, `--superficie-2`). Toda faixa tem uma ação ou uma instrução: faixa sem ação não existe (CHIS6, Carbon). A simulação não é faixa: é chip.

### 5.8 Diálogo de confirmação

`<dialog>` nativo com `showModal()` (aceito pela CSP: sem estilo nem script inline). Título é a pergunta com o verbo do botão ("Encerrar o painel?"), uma frase com a consequência, botão de confirmação com o mesmo verbo ("Encerrar o painel") e "Cancelar". Foco inicial em Cancelar quando a ação é destrutiva. Esc cancela. Por quê: o navegador pode suprimir `confirm()` e devolver `false` em silêncio (MDN), e os 10 `confirm()` de hoje têm texto genérico ou cru (`UX-19`). Ficam 7 confirmações: pular, trocar a fila, encerrar a fila, restaurar o DHCP, refazer o passo a passo, atualizar o painel, encerrar o painel. Saem a da placa (vira nota inline, 2.2) e a do erro ao salvar (vira erro no formulário, 5.2). O pular legado cai junto com a decisão legada.

### 5.9 Chip de estado (topo) e popover

Chip com ícone e uma palavra: "Placa", "Placa pronta", "Placa sem cabo", "Internet", "Sem internet", "Simulação". Neutro (`--superficie-2`, `--apoio`) no normal; `--falha` só quando pede ação. A regra da placa vem de `estado.rede`:

- simulação, ou sessão não concluída: neutro;
- `preparada` e `ok`: "Placa pronta" com ícone de concluído;
- sessão concluída, fora da simulação, e `ok` falso, ou `presente` falso, ou `cabo` falso: alarme, com a frase e o botão no popover ("Preparar a placa", "Ligue o cabo na Ethernet 2").

Popover: lista os IPs e faixas em mono, as ações Preparar a placa e Restaurar o DHCP, e o ifIndex só em "Detalhe técnico" (`UX-09`).

## 6. Escrita

Regras (seção de escrita da `frontend-design` e `auditoria-ux.md`):
1. **Botão é verbo mais objeto**, e a mesma ação tem o mesmo nome em todo o fluxo e na confirmação ("Montar a fila", e a confirmação diz "Fila montada").
2. **Erro diz o que houve e o conserto**, na voz do painel, sem pedir desculpa. O texto cru do servidor vai para "Detalhe técnico", em mono.
3. **Vazio convida a agir**, com o botão que resolve ali mesmo.
4. **Caixa de frase, pt-BR com acento, plural certo** ("1 instalada", "2 instaladas"; nunca "instalada(s)").
5. **Nome do operador, não do código:** nada de "ifIndex", "DHIP", "broadcast" ou "fase" na tela principal. Quando o termo é do `CONTEXT.md` e precisa aparecer (portão, vigia, faixa), ele vem explicado uma vez, no lugar em que surge.
6. **Texto do servidor sem acento não chega cru.** `textos.js` traduz as mensagens conhecidas (por código ou padrão) para frases do painel; a desconhecida aparece como "O painel recusou a ação." com o original em "Detalhe técnico" (`UX-40`, `UX-27`). As mensagens do servidor e do motor não mudam nesta frente (seção 8).

Glossário de rótulos (coerente com `CONTEXT.md`):

| Conceito (`CONTEXT.md`) | Rótulo na tela | Substitui |
|---|---|---|
| Senha | "Salvar a senha"; "Trocar a senha" (Sessão) | "Usar esta senha", "Usar esta senha e avançar" |
| Passo a passo | "Avançar", "Voltar", "Começar" | "Montar a fila e avançar", "Preparar placa e começar" |
| Sessão | aba "Sessão"; "Salvar alterações"; confirma "Alterações salvas" | "Opções", "Salvar placa/rede/faixa/câmera" |
| Fila | "Montar a fila", "Montar outra fila", "Encerrar a fila", "Usar a faixa seguinte" | "Montar fila", "Montar depois", "Montar a fila ao começar" |
| Posição | "Câmera 9" e, quando preciso, "posição 192.0.2.18" | "Sem posição" (vira "Na espera") |
| Vigia | "Ligar o vigia", "Desligar o vigia", "Vigia ligado" | "Ligar vigia" |
| Modo sequencial | "Configurar a câmera 3" (com "Ligue a câmera 3 no switch") | "Câmera conectada" |
| Decisão | "Tentar de novo", "Mudar o encoder", "Pular esta posição" (diálogo "Pular a câmera 9") | "Pular esta posição" sem consequência |
| Registro | aba interna "Registro"; "Ler o registro de novo"; "Exportar o relatório" | "Atualizar registro" |
| Placa escolhida | "Placa", "Preparar a placa", "Restaurar o DHCP", "Ler as placas de novo" | "Atualizar lista" |
| Atualização | "Atualizar o painel" (só para versão nova) | os três "Atualizar" |
| Porta e canal | "Porta do switch" e "Canal no NVR" no cabeçalho da tabela; "Porta" e "Canal" quando o espaço é curto, com o nome inteiro no cabeçalho | "Rack / porta" sem canal |
| Retomada | "Retomar esta câmera" | "Retomar" no `details` |
| Simulação | chip "Simulação"; "Senha não usada em simulação" | "Senha definida." em simulação |
| Encerrar | "Encerrar o painel"; tela "Painel encerrado. Pode fechar esta janela." | igual |

## 7. Arquitetura do front

Regra-mãe: **nenhum valor local solto.** Cor, tamanho, espaço, raio, sombra, duração e quebra vêm de `tokens.css`. Texto de UI vem de `textos.js`. Número com sentido (intervalo de consulta, trava de decisão, código HTTP) vem de `constantes.js`. Tudo continua em HTML, CSS e JS puros, sem build, servido pelo `HttpListener` com a CSP atual.

### 7.1 CSS

| Arquivo | Camada | Conteúdo |
|---|---|---|
| `tokens.css` | `tokens` | Primeira linha: `@layer tokens, base, componentes, telas;`. Primitivos da marca, semânticos com `light-dark()`, `[data-tema=claro]` e `[data-tema=escuro]` (o servidor já injeta `data-tema`), escalas, medidas, comentário das quebras, `prefers-reduced-motion` zerando as durações |
| `base.css` | `base` | Reset curto, `html`/`body`, tipo, links, foco visível global (`:focus-visible`), `.visualmente-oculto` |
| `componentes.css` | `componentes` | Botão, campo, chip, popover, aviso, faixa, diálogo, painel lateral, tabela, fita, trilha de passos |
| `telas.css` | `telas` | Grade de cada tela (topo, início, conferir, painel, sessão, ferramentas, fim). Só layout, sem cor nova |

Quatro `<link rel="stylesheet">` no `index.html`, nesta ordem. As camadas resolvem a cascata, então não há disputa de especificidade entre componente e tela (cuidado pedido pela `frontend-design`). Seletor só por classe e atributo: **sem seletor de id no CSS** (isso também deixa a regra do hex do teste sem ambiguidade). Divisão em 4 e não em 1: `tokens.css` precisa ser um arquivo só para o teste dizer "fora daqui não"; telas e componentes separados dão localidade para a fase B mexer numa tela sem tocar componente.

### 7.2 JS (ES modules)

`<script type="module" src="/app.js">` no lugar de `<script src="/app.js" defer>`. Módulos planos em `www/`, porque o servidor só serve a pasta sem subpastas (seção 7.3).

| Módulo | Interface | Responsabilidade |
|---|---|---|
| `app.js` | nenhuma (ponto de entrada) | Liga api, estado, rotas e telas; ciclo de consulta |
| `api.js` | `criarApi(transporte) -> { estado(), comando(rota, corpo), registro(), ... }` | Único módulo que faz `fetch`. Normaliza erro em `{ ok, codigo, mensagem, detalhe }` |
| `estado.js` | `derivar(bruto, registro) -> modelo`; `assinar(fn)` | **Módulo profundo**: contagens, posição da falha, etapa real, estado da placa, vigia, modo de reserva, conexão perdida, conflito da fila com o registro. Função pura |
| `rotas.js` | `iniciar(telas)`; `ir(rota)` | Rotas por hash da seção 2.1, foco no título da tela ao trocar |
| `textos.js` | `t(chave, dados)`; `traduzirServidor(msg)` | Toda string de UI, plurais (`Intl.PluralRules`), tradução das mensagens conhecidas do servidor |
| `formato.js` | `ip()`, `mac()`, `hora()`, `bitrate()` | Formatação com `Intl` |
| `constantes.js` | exportações nomeadas | `ETAPAS`, `CONSULTA_MS`, `FALHAS_ATE_PERDER_CONEXAO`, `TRAVA_DECISAO_MS`, códigos HTTP com nome |
| `dom.js` | `h(tag, atributos, filhos)`, `$()`, `focar()` | Criação de nó sem `innerHTML` com dado do servidor |
| `icones.js` | `icone(nome)` | Os SVG da seção 4.5 |
| `componentes.js` | `botao()`, `chip()`, `aviso()`, `confirmar(opcoes) -> Promise<boolean>`, `campo()`, `linhaCamera()` | Componentes da seção 5 |
| `formularios.js` | `FORMULARIOS.senha/placa/rede/camera/fila`; `montarFormulario(def, valores)` | Uma definição por seção da sessão, usada no passo a passo, em Sessão e no painel lateral (`UX-37`) |
| `tela-inicio.js` | `montar(raiz, ctx)`, `desenhar(modelo)` | Passo a passo e Conferir |
| `tela-painel.js` | igual | Painel, decisão, registro |
| `tela-sessao.js` | igual | Sessão |
| `tela-ferramentas.js` | igual | Ferramentas e log |
| `topo.js` | `criarTopo(ctx)` | Topo fixo: símbolo, abas, chips com popover, Encerrar o painel. Veio do protótipo (Task 5) |
| `marca.js` | `logo()`, `simbolo()` | As duas imagens da marca, com o texto alternativo de `textos.js`. Veio do protótipo (Task 5) |

Costuras e regras:
- **Telas não fazem `fetch` e não leem o estado bruto.** Recebem o `modelo` de `estado.derivar` e um `ctx` com `api`, `rotas`, `confirmar`. O teste da deleção: apagar `estado.js` espalharia contagem, etapa e regra da placa pelas 4 telas, que é exatamente o defeito de hoje (`UX-02`, `UX-04`). O módulo paga o próprio peso.
- **`api.js` é costura real, com dois adaptadores:** o transporte `fetch` do produto e o falso do protótipo (`docs/design/2026-11-ux/prototipo/api-falsa.js`, Task 5), que reproduz os cenários sem servidor. Fora isso não se cria costura hipotética.
- Nenhum arquivo do `www` pode ter "senha" no nome (o `Gerar-Instalador.ps1` recusa).
- `index.html` vira casca: `<html lang="pt-BR">` (o servidor injeta `data-tema`), `<title>`, metas `theme-color` dos dois temas, os 4 links de CSS, o favicon, o módulo, `<noscript>` e os pontos de montagem. Sem texto de UI fora de `<title>` e `<noscript>`.

### 7.3 Arquivos que a fase B serve e instala

**Servidor** (`fonte/web/Servidor-Painel.ps1`, linha 1617 hoje). A lista de `$tipos` passa a ser:

```powershell
$tipos = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.svg' = 'image/svg+xml'; '.png' = 'image/png' }
```

A linha 1615 (`foreach ($f in @(Get-ChildItem -LiteralPath $www -File))`) não muda: ela já serve todo arquivo plano do `www`. Por isso os módulos ficam planos.

**Arquivos do `www`** (24): `index.html`; `tokens.css`, `base.css`, `componentes.css`, `telas.css`; `app.js`, `api.js`, `estado.js`, `rotas.js`, `textos.js`, `formato.js`, `constantes.js`, `dom.js`, `icones.js`, `componentes.js`, `formularios.js`, `tela-inicio.js`, `tela-painel.js`, `tela-sessao.js`, `tela-ferramentas.js`, `topo.js`, `marca.js`; `logo.png`, `simbolo.png`. Ficam no protótipo e não vão ao `www`: `api-falsa.js`, `prototipo-barra.js`, `prototipo.css`, `pacote.js`, `gerar-pacote.ps1`, `modulos.html` e o `index.html` dele. Saem `app.css` e o `app.js` atual (o novo `app.js` é outro arquivo com o mesmo nome).

**Instalador** (`instalador/ConfigurarCameras.iss`, linhas 58 a 60 hoje). Saem:

```
Source: "{#Raiz}\fonte\web\www\index.html"; DestDir: "{app}\web\www"; Flags: ignoreversion
Source: "{#Raiz}\fonte\web\www\app.js"; DestDir: "{app}\web\www"; Flags: ignoreversion
Source: "{#Raiz}\fonte\web\www\app.css"; DestDir: "{app}\web\www"; Flags: ignoreversion
```

Entram, no mesmo lugar, uma linha por arquivo, sem curinga (o `Gerar-Instalador.ps1` recusa curinga), no formato:

```
Source: "{#Raiz}\fonte\web\www\<arquivo>"; DestDir: "{app}\web\www"; Flags: ignoreversion
```

para cada um dos 24 arquivos acima, na ordem da lista. O teste da seção 7.4 garante que a lista do `.iss` e a pasta `www` são iguais. Na seção `[InstallDelete]` que já existe (linha 66 do `.iss`), entra `Type: files; Name: "{app}\web\www\app.css"`: a atualização apaga o `app.css` velho e a pasta instalada fica igual à do repo.

### 7.4 Teste que guarda a regra: `fonte/Testes-Front.ps1`

Estático, em PowerShell 5.1, sem Node. Por quê: a régua e o CI rodam só `powershell.exe`, e o projeto não tem Node. Trade-off nomeado: a lógica de `estado.derivar` não ganha teste unitário de JS na régua. Ela é exercida pelo protótipo (`api-falsa.js`) e pelos testes de servidor que já existem. Se um dia entrar Node, `estado.js` já é a costura a testar.

Função `Test-Front -Www <pasta> -Iss <arquivo> -Servidor <arquivo>` que devolve a lista de violações `{ regra, arquivo, linha, trecho }`. O teste roda a função:
1. sobre o `fonte/web/www` real, esperando zero violações;
2. sobre uma pasta temporária por regra (em `$env:TEMP`, apagada no fim), com **uma** violação plantada, esperando exatamente aquela regra. Isso prova que cada regra pega o que promete.

Regras:

| Regra | O que falha |
|---|---|
| `hex` | `#` seguido de 3, 4, 6 ou 8 dígitos hex em qualquer `.css` que não seja `tokens.css`, em `.js` e no `index.html` (exceto as 2 metas `theme-color`). Hash de rota (`#/`) não conta |
| `medida` | número com unidade (`px`, `rem`, `em`, `ms`, `s`, `vh`, `vw`, `%`) fora de `tokens.css`. Exceções fixas: `0`, `100%`. Em linha `@media` só valem as quebras do comentário `/* quebras: 1100px 1600px */` de `tokens.css` |
| `numero-solto-css` | número sem unidade fora de `tokens.css` que não seja 0 ou 1 (peso, entrelinha, `z-index` são tokens) |
| `numero-solto-js` | literal numérico maior que 2 fora de `constantes.js` (intervalo, trava, código HTTP têm nome) |
| `estilo-inline` | `.style.` em JS que não seja `.style.setProperty('--`; `style=`, `<style>`, `<script>` sem `src` e atributo `on*=` no HTML |
| `id-no-css` | seletor de id em `.css` |
| `camada` | `.css` sem o `@layer` do seu nome; `tokens.css` sem a declaração de ordem na primeira regra |
| `texto-fora` | literal de string em `.js` fora de `textos.js` com letra acentuada, ou com duas ou mais palavras começando por maiúscula seguida de minúscula (texto de UI); texto no `<body>` do `index.html` fora de `<noscript>` |
| `import` | `import` de arquivo que não existe no `www` |
| `servido` | arquivo do `www` sem linha `Source:` no `.iss`, `Source:` do `www` sem arquivo, ou extensão sem entrada em `$tipos` no servidor |

Junto, a fase B move as asserções do teste "Front paralelo" de `Testes-Motor.ps1` (hoje lê `app.js` e `index.html`) para o conjunto inteiro do `www`: os mesmos textos exigidos e proibidos, sem afrouxar nenhum. O teste de `data-tema` no `<html lang="pt-BR">` fica como está.

`Testes-Front.ps1` entra:
- no `.github/workflows/release.yml`, como um passo novo "Testes do front" depois de "Testes do coordenador";
- no `instalador/Gerar-Instalador.ps1`, linha 41: `@('Testes-Motor.ps1', 'Testes-Descoberta.ps1', 'Testes-Orquestrador.ps1', 'Testes-Coordenador.ps1', 'Testes-Front.ps1')`;
- na régua do `CLAUDE.md`, linha nova antes de `git diff --check`: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Front.ps1`.

## 8. Mudanças no servidor

O plano permite o mínimo: tipos de arquivo estático, faixa no HTML e dado que já existe no `/api/estado`. A direção usa só uma:

1. **`'.png' = 'image/png'` em `$tipos`** (`Servidor-Painel.ps1:1617`). Por quê: a logo e o símbolo são PNG (decisão do usuário: sem vetorial). Sem a entrada, o servidor manda `application/octet-stream`. O arquivo continua UTF-8 com BOM (há teste para isso).

O que **não** muda, e por quê:
- **Faixa no HTML:** não é usada. O salto da página (`UI-06`) some com o topo de altura fixa desde o primeiro desenho e com a tela "Abrindo o painel…" até o primeiro `/api/estado`. A simulação vira chip dentro do topo, sem empurrar nada.
- **`/api/estado`:** tudo o que a direção precisa já existe (`rede.ok`, `preparada`, `presente`, `cabo`, `simular`, `fila`, `sessao`, `fase`, `vigia.ligado`, `vigia.broadcast`, `vigia.motivo`, `paralelo.dhip`, `senhaDefinida`, `ultimo`). O conflito da fila com o registro é calculado no cliente com `/api/registro`, que já existe.
- **Mensagens do servidor e do motor sem acento:** ficam como estão (fora do mínimo permitido). O front traduz as conhecidas (seção 6, regra 6). A parte de servidor do `UX-40` fica adiada.
- **Contrato de rotas:** nenhuma rota nova, nenhuma mudança de corpo.

## 9. Mapa de resolução

### 9.1 Achados graves (UX com severidade 3, UI com severidade alta): todos com destino

| Achado | Destino | Onde |
|---|---|---|
| `UX-01` Barra do topo vermelha sem motivo acionável | Resolvido | Chips neutros, alarme só com ação (P2, 5.9) |
| `UX-02` A falha some da visão da fila | Resolvido | Fita, contagem, linha e "Pede você" (P1, 3.2, 5.5) |
| `UX-05` Perda de conexão quase invisível | Resolvido | Faixa de alarme depois de 3 consultas e conteúdo inerte (3.6, 5.7) |
| `UX-12` Opções e Encerrar o painel enterrados | Resolvido | Abas no topo; Encerrar no topo, 2 cliques, 0 rolagem (2.1) |
| `UX-16` A sessão salva sugere uma fila já instalada | Resolvido | Conferir confere contra o registro; "Usar a faixa seguinte" (2.2, 3.1) |
| `UX-22` Os cartões não escalam para N câmeras | Resolvido | Tabela de linhas de 36 px; 16 câmeras em cerca de 1 tela (P3, 3.2) |
| `UX-25` O conserto de uma falha manda a lugar que não se vê | Resolvido | "Mudar o encoder" abre o painel lateral no próprio Painel (3.3) |
| `UX-28` Modo de reserva sem instrução | Resolvido | Faixa de atenção com a instrução e a porta do firewall (3.6) |
| `UI-01` O âmbar faz seis papéis | Resolvido | Âmbar só como atenção; um significado por cor (4.1, 4.2) |
| `UI-02` O painel não tem marca | Resolvido | Azul SmartSeg como ação; símbolo no topo; logo inteira na abertura e no fim; favicon (4.6) |
| `UI-03` Hierarquia de caixa e listra, não de tipo e espaço | Resolvido | Escala de tipo, espaço, sombra só no que flutua, tabela no lugar de caixas (4.3, 4.4) |

### 9.2 Demais achados

| Achado | Destino |
|---|---|
| `UX-03` "Conecte a câmera N" contradiz o vigia | Resolvido: um começo só, modo sequencial por link (2.2) |
| `UX-04` Etapa e texto discordam | Resolvido: etapa real na linha (3.2) |
| `UX-06` Painel abre rolado | Resolvido: rota foca o título e zera a rolagem; o Painel cabe em 1 tela (2.1, 3.2) |
| `UX-07` "Senha definida." em simulação | Resolvido (2.2) |
| `UX-08` Faixa de falha forçada vazia | Resolvido: falha forçada no popover do chip e na linha (4.2) |
| `UX-09` Jargão interno | Resolvido: ifIndex e DHIP em "Detalhe técnico"; termos do `CONTEXT.md` explicados (6) |
| `UX-10` Broadcast parece opcional, risco escondido | Resolvido: em Sessão > Rede com o risco escrito; chip "Qualquer faixa" (3.2) |
| `UX-11` Montar fila não confirma nem volta | Resolvido: painel lateral no Painel e "Fila montada" (2.2) |
| `UX-13` Decisão escondida age em instalada | Resolvido: botões só nas linhas em falha (3.2) |
| `UX-14` Mesma ação, nomes diferentes | Resolvido: glossário (6) |
| `UX-15` Âmbar sem sentido | Resolvido (4.2) |
| `UX-17` Placa sugerida dispara alerta | Resolvido: nota inline (2.2) |
| `UX-18` Dois valores de bitrate | Resolvido (2.2) |
| `UX-19` `confirm()` genéricos | Resolvido: diálogo próprio, 7 confirmações (5.8) |
| `UX-20` Começar abaixo da dobra | Resolvido: rodapé fixo (3.1) |
| `UX-21` Dois começos | Resolvido (2.2) |
| `UX-23` Instrução do vigia fixa | Resolvido: instrução só no estado vazio (3.6) |
| `UX-24` Log aberto no Painel | Resolvido: log em Ferramentas, fechado (3.4) |
| `UX-26` Falha crua e partida | Resolvido: uma frase com o conserto e o cru em "Detalhe técnico" (3.2, 6) |
| `UX-27` Avisos crus, sem origem, somem | Resolvido: aviso junto do controle, sem sumir sozinho (5.6) |
| `UX-29` Conserto só no LEIA-ME | Resolvido em parte: os sintomas que o painel detecta (placa, cabo, internet, reserva, conexão, senha recusada) dizem o conserto. Os outros sintomas da tabela do LEIA-ME ficam lá, porque o painel não os detecta |
| `UX-30` Vigia ligado sem câmera não convida | Resolvido (3.6) |
| `UX-31` Placas em "Lendo…" eterno | Resolvido (2.2) |
| `UX-32` Registro sem leitura e com dado velho | Resolvido (3.6, 5.4) |
| `UX-33` Registro quebra palavras | Resolvido (5.4) |
| `UX-34` Fila encerrada concluída e pendente | Resolvido (2.3, 3.6) |
| `UX-35` Encerrado segue consultando | Resolvido: consultas param (3.6) |
| `UX-36` Opções mistura sessão e painel | Resolvido: Sessão com o bloco Painel separado (2.1, 3.5) |
| `UX-37` Mesmo formulário, textos diferentes | Resolvido: `formularios.js` (7.2) |
| `UX-38` Ferramentas com peso de Painel | Resolvido: aba no topo, terceira posição (2.1) |
| `UX-39` Rótulos que não dizem a ação | Resolvido (6) |
| `UX-40` Plural preguiçoso, sem acento | Resolvido no front; a parte do servidor fica adiada, porque mudar mensagem do servidor está fora do mínimo permitido (8) |
| `UI-04` Escala tipográfica sem tokens | Resolvido (4.3) |
| `UI-05` Espaçamento fora do sistema | Resolvido e guardado pelo teste (4.4, 7.4) |
| `UI-06` A página salta ao abrir | Resolvido: topo fixo e tela Abrindo (8) |
| `UI-07` Mono fora de dado de máquina | Resolvido (4.3) |
| `UI-08` Faixa de simulação grita | Resolvido: chip neutro (4.2) |
| `UI-09` Estado da placa em texto técnico vermelho | Resolvido (5.9) |
| `UI-10` Trilha quebra o rótulo, estado só por cor | Resolvido (3.1) |
| `UI-11` Explicação só em `title` | Resolvido: ajuda visível e motivo do desabilitado escrito (5.1, 5.2) |
| `UI-12` Explicação longa antes do 1º campo | Resolvido (2.2) |
| `UI-13` Dois estilos de selo | Resolvido: um chip só (5.9) |
| `UI-14` Desabilitado com duas caras | Resolvido (5.1) |
| `UI-15` Pulso decorativo | Resolvido (4.4) |
| `UI-16` Glifo ⚙ como ícone | Resolvido (2.1, 4.5) |
| `UI-17` Link com `href="#"` | Resolvido: rotas reais ou `<button>` (2.1) |
| `UI-18` Placeholders inconsistentes | Resolvido (5.2) |
| `UI-19` Aviso neutro some em 4 s | Resolvido (5.6) |

Nenhum achado foi recusado.

### 9.3 Decisões do usuário na Task 6 (19/11)

1. Protótipo aprovado como está: a direção segue para a fase B sem ajuste.
2. Opções passa a se chamar **Sessão** (2.1).
3. No tema escuro, a logo oficial sobre a placa clara, em definitivo. A variante derivada não vai para a fase B (4.6).
4. Sem foco automático na falha: anúncio `aria-live`, a linha da câmera e o bloco "Pede você" (3.3).

A fase B está em frentes, na ordem do índice `docs/plans/2026-11-20-frente-redesenho-mapa.md`.

## Skills aplicadas e descartadas

| Skill | Aplicado | Descartado, e por quê |
|---|---|---|
| `mattpocock-skills:research` | Agente em segundo plano, fontes primárias, cada padrão com a fonte (seção Pesquisa) | Arquivo de pesquisa separado no repo: a Task só permite `direcao.md`, então os achados entram aqui |
| `frontend-design` | Plano em duas passagens com revisão contra os padrões genéricos (Conceito); ousadia num lugar só (a fita); regras de escrita (6); seletores com especificidade controlada (`@layer`, sem id) | Herói, fonte de destaque não-sistema, entrada animada: o painel é ferramenta de bancada, e o herói está nos Non-Goals |
| `design-taste-frontend` (`references/system.md`) | Um sistema de tokens; espaço em base 4; rótulo de 13 com peso 600, sem caixa alta; interface 90 a 95% neutra com um acento que move botão, link e foco; rótulo 4.5:1 no acento e acento 3:1 no fundo; raio por nível; formulário com rótulo visível, erro embaixo do campo ao enviar, `aria-invalid`/`aria-describedby`; acesso (nomes, ordem de títulos, sem `tabindex` positivo, anel de foco de 2 px na cor da ação) | As regras da casa, seções, hero, fotos, momentos e o gate (são de site de empresa); corpo de 16 px (o plano fixou 14 a 15 com piso de 13) |
| `mattpocock-skills:codebase-design` | Vocabulário de módulo, interface, profundidade e costura; `estado.js` como módulo profundo com teste da deleção; `api.js` como costura real com dois adaptadores (7.2) | Costura para cada tela ou componente: um adaptador só é costura hipotética |
