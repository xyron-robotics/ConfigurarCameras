# Linha de base do painel: inventário e jornada do operador

Frente `ux`, Task 1. Retrato do painel como ele está hoje, antes da auditoria (Tasks 2 e 3). Aqui só há fatos medidos e observados. Julgamento, severidade e solução ficam para as próximas Tasks.

## Como foi medido

- Painel v1.2.3 do worktree da frente, em simulação, com 3 câmeras simuladas e escala de atraso 1: `Servidor-Painel.ps1 -Simular -Porta 8766 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-ux`.
  - Porta 8766 porque a 8765 estava ocupada por outro processo do sistema.
- Navegador Chromium (Playwright), janela de 1366×768, navegação comum (cliques, campos, `confirm()` aceito).
- Dados só fictícios: rede `192.0.2.0/24`, gateway `192.0.2.1`, IP de fábrica `192.168.1.108`, MACs `AA:00:00:00:00:01` a `03`, seriais `SIM-1` a `SIM-3`, local "Obra exemplo", e-mail `suporte@example.com`.
- Falha forçada por `POST /api/simular` com `{"ligado":true,"falharEm":{"2":"encoder"}}`.
- **Clique** conta todo clique do operador, inclusive o OK de um `confirm()`. **Campo digitado** é campo que o operador teve de preencher. **Controles vistos** são os campos e listas na tela, preenchidos ou não. **Momento de dúvida** é um ponto em que a tela se contradiz, esconde o próximo passo ou obriga o operador a parar para interpretar.

### Limites da medição

- Em simulação o passo 1 (senha) é dado como cumprido (`senhaOk()` aceita `estado.simular`, `app.js:201`). Os números do passo 1 real vêm do código: 2 campos e 1 clique ("Usar esta senha e avançar").
- A faixa e a tela de atualização não aparecem com `-SemAtualizacao`. Entram no inventário só pelo código.
- O registro simulado guarda as câmeras instaladas, e o DHIP simulado deixa de achar as mesmas 3 câmeras de fábrica (`Get-AchadosSimulados`, `Coordenador-Cameras.ps1:976`). Para os cenários 2b e 3, o `registro-simulado.json` da pasta de dados de teste foi apagado entre uma abertura e outra.
- O painel lista as placas de rede reais deste PC, mesmo em simulação. Por isso o passo 2 e a seção Placa de Opções não têm captura de referência (o repositório é público).

## Inventário de telas e estados

Linhas de `fonte/web/www/app.js` (J) e `fonte/web/www/index.html` (H). "Visto" diz se o estado apareceu na sessão de medição.

### Moldura e navegação

| Tela ou estado | Seletor | Render (J) | Propósito | Visto |
|---|---|---|---|---|
| Faixa de simulação | `#faixa-simular`, `#faixa-falha` (H:18-20) | `desenhar` J:415 (J:420-423) | Avisa que nada vai para câmera nem placa; mostra a falha forçada | sim |
| Barra do topo: placa | `#placa` | `desenharPlaca` J:472 | Estado da placa escolhida e das duas faixas | sim |
| Barra do topo: internet | `#internet` | `desenharInternet` J:535 | Internet do PC, testada ao abrir e depois de preparar a placa | sim |
| Botão Preparar placa | `#btn-preparar` (H:40) | `desenhar` J:432 | Põe as faixas na placa quando faltam | sim |
| Menu lateral | `nav#menu` (H:45-49) | `trocarView` J:225 | Troca entre Painel, Ferramentas e Opções por hash | sim |
| Aviso geral e por seção | `#aviso`, `[data-aviso-de]` | `mostrarAviso` J:136 | Recusa ou erro de uma ação | sim |
| Anúncio para leitor de tela | `#anuncio` (aria-live) | `anunciar` J:352 | Confirmação falada de ações | não (invisível) |
| Log | `details#log-bloco`, `#log` (H:434) | `anexarLog` J:402 | Linhas do servidor; aberto só no Painel | sim |
| Roteamento e modo | `body.no-inicio`, `.view` | `rota` J:194, `precisaInicio` J:205, `desenharModo` J:264 | Decide entre passo a passo e modo normal | sim |

### Passo a passo (`#inicio`, H:56)

| Tela ou estado | Seletor | Render (J) | Propósito | Visto |
|---|---|---|---|---|
| Trilha dos 7 passos | `ol#passos`, `button.passo-botao` | `montarPasso` J:281 | Mostra feito, agora e bloqueado; passo além do sugerido fica desabilitado | sim |
| Rodapé | `#btn-voltar`, `#btn-montar-depois`, `#btn-avancar`, `#btn-comecar`, `#passo-n` (H:120-127) | `montarPasso` J:296-302 | Voltar, avançar, montar depois (passo 6), começar (passo 7) | sim |
| 1 Senha, sessão nova | `.passo[data-passo=1]`, `#form-senha` | `montarPasso` J:303-315 | Senha do admin das câmeras, digitada duas vezes | não (simulação pula) |
| 1 Senha, sessão salva | `#passo-escolha`, `#btn-usar-sessao`, `#btn-revisar-sessao` | `textoDaEscolha` J:342, handlers J:1623-1624 | Resume a última sessão; Usar vai ao 7, Revisar vai ao 2 | sim |
| 1 Senha já definida | `#senha-definida`, `#btn-trocar-senha` | J:309 | Mostra que há senha e oferece trocar | sim |
| 2 Placa de rede | `#form-placa`, `ul#placas` | `desenharPlacas` J:1410 | Escolha da placa ligada à bancada | sim |
| 3 Rede das câmeras | `#form-rede` | `slotDe` J:275 | Máscara, gateway, DNS e IP do PC na rede definitiva | sim |
| 4 Faixa de fábrica | `#form-fabrica` | `slotDe` J:275 | IP de fábrica e IP do PC nessa faixa | sim |
| 5 Câmera | `#form-camera`, `#faixa-principal`, `#faixa-secundario` | `desenharEncoder` J:1277, `desenharBitrates` J:1266, `desenharAvisosCamera` J:1315 | E-mail de recuperação e encoder dos dois streams | sim |
| 6 Fila | `#form-fila` | `desenharPrevia` J:939 | Faixa de IPs, local, rack, andar | sim |
| 7 Resumo | `#resumo`, `#resumo-montar` (H:115-117) | `desenharResumo` J:1443 | Confere tudo antes de começar | sim |
| Avançar, montar depois, começar | — | `avancar` J:1469, `montarDepois` J:1489, `comecar` J:1500 | Salva a seção e anda; começar conclui a sessão e vai ao Painel | sim |

### Painel (`#view-painel`, H:131)

| Tela ou estado | Seletor | Render (J) | Propósito | Visto |
|---|---|---|---|---|
| Sem fila | `#painel-sem-fila` (H:132) | `desenharFila` J:554-557 | Diz que não há fila e leva a Opções, seção Fila | sim |
| Fila montada | `#fita-bloco`, `ol#fita`, `#fita-resumo` (H:137-145) | `desenharFila` J:588-606 | Fita IP a IP com pendente, agora, próxima, instalada | sim |
| Encerrar a fila | `#btn-encerrar-fila` (H:142) | `desenharFila` J:566, handler J:1690-1696 | Fecha a fila; esconde em concluída ou encerrada | sim |
| Vigia desligado e ligado | `#vigia`, `#vigia-luz`, `#btn-vigia`, `#vigia-dhip` (H:149) | `desenharVigia` J:954 | Liga a configuração automática de cada câmera de fábrica que aparecer | sim |
| Bancada pronta | `#bancada-pronta`, `#form-conectada`, `details#retomar` (H:166) | `desenharFila` J:649-659 | "Conecte a câmera N de M": porta, canal e Câmera conectada | sim |
| Cartão na espera | `li.cartao[data-fase=espera]` | `novoCartao` J:690, `atualizarCartao` J:787 | Câmera achada, ainda sem posição | sim |
| Cartão no portão | `li.cartao[data-fase=portao]` | `atualizarCartao` J:814 | Câmera no IP de fábrica, recebendo senha, encoder e rede | sim |
| Cartão conferindo | `li.cartao[data-fase=conferindo]` | `atualizarCartao` J:814 | Câmera conferida no IP definitivo | sim |
| Cartão instalada, pulada, ignorada | `li.cartao.compacto` | `atualizarCartao` J:802 | Fim da câmera | instalada sim; pulada e ignorada não |
| Cartão em decisão | `.cartao-decisao` | `atualizarCartao` J:830-841, `botoesDecisao` J:754, `textoDaFalha` J:910, `focarDecisao` J:893 | Falha numa etapa: Tentar de novo ou Pular esta posição | sim |
| Trabalho manual (legado) | `#bancada-trabalho`, `ol#etapas` (H:184) | `desenharFila` J:621-636 | Retomada manual de câmera já inicializada | não |
| Decisão manual (legado) | `#bancada-decisao` (H:196) | `desenharFila` J:637-642 | Decisão sem cartão | não |
| Fila concluída | `#bancada-fim` (H:206) | `desenharFila` J:643-648 | Fim normal; Montar outra fila | sim |
| Fila encerrada | `#bancada-fim` | `desenharFila` J:643-648 | Fim por Encerrar a fila | sim |
| Última instalada | `#ultimo` (H:214) | `desenharFila` J:560-563 | Linha verde com a última câmera instalada | sim |
| Registro | `#registro-bloco`, `#registro-corpo` (H:216) | `carregarRegistro` J:1517 | Tabela do registro; Atualizar e Exportar relatório | sim |

### Ferramentas, Opções e telas de fim

| Tela ou estado | Seletor | Render (J) | Propósito | Visto |
|---|---|---|---|---|
| Ferramentas | `#view-ferramentas` (H:237), `#form-sondar`, `#btn-descobrir`, `#btn-verificar`, `#resultado-ferramenta` | `desenharFerramenta` J:995 | Sondar um IP, procurar câmeras (só real), verificar o registro | não |
| Opções: Senha | `.secao[data-secao=senha]` (H:273) | `montarOpcoes` J:328 | Trocar a senha das próximas câmeras | sim |
| Opções: Placa | `.secao[data-secao=placa]` (H:294) | `desenharPlacas` J:1410 | Trocar a placa | sim |
| Opções: Rede | `.secao[data-secao=rede]` (H:311) | `montarOpcoes` J:328 | Rede definitiva | sim |
| Opções: Fábrica | `.secao[data-secao=fabrica]` (H:332) | `montarOpcoes` J:328 | Faixa de fábrica | sim |
| Opções: Câmera | `.secao[data-secao=camera]` (H:350) | `desenharEncoder` J:1277 | E-mail e encoder | sim |
| Opções: Fila | `.secao[data-secao=fila]` (H:389), `#fila-previa`, `#fila-ultima` | `desenharPrevia` J:939 | Montar fila nova (substitui a atual) | sim |
| Opções: Painel e tema | `.secao[data-secao=painel]` (H:413), `#btn-restaurar`, `#btn-refazer`, `#btn-encerrar`, `fieldset#tema` | `aplicarTema` J:1750, `ligarTema` J:1761 | Restaurar DHCP, refazer o passo a passo, encerrar, versão e tema | sim |
| Faixa de atualização | `#atualizacao` (H:23), `#btn-atualizar` | `desenharAtualizacao` J:497 | Versão nova disponível, baixando, instalando ou erro | não |
| Tela de atualização | `#atualizando` (H:445) | `mostrarTelaFim('atualizando')` J:370 | Painel fora do ar durante a atualização | não |
| Tela de encerrado | `#encerrado`, `#encerrado-texto` (H:441) | `mostrarTelaFim('encerrado')` J:370, J:1741 | "Painel encerrado. Pode fechar esta janela." | sim |

O tema (sistema, claro, escuro) vem do servidor: `data-tema` no `<html>` (`Add-TemaNoHtml`), `PUT /api/tema` e `tema.txt` na pasta de dados. Não usa `localStorage`.

`confirm()` nativo em 10 pontos de `app.js`: pular câmera (J:770), placa que leva à internet (J:1363), erro ao salvar sessão (J:1382), trocar a fila (J:1639), pular no legado (J:1684), encerrar a fila (J:1695), restaurar DHCP (J:1708), refazer o passo a passo (J:1712), atualizar (J:1722), encerrar o painel (J:1737).

## Jornada do operador

### Números por cenário

| Cenário | Telas | Cliques | Campos digitados | Controles vistos | Rolagens obrigatórias | Tempo medido (simulação) | Momentos de dúvida |
|---|---|---|---|---|---|---|---|
| 1. Primeira abertura até a 1ª câmera instalada | 7 (passos 2 a 7 e Painel); real: 8 | 8; real: 9 | 5; real: 7 | 26 | 1 (Começar abaixo da dobra no Resumo) | 3 câmeras instaladas em até 20 s depois de Câmera conectada | 6 |
| 2a. Sessão salva cuja última fila já está instalada, até 3 instaladas | 5 (passo 1, passo 7, Painel com aviso, Opções/Fila, Painel) | 6 | 2 | 7 | 0 | 1ª no portão 5,7 s depois de Ligar vigia | 4 |
| 2b. Sessão salva com fila livre, até 3 instaladas | 3 (passo 1, passo 7, Painel) | 3 | 0 | 2 por cartão | 0 | 1ª no portão 5,7 s depois de Ligar vigia | 5 |
| 3. Falha na câmera 2 e recuperação | 3 | 4 | 0 | 2 por cartão | 0 | falha aparece 8,4 s depois de Ligar vigia; decisão sozinha na tela em 12,9 s; Tentar de novo até instalada: 3,2 s | 5 |
| 4a. Encerrar a fila | 1 (Painel) | 2 | 0 | 0 | 0 | imediato | 2 |
| 4b. Encerrar o painel | 2 (Opções, encerrado) | 3 | 0 | 0 | 2 (achar Opções no menu; descer até a seção Painel) | imediato | 3 |

"Real" soma o passo 1 de senha, que a simulação pula (2 campos e 1 clique, pelo código).

### Cenário 1: primeira abertura até a 1ª câmera instalada

Sequência: passo 2 Avançar com a placa sugerida, OK no `confirm()`, passo 3 gateway e Avançar, passo 4 Avançar, passo 5 e-mail e Avançar, passo 6 faixa, local e "Montar a fila e avançar", passo 7 Começar, Painel "Câmera conectada".

Momentos de dúvida:
1. A placa que o próprio painel marca como "sugerida" dispara um `confirm()` de risco ("é a que leva este PC à internet… Usar essa placa mesmo assim?").
2. O bitrate do stream principal vem como "Outro valor…" com 1596, e a lista ao lado diz "4096 (recomendado)".
3. No Resumo, a 1366×768, o botão Começar fica abaixo da dobra.
4. Depois de Começar, o Painel abre rolado 219 px: o título da fila e a fita ficam fora da vista (medido duas vezes).
5. Logo depois de Começar, que promete preparar a placa, a barra do topo fica vermelha: "Placa Ethernet sem as faixas…", com o botão Preparar placa. A tela não diz que em simulação a placa não é tocada.
6. O cartão da bancada oferece dois começos, Ligar vigia e Câmera conectada. Em simulação, Câmera conectada trouxe as 3 câmeras de uma vez, como "Sem posição / Na espera", cada uma com campos Porta e Canal.

### Cenário 2: sessão salva até 3 câmeras instaladas

2a reproduz o caso de quem reabre o painel com a mesma sessão depois de instalar a fila anterior. Sequência: Usar essa sessão, Começar, aviso, link "Monte uma em Opções, seção Fila", primeiro e último IP novos, Montar fila, Painel no menu, Ligar vigia.

Momentos de dúvida (2a):
1. Usar e Começar levam a um aviso vermelho, "Nenhuma posição livre nessa faixa (3 já no registro)", e a "Sem fila montada". A sessão salva sugere de novo a fila que já foi instalada.
2. A prévia da fila em Opções diz "3 endereços, de 192.0.2.10 a 192.0.2.12" sem dizer que os 3 já estão instalados.
3. Montar fila deixa o operador em Opções, sem confirmação visível e sem levar ao Painel.
4. A tabela do registro quebra palavras no meio a 1366 px: "SIMULA / DA", "Instalad / a", "exempl / o".

2b é o caminho feliz: Usar, Começar, Ligar vigia. As câmeras passam uma de cada vez pelo portão e conferem em paralelo.

Momentos de dúvida (2b):
1. O passo 1 diz "Senha definida." em simulação, sem senha nenhuma informada.
2. A barra do topo já está vermelha ("sem as faixas") no passo 1, antes de qualquer ação.
3. Com o vigia ligado, o bloco abaixo segue dizendo "Conecte a câmera 2 de 3", com o botão Câmera conectada.
4. Um cartão no portão mostra "Etapa 2 de 4: encoder" com o texto "Gravando a rede da câmera para 192.0.2.20".
5. Câmeras sem posição aparecem com campos Porta e Canal abertos, antes de saber em que IP vão ficar.

### Cenário 3: falha na câmera 2 e recuperação

Sequência: Usar, Começar, falha armada pela API (fora da conta de cliques), Ligar vigia, Tentar de novo no cartão da câmera 2. Linha do tempo depois de Ligar vigia: 5,5 s câmera 1 no portão; 8,4 s câmera 2 em decisão; 10,3 s câmera 1 instalada; 12,9 s câmera 3 instalada e a fase global vira decisão. O foco vai para Tentar de novo. Depois do clique: portão, conferência e instalada em 3,2 s.

Momentos de dúvida:
1. Na fita, a câmera que falhou aparece como "agora", em âmbar, a mesma marca das câmeras em curso.
2. O resumo da fila diz "2 instalada(s), 0 pendente(s)" e não conta a falha.
3. O texto de apoio manda conferir "a seção Câmera em Opções", e o link Opções do menu fica fora da vista (ver cenário 4b).
4. O erro vem em monoespaçado, numa caixa de fundo vermelho ("falha simulada: camera recusou o valor"), separado do título "Falhou na etapa encoder".
5. A faixa de falha forçada aparece vazia quando a falha é armada por câmera (mapa), porque só o texto `falharEm` é mostrado.

Observação técnica fora do caminho do operador: o cartão da câmera instalada guarda no DOM os botões de decisão escondidos. Um clique programático num deles mandou "tentar de novo" para a câmera 1, já instalada. O servidor aceitou e registrou no log, sem efeito na tela.

### Cenário 4: encerrar

4a. Encerrar a fila (com uma fila nova de 2 posições pendentes): botão no topo da fila e OK no `confirm()`.

Momentos de dúvida (4a):
1. O bloco diz "Fila encerrada" e, logo abaixo, "O vigia foi desligado: fila concluída".
2. O resumo continua "0 instalada(s), 2 pendente(s)" numa fila já encerrada.

4b. Encerrar o painel: Opções no menu, descer até a seção Painel, Encerrar o painel, OK no `confirm()`.

Momentos de dúvida (4b):
1. O link Opções do menu fica a 1304 px do topo no Painel (o menu tem 1257 px de altura). A 768 px de janela, só aparece rolando a página.
2. Opções é uma página única de 2847 px (3,7 telas). Encerrar o painel fica a 2648 px, na última seção.
3. A tela de encerrado mantém a rolagem anterior (barra no fim) e a página continua consultando `/api/estado`: 5 erros de conexão recusada no console depois do encerramento.

## Capturas de referência

Em `docs/design/2026-11-ux/capturas/`, PNG de 1366×768, só simulação. As versões clara de cartões e decisão foram feitas trocando `data-tema` na página (o mesmo que `aplicarTema` faz), segundos depois da escura. Por isso o estado das câmeras muda um pouco entre as duas.

| Arquivo | Estado |
|---|---|
| `t1-passo-rede-claro.png` | Passo 3, rede das câmeras, sessão nova |
| `t1-resumo-claro.png` | Passo 7, resumo |
| `t1-passo-sessao-salva-escuro.png` | Passo 1 com sessão salva: Usar ou Revisar |
| `t1-painel-vigia-escuro.png` | Painel com fila montada e vigia ligado, sem câmera |
| `t1-painel-cartoes-escuro.png` | Câmera 1 no portão, câmeras 2 e 3 na espera |
| `t1-painel-cartoes-claro.png` | Câmera 1 conferindo, câmera 2 no portão, câmera 3 na espera |
| `t1-painel-decisao-escuro.png` | Câmera 2 em decisão, 1 e 3 instaladas |
| `t1-painel-decisao-claro.png` | O mesmo estado, tema claro |
| `t1-painel-concluida-claro.png` | Fila concluída |
| `t1-encerrado-claro.png` | Tela de encerrado |
