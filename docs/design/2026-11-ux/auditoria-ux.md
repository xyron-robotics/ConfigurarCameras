# Auditoria de UX do painel

Frente `ux`, Task 2. Diagnóstico do painel v1.2.3 como experiência do operador de bancada. A base é a `linha-de-base.md` (Task 1): inventário, jornada medida em 4 cenários e capturas. Aqui entram julgamento e severidade. A solução fica para a direção (Task 4). A parte visual (cor, tipo, contraste, marca) é da Task 3. Ela só aparece aqui quando muda o que o operador entende.

## Método

1. **As 10 heurísticas de Nielsen.** Cada achado diz qual heurística fere (H1 a H10).
2. **Análise de tarefa** sobre os 4 cenários da Task 1. Em cada momento: o que o operador precisa saber, o que a tela mostra, o que esconde e o que pede à toa.
3. **Recuperação de erro:** falha de câmera, recusa do servidor, perda de conexão.
4. **Estados vazio, carregando e erro** de cada bloco que busca dado.
5. **Arquitetura de informação:** as 3 abas (Painel, Ferramentas, Opções) e o passo a passo.
6. **Carga com N câmeras:** vigia e cartões com 3, 8 e 16 câmeras (16 é um NVR comum de bancada).
7. **Escrita**, pela skill `frontend-design` (seção "More on writing in design"): verbo no botão, erro que diz o conserto, vazio como convite, mesma ação com o mesmo nome.

**Fontes.** Jornada e capturas da Task 1. Código lido em `fonte/web/www/app.js` (J), `fonte/web/www/index.html` (H) e `fonte/web/www/app.css` (C). Fluxo e vocabulário em `LEIA-ME.md` e `CONTEXT.md`.

**Severidade (Nielsen):**

| Nota | Significado |
|---|---|
| 0 | Não é problema de usabilidade |
| 1 | Cosmético: corrigir se sobrar tempo |
| 2 | Menor: atrasa ou confunde, mas o operador segue |
| 3 | Maior: leva a erro, a retrabalho ou a um beco; prioridade alta |
| 4 | Catástrofe: impede a tarefa ou causa dano; corrigir antes de liberar |

Nenhum achado recebeu 4. O caminho feliz (sessão salva, Usar, Começar, Ligar vigia) fecha 3 câmeras em 3 cliques, e a falha forçada se recupera em 1 clique. Os problemas graves estão no que acontece em volta desse caminho.

**Evidência:** `Cn.dk` é o momento de dúvida k do cenário n na `linha-de-base.md` (por exemplo, `C3.d2`). Captura é o arquivo em `capturas/`.

## Análise de tarefa

### Cenário 1: primeira abertura até a 1ª câmera instalada

| Momento | O operador precisa saber | A tela mostra | A tela esconde | Pede à toa |
|---|---|---|---|---|
| Passo 2, placa | Qual placa vai à bancada; se mexer nela derruba a internet | Lista de placas, a sugerida marcada | Por que a sugerida é a da internet | Um `confirm()` de risco na escolha que o próprio painel sugeriu |
| Passo 5, câmera | Que encoder cada câmera vai receber | Bitrate "Outro valor…" 1596 e a lista com "4096 (recomendado)" | Qual dos dois vale e de onde veio o 1596 | Interpretar dois valores para o mesmo campo |
| Passo 7, resumo | Que tudo está certo, e como começar | Cartões por seção, com Alterar | O botão Começar, abaixo da dobra | Uma rolagem para achar a ação principal |
| Painel, logo depois | Que a placa está pronta e a fila espera câmera | Barra vermelha "sem as faixas", página rolada 219 px | O título da fila e a fita | Decidir se o vermelho é problema |
| Bancada | Se liga o vigia ou se clica Câmera conectada | Os dois, lado a lado | Quando usar cada um | Escolher entre dois começos sem critério |

### Cenário 2: sessão salva até 3 câmeras instaladas

| Momento | O operador precisa saber | A tela mostra | A tela esconde | Pede à toa |
|---|---|---|---|---|
| Passo 1 | Se a sessão serve para hoje | Resumo da sessão, Usar ou Revisar | Que a fila sugerida já está toda no registro (2a) | Nada, se a fila está livre (2b) |
| Começar (2a) | Que a fila precisa de outra faixa | Aviso vermelho "Nenhuma posição livre", "Sem fila montada" | O motivo antes do clique | Usar e Começar para descobrir o erro |
| Opções, Fila (2a) | Quantas posições livres a faixa nova dá | "3 endereços, de … a …" | Quantos desses já estão instalados | Voltar ao Painel pelo menu, sem aviso de que a fila foi montada |
| Vigia ligado | Que é só ligar as câmeras no switch | O texto do vigia e, embaixo, "Conecte a câmera 2 de 3" com Câmera conectada | Que o bloco "Conecte" não vale com o vigia ligado | Ler dois comandos que se contradizem |
| Cartões | Em que etapa cada câmera está | "Etapa 1 de 4: inicialização" com "Gravando a rede…" | A etapa real | Campos Porta e Canal em câmera ainda sem posição |

### Cenário 3: falha na câmera 2 e recuperação

| Momento | O operador precisa saber | A tela mostra | A tela esconde | Pede à toa |
|---|---|---|---|---|
| Falha | Que uma câmera espera decisão, qual e por quê | Cartão vermelho com título, erro cru e apoio | Na fita, a falha aparece como "agora", igual às em curso; o resumo não conta a falha | Ler o cartão para saber que há falha |
| Decidir | Se tentar de novo resolve ou se é preciso mudar algo antes | "Confira a seção Câmera em Opções antes de tentar de novo" | Onde fica Opções: o link do menu está fora da vista | Rolar a página para achar o menu |
| Depois | Que a fila voltou ao normal | Cartão instalado | Nada | Nada |

### Cenário 4: encerrar

| Momento | O operador precisa saber | A tela mostra | A tela esconde | Pede à toa |
|---|---|---|---|---|
| Encerrar a fila | Que as pendentes ficaram sem câmera | "Fila encerrada" e "O vigia foi desligado: fila concluída" | Qual dos dois é verdade | Conciliar "encerrada" com "concluída" e com "2 pendente(s)" |
| Encerrar o painel | Que a placa volta ao DHCP e pode fechar | Nada no Painel | O botão, na última seção de Opções, a 2648 px | Duas rolagens: achar Opções no menu e descer 3,5 telas |

## Achados

Cada achado: id, severidade, heurística, evidência, código e impacto no operador.

### Visibilidade do estado

**UX-01. Barra do topo vermelha sem motivo acionável.** Severidade 3. H1, H9.
- Evidência: `C1.d5`, `C2b.d2`. Todas as capturas do Painel (`t1-painel-*`) mostram "Placa Ethernet sem as faixas: 192.168.1.x (camera de fabrica em …); 192.0.2.0/24 (conferencia no IP definitivo)".
- Código: J:484 junta a lista `faltando` do servidor, crua e sem acento (`Servidor-Painel.ps1:507`). O texto não diz o conserto, que só está no `LEIA-ME.md` ("clique em Preparar placa; se não resolver, falta Administrador").
- Impacto: o vermelho aparece desde o passo 1 e segue depois de Começar, que promete preparar a placa. O operador aprende a ignorar o vermelho do topo. No dia em que a placa de fato perder a faixa, o alarme não se distingue do ruído de sempre.

**UX-02. A falha some da visão da fila.** Severidade 3. H1.
- Evidência: `C3.d1`, `C3.d2`. Captura `t1-painel-decisao-escuro.png`: "câmera 2 agora" em âmbar e "2 instalada(s), 0 pendente(s)".
- Código: a fita marca "agora" toda posição com cartão em portão, conferindo **ou decisão** (J:580, J:597). O resumo conta só `feita` e `pendente` (J:571-572, J:589).
- Impacto: quem olha o topo da fila lê "quase pronto, nada pendente". A câmera que espera decisão só aparece no cartão dela. Com 16 cartões, ela pode estar fora da vista. A fila não anda para essa posição até alguém decidir.

**UX-03. Bloco "Conecte a câmera N de M" contradiz o vigia ligado.** Severidade 2. H1, H4.
- Evidência: `C2b.d3`, `C1.d6`. Captura `t1-painel-cartoes-claro.png` ("Conecte a câmera 3 de 3" embaixo dos cartões, com o vigia ligado).
- Código: J:649-656. Com o vigia ligado, só muda o apoio, e o apoio diz que "Câmera conectada fica para retomar uma câmera já inicializada". O `LEIA-ME.md` (seção Fila, "Sem o vigia") diz o contrário: Câmera conectada procura câmeras de fábrica, e retomar é o bloco "Retomar câmera já inicializada".
- Impacto: dois comandos na mesma tela, e um deles descreve errado o próprio botão. O operador não sabe se precisa clicar algo além de ligar as câmeras.

**UX-04. Etapa e texto do cartão discordam.** Severidade 2. H1.
- Evidência: `C2b.d4`. Captura `t1-painel-cartoes-claro.png`: "Etapa 1 de 4: inicialização" e, logo abaixo, "Gravando a rede da câmera para 192.0.2.21".
- Código: a etapa vem de `c.etapa` e o texto de `c.trabalho`, dois campos que o cartão mostra sem conciliar (J:817-827). No registro, o mesmo nome de etapa aparece como "concluiu: …" (J:1525). Provável causa: o cartão mostra a última etapa concluída como se fosse a etapa em curso.
- Impacto: o operador não sabe onde a câmera está. Se ela falhar, não sabe o que já foi gravado nela.

**UX-05. Perda de conexão com o servidor quase invisível.** Severidade 3. H1, H9.
- Evidência: `C4b.d3` (5 erros de conexão no console depois de encerrar). Pelo código, o mesmo vale para qualquer queda do servidor.
- Código: J:384-389 troca só o texto da placa para "Painel sem resposta". O resto da tela fica como estava, com os botões ativos. `ciclo()` tenta de novo a cada 600 ou 1500 ms, sem limite e sem aviso geral (J:1773-1777).
- Impacto: o operador olha cartões congelados e acha que a câmera está parada na etapa. Os cliques vão para um servidor que não responde.

**UX-06. O Painel abre rolado depois de Começar.** Severidade 2. H1.
- Evidência: `C1.d4`, medido duas vezes (219 px).
- Código: `trocarView` só rola em Opções (J:257). Ao ir para o Painel, a rolagem herdada do Resumo fica (o Resumo é rolado para achar Começar, ver UX-20).
- Impacto: o título da fila e a fita, a primeira coisa que confirma que a fila começou, ficam fora da vista.

**UX-07. Em simulação, o passo 1 diz "Senha definida." sem senha.** Severidade 1. H1.
- Evidência: `C2b.d1`.
- Código: `senhaOk()` aceita `estado.simular` (J:201).
- Impacto: só ensaio e demonstração. Ensina um passo 1 que não existe no uso real.

**UX-08. Faixa de falha forçada vazia.** Severidade 1. H1.
- Evidência: `C3.d5`.
- Código: a faixa mostra `falharEm` só como texto (J:420-423); com o mapa por câmera, sai vazia.
- Impacto: só em ensaio. Quem ensaia não vê qual falha armou.

### Correspondência com o mundo do operador

**UX-09. Jargão interno na tela.** Severidade 2. H2.
- Evidência: capturas do Painel e do vigia. Termos visíveis: "broadcast" (H:158, J:970-972), "DHIP" e "UDP 37810" (H:158 no `title`, J:1025), "ifIndex" no Resumo (J:1451), "Sem posição" (J:792), "faixa", "portão" e "conferência" na barra do topo, que chegam sem acento do servidor.
- Impacto: o operador de bancada pensa em cabo, switch, etiqueta e NVR. Parte dos termos é do `CONTEXT.md` e pode ficar se a tela os explicar uma vez. "ifIndex" e "DHIP" são termos de código e não ajudam a decidir nada.

**UX-10. A caixa do vigia sugere que o broadcast é opcional, e o risco fica escondido.** Severidade 2. H2, H5.
- Evidência: capturas `t1-painel-vigia-escuro.png` e `t1-painel-decisao-escuro.png`.
- Código: H:158. O rótulo é "Aceitar câmera de fábrica em qualquer faixa (broadcast)", mas o vigia sempre observa por broadcast (`CONTEXT.md`, Vigia). O aviso de risco ("na rede do escritório, só com a bancada isolada") está no `title` (dica ao passar o mouse) e no fim de um parágrafo de 3 linhas (J:968-970).
- Impacto: marcar a caixa com a bancada ligada à rede do escritório faz o painel configurar qualquer câmera de fábrica da rede. O alerta, que deveria estar colado na caixa, só aparece para quem para o mouse em cima dela.

### Controle e liberdade

**UX-11. Montar fila em Opções não confirma e não volta ao Painel.** Severidade 2. H1, H3.
- Evidência: `C2a.d3`.
- Código: o submit de `#form-fila` em Opções chama `comando('/api/fila')` (J:1635-1644) e fica na seção. "Montar outra fila" no fim da fila (H:209) e "Monte uma em Opções, seção Fila" (H:134) também tiram o operador do Painel.
- Impacto: o operador monta a fila e não vê o resultado. Volta ao Painel pelo menu e só lá descobre se deu certo. A fila é a tarefa central; montar uma nova não deveria exigir sair da tela da fila.

**UX-12. Opções e Encerrar o painel enterrados.** Severidade 3. H3, H7.
- Evidência: `C4b.d1`, `C4b.d2`. Captura `t1-painel-cartoes-claro.png`: o menu mostra Painel e Ferramentas, e Opções não aparece.
- Código: `.menu-opcoes { margin-top: auto }` (C:154) empurra Opções para o fim de uma coluna tão alta quanto a página (C:146). No Painel, o link fica a 1304 px do topo. Opções é uma página única de 2847 px (3,7 telas), e Encerrar o painel é a última seção (H:413-419).
- Impacto: Opções é o destino de três recuperações: falha de encoder (UX-14), placa que sumiu (J:479) e sem internet (J:542). Encerrar é a ação de todo fim de dia, a que devolve a placa ao DHCP. As duas pedem rolagem para serem achadas.

**UX-13. Botões de decisão escondidos ainda agem em câmera instalada.** Severidade 1. H3, H5.
- Evidência: observação técnica do cenário 3 na `linha-de-base.md`: um clique programático mandou "tentar de novo" para a câmera 1 já instalada, e o servidor aceitou.
- Código: os botões de decisão ficam no DOM do cartão instalado, só ocultos (J:830-841).
- Impacto: o operador não chega a eles com um clique normal. Fica como risco para a fase B, que reescreve os cartões: a decisão só deve existir em cartão em falha.

### Consistência e padrões

**UX-14. A mesma ação com nomes diferentes.** Severidade 2. H4.
- Evidência e código:
  - Senha: "Usar esta senha" (H:287), "Usar esta senha e avançar" (J:301), "Trocar a senha" (H:78).
  - Fila: "Montar a fila e avançar" (J:301), "Montar depois" (H:124), "Montar a fila ao começar" (H:116), "Montar fila" (H:405), "Montar outra fila" (H:209).
  - Gravar uma seção: "Avançar" no passo a passo, "Salvar placa", "Salvar rede", "Salvar faixa" e "Salvar câmera" em Opções (H:304-382).
  - Três "Atualizar" com objetos diferentes: "Atualizar o painel" (versão nova, H:26), "Atualizar registro" (H:220), "Atualizar lista" (placas, H:303).
  - Porta e canal: "Porta do switch" e "Canal no NVR" na bancada (H:172-173), "Porta" e "Canal" no cartão (J:719-723), "Rack / porta" no registro, sem canal (H:227, J:1533).
  - Começar: "Preparar placa e começar" no uso real e "Começar" em simulação (J:1464, H:126).
- Impacto: o vocabulário da tela é o mapa do operador. "Atualizar" no topo baixa um instalador e fecha o painel; "Atualizar" no registro só relê a tabela. Quem aprendeu um pode ter medo do outro, ou o contrário.

**UX-15. O âmbar não quer dizer nada.** Severidade 2. H4, H8.
- Evidência: todas as capturas. O âmbar marca a faixa de simulação, a borda do bloco do vigia, a posição "agora", a câmera em falha na fita, o selo "No portão", o cartão no portão e o botão principal ("Tentar de novo").
- Impacto: a cor deixa de distinguir "em curso", "atenção" e "ação". A câmera em falha e as câmeras andando têm a mesma cor na fita (UX-02). O tratamento visual é da Task 3; aqui conta que a cor não ajuda a ler o estado.

### Prevenção de erro

**UX-16. A sessão salva sugere uma fila que já está instalada.** Severidade 3. H5.
- Evidência: `C2a.d1`, `C2a.d2`.
- Código: a prévia da fila (J:939-948) só conta endereços e checa a ordem. Não diz quantos já estão no registro nem quantos ficam de fora (gateway, fora da rede). O erro só aparece depois de Usar e Começar, como aviso vermelho e "Sem fila montada".
- Impacto: é o caminho mais comum de quem volta à obra no dia seguinte. O dia começa com um erro vermelho, e o conserto (nova faixa em Opções) leva a UX-11 e UX-12.

**UX-17. A placa sugerida dispara um alerta de risco.** Severidade 2. H5, H4.
- Evidência: `C1.d1`.
- Código: J:1363-1365, um `confirm()` de 3 parágrafos que termina em "Usar essa placa mesmo assim?".
- Impacto: o painel sugere e, no mesmo clique, alerta contra a sugestão. O operador aprende a apertar OK em `confirm()` de risco sem ler, e isso vale para os outros 9.

**UX-18. Dois valores de bitrate para o mesmo campo.** Severidade 2. H5, H1.
- Evidência: `C1.d2`.
- Código: `desenharBitrates` e o campo "Outro valor…" (J:1266-1309).
- Impacto: o encoder vai igual para todas as câmeras da fila. O operador não sabe se grava 1596 ou 4096, nem se 1596 foi escolha de alguém.

**UX-19. Confirmações nativas genéricas, longas ou cruas.** Severidade 2. H5, H9.
- Evidência: os 10 `confirm()` listados na `linha-de-base.md`.
- Código: OK e Cancelar não nomeiam a ação. Textos de até 3 parágrafos (J:1363, J:1719-1722, J:1728-1737). J:1382 mostra num `confirm()` o texto do servidor como veio (`e.dados.erro`).
- Impacto: a decisão já tomada aceita `confirm()` nativo para ação destrutiva. O achado é sobre o uso: com 10 pontos, alguns longos e um com texto cru, a confirmação deixa de proteger. A direção decide se defende um diálogo próprio.

### Reconhecer em vez de lembrar

**UX-20. Começar abaixo da dobra no Resumo.** Severidade 2. H6.
- Evidência: `C1.d3`. Captura `t1-resumo-claro.png`.
- Código: rodapé do passo a passo (H:120-127), depois dos cartões do resumo.
- Impacto: a ação que fecha o passo a passo exige uma rolagem a 1366×768, a resolução-alvo.

### Eficiência

**UX-21. Dois começos na bancada sem critério de escolha.** Severidade 2. H7, H4.
- Evidência: `C1.d6`. Em simulação, Câmera conectada trouxe as 3 câmeras de uma vez.
- Código: vigia (H:149-162) e bancada pronta (H:166-177), um sobre o outro.
- Impacto: o vigia cobre o caso comum, de várias câmeras no switch. Câmera conectada vira uma segunda forma de fazer o mesmo, com o mesmo destaque na primeira vez. O operador não sabe qual é o caminho normal.

### Estética e minimalismo

**UX-22. Os cartões não escalam para N câmeras.** Severidade 3. H8, H7.
- Evidência: captura `t1-painel-cartoes-claro.png`. Com 3 câmeras, uma linha de cartões ocupa toda a largura e a altura útil da tela.
- Código:
  - Porta e Canal ocupam dois campos de altura cheia em todas as fases, inclusive instalada e sem posição (J:719-723, J:846).
  - O cartão "compacto" só reduz o espaço de baixo (C:393).
  - A ordem é por posição, sem agrupar por estado (J:856-863).
  - Não há limite de altura nem rolagem própria em `#cartoes`, e a fita não tem limite (J:593).
- Impacto: com 16 câmeras são 6 linhas de cartões, perto de 5 telas, e o registro embaixo. A câmera em falha fica na posição numérica dela, não no topo. Os cartões instalados, que já não pedem nada além da porta, pesam o mesmo que os que pedem decisão.

**UX-23. Instrução do vigia fixa na tela.** Severidade 1. H8.
- Evidência: capturas do vigia (3 linhas de texto, sempre visíveis).
- Código: J:966-975.
- Impacto: útil na primeira vez, ruído da segunda em diante. Ocupa a altura que os cartões precisam (UX-22).

**UX-24. Log aberto por padrão no Painel.** Severidade 1. H8.
- Evidência: inventário da Task 1 (Log: aberto só no Painel). Fica abaixo da bancada, fora das capturas a 1366×768.
- Código: J:250 abre o `details#log-bloco` ao entrar no Painel.
- Impacto: o log é ferramenta de diagnóstico. Aberto, disputa espaço com a bancada.

### Diagnosticar e recuperar de erros

**UX-25. O conserto de uma falha manda a um lugar que não se vê.** Severidade 3. H9, H6.
- Evidência: `C3.d3`. Captura `t1-painel-decisao-escuro.png`.
- Código: `textoDaFalha` para recusa de valor manda conferir "a seção Câmera em Opções" (J:917), sem link. O link Opções está fora da vista (UX-12).
- Impacto: quando a câmera recusa um valor do encoder, "Tentar de novo" com o mesmo valor falha de novo. O caminho certo (mudar o valor e tentar de novo) pede que o operador ache Opções, desça até Câmera, mude, volte ao Painel e ache o cartão.

**UX-26. Mensagem de falha crua e partida em dois blocos.** Severidade 2. H9.
- Evidência: `C3.d4`. Captura `t1-painel-decisao-escuro.png`: "Falhou na etapa encoder" e, numa caixa monoespaçada vermelha, "falha simulada: camera recusou o valor".
- Código: J:841-843 mostram `f.erro` do servidor como veio. `textoDaFalha` descreve o estado sem dizer o conserto nas etapas de inicialização, encoder e rede (J:921-924).
- Impacto: o operador lê duas frases para uma ideia, uma delas sem acento e com cara de log. O que fazer em seguida não está escrito.

**UX-27. Avisos do servidor crus, sem origem, e alguns somem em 4 s.** Severidade 2. H9.
- Evidência: `C2a.d1`: o aviso vermelho "Nenhuma posição livre nessa faixa (3 já no registro)" é texto do servidor repassado.
- Código: `comando()` repassa `e.message` (J:162-163). J:1170, J:1404, J:1536 e J:1579 jogam o erro no aviso do topo, sem dizer de qual ação veio. Resposta 409 vira aviso neutro que some em 4 s (J:147).
- Impacto: o operador olhando a bancada perde o aviso que sumiu. Quando lê, não sabe a que clique ele responde.

**UX-28. Modo de reserva sem instrução.** Severidade 3. H9, H10.
- Evidência: não reproduzido em simulação (o broadcast simulado sempre responde). Leitura de código e da tabela "Se algo der errado" do `LEIA-ME.md`.
- Código: "Sem broadcast: uma câmera por vez." (H:156, J:976) é todo o aviso.
- Impacto: no modo de reserva, o operador precisa ligar **uma câmera de fábrica por vez** no switch. Se ligar várias, elas disputam o mesmo IP de fábrica e o painel para com outro aviso. O que fazer (uma por vez; liberar a porta no firewall) está só na tabela "Se algo der errado" do `LEIA-ME.md`.

**UX-29. Conserto dos sintomas só no LEIA-ME.** Severidade 2. H10.
- Evidência: a tabela "Se algo der errado" do `LEIA-ME.md` tem 20 sintomas. Os textos que o painel mostra para "sem as faixas" (J:484), "Painel sem resposta" (J:386), "Desligado: erro interno (veja o log)" (J:29) e as recusas do servidor não apontam o conserto.
- Impacto: o LEIA-ME não está aberto na bancada. O painel sabe o que deu errado e não diz o que fazer.

### Estados vazio, carregando e erro

| Bloco | Vazio | Carregando | Erro | Achado |
|---|---|---|---|---|
| Fila | "Sem fila montada" e link para Opções (H:132-135) | — | Aviso no topo | UX-11 |
| Cartões | Nada: `#cartoes` some (J:885) | — | — | UX-30 |
| Registro | "Nenhuma câmera registrada ainda." (H:232) | Nenhum sinal; o botão não desabilita | Aviso cru; a tabela antiga fica (J:1536) | UX-32 |
| Placas | "Nenhuma placa de rede física encontrada. Conecte um adaptador…" (J:1418), bom | "Lendo as placas de rede…" (J:1412) | Fica em "Lendo…" para sempre (J:1404) | UX-31 |
| Ferramentas | "Nada encontrado… Confira o cabo e o PoE" (J:1025), bom | Título, progresso e botões desabilitados (J:1003-1007), bom | Só aviso do comando | — |
| Prévia da fila | Escondida até os dois IPs valerem (J:944) | — | Ordem e máximo, com conserto (J:947-948), bom | UX-16 |
| Resumo | — | "Carregando…" (J:1447) | — | — |
| Conexão com o servidor | — | — | "Painel sem resposta" só na barra da placa | UX-05 |

**UX-30. Vigia ligado sem câmera: a bancada não convida.** Severidade 2. H1, H6.
- Evidência: captura `t1-painel-vigia-escuro.png`.
- Código: sem cartões, `#cartoes` some (J:885). O único texto é o parágrafo do vigia.
- Impacto: o momento "vigia ligado, nenhuma câmera ainda" é o mais comum no início de cada fila. A tela não diz que está esperando nem que uma câmera recém-ligada leva cerca de um minuto para responder, como diz o `LEIA-ME.md`. O operador não sabe se o painel está trabalhando.

**UX-31. A lista de placas fica em "Lendo…" quando a leitura falha.** Severidade 2. H9.
- Evidência: inventário da Task 1 (passo 2, `ul#placas`). A leitura que falha não foi reproduzida; leitura de código.
- Código: J:1404 joga o erro no aviso do topo e a lista segue em "Lendo as placas de rede…" (J:1412). "Atualizar lista" não desabilita nem mostra que está lendo (J:1661).
- Impacto: no passo 2, sem placa não se avança. O operador espera uma leitura que já falhou.

**UX-32. Registro sem sinal de leitura e com dado velho em erro.** Severidade 1. H1.
- Evidência: registro visto no cenário 2a. A leitura que falha não foi reproduzida; leitura de código.
- Código: `carregarRegistro` (J:1517-1536).
- Impacto: depois de "Atualizar registro", a tabela pode ser a antiga sem nada que diga isso.

**UX-33. Tabela do registro quebra palavras no meio.** Severidade 1. H8.
- Evidência: `C2a.d4` ("SIMULA / DA", "Instalad / a", "exempl / o").
- Impacto: leitura lenta do relatório na tela. O tratamento é da Task 3.

### Estados de fim

**UX-34. Fila encerrada se diz concluída e pendente ao mesmo tempo.** Severidade 2. H1, H4.
- Evidência: `C4a.d1`, `C4a.d2`.
- Código: o motivo do vigia vem do servidor e é traduzido por `MOTIVO_VIGIA` (J:27-32); o bloco de fim o repete (J:648). O resumo segue contando pendentes (J:589).
- Impacto: o operador não sabe se a fila acabou bem ou foi cortada, e o que fica para o relatório.

**UX-35. Tela de encerrado segue consultando o servidor.** Severidade 1. H1.
- Evidência: `C4b.d3`.
- Código: `mostrarTelaFim` (J:370-374) não para o `ciclo()` (J:1773-1777), e a rolagem anterior fica.
- Impacto: invisível para o operador, mas a página fica tentando um servidor que ele mesmo encerrou.

### Arquitetura de informação

**UX-36. Opções mistura editar a sessão com o ciclo do painel.** Severidade 2. H4, H7.
- Evidência: `C4b.d2`: Encerrar o painel na última seção de Opções, a 2648 px.
- Código: a página Opções (H:273-427) junta 6 seções de sessão, Restaurar DHCP, Refazer o passo a passo, Encerrar o painel, a versão e o tema.
- Impacto: Encerrar e Restaurar DHCP são ações do dia de trabalho, ao lado de tema e versão. Ver UX-12.

**UX-37. Passo a passo e Opções: mesmo formulário, textos diferentes.** Severidade 1. H4.
- Evidência: inventário da Task 1: as seções de Opções usam os mesmos renders do passo a passo.
- Código: os 6 formulários existem uma vez e são movidos entre os dois lugares (`slotDe` J:275-279, `montarPasso` J:291-295, `montarOpcoes` J:328-336). Os títulos e as explicações são duplicados e diferentes: `h2` e `p.explica` no passo a passo (H:69-108), `h3` e `p.apoio` em Opções (H:274-391). Os botões também mudam de nome (UX-14).
- Impacto: a base técnica está certa, uma fonte só por campo. O operador lê duas explicações diferentes para o mesmo campo, e quem mantém o painel tem duas para manter.

**UX-38. Ferramentas no menu com o peso de Painel.** Severidade 1. H8.
- Evidência: `C4b.d1`. Captura `t1-painel-cartoes-claro.png`: o menu mostra Ferramentas e não mostra Opções.
- Código: menu (H:46-48).
- Impacto: Sondar, Procurar e Verificar são diagnóstico ocasional. Ocupam a segunda posição do menu, enquanto Opções, que entra em três recuperações e no fim do dia, fica fora da vista (UX-12).

**Resposta às perguntas da Task.**
- **As 3 abas e o passo a passo fazem sentido?** O passo a passo, sim: ele monta a sessão uma vez e, com sessão salva, vira 3 cliques. As abas não refletem a frequência de uso. Painel é o lugar de quase todo o trabalho. Opções junta edição rara (sessão) com ação diária (encerrar) e é a saída de três recuperações. Ferramentas é rara e está em destaque (UX-12, UX-36, UX-38).
- **As Opções duplicam o passo a passo?** Os campos, não: são os mesmos formulários. Os textos e os nomes das ações, sim (UX-14, UX-37). O que falta em Opções é o vínculo com o Painel: mudar a fila ou o encoder no meio do trabalho tira o operador da bancada (UX-11, UX-25).

### Carga do vigia e dos cartões com N câmeras

Contas a partir da captura `t1-painel-cartoes-claro.png` (3 cartões por linha a 1366 px, cerca de 280 px de altura cada) e do código citado em UX-22:

| Câmeras | Linhas de cartões | Altura dos cartões | Onde fica a câmera em falha |
|---|---|---|---|
| 3 | 1 | cerca de 0,4 tela | visível |
| 8 | 3 | cerca de 1,1 tela | pode ficar fora da vista |
| 16 | 6 | cerca de 2,2 telas, mais vigia, fita e bancada: perto de 5 telas até o registro | quase sempre fora da vista |

O vigia mostra seu estado por uma luz, a palavra "ligado" ou "desligado" e o parágrafo (J:960-975). O motivo de desligar aparece no começo do parágrafo ("Desligado: fila concluída."). O modo de reserva é uma linha solta (UX-28). Com N câmeras, o que o operador precisa ver o tempo todo é: quantas faltam, quais esperam decisão e quais pedem porta e canal. Hoje isso está espalhado entre a fita, o resumo e os cartões, e o resumo erra a conta (UX-02).

## Escrita (skill `frontend-design`)

O que a seção de escrita da skill pede e onde o painel falha:

| Regra da skill | Situação no painel | Achados |
|---|---|---|
| O botão diz exatamente o que acontece, com verbo | "Câmera conectada" (H:174) é um estado, não uma ação. "Alterar" no Resumo (J:1449) não diz o quê. "Atualizar" sozinho tem três sentidos. "Pular esta posição" não diz que a câmera fica registrada como falha (isso só aparece no `confirm()`). | UX-14, UX-39 |
| A mesma ação tem o mesmo nome no fluxo inteiro, e a confirmação repete o nome | Montar a fila tem 5 nomes. "Montar fila" em Opções não confirma nada (sem "Fila montada"). | UX-11, UX-14 |
| O erro diz o que houve e como consertar, na voz da interface | Bons exemplos: J:947, J:948, J:1025, J:1076, J:1238, J:479, J:542. Ruins: J:484, J:386, J:841-843, J:921-924, J:1768, e todo erro do servidor repassado cru. | UX-01, UX-26, UX-27, UX-29 |
| O vazio é um convite à ação | "Sem fila montada" convida, mas manda para outra tela. Cartões vazios com o vigia ligado não dizem nada. "Nenhuma câmera registrada ainda." está bem para um registro. | UX-11, UX-30 |
| Caixa de frase, sem enchimento, nomes do usuário e não do sistema | Caixa de frase está bem, e não há caixa alta. "instalada(s)" e "pendente(s)" (J:589) são plural preguiçoso. "ifIndex", "DHIP" e textos sem acento do servidor são nomes do sistema. | UX-09, UX-40 |

**UX-39. Rótulos de botão que não dizem a ação.** Severidade 2. H2, H4.
- Evidência: `C1.d6` (Câmera conectada). Captura `t1-resumo-claro.png` (Alterar em cada cartão).
- Código: "Câmera conectada" (H:174), "Alterar" (J:1449), "Atualizar lista", "Atualizar registro", "Atualizar o painel" (H:303, H:220, H:26), "Pular esta posição" (H:202, J:715).
- Impacto: o operador precisa clicar ou ler o `confirm()` para saber o que o botão faz.

**UX-40. Plural preguiçoso e texto sem acento.** Severidade 1. H4.
- Evidência: captura `t1-painel-decisao-escuro.png`: "2 instalada(s), 0 pendente(s)" e "falha simulada: camera recusou o valor".
- Código: J:589 ("instalada(s)", "pendente(s)"). Textos do servidor sem acento na barra do topo ("camera de fabrica", "conferencia"), na falha ("camera recusou o valor") e nas recusas.
- Impacto: a tela parece log. Em pt-BR, o texto sem acento lê como erro de sistema, não como frase do painel.

**O que da skill foi aplicado e o que ficou de fora.**
- Aplicado: toda a seção de escrita (as cinco regras da tabela acima) e a ideia de que a estrutura visual é informação, usada em UX-15 (cor sem significado) e UX-22 (cartão instalado com o mesmo peso do cartão em falha).
- Descartado: herói, tipografia de destaque, plano de paleta, layout em wireframe e o processo em duas passadas de construção. Isso é direção e protótipo (Tasks 4 e 5), e o herói está nos Non-Goals da frente.

## Os 5 problemas de maior impacto

1. **A falha não é vista fora do cartão, e o conserto manda a um lugar escondido** (UX-02, UX-25, UX-12). A fita diz "agora", o resumo não conta a falha, e o texto manda a Opções, que fica fora da vista. A câmera que mais precisa do operador é a mais difícil de achar e de resolver.
2. **O vermelho do topo é ruído permanente** (UX-01, UX-29). A barra da placa fica vermelha do passo 1 em diante, com texto técnico e sem conserto. O alarme que devia parar o operador vira paisagem, e o caso real (placa sem faixa, sem Administrador) passa sem ser notado.
3. **Voltar à obra com a sessão salva começa por um erro** (UX-16, UX-11). A sessão sugere a fila já instalada, o erro só aparece depois de Começar, e o conserto tira o operador do Painel sem confirmar nada. É o caminho de todo segundo dia.
4. **A bancada não escala para N câmeras** (UX-22, UX-30, UX-23). Cartões altos, Porta e Canal sempre abertos, sem agrupar por estado, sem limite. Com 16 câmeras são perto de 5 telas, e a câmera em falha some no meio.
5. **O vocabulário e o desenho das ações não se sustentam** (UX-14, UX-03, UX-21, UX-36). A mesma ação tem nomes diferentes, há dois começos na bancada, e Encerrar e Restaurar DHCP moram ao lado do tema. O operador não forma um mapa estável do painel.
