# Configurar Câmeras Intelbras — painel de campo

Painel web local que leva câmeras IP Intelbras (base Dahua) de fábrica a
instaladas, várias ao mesmo tempo, ligadas no mesmo switch: cria o `admin`,
grava a recuperação de senha **apenas por e-mail**, ajusta o encoder dos dois
streams, grava IP/máscara/gateway/DNS, confere lendo de volta e registra cada
câmera. Tudo roda neste PC; nada vai para a internet.

Validado em câmera real: **VIP-1230-D-G3** (firmware 2.800). A VIP-5460-Z-IA foi
validada só na versão antiga em CGI (veja Pendências).

---

## Requisitos

| Requisito | Situação |
|---|---|
| Windows 10 (1803 ou mais novo) ou Windows 11 | traz `curl.exe` e PowerShell 5.1, que é tudo o que o painel usa |
| Administrador local | pedido uma vez, ao abrir: preparar a placa de rede e prender a câmera no IP de fábrica exigem. Sem ele, o painel fica no modo de reserva: uma câmera por vez |
| Placa de rede ligada ao switch das câmeras | Ethernet ou Wi-Fi; a Ethernet com cabo vem sugerida em primeiro. USB-Ethernet serve |
| Switch com PoE para as câmeras | ou um injetor PoE por câmera, na saída **P+D** |
| Porta UDP 37810 liberada no firewall do PC | é por ela que o broadcast (DHIP) distingue as câmeras de fábrica, todas no mesmo IP. Sem resposta do broadcast, o painel fica no modo de reserva: uma câmera por vez |
| Microsoft Edge | opcional; sem ele o painel abre no navegador padrão |

O painel roda `powershell.exe -ExecutionPolicy Bypass`. Se a empresa trava isso por
GPO (ExecutionPolicy `AllSigned` forçada ou modo FIPS), peça exceção para a pasta
do painel antes de instalar.

## Instalar

**Com o instalador (recomendado):** baixe o `ConfigurarCameras-<versão>-instalador.exe`
da última versão em <https://github.com/xyron-robotics/ConfigurarCameras/releases>,
aceite o pedido de Administrador e siga. Ele instala em `C:\Program Files\ConfigurarCameras`
e cria o atalho **Configurar Câmeras** no Menu Iniciar (e na área de trabalho, se
marcado). Desinstalar pelo Windows remove só o programa: o registro e a sessão
ficam em `%ProgramData%\ConfigurarCameras`.

**Sem instalador:** copie a pasta `fonte\` inteira para o PC e dê duplo clique em
`fonte\INICIAR-PAINEL.vbs`. Funciona de qualquer pasta, inclusive pen drive.

## Primeiro uso: o passo a passo

Abra o painel pelo atalho (ou pelo `.vbs`). Só o pedido do Windows e a janela
do painel aparecem: nenhuma janela preta. Com o painel já aberto, o atalho só
reabre a janela dele. Aceite o pedido do Windows (preparar a placa de rede
exige Administrador).

Toda abertura começa pelo **passo a passo**, seis passos, um depois do
outro, que montam a **sessão** de trabalho. A trilha no alto mostra os seis;
o rodapé tem **Voltar** e **Avançar** (no último, **Começar**). Com uma
sessão guardada da última vez, o painel abre direto em **Conferir**, com a
senha na primeira linha.

1. **Senha**: digitada duas vezes, **Salvar a senha**. Vira a senha do
   `admin` de cada câmera configurada nesta sessão. Fica só na memória do
   painel: nunca vai para disco, log, registro ou relatório, e é pedida de
   novo a cada abertura. Em simulação o passo diz "Senha não usada em
   simulação".
2. **Placa**: a placa deste PC ligada à bancada ou ao switch das
   câmeras (Ethernet ou Wi-Fi; a sugerida já vem marcada).
   **Só ela é usada**: é por ela que o painel procura a câmera, dá os
   endereços ao PC e confere a câmera no IP novo. Um endereço igual noutra
   placa do PC não conta. A placa que leva à internet ganha uma nota na
   própria linha: ao começar, a rede pisca por alguns segundos e a internet
   é testada depois. Se a leitura das placas falhar, **Ler as placas de
   novo**.
3. **Rede**: máscara, gateway e DNS gravados em cada câmera (a rede do NVR;
   o gateway vem vazio, é da obra) e, opcional, o IP do PC nessa rede
   (vazio = `.200` a `.249`, derivado do MAC da placa). A **faixa de
   fábrica** fica recolhida embaixo, com o resumo e **Alterar**: onde a
   câmera nova aparece (`192.168.1.108`) e, opcional, o IP do PC nessa
   faixa (vazio = `.220`). Precisa ser diferente da rede das câmeras.
4. **Câmera**: e-mail de recuperação (única forma de recuperar a senha do
   admin: use um e-mail da empresa; vem vazio) e encoder dos dois streams (resolução,
   fps, bitrate, codec; o GOP é gravado como o dobro do fps). Fps e bitrate
   são listas de valores prontos, com **Outro valor…** para abrir o campo e
   digitar um número fora dela; a de bitrate segue a resolução e o codec do
   stream e vem com o recomendado selecionado. Resolução e codec dizem se já foram testados em câmera
   real. **Por que isso importa** explica o GOP e o H.265. A câmera recebe
   o encoder em duas gravações: primeiro resolução, fps e codec; depois
   bitrate e GOP.
5. **Fila**: primeiro e último IP, local, rack e andar. A prévia diz quantas
   posições a faixa tem e quantas já estão no registro; a última fila volta
   preenchida como sugestão.
6. **Conferir**: uma linha por seção, cada uma com **Alterar a senha**,
   **Alterar a placa** e assim por diante. Se todas as posições da fila já
   estão no registro como instaladas, a linha da Fila diz isso e oferece
   **Usar a faixa seguinte**. **Começar** acrescenta à placa escolhida dois
   endereços (um na faixa de fábrica, um na rede das câmeras), sem tirar
   nenhum, testa a internet, monta a fila e abre o Painel. **Ao encerrar o
   painel a placa volta ao DHCP sozinha**.

Depois disso o painel tem um topo fixo com três abas, **Painel** (fila,
bancada, vigia e o registro), **Sessão** e **Ferramentas**, os chips da
placa e da internet (e o de simulação, quando é o caso) e **Encerrar o
painel**. Cada chip abre um quadro com o detalhe; o da placa tem **Preparar
a placa** e **Restaurar o DHCP**. A aba **Sessão** (antes chamada Opções)
mostra uma seção por vez (Senha, Placa, Rede, Câmera, Fila e, separada,
Painel), cada uma com **Salvar alterações**, que confirma com "Alterações
salvas.". Trocar a placa ou as faixas em Sessão devolve a placa e a prepara
de novo; se há fila montada, pede confirmação e a fila continua se a faixa
ainda cabe na rede nova. A seção Painel tem o tema (Sistema, Claro, Escuro),
a versão e **Refazer o passo a passo**.

## Fila

Monte a fila no passo 5 ou em **Sessão > Fila** (primeiro e último IP,
**Montar a fila**). Gateway, endereços fora da rede e IPs com câmera instalada
no registro ficam de fora (câmera que falhou não ocupa a posição; se ela
ainda responde no IP, o ping na hora de usar a posição pula); uma faixa sem
posição livre é recusada.

1. **Ligue o vigia** (desligado por padrão). Ligado, ele mostra: "Observando
   <IP> por broadcast. Ligue quantas câmeras quiser no switch: cada uma entra
   na próxima posição livre. Digite porta e canal no cartão de cada câmera,
   pelo serial da etiqueta." O vigia procura pelo broadcast DHIP na placa
   escolhida. A caixa **Aceitar câmera de fábrica em qualquer faixa
   (broadcast)** faz ele aceitar também câmera de fábrica fora do IP de
   fábrica (a placa recebe um IP temporário na rede dela e, se a faixa for de
   outra placa do PC, uma rota de host): use só com a bancada isolada da rede
   do escritório, senão qualquer câmera de fábrica da rede entra na fila.
2. **Ligue as câmeras no switch**, quantas quiser. Cada uma recebe a próxima
   posição livre quando entra no portão do IP de fábrica, na ordem em que
   aparece no broadcast, que não é a ordem do cabo. Uma câmera recém-ligada
   pode levar cerca de um minuto para responder ao broadcast.
3. **Cada câmera tem um cartão** na bancada, com posição, modelo, serial,
   MAC, destino e o estado: "Na espera", "No portão", "Conferindo",
   "Falhou", "Instalada", "Pulada" ou "Já inicializada: não tocada". Digite
   "Porta" e "Canal" no cartão da câmera certa, conferindo o serial da
   etiqueta; o cartão mostra "Salvo" quando o painel recebe. Os dois campos
   ficam editáveis até a fila fechar, inclusive depois de "Instalada" (o
   registro é atualizado); câmera pulada ou já inicializada não tem porta nem
   canal.
4. **Portão e conferência.** Uma câmera por vez passa pelo portão do IP de
   fábrica: o painel a prende pelo MAC (um vizinho estático na placa
   escolhida, que sai quando ela sai) e faz, nesta ordem, inicialização →
   encoder → rede. Ao gravar a rede, a câmera reinicia no IP novo e o portão
   passa à próxima. A conferência no IP novo (espera do boot até 120 s, com
   contagem no cartão) roda em paralelo, para quantas câmeras houver, e nunca
   consulta o IP de fábrica. Câmera com porta HTTP diferente de 80 (anunciada
   no broadcast) é atendida nela.
5. **Falha** numa câmera abre a decisão só no cartão dela, com a etapa e o
   motivo, e os botões "Tentar de novo" e "Pular esta posição"; as outras
   seguem, e o vigia continua. "Tentar de novo" continua da etapa que falhou
   (quem falhou na conferência volta direto a ela, sem passar pelo portão).
   Pular deixa a câmera como está, registrada como falha, e a posição fica
   pulada. Se a câmera recusou a senha, "Tentar de novo" fica travado até uma
   senha nova: repetir a senha errada bloqueia o `admin` da câmera por
   minutos.
6. **"Encerrar a fila"**, botão da fila, para de admitir câmeras: as que
   estão no portão ou conferindo terminam, e as que estão em decisão ainda
   podem tentar de novo. As posições pendentes ficam sem câmera.

Uma câmera **já inicializada** que aparece no broadcast fica no cartão como
"Já inicializada: não tocada": o painel não faz login nela. O vigia desliga
sozinho quando a fila acaba ou é encerrada, e depois de 5 rodadas seguidas
vendo câmera sem poder configurar (sem posição livre, por exemplo).

**Modo de reserva: uma câmera por vez.** Sem resposta do broadcast (em geral,
a porta UDP 37810 fechada no firewall do PC), o painel não distingue as
câmeras de fábrica, todas no mesmo IP: passa a configurar uma por vez, pelo IP
de fábrica, e o vigia mostra "Sem broadcast: uma câmera por vez.". Sem
Administrador, o painel não põe o vizinho estático e também fica numa câmera
por vez desde a montagem da fila. Nos dois casos o painel avisa; ligue uma
câmera de fábrica por vez no switch até resolver.

**Sem o vigia:** **Câmera conectada** procura câmeras de fábrica uma vez, na
hora; as que aparecem seguem como com o vigia. **Retomar câmera já
inicializada** serve para uma câmera que já recebeu a senha desta sessão (por
exemplo, depois de uma falha com o painel fechado): informe o IP em que ela
responde agora. A retomada é uma câmera por vez e só começa com nenhuma
câmera no portão ou conferindo.

Uma câmera **instalada** nunca é reconfigurada. Para refazer, volte a câmera
de fábrica pela tela dela (Configuração > Sistema > Padrão de fábrica) ou pelo
botão físico; ela reaparece como câmera de fábrica, e ao ser configurada de
novo a entrada antiga do registro é substituída e o IP antigo fica livre.

## Registro e relatório

O **Registro**, embaixo da fila no Painel, lista cada câmera que passou pelo
painel (pelo MAC): IP, modelo, situação (em andamento, instalada, falhou),
encoder, local, rack/porta e data. **Exportar relatório** gera o CSV. Os
dados ficam em `%ProgramData%\ConfigurarCameras` (`registro.json`,
`sessao.json`, `log.txt` e, enquanto a placa está preparada,
`placa-sessao.json`, o rastro do que o painel fez nela): é a única cópia,
faça backup. Na primeira abertura da 1.2.0, `padroes.json` e
`ultima-fila.json` de versões anteriores viram `sessao.json` (os antigos ficam
como `.migrado`). Para usar outra pasta: `Servidor-Painel.ps1 -PastaDados
D:\obra`. Sem permissão de escrita em ProgramData o painel usa
`%LOCALAPPDATA%\ConfigurarCameras` e avisa no quadro do chip da placa.

## Ferramentas

| Ferramenta | O que faz |
|---|---|
| **Sondar** | lê uma câmera pelo IP: estado, modelo, serial, MAC, rede e encoder. Não altera nada |
| **Procurar** | broadcast DHIP pela placa escolhida (responde de qualquer faixa, com IP, máscara, MAC, modelo, serial, firmware e porta) e, se nada vier, varredura por ping. Lista câmeras de fábrica, já inicializadas, NVRs e controladores. "De fábrica" fora das faixas da placa é o que a câmera anunciou; o painel confirma por HTTP antes de configurar |
| **Verificar** | faz login em cada câmera instalada do registro e confere IP e MAC. Para na primeira senha recusada |

Não há reset pelo painel: nenhuma chamada por RPC faz reset de fábrica
completo neste firmware (a VIP-1230-D-G3 2.800 só restaura configurações e
mantém senha e rede). Use a tela da câmera ou o botão físico.

**Simulação** (sem tela): `Servidor-Painel.ps1 -Simular` ensaia a fila
inteira sem câmera, com registro separado; nada vai para câmera nem para a
placa. Serve para diagnóstico e para os testes. Ligada, o topo mostra o chip
**Simulação**.

**Encerrar o painel**, no topo, pede confirmação, fecha o servidor e devolve a placa de rede ao
estado de antes (DHCP, endereços, rotas de host e rota que o painel pôs saem);
a fila em memória se perde, o registro e a sessão ficam. Com câmera no portão
ou conferindo, o painel recusa encerrar e pede para esperar as câmeras
terminarem; se ele fechar mesmo assim com câmera em curso, espera cada uma
terminar (até 3 minutos) antes de devolver a placa. Fechar só a janela do
navegador não encerra: o painel continua
e, depois de 3 minutos sem a página e sem nada em curso (câmera sendo
configurada, decisão pendente, vigia ligado), encerra sozinho e devolve a placa.
Para voltar antes disso, abra o atalho de novo. Se o processo for morto no meio,
a placa fica preparada e o próximo painel avisa e devolve ao encerrar.

## Versões e atualização

A versão do painel aparece em **Sessão > Painel** e vem de
`VERSAO.txt`. Cada versão é publicada em
<https://github.com/xyron-robotics/ConfigurarCameras/releases>: o instalador e o
`.sha256` dele são gerados pelo GitHub Actions a partir da tag `vX.Y.Z` (que
precisa bater com `VERSAO.txt`), depois de os testes passarem. Instalar uma
versão nova por cima mantém o registro e a sessão.

**Atualizar pelo painel:** uma vez por dia (10 s depois de abrir) o painel
consulta o GitHub. Havendo versão mais nova, aparece a faixa "Versão X
disponível" com o botão **Atualizar** e o link "o que mudou". Atualizar baixa o
instalador, confere o SHA-256 publicado e o tamanho, fecha o painel (a placa
volta ao DHCP), instala em silêncio e reabre o painel na versão nova (a sessão e o registro ficam). Só com o
painel parado: sem câmera no portão ou conferindo, vigia desligado, e aberto
como Administrador. Com câmera em curso, o painel recusa e pede para esperar
as câmeras terminarem; durante o download nenhuma câmera nova começa, e se
uma tiver começado mesmo assim, nada é instalado até ela terminar. Sem internet (ou só com proxy) a
consulta falha em silêncio e tenta no dia seguinte; o aviso da última consulta
fica guardado. O instalador silencioso grava `instalador.log` na pasta de dados.
Se o SHA-256 não conferir, nada é instalado e a faixa diz o motivo.

## Segurança

- A senha da sessão fica só na memória do worker do painel. Não vai para
  registro, relatório, log nem resposta HTTP. O Edge abre InPrivate.
- O painel só escuta em `127.0.0.1`, numa porta escolhida na hora, e recusa
  requisições de outra origem.
- Câmera Dahua bloqueia o `admin` depois de cerca de 5 senhas erradas. O painel
  nunca repete um login recusado: troque a senha antes de tentar de novo.
- A recuperação de senha gravada na câmera é só por e-mail (o da seção Câmera
  da sessão).

## Se algo der errado

| Sintoma | O que fazer |
|---|---|
| O painel não abre, ou abre uma caixa de erro | a caixa diz o motivo. Para o detalhe, abra pelo `INICIAR-PAINEL-COM-CONSOLE.bat`: a mensagem fica na tela até apertar Enter |
| O atalho não faz nada | o painel já está aberto: a janela dele é reaberta. Se não aparecer, apague `painel.json` na pasta de dados e tente de novo (ou a empresa bloqueia o `wscript.exe`: use o `.bat`) |
| Chip "Placa sem as faixas" no topo | abra o chip e clique em **Preparar a placa**; se não resolver, o painel está sem Administrador (feche e abra de novo aceitando o UAC) |
| Chip "Placa ausente" ("não está mais neste PC") | a placa escolhida sumiu (USB desconectado, renumerada): escolha outra em **Sessão > Placa** |
| Câmera na bancada não aparece, mas responde pelo Wi-Fi | a placa escolhida é a errada, ou a câmera está numa faixa que o Wi-Fi também tem: confira a placa em **Sessão > Placa**. Se o IP dela cai na faixa de outra placa, o painel põe um IP temporário e uma rota de host na placa escolhida ao configurar |
| Câmera não responde ao ping | cabo, injetor PoE sem energia ou porta errada do injetor (saída **P+D**) |
| Procurar diz "0 respostas" ao broadcast | um firewall no PC está barrando UDP de entrada (porta 37810). O painel ainda acha pelo IP de fábrica e pela varredura; libere o `powershell.exe` no firewall para o broadcast voltar |
| Aviso de que o broadcast não responde, e o vigia em "Sem broadcast: uma câmera por vez." | o firewall do PC barra a porta UDP 37810, ou a placa perdeu o IP da faixa de fábrica (clique em **Preparar a placa**, no chip da placa). Enquanto isso o painel fica no modo de reserva: ligue uma câmera de fábrica por vez no switch. Libere o `powershell.exe` no firewall para UDP 37810; com o broadcast de volta, as câmeras voltam a andar em paralelo sozinhas |
| Aviso de que duas câmeras respondem em 192.168.1.108 | há mais de uma câmera de fábrica no switch e o broadcast não responde, então o painel não sabe qual está atendendo. Deixe ligada só a câmera de fábrica que vai ser configurada agora (as já instaladas podem ficar) e libere a porta UDP 37810, como na linha acima |
| Aviso de que o painel está sem Administrador e vai uma câmera por vez | o pedido do Windows foi recusado: sem Administrador o painel não põe o vizinho estático nem prepara a placa, e fica no modo de reserva. Encerre o painel e abra pelo atalho aceitando o pedido |
| "fora das faixas do PC" na lista | a câmera está noutra rede; ao configurar, a placa recebe um IP temporário nessa rede (sai no **Restaurar o DHCP** / ao encerrar) |
| `senha recusada pela camera` | a câmera já tem outra senha. Não insista: troque a senha em **Sessão > Senha** ou volte a câmera de fábrica pela tela dela |
| `camera recusou o encoder no passo N` | a câmera não aceitou o que o passo grava (passo 1: resolução, fps ou codec; passo 2: bitrate ou GOP). O log mostra o encoder lido antes. Volte a um valor marcado "(testado)" em **Sessão > Câmera** e **Tentar de novo** |
| `conta admin BLOQUEADA` | espere alguns minutos; depois confirme a senha certa antes de qualquer tentativa |
| PC ficou sem internet depois de preparar a placa | o chip "Sem internet" diz, no quadro dele, que a internet caiu depois que o painel preparou a placa. **Restaurar o DHCP**, no chip da placa, devolve na hora; encerrar o painel também. Se nada disso resolver: `ncpa.cpl` > placa > IPv4 > "Obter um endereço IP automaticamente" |
| Chip "Sem internet", mas o navegador navega | a rede só sai por proxy; o teste do painel (`curl.exe`) não usa proxy. Pode ignorar |
| "ficou preparada desde a última vez" ao abrir | o painel anterior foi fechado no X. Nada a fazer: ela volta ao DHCP ao encerrar (ou em **Restaurar o DHCP**, no chip da placa) |
| A faixa de atualização diz "SHA-256 não confere" | o download veio diferente do publicado (proxy que troca conteúdo, download interrompido). Nada foi instalado; tente de novo ou baixe pelo navegador na página de releases |
| Atualizou e o painel não reabriu | abra pelo atalho. O que o instalador fez está em `instalador.log` na pasta de dados |
| O painel abre sempre no passo a passo | é assim: com uma sessão guardada, cada abertura vai direto a **Conferir**, que pede a senha na primeira linha. Se abre num passo, a sessão ficou incompleta (placa que sumiu, campo inválido): é o passo que falta |

O `log.txt` na pasta de dados guarda tudo com data e hora. É o primeiro lugar a olhar.

## Pendências

- **VIP-5460-Z-IA** ainda não validada pelo painel (RPC2). O CLI antigo em CGI
  que a validou saiu do repositório em 30/09/2026 e está no histórico do git
  (commit `a638fce` e anteriores).
- **Reset de fábrica** por RPC não existe neste firmware (só o parcial, que
  mantém senha e rede): o painel não tem mais reset. Ver
  `fonte\API-INTELBRAS.md`, "Reset de fábrica".
- **Rota de host** (câmera na faixa de outra placa do PC): validada por teste
  unitário e pelo contorno manual de 01/10/2026; ainda não vista pelo painel
  numa câmera de fábrica real.
- Stream secundário validado só em `704 × 480` (H.264 e H.265). A
  VIP-1230-D-G3 **recusa** `1280 × 720` no secundário (02/10/2026): a lista
  mostra "(recusado na VIP-1230-D-G3)". `352 × 240` e `640 × 480` seguem a
  nomenclatura Dahua sem teste.
- **Modo paralelo** sem rodada em câmera real: o broadcast DHIP, o ARP, o
  vizinho estático, a conferência em paralelo e o modo sem Administrador só
  têm prova em simulação e na bancada de 17/11/2026, feita sem o painel. Falta
  uma rodada com 2 a 3 câmeras de fábrica reais do começo ao fim.
- **Vigia** e a **contagem do boot real** ainda não foram usados em campo pelo
  painel (o vigia mudou para o modo paralelo).
- **Descoberta DHIP**: validada com 33 aparelhos já inicializados (01/10/2026),
  inclusive dois com porta HTTP 8081. Em 17/11/2026, na bancada, o broadcast
  listou 3 câmeras de fábrica no mesmo IP, com MACs distintos e `Init` de
  fábrica. O **IP temporário** na placa, posto pelo painel, ainda não foi
  visto ao vivo.
- **Assinatura de código**: o instalador não é assinado; baixado pelo
  navegador, o SmartScreen pode avisar (pelo painel não, o `curl.exe` não grava
  a marca da web). Assinar exige um certificado.
- Achados baixos da revisão de 30/09 não feitos: sem retentativa automática no
  tique do vigia; arquivos temporários `rpc-*.json` ficam em `%TEMP%`; a
  bandeira `admin` do estado não é mostrada na página; sem teste automático do
  servidor HTTP (só em simulação, pela API).

## Desenvolvimento

```
LEIA-ME.md                  este arquivo
CONTEXT.md                  glossário do domínio
docs/adr/                   decisões de arquitetura
fonte/VERSAO.txt            versão do painel (única fonte: painel, instalador e tag)
fonte/Motor-Cameras.ps1     tudo o que fala com a câmera e com a placa de rede
fonte/Orquestrador-Cameras.ps1   fases de cada câmera, portão e admissão na fila (funções puras)
fonte/Coordenador-Cameras.ps1    executa o que o orquestrador decide: vigia paralelo, vizinho estático, jobs por câmera
fonte/web/Servidor-Painel.ps1 + web/www/   o painel (HttpListener + página)
fonte/INICIAR-PAINEL.vbs    abre o painel sem console (atalho do instalador)
fonte/INICIAR-PAINEL-COM-CONSOLE.bat   o mesmo, com console (diagnóstico)
fonte/Testes-Motor.ps1      testes do motor (sessão, placa escolhida, rede, fila, registro), sem câmera nem rede
fonte/Testes-Descoberta.ps1 testes das funções puras de descoberta (inclui DHIP)
fonte/Testes-Orquestrador.ps1   testes das fases, do portão e da admissão
fonte/Testes-Coordenador.ps1    testes do coordenador, com rede e jobs falsos
fonte/API-INTELBRAS.md      protocolo da câmera, o que foi visto ao vivo
fonte/testes/               tabelas lidas da VIP-1230-D-G3 e respostas DHIP (MAC, série e IPs trocados por exemplos)
fonte/testes/Smoke-Paralelo.ps1   smoke do painel em simulação, fora do CI e do instalador
instalador/                 ConfigurarCameras.iss + Gerar-Instalador.ps1 (Inno Setup 6); icone.ico (Gerar-Icone.ps1)
.github/workflows/release.yml   tag v* -> testes, instalador e release no GitHub
```

Publicar uma versão: ajuste `fonte\VERSAO.txt`, commit, `git tag vX.Y.Z` e
`git push origin vX.Y.Z`; o Actions gera o instalador e o release.

Rodar os testes (PowerShell 5.1, na raiz do repo; a contagem sai na tela):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Motor.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Descoberta.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Orquestrador.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\Testes-Coordenador.ps1
git diff --check
```

**Simulação para desenvolver:** `Servidor-Painel.ps1 -Simular` aceita
`-SimularCameras` (câmeras de fábrica fictícias no broadcast, de 1 a 16;
padrão 3, a câmera n com MAC `AA:00:00:00:00:<n em hex>` e serial `SIM-n`) e
`-SimularEscala` (multiplica as esperas simuladas; padrão 1, 0 = sem espera).
Com o painel no ar, `POST /api/simular {ligado, falharEm}` liga a simulação e
arma uma falha: `falharEm` em texto (uma etapa: `inicializada`, `encoder`,
`rede` ou `conferida`; falha uma vez, na primeira câmera que chegar nela) ou
em mapa por câmera, `{ "<n>": "<etapa>|mac-trocado|ja-inicializada" }`. O
`fonte\testes\Smoke-Paralelo.ps1` sobe o painel em simulação numa pasta
temporária e roda um cenário de ponta a ponta pela API (`-Cenario basico`,
`falha-rede-2`, `mac-trocado-2`, `ja-inicializada-3` ou `encerrar`; `-Cameras`
de 2 a 16). Fica fora do CI e do instalador.

Gerar o instalador:
`instalador\Gerar-Instalador.ps1` (roda os testes, confere que nenhum
`*.local.ps1` entra e chama o ISCC; saída em `instalador\saida\`, fora do git).
`fonte\senha.local.ps1` é opcional, fora do git e nunca distribuído.
