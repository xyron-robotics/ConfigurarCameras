<#
    Testes-Descoberta.ps1
    Testes das funcoes PURAS de descoberta de camera do Motor-Cameras.ps1.

    COMO ELE CARREGA AS FUNCOES SEM EXECUTAR NADA
      O arquivo alvo e lido pelo PARSER do PowerShell e somente as definicoes
      de funcao sao avaliadas. Nada mais roda, e o codigo de producao nao
      precisa de nenhum gancho de teste. (O motor nao executa nada ao
      carregar, mas a carga por AST fica como garantia dupla.)

    O QUE ESTA COBERTO
      A matematica de faixa de rede, que e a peca mais perigosa: um
      off-by-one na fronteira de /22, incluir rede ou broadcast, ou incluir o
      IP do proprio PC falham TODOS em silencio - o sintoma unico e "a
      varredura nao achou a camera". Tambem MAC/OUI/blacklist, a leitura do
      DevInit.getStatus e o contrato de retorno de colecao (zero, um e N).

    Uso:
        .\Testes-Descoberta.ps1
    Sai com codigo 1 se algum teste falhar, para servir em automacao.
#>
[CmdletBinding()]
param([string]$Alvo = '')

$ErrorActionPreference = 'Stop'

$raiz = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($raiz)) { $raiz = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($Alvo)) { $Alvo = Join-Path $raiz 'Motor-Cameras.ps1' }
if (-not (Test-Path $Alvo)) { throw "nao achei o script alvo: $Alvo" }

# ------------------------------------------------ carga por AST, sem executar

$errosSintaxe = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Alvo, [ref]$null, [ref]$errosSintaxe)
if ($errosSintaxe) {
    foreach ($e in $errosSintaxe) {
        Write-Host ("  SINTAXE linha " + $e.Extent.StartLineNumber + ": " + $e.Message) -ForegroundColor Red
    }
    throw "o script alvo tem erro de sintaxe - corrija antes de testar"
}

$defs = $ast.FindAll({
    param($no)
    $no -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true)

foreach ($d in $defs) { Invoke-Expression $d.Extent.Text }
Write-Host ""
Write-Host ("  " + $defs.Count + " funcoes carregadas de " + (Split-Path -Leaf $Alvo)) -ForegroundColor DarkGray
Write-Host ""

# ------------------------------------------------------------------ arcabouco

$script:Ok = 0
$script:Falhou = 0
$script:Falhas = @()

function T {
    param([string]$Nome, [scriptblock]$Bloco)
    try {
        & $Bloco
        $script:Ok++
        Write-Host ("  ok     " + $Nome) -ForegroundColor DarkGreen
    } catch {
        $script:Falhou++
        $script:Falhas += ($Nome + ' :: ' + $_.Exception.Message)
        Write-Host ("  FALHOU " + $Nome) -ForegroundColor Red
        Write-Host ("           " + $_.Exception.Message) -ForegroundColor DarkGray
    }
}

function Assert-Igual {
    param($Esperado, $Obtido, [string]$Que = 'valor')
    if ([string]$Esperado -ne [string]$Obtido) {
        throw ($Que + ': esperado <' + $Esperado + '> obtido <' + $Obtido + '>')
    }
}

function Assert-Verdade {
    param($Valor, [string]$Que = 'condicao')
    if (-not $Valor) { throw ($Que + ' deveria ser verdadeiro') }
}

function Assert-Falso {
    param($Valor, [string]$Que = 'condicao')
    if ($Valor) { throw ($Que + ' deveria ser falso') }
}

function Assert-Estoura {
    param([scriptblock]$Bloco, [string]$Que = 'chamada')
    $estourou = $false
    try { & $Bloco } catch { $estourou = $true }
    if (-not $estourou) { throw ($Que + ' deveria ter estourado e nao estourou') }
}

# ------------------------------------------------------- IPv4 e aritmetica

Write-Host "IPv4 e aritmetica de faixa" -ForegroundColor Cyan

T 'Test-Ipv4Estrito aceita IPv4 completo' {
    Assert-Verdade (Test-Ipv4Estrito '10.204.12.1')   'ip normal'
    Assert-Verdade (Test-Ipv4Estrito '0.0.0.0')       'zeros'
    Assert-Verdade (Test-Ipv4Estrito '255.255.255.255') 'maximo'
    Assert-Verdade (Test-Ipv4Estrito '  10.204.12.1 ') 'com espaco em volta'
}

T 'Test-Ipv4Estrito recusa o que TryParse aceitaria' {
    # Este e o motivo da funcao existir: [ipaddress]::TryParse('10') passa.
    Assert-Falso (Test-Ipv4Estrito '10')          'um octeto'
    Assert-Falso (Test-Ipv4Estrito '10.204.12')   'tres octetos'
    Assert-Falso (Test-Ipv4Estrito '256.1.1.1')   'octeto acima de 255'
    Assert-Falso (Test-Ipv4Estrito '10.204.12.1.5') 'cinco octetos'
    Assert-Falso (Test-Ipv4Estrito 'abc')         'texto'
    Assert-Falso (Test-Ipv4Estrito '')            'vazio'
    Assert-Falso (Test-Ipv4Estrito $null)         'nulo'
}

T 'ConvertTo/From-Ipv4Numero fecham o ciclo' {
    foreach ($ip in @('0.0.0.0', '10.204.12.1', '192.168.1.108', '10.16.251.71', '255.255.255.255')) {
        Assert-Igual $ip (ConvertFrom-Ipv4Numero (ConvertTo-Ipv4Numero $ip)) ('ciclo de ' + $ip)
    }
}

T 'ConvertTo-Ipv4Numero tem os bytes na ordem certa' {
    Assert-Igual 0          (ConvertTo-Ipv4Numero '0.0.0.0')     'zero'
    Assert-Igual 1          (ConvertTo-Ipv4Numero '0.0.0.1')     'um'
    Assert-Igual 16777216   (ConvertTo-Ipv4Numero '1.0.0.0')     'primeiro octeto vale 2^24'
    Assert-Igual 4294967295 (ConvertTo-Ipv4Numero '255.255.255.255') 'maximo'
}

T 'ConvertTo-PrefixoDeMascara converte e recusa mascara furada' {
    Assert-Igual 24 (ConvertTo-PrefixoDeMascara '255.255.255.0')   '/24'
    Assert-Igual 22 (ConvertTo-PrefixoDeMascara '255.255.252.0')   '/22'
    Assert-Igual 16 (ConvertTo-PrefixoDeMascara '255.255.0.0')     '/16'
    Assert-Igual 32 (ConvertTo-PrefixoDeMascara '255.255.255.255') '/32'
    Assert-Igual 0  (ConvertTo-PrefixoDeMascara '0.0.0.0')         '/0'
    Assert-Estoura { ConvertTo-PrefixoDeMascara '255.0.255.0' } 'mascara nao contigua'
}

T 'Get-HostsNaFaixa conta certo, inclusive RFC 3021' {
    Assert-Igual 254  (Get-HostsNaFaixa 24) '/24'
    Assert-Igual 1022 (Get-HostsNaFaixa 22) '/22'
    Assert-Igual 2    (Get-HostsNaFaixa 30) '/30'
    Assert-Igual 2    (Get-HostsNaFaixa 31) '/31 nao desconta rede e broadcast'
    Assert-Igual 1    (Get-HostsNaFaixa 32) '/32 e um host'
}

# --------------------------------------------------------------- Expand-Faixa

Write-Host ""
Write-Host "Expand-Faixa" -ForegroundColor Cyan

T '/24 tem 254 hosts, do .1 ao .254' {
    $l = @(Expand-Faixa -Ip '10.204.12.0' -Prefixo 24)
    Assert-Igual 254             $l.Count   'quantidade'
    Assert-Igual '10.204.12.1'   $l[0]      'primeiro'
    Assert-Igual '10.204.12.254' $l[-1]     'ultimo'
}

T '/24 exclui rede e broadcast' {
    $l = @(Expand-Faixa -Ip '10.204.12.0' -Prefixo 24)
    Assert-Falso ($l -contains '10.204.12.0')   'endereco de rede fora'
    Assert-Falso ($l -contains '10.204.12.255') 'broadcast fora'
}

T '/24 aceita qualquer IP de dentro da faixa, nao so o .0' {
    $a = @(Expand-Faixa -Ip '10.204.12.0'   -Prefixo 24)
    $b = @(Expand-Faixa -Ip '10.204.12.137' -Prefixo 24)
    Assert-Igual $a.Count $b.Count "mesma faixa, mesma contagem"
    Assert-Igual $a[0]    $b[0]    'mesmo primeiro host'
}

T '/22 atravessa a fronteira de octeto corretamente' {
    # 10.16.248.0/22 vai de 10.16.248.0 a 10.16.251.255.
    # Este e o caso do log real: a placa estava em 10.16.251.71/22.
    $l = @(Expand-Faixa -Ip '10.16.251.71' -Prefixo 22)
    Assert-Igual 1022            $l.Count 'quantidade'
    Assert-Igual '10.16.248.1'  $l[0]    'primeiro host da /22'
    Assert-Igual '10.16.251.254' $l[-1]  'ultimo host da /22'
    Assert-Verdade ($l -contains '10.16.249.1') 'octeto do meio presente'
    Assert-Verdade ($l -contains '10.16.250.99') 'outro octeto do meio presente'
    Assert-Falso   ($l -contains '10.16.252.1') 'nao invade a faixa vizinha'
    Assert-Falso   ($l -contains '10.16.247.254') 'nao invade a faixa anterior'
}

T '-Excluir tira o IP do proprio PC' {
    $l = @(Expand-Faixa -Ip '10.204.12.0' -Prefixo 24 -Excluir @('10.204.12.4', '10.204.12.220'))
    Assert-Igual 252 $l.Count 'duas exclusoes'
    Assert-Falso ($l -contains '10.204.12.4')   'excluido 1'
    Assert-Falso ($l -contains '10.204.12.220') 'excluido 2'
}

T '-Excluir ignora entrada invalida em vez de estourar' {
    $l = @(Expand-Faixa -Ip '10.204.12.0' -Prefixo 24 -Excluir @('', $null, 'lixo', '10.204.12.4'))
    Assert-Igual 253 $l.Count 'so a exclusao valida conta'
}

T '/30 e /31 e /32 nas bordas' {
    Assert-Igual 2 @(Expand-Faixa -Ip '10.0.0.0' -Prefixo 30).Count '/30 tem 2 hosts'
    Assert-Igual '10.0.0.1' @(Expand-Faixa -Ip '10.0.0.0' -Prefixo 30)[0] '/30 comeca no .1'

    $p31 = @(Expand-Faixa -Ip '10.0.0.0' -Prefixo 31)
    Assert-Igual 2 $p31.Count '/31 tem 2 enderecos (RFC 3021)'
    Assert-Igual '10.0.0.0' $p31[0] '/31 inclui o proprio endereco de rede'

    $p32 = @(Expand-Faixa -Ip '10.0.0.5' -Prefixo 32)
    Assert-Igual 1 $p32.Count '/32 nao pode sair vazio'
    Assert-Igual '10.0.0.5' $p32[0] '/32 e o proprio IP'
}

T 'Expand-Faixa recusa entrada invalida' {
    Assert-Estoura { Expand-Faixa -Ip '10.204.12' -Prefixo 24 } 'IP truncado'
    Assert-Estoura { Expand-Faixa -Ip '10.204.12.0' -Prefixo 33 } 'prefixo 33'
    Assert-Estoura { Expand-Faixa -Ip '10.204.12.0' -Prefixo -1 } 'prefixo negativo'
    Assert-Estoura { Expand-Faixa -Ip '10.0.0.0' -Prefixo 8 -Maximo 1024 } 'acima do maximo'
}

# ------------------------------------------------------------ Get-FaixaDeTexto

Write-Host ""
Write-Host "Get-FaixaDeTexto e Resolve-FaixasVarredura" -ForegroundColor Cyan

T 'Get-FaixaDeTexto aceita as tres formas de escrever' {
    $a = Get-FaixaDeTexto '10.204.12.0/24'
    Assert-Igual 24 $a.Prefixo 'CIDR'
    Assert-Igual '10.204.12.0' $a.Rede 'rede do CIDR'

    $b = Get-FaixaDeTexto '10.204.12.0/255.255.255.0'
    Assert-Igual 24 $b.Prefixo 'mascara pontilhada'

    $c = Get-FaixaDeTexto '10.204.12.0'
    Assert-Igual 24 $c.Prefixo 'sem prefixo assume /24'
}

T 'Get-FaixaDeTexto calcula a rede a partir de um host qualquer' {
    $f = Get-FaixaDeTexto '10.16.251.71/22'
    Assert-Igual '10.16.248.0' $f.Rede  'rede da /22'
    Assert-Igual '10.16.248.0/22' $f.Chave 'chave canonica'
}

T 'Get-FaixaDeTexto recusa lixo' {
    Assert-Estoura { Get-FaixaDeTexto '' }               'vazio'
    Assert-Estoura { Get-FaixaDeTexto '10.204.12/24' }   'IP truncado'
    Assert-Estoura { Get-FaixaDeTexto '10.204.12.0/99' } 'prefixo fora de faixa'
    Assert-Estoura { Get-FaixaDeTexto '10.204.12.0/xyz' } 'prefixo nao numerico'
}

T 'Resolve-FaixasVarredura junta fabrica, destino e placa' {
    $r = @(Resolve-FaixasVarredura -IpFabrica '192.168.1.108' -Gateway '10.70.20.1' `
                                 -LocaisPlaca @(@{ Ip = '10.16.251.71'; Prefixo = 22 }))
    Assert-Igual 3 $r.Count 'tres faixas distintas'
    Assert-Verdade ($r.Chave -contains '192.168.1.0/24')  'faixa de fabrica'
    Assert-Verdade ($r.Chave -contains '10.70.20.0/24')  'faixa de destino'
    Assert-Verdade ($r.Chave -contains '10.16.248.0/22') 'faixa da placa'
    foreach ($f in $r) { Assert-Verdade $f.Varrer ('varre ' + $f.Chave) }
}

T 'Resolve-FaixasVarredura nao repete faixa' {
    # Gateway na mesma /24 do IP de fabrica: uma faixa, nao duas.
    $r = @(Resolve-FaixasVarredura -IpFabrica '192.168.1.108' -Gateway '192.168.1.1' -LocaisPlaca @())
    Assert-Igual 1 $r.Count 'faixa unica'
}

T 'Resolve-FaixasVarredura respeita o teto' {
    $r = @(Resolve-FaixasVarredura -IpFabrica '192.168.1.108' -Gateway '' `
                                 -LocaisPlaca @(@{ Ip = '10.16.251.71'; Prefixo = 16 }) -Teto 1024)
    $grande = @($r | Where-Object { $_.Prefixo -eq 16 })[0]
    Assert-Igual 65534 $grande.Hosts 'contagem da /16'
    Assert-Falso $grande.Varrer 'nao varre acima do teto'
    Assert-Verdade ($grande.Aviso -like '*acima do teto*') 'explica por que nao varreu'

    $pequena = @($r | Where-Object { $_.Prefixo -eq 24 })[0]
    Assert-Verdade $pequena.Varrer 'a faixa pequena continua sendo varrida'
}

T 'Resolve-FaixasVarredura deixa -FaixasVarredura mandar' {
    $r = @(Resolve-FaixasVarredura -IpFabrica '192.168.1.108' -Gateway '10.70.20.1' `
                                 -LocaisPlaca @(@{ Ip = '10.16.251.71'; Prefixo = 22 }) `
                                 -Explicitas @('10.204.12.0/24'))
    Assert-Igual 1 $r.Count 'so a faixa declarada'
    Assert-Igual '10.204.12.0/24' $r[0].Chave 'a que foi declarada'
}

T 'Resolve-FaixasVarredura ignora placa com IP invalido' {
    $r = @(Resolve-FaixasVarredura -IpFabrica '192.168.1.108' -Gateway '' `
                                 -LocaisPlaca @(@{ Ip = '169.254'; Prefixo = 16 }, @{ Ip = $null }))
    Assert-Igual 1 $r.Count 'somente a faixa de fabrica'
}

# ------------------------------------------------------------- MAC, OUI, lista

Write-Host ""
Write-Host "MAC, OUI e blacklist" -ForegroundColor Cyan

T 'Get-MacNormalizado tira separador e sobe caixa' {
    Assert-Igual '98E55BA600F5' (Get-MacNormalizado '98:e5:5b:a6:00:f5') 'dois pontos'
    Assert-Igual '98E55BA600F5' (Get-MacNormalizado '98-E5-5B-A6-00-F5') 'hifen'
    Assert-Igual '98E55BA600F5' (Get-MacNormalizado '98e55ba600f5')      'sem separador'
    Assert-Igual ''             (Get-MacNormalizado '')                  'vazio'
    Assert-Igual ''             (Get-MacNormalizado $null)               'nulo'
}

T 'Get-OuiCameras traz os dois prefixos confirmados no inventario' {
    $o = @(Get-OuiCameras)
    Assert-Verdade ($o -contains '98E55B') 'VIP-5460-Z-IA e VIP-3430-D-IA'
    Assert-Verdade ($o -contains '54BAD9') 'VIP-5460-LPR-IA'
}

T 'Get-OuiCameras aceita extra sem duplicar' {
    $o = @(Get-OuiCameras -Extra @('aa:bb:cc:11:22:33', '98:e5:5b:00:00:00'))
    Assert-Verdade ($o -contains 'AABBCC') 'extra entrou'
    Assert-Igual 1 (@($o | Where-Object { $_ -eq '98E55B' }).Count) 'nao duplicou o que ja existia'
}

T 'Test-OuiConhecido casa pelo prefixo, nao pelo MAC inteiro' {
    $o = @(Get-OuiCameras)
    Assert-Verdade (Test-OuiConhecido '98:e5:5b:ff:ff:ff' $o) 'outro sufixo, mesmo OUI'
    Assert-Falso   (Test-OuiConhecido '00:11:22:33:44:55' $o) 'OUI desconhecido'
    Assert-Falso   (Test-OuiConhecido '98:e5' $o)             'MAC curto demais'
    Assert-Falso   (Test-OuiConhecido '' $o)                  'vazio'
}

T 'Blacklist grava e le de volta' {
    $arq = Join-Path $env:TEMP ('bl-' + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
        Assert-Verdade (Add-Blacklist -Caminho $arq -Mac '00:11:22:33:44:55' -Motivo 'impressora') 'gravou'
        Assert-Verdade (Add-Blacklist -Caminho $arq -Mac 'aa-bb-cc-dd-ee-ff' -Motivo 'desktop')   'gravou 2'
        $h = Import-Blacklist -Caminho $arq
        Assert-Igual 2 $h.Count 'duas entradas'
        Assert-Verdade $h.ContainsKey('001122334455') 'chave normalizada 1'
        Assert-Verdade $h.ContainsKey('AABBCCDDEEFF') 'chave normalizada 2'
        Assert-Igual 'impressora' $h['001122334455'] 'motivo preservado'
    } finally {
        Remove-Item $arq -Force -ErrorAction SilentlyContinue
    }
}

T 'Blacklist ignora comentario, linha vazia e MAC furado' {
    $arq = Join-Path $env:TEMP ('bl-' + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
        Set-Content -Path $arq -Encoding utf8 -Value @(
            '# comentario no topo',
            '',
            '   # comentario indentado',
            '00:11:22:33:44:55;2026-08-28 10:00;impressora',
            'nao-e-mac;2026-08-28 10:00;lixo',
            '00:11:22;2026-08-28 10:00;curto demais'
        )
        $h = Import-Blacklist -Caminho $arq
        Assert-Igual 1 $h.Count 'so a entrada valida'
        Assert-Verdade $h.ContainsKey('001122334455') 'a valida entrou'
    } finally {
        Remove-Item $arq -Force -ErrorAction SilentlyContinue
    }
}

T 'Blacklist inexistente devolve vazio em vez de estourar' {
    $h = Import-Blacklist -Caminho (Join-Path $env:TEMP 'nao-existe-mesmo-12345.txt')
    Assert-Igual 0 $h.Count 'hashtable vazia'
    $h2 = Import-Blacklist -Caminho ''
    Assert-Igual 0 $h2.Count 'caminho vazio'
}

T 'Add-Blacklist recusa MAC invalido' {
    $arq = Join-Path $env:TEMP ('bl-' + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
        Assert-Falso (Add-Blacklist -Caminho $arq -Mac 'xyz')      'texto'
        Assert-Falso (Add-Blacklist -Caminho $arq -Mac '00:11:22') 'curto'
        Assert-Falso (Add-Blacklist -Caminho $arq -Mac '')         'vazio'
    } finally {
        Remove-Item $arq -Force -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------- contrato de retorno de colecao

Write-Host ""
Write-Host "Contrato de retorno: zero, um e N" -ForegroundColor Cyan

<#
    Esta secao existe por causa de um bug real que passou pela primeira versao
    destes testes.

    A tentativa de garantir array com o idioma 'return ,$array' funcionou para
    UM item e QUEBROU o caso VAZIO: o valor volta como um objeto que E um array
    vazio, e @() em cima dele conta 1. Na pratica a varredura passou a relatar
    um host vivo onde nao havia nenhum, e o atalho foi sondar um 192.168.1.108
    que nao existia - com a mensagem convincente de que 'responde ao ping mas
    nao e camera'.

    Nenhum teste da primeira versao exercitava retorno vazio. Estes exercitam.
#>

T 'Retorno vazio conta zero, nao um' {
    Assert-Igual 0 @(Invoke-PingSweep -Ips @()).Count 'ping sweep sem alvo'
    Assert-Igual 0 @(Resolve-FaixasVarredura -IpFabrica '' -Gateway '' -LocaisPlaca @()).Count 'nenhuma faixa resolvivel'
    Assert-Igual 0 @(Expand-Faixa -Ip '10.0.0.5' -Prefixo 32 -Excluir @('10.0.0.5')).Count 'unico host excluido'
}

T 'Retorno de um item conta um e indexa o item, nao o caractere' {
    $f = @(Resolve-FaixasVarredura -IpFabrica '192.168.1.108' -Gateway '' -LocaisPlaca @())
    Assert-Igual 1 $f.Count 'uma faixa'
    Assert-Igual '192.168.1.0/24' $f[0].Chave 'indexa o objeto'

    $e = @(Expand-Faixa -Ip '10.0.0.5' -Prefixo 32)
    Assert-Igual 1 $e.Count 'um host'
    Assert-Igual '10.0.0.5' $e[0] 'indexa o IP inteiro e nao o primeiro digito'
}

T 'Invoke-PingSweep aceita lista nula sem estourar' {
    Assert-Igual 0 @(Invoke-PingSweep -Ips $null).Count 'nulo'
}

# --------------------------------------------------- leitura do getStatus

Write-Host ""
Write-Host "Read-RespostaInit" -ForegroundColor Cyan

T 'Camera de fabrica: Init=1 e Find lido' {
    $r = Read-RespostaInit '{"id":1,"params":{"Find":"AB","Init":1,"Status":0},"result":true,"session":0}'
    Assert-Verdade $r.EhCamera   'e camera'
    Assert-Verdade $r.Ok         'result true'
    Assert-Verdade $r.PareceJson 'parece json'
    Assert-Igual 1    $r.Init 'de fabrica'
    Assert-Igual 'AB' $r.Find 'telefone e e-mail suportados'
}

T 'Camera ja inicializada: Init=0' {
    $r = Read-RespostaInit '{"id":1,"params":{"Find":"AB","Init":0,"Status":0},"result":true,"session":0}'
    Assert-Verdade $r.EhCamera 'e camera'
    Assert-Igual 0 $r.Init 'ja inicializada'
}

T 'Resposta vazia nao e camera e nao parece json' {
    $r = Read-RespostaInit ''
    Assert-Falso $r.EhCamera   'nao e camera'
    Assert-Falso $r.PareceJson 'nao parece json'
    Assert-Igual -1 $r.Init 'init desconhecido'

    $r2 = Read-RespostaInit $null
    Assert-Falso $r2.EhCamera 'nulo tambem'
}

T 'HTML de outro equipamento nao e camera nem parece json' {
    # Este e o unico caso em que o MAC pode ir para a blacklist.
    $r = Read-RespostaInit '<html><head><title>Impressora</title></head><body>404</body></html>'
    Assert-Falso $r.EhCamera   'nao e camera'
    Assert-Falso $r.PareceJson 'HTML nao passa por json'
}

T 'Notificacao assincrona do firmware conta como camera' {
    # O API-INTELBRAS.md registra que a camera EMPURRA notificacao que sai como
    # corpo da resposta seguinte. Se isso nao contasse como camera, o MAC dela
    # iria para a blacklist e ela ficaria invisivel nas proximas execucoes.
    $r = Read-RespostaInit '{ "NotifyMethod" : "1.2" }'
    Assert-Verdade $r.EhCamera   'reconhecida apesar de nao ser o getStatus'
    Assert-Verdade $r.PareceJson 'parece json'
    Assert-Igual -1 $r.Init 'sem Init nessa resposta'
}

T 'Erro de RPC do firmware ainda identifica camera' {
    $r = Read-RespostaInit '{"error":{"code":268632079,"message":"login challenge!"},"id":1,"result":false}'
    Assert-Verdade $r.EhCamera 'e camera'
    Assert-Falso   $r.Ok       'result false'
}

T 'JSON de servico qualquer nao vira camera, mas escapa da blacklist' {
    # Nao e camera, e tambem nao vai para a blacklist: parece json, e o criterio
    # para marcar e ser CLARAMENTE outra coisa. Conservador de proposito - errar
    # aqui esconderia uma camera boa das execucoes seguintes.
    $r = Read-RespostaInit '{"status":"ok","uptime":1234}'
    Assert-Falso   $r.EhCamera   'nao e camera'
    Assert-Verdade $r.PareceJson 'freio da blacklist ativo'
}

T 'Bruto e preservado para o log' {
    $bruto = '{"id":1,"params":{"Init":1},"result":true}'
    Assert-Igual $bruto (Read-RespostaInit $bruto).Bruto 'resposta crua guardada'
}

# ------------------------------------------------------- descoberta DHIP

Write-Host ""
Write-Host "Descoberta DHIP (UDP 37810)" -ForegroundColor Cyan

# Resposta REAL de uma VIP-1230-D-G4 em 30/09/2026 (so o JSON; o datagrama
# traz 32 bytes de cabecalho antes e um NUL depois).
$script:dhipJson = ([IO.File]::ReadAllText((Join-Path $raiz 'testes\dhip-notifydevinfo-vip1230-d-g4.json'), [Text.Encoding]::ASCII)).Trim()

T 'New-PacoteDhip: 32 bytes de cabecalho (0x20, DHIP, id, tamanho) + JSON do DHDiscover.search' {
    $p = New-PacoteDhip -Id 7
    $json = '{"method":"DHDiscover.search","params":{"mac":"","uni":1},"id":7}'
    Assert-Igual (32 + $json.Length) $p.Length 'tamanho total'
    Assert-Igual 32 ([int]$p[0]) 'byte 0 (0x20)'
    Assert-Igual 'DHIP' ([Text.Encoding]::ASCII.GetString($p, 4, 4)) 'assinatura'
    Assert-Igual 0 ([BitConverter]::ToUInt32($p, 8)) 'sessao 0'
    Assert-Igual 7 ([BitConverter]::ToUInt32($p, 12)) 'id'
    Assert-Igual $json.Length ([BitConverter]::ToUInt32($p, 16)) 'tamanho em 16'
    Assert-Igual $json.Length ([BitConverter]::ToUInt32($p, 24)) 'tamanho em 24'
    Assert-Igual $json ([Text.Encoding]::ASCII.GetString($p, 32, $json.Length)) 'json'
}

T 'ConvertFrom-RespostaDhip le a resposta real: IP, mascara, gateway, MAC, modelo, serial, firmware, porta, classe, Init' {
    $r = ConvertFrom-RespostaDhip -Json $script:dhipJson
    Assert-Verdade ($null -ne $r) 'leu'
    Assert-Igual '10.16.250.102|255.255.255.0|10.16.250.1|False' ($r.Ip + '|' + $r.Mascara + '|' + $r.Gateway + '|' + $r.Dhcp) 'rede'
    Assert-Igual '30E1F1000065' $r.Mac 'MAC normalizado'
    Assert-Igual 'VIP-1230-D-G4|EXEMPLO0000001|2.800.00IB00C.0.T' ($r.Modelo + '|' + $r.Serial + '|' + $r.Firmware) 'identidade'
    Assert-Igual '80|37777|IPC' ([string]$r.HttpPort + '|' + $r.Porta + '|' + $r.Classe) 'portas e classe'
    Assert-Igual '3210|2|BC|IntelBras' ([string]$r.InitBruto + '|' + $r.Init + '|' + $r.Find + '|' + $r.Fabricante) 'init normalizado'
    Assert-Igual $script:dhipJson $r.Bruto 'bruto'
}

T 'ConvertFrom-RespostaDhip -Bytes: cabecalho + JSON + NUL; assinatura errada, outro metodo e lixo dao nulo' {
    $json = [Text.Encoding]::ASCII.GetBytes($script:dhipJson)
    $cab = New-Object byte[] 32
    $cab[0] = 0x20
    [Array]::Copy([Text.Encoding]::ASCII.GetBytes('DHIP'), 0, $cab, 4, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]($json.Length + 1)), 0, $cab, 16, 4)
    $dat = [byte[]]($cab + $json + [byte[]]@(0))
    $r = ConvertFrom-RespostaDhip -Bytes $dat
    Assert-Igual '10.16.250.102|30E1F1000065' ($r.Ip + '|' + $r.Mac) 'datagrama inteiro'
    # Tamanho no cabecalho maior que o datagrama: usa o que tem.
    [Array]::Copy([BitConverter]::GetBytes([uint32]9999), 0, $dat, 16, 4)
    Assert-Igual '10.16.250.102' (ConvertFrom-RespostaDhip -Bytes $dat).Ip 'tamanho furado'
    $ruim = [byte[]]($dat.Clone()); $ruim[4] = 0x58
    Assert-Verdade ($null -eq (ConvertFrom-RespostaDhip -Bytes $ruim)) 'assinatura errada'
    Assert-Verdade ($null -eq (ConvertFrom-RespostaDhip -Bytes ([byte[]]@(1, 2, 3)))) 'curto demais'
    Assert-Verdade ($null -eq (ConvertFrom-RespostaDhip -Json '{"method":"client.notifyOther","params":{}}')) 'outro metodo'
    Assert-Verdade ($null -eq (ConvertFrom-RespostaDhip -Json '{"method":"client.notifyDevInfo","params":{}}')) 'sem deviceInfo'
    Assert-Verdade ($null -eq (ConvertFrom-RespostaDhip -Json 'nao e json')) 'lixo'
    Assert-Verdade ($null -eq (ConvertFrom-RespostaDhip -Json '')) 'vazio'
    # Sem HttpPort e sem Init: 80 e desconhecido.
    $r = ConvertFrom-RespostaDhip -Json '{"mac":"aa:bb:cc:00:00:01","method":"client.notifyDevInfo","params":{"deviceInfo":{"IPv4Address":{"IPAddress":"10.0.0.5"}}}}'
    Assert-Igual '10.0.0.5|80|-1|-1' ($r.Ip + '|' + $r.HttpPort + '|' + $r.InitBruto + '|' + $r.Init) 'defaults'
}

T 'Init normalizado: os dois bits baixos dizem o estado; 1 = de fabrica' {
    Assert-Igual 2 (Get-InitNormalizado 3210) '3210 (VIP-1230-D-G4)'
    Assert-Igual 2 (Get-InitNormalizado 3222) '3222 (BSC)'
    Assert-Igual 2 (Get-InitNormalizado 3734) '3734 (VIP-1430)'
    Assert-Igual 2 (Get-InitNormalizado 3238) '3238 (NVR)'
    Assert-Igual 2 (Get-InitNormalizado 3722) '3722 (VIPC-1230)'
    Assert-Igual 1 (Get-InitNormalizado 1) 'HTTP getStatus de fabrica'
    Assert-Igual 1 (Get-InitNormalizado 3209) 'bitmap com bit de fabrica'
    Assert-Igual 0 (Get-InitNormalizado 0) 'HTTP firmware antigo'
    Assert-Igual 2 (Get-InitNormalizado '2') 'texto'
    Assert-Igual -1 (Get-InitNormalizado -1) 'desconhecido'
    Assert-Igual -1 (Get-InitNormalizado $null) 'nulo'
    Assert-Igual -1 (Get-InitNormalizado 'x') 'lixo'
    Assert-Verdade (Test-InitDeFabrica 1) 'de fabrica'
    Assert-Verdade (Test-InitDeFabrica 3209) 'de fabrica no bitmap'
    Assert-Falso (Test-InitDeFabrica 3210) 'inicializada'
    Assert-Falso (Test-InitDeFabrica -1) 'desconhecido nao e de fabrica'
}

T 'Get-AchadosDhipUnicos: um por MAC, so IPC salvo -IncluirOutros; zero, um e N' {
    $a = @(
        [pscustomobject]@{ Ip = '10.16.250.102'; Mac = '30E1F1000065'; Classe = 'IPC' },
        [pscustomobject]@{ Ip = '10.16.250.102'; Mac = '30E1F1000065'; Classe = 'IPC' },   # respondeu de novo (outro destino)
        [pscustomobject]@{ Ip = '10.16.250.200'; Mac = '58108C88984A'; Classe = 'NVR' },
        [pscustomobject]@{ Ip = '10.16.250.11';  Mac = 'C0395A69736E'; Classe = 'BSC' },
        [pscustomobject]@{ Ip = '192.168.1.108';  Mac = '';             Classe = '' },      # sem MAC nem classe: entra por IP
        [pscustomobject]@{ Ip = '192.168.1.108';  Mac = '';             Classe = '' },
        [pscustomobject]@{ Ip = 'lixo';           Mac = 'AABBCC000001'; Classe = 'IPC' }
    )
    $u = @(Get-AchadosDhipUnicos -Achados $a)
    Assert-Igual '10.16.250.102,192.168.1.108' (($u | ForEach-Object { $_.Ip }) -join ',') 'so IPC e sem classe'
    $u = @(Get-AchadosDhipUnicos -Achados $a -IncluirOutros)
    Assert-Igual 4 $u.Count 'com NVR e BSC'
    Assert-Igual 0 @(Get-AchadosDhipUnicos -Achados @()).Count 'vazio'
    Assert-Igual 0 @(Get-AchadosDhipUnicos -Achados $null).Count 'nulo'
    $um = @(Get-AchadosDhipUnicos -Achados @($a[0]))
    Assert-Igual 1 $um.Count 'um'
    Assert-Igual '10.16.250.102' $um[0].Ip 'indexa o objeto'
}

T 'Get-BroadcastDaFaixa e Test-IpAlcancavel' {
    Assert-Igual '10.16.251.255' (Get-BroadcastDaFaixa -Ip '10.16.251.207' -Prefixo 22) '/22'
    Assert-Igual '192.168.1.255'  (Get-BroadcastDaFaixa -Ip '192.168.1.220' -Prefixo 24) '/24'
    Assert-Igual '10.0.255.255'   (Get-BroadcastDaFaixa -Ip '10.0.3.4' -Prefixo 16) '/16'
    Assert-Igual '10.0.0.3'       (Get-BroadcastDaFaixa -Ip '10.0.0.1' -Prefixo 30) '/30'
    Assert-Estoura { Get-BroadcastDaFaixa -Ip '10.0.0.1' -Prefixo 33 } 'prefixo 33'

    $locais = @(@{ Ip = '10.16.251.207'; Prefixo = 22 }, @{ Ip = '192.168.1.220'; Prefixo = 24 })
    Assert-Verdade (Test-IpAlcancavel -Ip '10.16.250.102' -Locais $locais) 'outro /24 da mesma /22'
    Assert-Verdade (Test-IpAlcancavel -Ip '192.168.1.108' -Locais $locais) 'faixa de fabrica'
    Assert-Falso   (Test-IpAlcancavel -Ip '192.168.0.64' -Locais $locais) 'fora'
    Assert-Falso   (Test-IpAlcancavel -Ip '10.16.252.1' -Locais $locais) 'vizinha da /22'
    Assert-Verdade (Test-IpAlcancavel -Ip '10.0.0.9' -Locais @(@{ Ip = '10.0.0.1' })) 'sem prefixo assume /24'
    Assert-Falso   (Test-IpAlcancavel -Ip 'lixo' -Locais $locais) 'IP invalido'
    Assert-Falso   (Test-IpAlcancavel -Ip '10.0.0.1' -Locais @()) 'sem locais'
}

T 'Get-CandidatosIpLocal: .220 primeiro, depois .200-.249 pelo MAC; exclui camera, gateway, rede, broadcast' {
    $c = @(Get-CandidatosIpLocal -IpCamera '192.168.0.64' -Mascara '255.255.255.0' -Gateway '192.168.0.1' -MacPlaca '00-11-22-33-44-55')
    Assert-Igual '192.168.0.220' $c[0] 'primeiro'
    Assert-Igual 50 $c.Count '.220 + 49 restantes de .200-.249 (o .220 nao repete)'
    foreach ($ip in $c) { $n = [int]($ip -split '\.')[3]; Assert-Verdade ($n -ge 200 -and $n -le 249) ('dentro de .200-.249: ' + $ip) }
    $c2 = @(Get-CandidatosIpLocal -IpCamera '192.168.0.64' -Mascara '255.255.255.0' -Gateway '192.168.0.1' -MacPlaca '00-11-22-33-44-55')
    Assert-Igual ($c -join ',') ($c2 -join ',') 'deterministico pelo MAC'
    $c3 = @(Get-CandidatosIpLocal -IpCamera '192.168.0.64' -Mascara '255.255.255.0' -Gateway '192.168.0.1' -MacPlaca 'FF-EE-DD-CC-BB-AA')
    Assert-Verdade ($c3[1] -ne $c[1] -or $c3[2] -ne $c[2]) 'outro MAC, outra ordem'

    # Camera no .220 e gateway no .201: os dois saem; -Excluir tambem.
    $c = @(Get-CandidatosIpLocal -IpCamera '192.168.0.220' -Mascara '255.255.255.0' -Gateway '192.168.0.201' -Excluir @('192.168.0.202'))
    Assert-Falso ($c -contains '192.168.0.220') 'camera fora'
    Assert-Falso ($c -contains '192.168.0.201') 'gateway fora'
    Assert-Falso ($c -contains '192.168.0.202') 'excluido fora'
    Assert-Igual 47 $c.Count '50 - 3'

    # /16: continua no /24 da camera.
    $c = @(Get-CandidatosIpLocal -IpCamera '10.20.30.40' -Mascara '255.255.0.0')
    Assert-Igual '10.20.30.220' $c[0] 'no /24 da camera'
    # /26 (rede pequena): hosts do topo para baixo, sem rede/broadcast/camera.
    $c = @(Get-CandidatosIpLocal -IpCamera '10.0.0.70' -Mascara '255.255.255.192' -Gateway '10.0.0.65')
    Assert-Igual '10.0.0.126' $c[0] 'topo da /26'
    Assert-Falso ($c -contains '10.0.0.127') 'broadcast fora'
    Assert-Falso ($c -contains '10.0.0.70') 'camera fora'
    Assert-Falso ($c -contains '10.0.0.65') 'gateway fora'
    Assert-Igual 50 $c.Count 'teto de 50'
    Assert-Igual 3 @(Get-CandidatosIpLocal -IpCamera '10.0.0.70' -Mascara '255.255.255.192' -Maximo 3).Count '-Maximo'
    # Mascara furada cai para /24.
    Assert-Igual '10.0.0.220' @(Get-CandidatosIpLocal -IpCamera '10.0.0.70' -Mascara 'lixo')[0] 'mascara invalida'
}

T 'Porta HTTP por IP e URL da camera' {
    $script:PortasHttp = $null
    Assert-Igual 80 (Get-CamPortaHttp '10.16.250.213') 'sem registro = 80'
    Assert-Igual 'http://10.16.250.213/OutsideCmd' (ConvertTo-UrlCam -Ip '10.16.250.213' -Endpoint '/OutsideCmd') 'sem porta'
    Set-CamPortaHttp -Ip '10.16.250.213' -Porta 8081
    Assert-Igual 8081 (Get-CamPortaHttp '10.16.250.213') 'registrada'
    Assert-Igual 'http://10.16.250.213:8081/RPC2' (ConvertTo-UrlCam -Ip '10.16.250.213' -Endpoint '/RPC2') 'com porta'
    Assert-Igual 'http://10.16.250.213:9000/RPC2' (ConvertTo-UrlCam -Ip '10.16.250.213' -Endpoint '/RPC2' -Porta 9000) 'porta explicita manda'
    Assert-Igual 'http://10.0.0.5/RPC2' (ConvertTo-UrlCam -Ip '10.0.0.5' -Endpoint '/RPC2') 'outro IP continua 80'
    Set-CamPortaHttp -Ip '10.16.250.213' -Porta 80
    Assert-Igual 80 (Get-CamPortaHttp '10.16.250.213') '80 apaga o registro'
    Set-CamPortaHttp -Ip 'lixo' -Porta 8081
    Assert-Igual 80 (Get-CamPortaHttp 'lixo') 'IP invalido nao registra'
}

# ------------------------------------------------------------------- resultado

Write-Host ""
Write-Host ("  " + $script:Ok + " passaram, " + $script:Falhou + " falharam") -ForegroundColor $(
    if ($script:Falhou -eq 0) { 'Green' } else { 'Red' })
if ($script:Falhou -gt 0) {
    Write-Host ""
    foreach ($f in $script:Falhas) { Write-Host ("  - " + $f) -ForegroundColor Red }
    Write-Host ""
    exit 1
}
Write-Host ""
