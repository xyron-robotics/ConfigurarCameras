# API Intelbras / Dahua — engenharia reversa

> **Como ler este arquivo.** As seções até "Método de captura em runtime" foram
> levantadas em 08/2026 contra a **VIP-5460-Z-IA** (firmware `3.120.00IB001.0.R`,
> base Dahua `IPC-HFW4441T-ZAS`) pela versão antiga em CGI. O painel atual usa
> **só RPC2** (seção "Configuração por RPC2", validada na VIP-1230-D-G3 em
> 09/2026) e a inicialização anônima por `/OutsideCmd`. A CGI com Digest fica
> documentada porque explica o protocolo, mas não é mais usada.

Tudo aqui foi **verificado ao vivo**, não é suposição, salvo onde está marcado
como pendente.

## Endpoints

| Endpoint | Autenticação | Para quê |
|---|---|---|
| `/cgi-bin/*.cgi` | HTTP Digest | configuração normal (rede, sistema) |
| `/RPC2_Login` | nenhuma | handshake de login |
| `/RPC2` | sessão do login | chamadas autenticadas |
| `/OutsideCmd` | **nenhuma** | inicialização de fábrica e reset de senha |
| UDP 37810 (DHIP) | nenhuma | descoberta por broadcast: a câmera responde de qualquer faixa de IP (seção "Descoberta DHIP") |

`/OutsideCmd` é o endpoint que faltava. Sondar métodos de init em `/RPC2` sempre
volta vazio, o que induz ao erro de achar que não existem.

## Descoberta DHIP (UDP 37810)

É o protocolo da ferramenta de busca da Intelbras/Dahua (ConfigTool). Verificado
ao vivo em 30/09/2026 e 01/10/2026 deste PC (10.16.251.207/22): **35 respostas
em 3 s, 33 aparelhos**, inclusive, no dia 30, câmeras em 192.168.1.x que o PC não
alcançava por IP. A resposta é UDP para o MAC de quem perguntou, por isso
atravessa faixas.

**Pedido**: datagrama para a porta 37810, enviado a `255.255.255.255`, ao
broadcast dirigido da interface e ao multicast `239.255.255.251`. Cabeçalho de
32 bytes, `uint32` little-endian: `0x20`, `"DHIP"`, sessão `0`, `id`, tamanho
do JSON, `0`, tamanho do JSON, `0`. Depois o JSON:

```json
{"method":"DHDiscover.search","params":{"mac":"","uni":1},"id":1}
```

**Resposta** (mesmo cabeçalho, JSON terminado em NUL), real de uma VIP-1230-D-G4:

```json
{"mac":"30:e1:f1:00:00:65","method":"client.notifyDevInfo","params":{"deviceInfo":{
 "DeviceClass":"IPC","DeviceType":"VIP-1230-D-G4","HttpPort":80,"Port":37777,
 "IPv4Address":{"DefaultGateway":"10.16.250.1","DhcpEnable":false,"IPAddress":"10.16.250.102","SubnetMask":"255.255.255.0"},
 "MachineName":"EXEMPLO0000001","SerialNo":"EXEMPLO0000001","Vendor":"IntelBras","Version":"2.800.00IB00C.0.T",
 "Init":3210,"Find":"BC", ...}}}
```

O que o painel usa:

| Campo | Uso |
|---|---|
| `mac` (fora do `deviceInfo`) | identidade; a mesma câmera responde várias vezes (uma por destino e por interface), o painel deduplica por MAC |
| `IPv4Address.{IPAddress, SubnetMask, DefaultGateway}` | onde ela está; se estiver fora das faixas do PC, a placa recebe um IP temporário nessa rede |
| `DeviceClass` | `IPC` (câmera), `NVR`, `BSC` (controlador de acesso/face). Só IPC entra na fila; Procurar lista todos |
| `DeviceType`, `SerialNo`, `Version` | modelo, serial e firmware sem login |
| `HttpPort` | porta HTTP da câmera. Vistas `80` e **`8081`**; o painel guarda por IP e usa em todas as URLs (`Get-CamPortaHttp`) |
| `Init` | bitmap. Nas inicializadas: `3210`, `3222`, `3238`, `3722`, `3734` (`Init -band 3 = 2`). **Premissa**: câmera de fábrica tem `Init -band 3 = 1`, como no `DevInit.getStatus`. **Nunca se age só por isso**: o painel confirma `Init=1` pelo `getStatus` por HTTP antes de inicializar |

Observado: as duas BSC em `10.16.250.14` e a câmera `10.16.250.213` anunciam
`HttpPort 8081`. Firewall que barra UDP de entrada no PC = zero respostas, sem
erro; aí o painel cai no atalho (ping no IP de fábrica) e na varredura por ping.

Implementação: `New-PacoteDhip`, `ConvertFrom-RespostaDhip`, `Get-InitNormalizado`,
`Get-AchadosDhipUnicos`, `Invoke-DescobertaDhip` (um `UdpClient` por interface),
`Add-IpTemporarioPlaca`; `Find-CamerasNaRede` faz o broadcast antes do atalho e da
varredura.

## Login em dois passos (MD5)

Passo 1 — desafio, em `/RPC2_Login`:

```json
{"method":"global.login","params":{"userName":"admin","password":"","clientType":"Web5.0"},"id":1,"session":0}
```

Resposta traz `error.code = 268632079` ("login challenge!") e, em `params`,
`realm`, `random`, `opaque`, `authorization`.

Passo 2 — resposta ao desafio, no mesmo endpoint:

```
H1 = MD5( "admin:" + realm  + ":" + senha ).hex.MAIÚSCULO
H2 = MD5( "admin:" + random + ":" + H1    ).hex.MAIÚSCULO
```

```json
{"method":"global.login","params":{"userName":"admin","password":"<H2>","clientType":"Web5.0",
 "realm":"<realm>","random":"<random>","passwordType":"Default","authorityType":"Default"},
 "id":2,"session":"<session do passo 1>"}
```

Sucesso: `{"result":true,"params":{"keepAliveInterval":60}}`. A `session` do passo 1
continua valendo.

## O envelope criptografado

Métodos sensíveis não aceitam texto claro. Recebem `{cipher, salt, content}`.
O nome `RPAC-256` **não é cifra proprietária** — o JavaScript da interface revela
que é AES puro:

```js
~t.indexOf("RPAC") && (u = z.mode.CBC, l = "RPAC-256",
                       d.iv = z.enc.Utf8.parse("0000000000000000"))
z.AES.encrypt(z.enc.Utf8.parse(JSON.stringify(i)), c, d).toString()
```

Receita completa:

1. **Chave**: string **numérica** aleatória de `saltLen` dígitos.
   `saltLen = 32` se `SecurityBaselineVersion == "V2.0"`, senão `16`.
   Na VIP-5460-Z-IA testada: **32** (AES-256).
2. **`salt`**: essa string cifrada com a pública RSA do aparelho,
   **PKCS#1 v1.5**, saída em **hex minúsculo** (512 chars para RSA-2048).
   A chave vem de `Security.getEncryptInfo`, no formato `"N:<hex>,E:010001"`.
   `getEncryptInfo` responde **sem autenticação**, com `session:0`.
3. **`content`**: `JSON.stringify(payload)` cifrado em **AES-CBC**, padding
   **Zero** (não PKCS7), **IV = os 16 caracteres ASCII `0000000000000000`**
   (bytes `0x30`, não `0x00`), chave = os bytes ASCII da string do item 1,
   saída em **Base64**.
4. **`cipher`**: a string `"RPAC-256"`.

Confirmação numérica: payload de 72 B → zero-padding para 80 B (5 blocos) →
108 chars de Base64. Bate exatamente com o que a interface web envia.

Em .NET tudo é nativo: `RSACryptoServiceProvider.Encrypt(dados, $false)` faz
PKCS#1 v1.5, e `Aes` com `Mode=CBC`/`Padding=None` mais zero-fill manual faz o resto.

## Recuperação de senha só por e-mail

**Este é o ponto que o IP Utility Next não faz.** Método `PasswdFind.setContact`
em `/RPC2` (com sessão), payload em texto claro **antes** de cifrar:

```json
{"contactEmail":"recuperacao@exemplo.com.br","contactPhone":"","mode":3}
```

`mode: 3` com `contactPhone` vazio = **somente e-mail**. Testado: retorna
`{"result":true}`.

O booleano de habilitação fica numa tabela de config comum, legível pela CGI:

    configManager.cgi?action=getConfig&name=PwdReset
    -> table.PwdReset.Enable=true

O e-mail em si **não** fica em tabela de config — só passa pelo RPC cifrado.

## Inicialização de fábrica

Câmera virgem responde **HTTP 401 `Invalid Authority!`** em toda a CGI, inclusive
em endpoints que normalmente não exigem autenticação. Não é senha errada, é
estado do aparelho.

API em `/OutsideCmd`, sem autenticação e **sem campo `session`**:

```
DevInit.getStatus            DevInit.getDevCaps
DevInit.getCurrentTime       DevInit.setCurrentTime
DevInit.getProtocolAgree     DevInit.setProtocolAgree({ProtocolEnable})
DevInit.getLocalityConfig    DevInit.setLocalityConfig({cipher,salt,content})
DevInit.account({cipher,salt,content})    <-- cria o admin
DevInit.access({salt,cipher,content})
```

E, para reset de senha esquecida:

```
PasswdFind.getDescript({name:"admin"})   PasswdFind.resetPassword({cipher,salt,content})
PasswdFind.sendVerificationCode({username:"admin"})
PasswdFind.checkAuthCode({cipher,salt,content})
```

`Account.DevInit` aparece na lista de eventos de log de auditoria, confirmando
que a inicialização é uma operação registrada do aparelho.

### Detalhe que muda tudo: dois construtores de requisição

O JavaScript monta os pedidos com duas funções diferentes, e a escolha por
método **não é arbitrária**:

```js
g = (m, p) => ({method: m, params: p, id: h++, session: v()})   // COM session
b = (m, p) => ({method: m, params: p, id: h++})                 // SEM session
```

| Método | Construtor | Leva `session`? |
|---|---|---|
| `DevInit.getStatus`, `account`, `access`, `getDevCaps`, `getLocalityConfig`, `getCurrentTime` | `b` | **não** |
| `DevInit.setProtocolAgree`, `setCurrentTime`, `setLocalityConfig`, `getProtocolAgree` | `g` | sim |

Mandar `session` num método que usa `b` é um jeito fácil de tomar recusa sem
entender por quê.

### Schema do `DevInit.account`

Lido direto do código do assistente (chunk lazy **86**):

```js
var d = { name: i,                    // state.username, default "admin"
          pwd:  h.newPassword,
          CellPhone: r ? s : "",      // r = orUsePhone, s = prefixo + numero
          Mail:      o ? l : "" };    // o = orUseEmail, l = e-mail
K.a.setAccount(d)   // -> DevInit.account({cipher,salt,content})
```

Portanto o `content`, antes de cifrar, é:

```json
{"name":"admin","pwd":"<senha>","CellPhone":"","Mail":"recuperacao@exemplo.com.br"}
```

**`CellPhone` vazio + `Mail` preenchido = recuperação somente por e-mail.** Não
precisa de `PasswdFind.setContact` depois: a própria inicialização grava o
contato.

### Verificação depois de inicializar (VIP-5460-Z-IA, 2026-08-20)

`PasswdFind.getDescript({"name":"admin"})` em `/OutsideCmd`, sem autenticação,
devolve o contato gravado:

```json
{"contactEmail":"recuperacao@exemplo.com.br","contactPhone":"","desc":"XXXXXXXX...","mode":2}
```

E via CGI: `configManager.cgi?action=getConfig&name=PwdReset` →
`table.PwdReset.Enable=true`.

`contactPhone` vazio com `contactEmail` preenchido: **recuperação apenas por
e-mail, confirmada lendo de volta do aparelho.** O `desc` é o blob que a
Intelbras usa para gerar o código de reset.

Detalhe em aberto: o `DevInit.account` resultou em `mode:2`, enquanto o
`PasswdFind.setContact` da interface web mandava `mode:3` para o mesmo efeito.
Os dois deixam o telefone vazio e o reset habilitado, então na prática dá no
mesmo; a semântica exata do campo `mode` não foi determinada.

### Sequência completa da inicialização

1. `DevInit.getStatus` → confere `Init == 1` (de fábrica) e `Find` (`"AB"` =
   telefone e e-mail suportados; `B` é o que interessa)
2. `DevInit.setProtocolAgree` com `{"ProtocolEnable":true}` — aceite do termo;
   sem isso o resto é recusado
3. `DevInit.account` com o envelope cifrado acima
4. `DevInit.access` com `{"NetAccess":0,"UpgradeCheck":2}` — `NetAccess:0` deixa
   P2P/nuvem desligado, `UpgradeCheck:2` não procura firmware sozinho. São os
   valores que o assistente envia com as caixas desmarcadas. O próprio
   assistente tolera falha neste passo, então não vale abortar por causa dele.

Opcionais, que o assistente faz mas não são necessários:
`DevInit.setCurrentTime({time,tolerance:5})` e
`DevInit.setLocalityConfig({NTP:{TimeZone,TimeZoneDesc},Locales:{TimeFormat},Country,Language,VideoStandard})`.

### `saltLen` numa câmera virgem

`saltLen = "V2.0" === SecurityBaselineVersion ? 32 : 16`, e neste firmware
`SecurityBaselineVersion:"V2.0"` está **fixo no bundle**, não vem do aparelho.
Logo: **32 sempre** (AES-256). Confirmado idêntico na câmera virgem e na já
inicializada.

`Security.getEncryptInfo` responde sem autenticação em `/RPC2` **e** em
`/OutsideCmd`, mesmo em aparelho de fábrica. Resposta real da virgem:

```json
{"AESPadding":["ZERO","PKCS7"],"asymmetric":"RSA","cipher":["AES","RPAC"],
 "pub":"N:DC03...6113,E:010001","suggestedAsymmetric":"RSA"}
```

## Como o bundle foi obtido

Este foi o atalho que resolveu o problema. Uma câmera **virgem** serve os
chunks lazy que uma já inicializada não serve, e o `index.html` traz o mapa
completo de id → hash:

```
curl http://192.168.1.108/ -o index.html
# o runtime webpack inline tem {13:"44c92691",14:"4a56ccf4",...}
curl http://192.168.1.108/static/js/86.5f52ba17.chunk.js
```

São 144 chunks lazy (ids 13–160). `grep -l setAccount` aponta o **86** — o
assistente de inicialização. Baixar **serialmente**: em paralelo o firmware
derruba as conexões.

Ler o código estático é melhor que capturar em runtime: dá o schema inteiro,
inclusive os campos que a interface só usa em outros caminhos.

## Método de captura em runtime (alternativa)

Quando não houver o chunk, instalar no console **antes** de operar a interface:

```js
var orig = JSON.stringify;
JSON.stringify = function (v) {
  var out = orig.apply(JSON, arguments);
  if (/contactEmail|userName|password/i.test(out)) window.__cap.push(out);
  return out;
};
```

Funciona porque o payload é serializado com `JSON.stringify` imediatamente antes
de entrar no AES. Capturar o tráfego HTTP não serve: ali o dado já está cifrado.
Foi assim que o payload do `setContact` foi obtido.

## Configuração por RPC2 (`configManager`)

Validado em **VIP-1230-D-G3**, firmware `2.800.00IB003.0.T` (2022), em 29/09/2026.
Nesse firmware a CGI com Digest devolve **401 mesmo com a senha certa**, e o RPC2
aceita o mesmo login. Por isso o painel fala só RPC2 (`docs/adr/0001`).

O login é o descrito acima, com `clientType:"Web3.0"` e `loginType:"Direct"`. O
primeiro passo devolve `params.encryption = "Default"`. Depois, toda chamada vai em
`POST /RPC2` com `{"method", "params", "id", "session"}`.

| Método | `params` | Resposta útil |
|---|---|---|
| `magicBox.getDeviceType` | `null` | `params.type` = modelo |
| `magicBox.getSerialNo` | `null` | `params.sn` |
| `magicBox.getSoftwareVersion` | `null` | `params.version.Version` |
| `configManager.getConfig` | `{"name":"Encode"}` | `params.table[0].{MainFormat[4], ExtraFormat[3], SnapFormat[3]}` |
| `configManager.getConfig` | `{"name":"Network"}` | `params.table.{DefaultInterface, Hostname, eth0.{IPAddress, SubnetMask, DefaultGateway, DhcpEnable, DnsServers[2], PhysicalAddress, MTU}}` |
| `configManager.setConfig` | `{"name":..., "table":<tabela INTEIRA lida e modificada>, "options":[]}` | `result:true` |
| `global.logout` | `null` | fecha a sessão |
| `encode.getConfigCaps` | `{"channel":0}` | **"internal error"** neste firmware: sem limites por modelo |

Cada entrada de `Encode` traz `.Video.{Width, Height, FPS, BitRate, GOP,
BitRateControl, Compression, CustomResolutionName, Profile, Quality}`. O
`CustomResolutionName` acompanha a resolução (`1920x1080` = `1080P`, `704x480` = `D1`).

O ajuste de encoder grava, em **todas** as entradas de `MainFormat[]` (stream
principal) e de `ExtraFormat[]` (stream secundário): `Width`, `Height`, `FPS`,
`BitRate`, `GOP` (sempre `2 × FPS`), `Compression` (`H.264` ou `H.265`) e
`CustomResolutionName`. `BitRateControl`, `Profile`, `Quality`, áudio e
`SnapFormat` ficam como vieram. A leitura de volta confere os mesmos campos.

Desde a 1.2.1 a gravação é em **dois** `setConfig` (`Set-CamEncodeEmPassos`):
passo 1 só `Width`, `Height`, `FPS`, `Compression` e `CustomResolutionName`,
com `BitRate` e `GOP` como lidos; passo 2 a tabela completa. Passo cuja
tabela já é a lida é pulado (retomada). Motivo: em 01/10/2026 a VIP-1230-D-G3
recém resetada recusou duas vezes a gravação única que trocava tudo
(principal `1920x1080` 24 fps 1500 kbps `H.265` GOP 48; secundário
`1280x720` 12 fps 750 kbps `H.265` GOP 24) com
`code 268959743: Unknown error! error code was not set in service!`; em
29/09, partindo do mesmo estado de fábrica em duas gravações, aceitou.
Causa isolada na bancada em 02/10/2026, já em duas gravações: o passo 1 é
recusado (mesmo código) com o secundário em `1280x720` (`720P`), tanto em
`H.265` quanto em `H.264`; com o secundário em `704x480` `H.265` os dois
passos passaram e a leitura de volta conferiu. Esta câmera (2 MP) não aceita
720P no stream secundário; `recusado` de `Get-CatalogoEncoder` registra.

`Get-CatalogoEncoder` guarda os valores prontos da página (fps, degraus de
bitrate Dahua, faixa usual por resolução com recomendado em H.264 e H.265) e
o que a câmera de referência aceitou (`testado`) ou recusou (`recusado`) por
stream. Só muda com teste em câmera real.

Validado em câmera real (VIP-1230-D-G3, 29/09/2026): principal `1920x1080`
em `H.264` e em `H.265` (o `setConfig` com troca de codec respondeu, a sessão
continuou e a leitura de volta conferiu), secundário `704x480` (`D1`) com
512 kbps, e GOP `2 × FPS` nos dois. Em 02/10/2026: secundário `704x480` em
`H.265` (12 fps, 750 kbps, GOP 24) aceito; `1280x720` recusado. Ainda não
validados no secundário: `352x240` (`CIF`) e `640x480` (`VGA`). Os nomes seguem a
nomenclatura Dahua. Se a câmera recusar ou gravar outro valor, a configuração
falha na etapa encoder e a fila para.

Pegadinhas:

- `table` de `Encode` é um **array** (um item por canal). O PowerShell desembrulha
  array de um item no retorno de função. Se o `setConfig` levar um objeto em vez
  do array, a gravação falha. Os testes (`Testes-Motor.ps1`) conferem isso.
- `setConfig Network` mantendo o mesmo IP responde normalmente (`result:true`),
  tanto com `DhcpEnable` false quanto com true. Com troca de IP, espera-se que
  a resposta não volte, porque a câmera muda de endereço no meio. Esse caso ainda
  não foi visto ao vivo.

Tabelas reais em `testes/encode-vip1230-d-g3.json` e `testes/network-vip1230-d-g3.json`.

### Reset de fábrica (`configManager.restore`)

**Sem uso no painel desde a 1.2.0**: nenhuma forma por RPC2 faz reset de
fábrica completo neste firmware (veja a tabela abaixo), e a ferramenta
"Resetar câmera para a fábrica" (1.0.x a 1.1.1) foi removida. Para voltar
uma câmera de fábrica, use a tela da própria câmera (Configuração > Sistema
> Padrão de fábrica) ou o botão físico. Fica aqui o que foi visto, para
quem quiser retomar.

| Método | `params` | Efeito |
|---|---|---|
| `configManager.restore` | `{}` | reset total: senha, rede, encoder; a câmera reinicia (não obtido neste firmware) |
| `configManager.restoreExcept` | `{"except":["Network", ...]}` | reset mantendo as seções listadas |
| `magicBox.reboot` | `null` | só reinicia |

**Visto ao vivo na VIP-1230-D-G3, firmware 2.800.00IB003.0.T (30/09/2026):**

| Chamada | Resposta | Efeito |
|---|---|---|
| `configManager.restore` `{}` | `{"result":false,"error":"internal error"}` | nada |
| `configManager.restore` `{"names":["All"]}`, `{"names":[]}`, `{"names":["Encode"]}` | `internal error` | nada |
| `configManager.restoreExcept` `{"names":[]}` | `result:true` | **restaurou as configurações** (encoder voltou a 1080p 30 fps 4096 kbps GOP 60, secundário 30 fps 1024 kbps) mas **manteve o admin, a senha e a rede** (IP estático, DHCP off). A câmera não reiniciou e continuou `Init=2`. |

Ou seja, nesse firmware o `restoreExcept` equivale ao botão "Padrão" da
interface web (tudo menos rede e usuários). O reset total (voltar a pedir
`DevInit`) não foi obtido por RPC: `magicBox.resetSystem` existe
(`magicBox.listMethod`), mas a interface web o envia dentro de um envelope
autenticado com a senha do admin, e reproduzir esse mecanismo ficou fora do
escopo. Para devolver a câmera ao estado de fábrica, use o **botão físico
de reset**. Depois de um `restoreExcept`, a câmera pode ser retomada pelo
painel ("Retomar câmera já inicializada" com o IP dela) para receber os
padrões de novo; foi assim que a .208 voltou aos padrões em 30/09.

As funções `Invoke-CamResetFabrica` e `Wait-CamDeFabrica` que faziam isso
saíram do motor na 1.2.0 (estão no histórico do git, até o commit `339742c`).
Uma câmera já registrada que reaparece de fábrica (reset pela tela dela ou
pelo botão) tem a entrada substituída ao ser configurada de novo.

## Implementação

- Painel (RPC2): `Motor-Cameras.ps1`, com `New-CamSessao`, `Invoke-CamRpc2`,
  `Get-CamInfoRpc`, `Get-CamEncode`/`Set-CamEncode`, `Get-CamRedeRpc`/`Set-CamRedeRpc`
  e `Invoke-ConfiguracaoCamera`.
- Inicialização de fábrica (anônima, `/OutsideCmd`): `Invoke-CamRpc`,
  `Get-CamInitStatus`, `New-CamEnvelope`, `Invoke-CamRpcCifrado`, `Initialize-Cam`,
  também no `Motor-Cameras.ps1`.
- Descoberta DHIP (UDP 37810): `New-PacoteDhip`, `ConvertFrom-RespostaDhip`,
  `Invoke-DescobertaDhip`, `Find-CamerasNaRede`; resposta real em
  `testes\dhip-notifydevinfo-vip1230-d-g4.json`.
- O CLI antigo em CGI (`Configurar-Cameras.ps1`) saiu do repositório em 30/09/2026;
  está no histórico do git (commit a638fce e anteriores).
