# Configurar Câmeras Intelbras — painel de campo

Painel web local que coloca câmeras IP Intelbras (base Dahua) em serviço, uma
por vez, pelo cabo: cria o `admin`, grava a recuperação de senha **apenas por
e-mail**, ajusta o encoder dos dois streams, grava IP/máscara/gateway/DNS,
confere lendo de volta e registra cada câmera. Tudo roda neste PC; nada vai
para a internet.

Validado em câmera real: **VIP-1230-D-G3** (firmware 2.800). A VIP-5460-Z-IA foi
validada só na versão antiga em CGI (veja Pendências).

---

## Requisitos

| Requisito | Situação |
|---|---|
| Windows 10 (1803 ou mais novo) ou Windows 11 | traz `curl.exe` e PowerShell 5.1, que é tudo o que o painel usa |
| Administrador local | pedido uma vez, ao abrir: preparar a placa de rede exige |
| Placa Ethernet com cabo | Wi-Fi não serve; USB-Ethernet serve |
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

Toda abertura começa pelo **passo a passo**, uma tela depois da outra, que
monta a **sessão** de trabalho. Com uma sessão guardada da última vez, depois
da senha o painel oferece **Usar essa sessão** (vai direto ao resumo) ou
**Revisar passo a passo** (cada tela já preenchida).

1. **Senha**: digitada duas vezes. Vira a senha do `admin` de cada câmera
   configurada nesta sessão. Fica só na memória do painel: nunca vai para
   disco, log, registro ou relatório, e é pedida de novo a cada abertura.
2. **Placa de rede**: a placa deste PC ligada à bancada ou ao switch das
   câmeras (Ethernet ou Wi-Fi; a Ethernet com cabo vem sugerida em primeiro).
   **Só ela é usada**: é por ela que o painel procura a câmera, dá os
   endereços ao PC e confere a câmera no IP novo. Um endereço igual noutra
   placa do PC não conta. Escolher a placa que leva à internet pede
   confirmação: a rede pisca por alguns segundos e a internet é testada
   depois.
3. **Rede das câmeras**: máscara, gateway e DNS gravados em cada câmera (a
   rede do NVR; o gateway vem vazio, é da obra) e, opcional, o IP do PC nessa rede (vazio = `.200` a `.249`,
   derivado do MAC da placa).
4. **Faixa de fábrica**: onde a câmera nova aparece (`192.168.1.108`) e,
   opcional, o IP do PC nessa faixa (vazio = `.220`). Precisa ser diferente da
   rede das câmeras.
5. **Câmera**: e-mail de recuperação (única forma de recuperar a senha do
   admin: use um e-mail da empresa; vem vazio) e encoder dos dois streams (resolução,
   fps, bitrate, codec; o GOP é gravado como o dobro do fps). Fps e bitrate
   são listas de valores prontos, com **Outro valor…** no fim para digitar
   um número fora dela; a lista de bitrate segue a
   resolução e o codec do stream, com o recomendado marcado e a faixa usual
   embaixo. Resolução e codec dizem se já foram testados em câmera real.
   A câmera recebe o encoder em duas gravações: primeiro resolução, fps e
   codec; depois bitrate e GOP.
6. **Fila**: primeiro e último IP, local, rack e andar. Opcional (**Montar
   depois**); a última fila volta preenchida como sugestão.
7. **Resumo**: um cartão por seção, com **Alterar**. **Preparar placa e
   começar** acrescenta à placa escolhida dois endereços (um na faixa de
   fábrica, um na rede das câmeras), sem tirar nenhum, testa a internet e
   monta a fila se houver. **Ao encerrar o painel a placa volta ao DHCP
   sozinha**.

Depois disso o painel tem três telas: **Painel** (fila, bancada, vigia e o
registro), **Ferramentas** e **Opções** (engrenagem), com as mesmas seções do
passo a passo para mudar qualquer coisa no meio da sessão. Trocar a placa ou
as faixas em Opções devolve a placa e a prepara de novo; se há fila montada,
pede confirmação e a fila continua se a faixa ainda cabe na rede nova.

## Fila

Monte a fila no passo 6 ou em **Opções > Fila** (primeiro e último IP,
**Montar fila**). Gateway, endereços fora da rede e IPs com câmera instalada
no registro ficam de fora (câmera que falhou não ocupa a posição; se ela
ainda responde no IP, o ping na hora de usar a posição pula); uma faixa sem
posição livre é recusada. Para cada posição: ligue **uma**
câmera no cabo e clique em **Câmera conectada**. O painel acha a câmera de
fábrica, pela placa escolhida, pelo broadcast DHIP (em qualquer faixa de IP;
se ela estiver fora das faixas da placa, a placa recebe um IP temporário na
rede dela e, se a faixa for de outra placa do PC, uma rota de host), pelo IP
de fábrica `192.168.1.108` e, se nada vier, pela varredura por ping. Depois
faz, nesta ordem: inicialização → encoder → rede → conferência no IP novo
(espera do boot até 120 s, com contagem na tela). Câmera com porta HTTP
diferente de 80 (anunciada no broadcast) é atendida nela.

- **Retomar câmera já inicializada**: para uma câmera que já recebeu a senha
  desta sessão (por exemplo, depois de uma falha com o painel fechado). Informe o
  IP em que ela responde agora.
- **Vigia**: desligado por padrão. Com a fila montada, informe porta e canal da
  primeira câmera e ligue. O painel observa o IP de fábrica e configura sozinho
  cada câmera de fábrica que aparece; porta e canal somam 1 a cada câmera. A
  caixa **Aceitar câmera de fábrica em qualquer faixa (broadcast)** faz o vigia
  observar também pelo broadcast: use só com a bancada isolada da rede do
  escritório, senão qualquer câmera de fábrica da rede entra na fila. Uma
  câmera **já inicializada** no IP de fábrica só gera aviso. O vigia desliga
  sozinho quando a fila acaba e depois de 5 tentativas seguidas sem configurar.
- **Falha**: a fila para e mostra a etapa, o motivo e o que a câmera já recebeu,
  com **Tentar de novo**, **Pular esta posição** e **Encerrar**. Se a câmera
  recusou a senha, **Tentar de novo** fica travado até uma senha nova: repetir a
  senha errada bloqueia o `admin` da câmera por minutos.

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
`%LOCALAPPDATA%\ConfigurarCameras` e avisa na barra.

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
placa. Serve para diagnóstico e para os testes.

**Encerrar o painel** (Opções) fecha o servidor e devolve a placa de rede ao
estado de antes (DHCP, endereços, rotas de host e rota que o painel pôs saem);
a fila em memória se perde, o registro e a sessão ficam. Fechar só a janela do
navegador não encerra: o painel continua
e, depois de 3 minutos sem a página e sem nada em curso (câmera sendo
configurada, decisão pendente, vigia ligado), encerra sozinho e devolve a placa.
Para voltar antes disso, abra o atalho de novo. Se o processo for morto no meio,
a placa fica preparada e o próximo painel avisa e devolve ao encerrar.

## Versões e atualização

A versão do painel aparece em Opções ("Painel v1.2.0") e vem de
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
painel parado: sem câmera em configuração, sem decisão pendente, vigia
desligado, e aberto como Administrador. Sem internet (ou só com proxy) a
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
| "Placa ... sem as faixas" na barra | clique em **Preparar placa**; se não resolver, o painel está sem Administrador (feche e abra de novo aceitando o UAC) |
| "Placa ... não está mais neste PC" | a placa escolhida sumiu (USB desconectado, renumerada): escolha outra em **Opções > Placa de rede** |
| Câmera na bancada não aparece, mas responde pelo Wi-Fi | a placa escolhida é a errada, ou a câmera está numa faixa que o Wi-Fi também tem: confira a placa em Opções. Se o IP dela cai na faixa de outra placa, o painel põe um IP temporário e uma rota de host na placa escolhida ao configurar |
| Câmera não responde ao ping | cabo, injetor PoE sem energia ou porta errada do injetor (saída **P+D**) |
| Procurar diz "0 respostas" ao broadcast | um firewall no PC está barrando UDP de entrada (porta 37810). O painel ainda acha pelo IP de fábrica e pela varredura; libere o `powershell.exe` no firewall para o broadcast voltar |
| "fora das faixas do PC" na lista | a câmera está noutra rede; ao configurar, a placa recebe um IP temporário nessa rede (sai no Restaurar DHCP / ao encerrar) |
| `senha recusada pela camera` | a câmera já tem outra senha. Não insista: troque a senha em Opções ou volte a câmera de fábrica pela tela dela |
| `camera recusou o encoder no passo N` | a câmera não aceitou o que o passo grava (passo 1: resolução, fps ou codec; passo 2: bitrate ou GOP). O log mostra o encoder lido antes. Volte a um valor marcado "(testado)" em **Opções > Câmera** e **Tentar de novo** |
| `conta admin BLOQUEADA` | espere alguns minutos; depois confirme a senha certa antes de qualquer tentativa |
| PC ficou sem internet depois de preparar a placa | a barra mostra "sem internet desde o preparo da placa". **Restaurar DHCP** devolve na hora; encerrar o painel também. Se nada disso resolver: `ncpa.cpl` > placa > IPv4 > "Obter um endereço IP automaticamente" |
| Barra diz "sem internet" mas o navegador navega | a rede só sai por proxy; o teste do painel (`curl.exe`) não usa proxy. Pode ignorar |
| "ficou preparada desde a última vez" ao abrir | o painel anterior foi fechado no X. Nada a fazer: ela volta ao DHCP ao encerrar (ou em **Restaurar DHCP**) |
| A faixa de atualização diz "SHA-256 não confere" | o download veio diferente do publicado (proxy que troca conteúdo, download interrompido). Nada foi instalado; tente de novo ou baixe pelo navegador na página de releases |
| Atualizou e o painel não reabriu | abra pelo atalho. O que o instalador fez está em `instalador.log` na pasta de dados |
| O painel abre sempre no passo a passo | é assim: a cada abertura ele pede a senha e oferece usar ou revisar a sessão guardada. Se não oferece, a sessão ficou incompleta (placa que sumiu, campo inválido): o passo que falta aparece |

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
- **Vigia** e a **contagem do boot real** ainda não foram usados em campo.
- **Descoberta DHIP**: validada com 33 aparelhos já inicializados (01/10/2026),
  inclusive dois com porta HTTP 8081. Uma **câmera de fábrica** respondendo ao
  broadcast (`Init` com bit 1) e o **IP temporário** na placa ainda não foram
  vistos ao vivo; o painel confirma por HTTP antes de agir.
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
fonte/web/Servidor-Painel.ps1 + web/www/   o painel (HttpListener + página)
fonte/INICIAR-PAINEL.vbs    abre o painel sem console (atalho do instalador)
fonte/INICIAR-PAINEL-COM-CONSOLE.bat   o mesmo, com console (diagnóstico)
fonte/Testes-Motor.ps1      95 provas do motor (sessão, placa escolhida, rede, fila, registro), sem câmera nem rede
fonte/Testes-Descoberta.ps1 49 provas das funções puras de descoberta (inclui DHIP)
fonte/API-INTELBRAS.md      protocolo da câmera, o que foi visto ao vivo
fonte/testes/               tabelas lidas da VIP-1230-D-G3 (MAC, série e IPs trocados por exemplos)
instalador/                 ConfigurarCameras.iss + Gerar-Instalador.ps1 (Inno Setup 6); icone.ico (Gerar-Icone.ps1)
.github/workflows/release.yml   tag v* -> testes, instalador e release no GitHub
```

Publicar uma versão: ajuste `fonte\VERSAO.txt`, commit, `git tag vX.Y.Z` e
`git push origin vX.Y.Z`; o Actions gera o instalador e o release.

Rodar os testes: `powershell -ExecutionPolicy Bypass -File fonte\Testes-Motor.ps1`
e o mesmo para `Testes-Descoberta.ps1`. Gerar o instalador:
`instalador\Gerar-Instalador.ps1` (roda os testes, confere que nenhum
`*.local.ps1` entra e chama o ISCC; saída em `instalador\saida\`, fora do git).
`fonte\senha.local.ps1` é opcional, fora do git e nunca distribuído.
