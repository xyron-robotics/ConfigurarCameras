<#
    Motor-Cameras.ps1
    Motor do painel: tudo o que fala com a camera e com a placa de rede do PC,
    sem nenhuma interacao com o operador (nenhum Read-Host). Carregado por
    dot-source no runspace do worker do Servidor-Painel.ps1.

    ORIGEM
      As funcoes de rede, descoberta e inicializacao vieram do CLI antigo
      (Configurar-Cameras.ps1, removido do repositorio em 30/09/2026; esta no
      historico do git). O CLI falava CGI; o RPC2 ainda nao foi validado em
      campo numa VIP-5460 (docs/adr/0001).

    PROTOCOLO
      RPC2 em tudo: login MD5 em desafio (/RPC2_Login) e chamadas com sessao
      (/RPC2). A CGI com Digest da 401 em firmware antigo mesmo com a senha
      certa (VIP-1230-D-G3, fw 2.800, 29/09/2026). A inicializacao continua no
      /OutsideCmd, que e anonimo.

    CONFIGURACAO (glossario em CONTEXT.md)
      Passada unica, nesta ordem, cada etapa gravada no registro ao terminar:
        inicializada -> encoder -> rede -> conferida
      Falha antes da conferencia retoma da etapa que falhou. Encoder vem ANTES
      da rede porque, depois que o IP muda, a camera so responde no IP novo.

    SESSAO E PLACA ESCOLHIDA (desde a 1.2.0; glossario em CONTEXT.md)
      sessao.json guarda o que o passo a passo monta (placa escolhida, rede
      das cameras, faixa de fabrica, camera, ultima fila). A placa escolhida
      e a UNICA via ate as cameras: placa pronta, alcance, broadcast e IP
      temporario olham so para ela (-IfIndex). Camera cujo IP cai na faixa
      de outra placa do PC recebe rota de host /32 na escolhida (ADR 0003).
      "SessaoPlaca" (placa-sessao.json) e outra coisa: o RASTRO do que o
      painel fez na placa, para devolver ao encerrar (ADR 0002).

    REGRAS
      - Nada roda ao carregar: so definicoes e defaults em $script:.
      - Toda dependencia entra por parametro (as globais do CLI sairam).
      - A senha nunca vai para log, registro ou relatorio.
      - Chamadas contra a MESMA camera sao serializadas - o firmware nao
        aguenta concorrencia. Quem garante e o worker unico do servidor.
#>

# ------------------------------------------------------------------- log

# $script:LogFile vazio = sem arquivo. $script:LogSink = scriptblock
# { param($Ts, $Msg, $Cor) } que recebe cada linha (o servidor manda para o
# painel). Sem sink, a linha vai para a tela, como no CLI.
$script:LogFile = ''
$script:LogSink = $null

function Set-MotorLog {
    param([string]$Arquivo = '', [scriptblock]$Sink = $null)
    $script:LogFile = $Arquivo
    $script:LogSink = $Sink
}

function Write-Log {
    param([string]$Msg, [string]$Cor = 'Gray', [switch]$SemTela)
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    if (-not [string]::IsNullOrWhiteSpace($script:LogFile)) {
        # Gravar log nunca pode derrubar a configuracao de uma camera.
        try { Add-Content -Path $script:LogFile -Value ("[$ts] " + $Msg) -Encoding utf8 -ErrorAction Stop } catch { }
    }
    if ($SemTela) { return }
    if ($null -ne $script:LogSink) {
        try { & $script:LogSink $ts $Msg $Cor } catch { }
    } else {
        Write-Host $Msg -ForegroundColor $Cor
    }
}

# Etapa em andamento, para o painel mostrar ao vivo.
# Sink = { param($Etapa, $Detalhe, $Atual, $Total) }. Etapa vazia = mesma
# etapa, so o detalhe muda (ex.: contagem da espera do boot). Total 0 = sem
# contagem. O detalhe vai para a tela: com acento.
$script:ProgressoSink = $null

function Set-MotorProgresso {
    param([scriptblock]$Sink = $null)
    $script:ProgressoSink = $Sink
}

function Write-Progresso {
    param([string]$Etapa = '', [string]$Detalhe = '', [int]$Atual = 0, [int]$Total = 0)
    if ($null -ne $script:ProgressoSink) { try { & $script:ProgressoSink $Etapa $Detalhe $Atual $Total } catch { } }
}

# Corpo de resposta para log: curto e numa linha. Resposta de camera nunca
# traz a senha, mas pode ser enorme (a tabela Encode tem 4 KB).
function Get-TrechoSeguro {
    param([string]$Texto, [int]$Maximo = 200)
    if ([string]::IsNullOrEmpty($Texto)) { return '(vazio)' }
    $t = ($Texto -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Maximo) { $t = $t.Substring(0, $Maximo) + '...' }
    return $t
}

# ------------------------------------------------------------------
# Utilitarios de rede local e descoberta (herdados do CLI antigo).
# Cobertos por Testes-Descoberta.ps1.
# ------------------------------------------------------------------

function Assert-Curl {
    if ($null -eq (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw "curl.exe nao encontrado. O painel usa o curl.exe do Windows para falar com a camera. " +
              "Vem de fabrica no Windows 10 1803+ e no Windows 11."
    }
}

# -IfIndex > 0: so os IPs daquela placa (a placa escolhida na sessao e a unica
# via do painel ate as cameras; o IP do Wi-Fi na mesma faixa nao conta).
# 0 = todas as placas.
function Get-IpsLocais {
    param([int]$IfIndex = 0)
    return @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and ($IfIndex -le 0 -or [int]$_.InterfaceIndex -eq $IfIndex) } |
             Select-Object -ExpandProperty IPAddress)
}

function Get-Prefixo24 {
    param([string]$Ip)
    $p = $Ip -split '\.'
    if ($p.Count -lt 3) { return '' }
    return ($p[0] + '.' + $p[1] + '.' + $p[2])
}

function Test-EhAdministrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IpEmUso {
    param([string]$Ip)
    return [bool](Test-Connection -ComputerName $Ip -Count 2 -Quiet -ErrorAction SilentlyContinue)
}

function Test-IpLocal {
    param([string]$Ip)
    $meus = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Select-Object -ExpandProperty IPAddress)
    return ($meus -contains $Ip)
}

# --- pecas puras: IPv4, faixa, MAC, OUI, blacklist

function Test-Ipv4Estrito {
    param([string]$Ip)

    if ([string]::IsNullOrWhiteSpace($Ip)) { return $false }
    $p = $Ip.Trim() -split '\.'
    if ($p.Count -ne 4) { return $false }
    foreach ($o in $p) {
        if ($o -notmatch '^\d{1,3}$') { return $false }
        if ([int]$o -gt 255)          { return $false }
    }
    return $true
}

function ConvertTo-Ipv4Numero {
    param([Parameter(Mandatory)][string]$Ip)

    if (-not (Test-Ipv4Estrito $Ip)) { throw ("IP invalido: " + $Ip) }
    $p = $Ip.Trim() -split '\.'
    $n = ([uint64][int]$p[0] -shl 24) -bor ([uint64][int]$p[1] -shl 16) -bor
         ([uint64][int]$p[2] -shl  8) -bor  [uint64][int]$p[3]
    return [uint32]$n
}

function ConvertFrom-Ipv4Numero {
    param([Parameter(Mandatory)][uint32]$Numero)

    $n = [uint64]$Numero
    return ([string](($n -shr 24) -band 255) + '.' +
            [string](($n -shr 16) -band 255) + '.' +
            [string](($n -shr  8) -band 255) + '.' +
            [string]( $n          -band 255))
}

function Get-HostsNaFaixa {
    param([Parameter(Mandatory)][int]$Prefixo)

    if ($Prefixo -lt 0 -or $Prefixo -gt 32) { throw ("prefixo invalido: " + $Prefixo) }
    $total = [int64][math]::Pow(2, 32 - $Prefixo)
    if ($Prefixo -ge 31) { return $total }
    return ($total - 2)
}

function ConvertTo-PrefixoDeMascara {
    param([Parameter(Mandatory)][string]$Mascara)

    if (-not (Test-Ipv4Estrito $Mascara)) { throw ("mascara invalida: " + $Mascara) }
    $n = [uint64](ConvertTo-Ipv4Numero $Mascara)
    $bits = 0
    $vendoUm = $true
    for ($i = 31; $i -ge 0; $i--) {
        if ((($n -shr $i) -band 1) -eq 1) {
            if (-not $vendoUm) { throw ("mascara nao contigua: " + $Mascara) }
            $bits++
        } else {
            $vendoUm = $false
        }
    }
    return $bits
}

function Expand-Faixa {
    param(
        [Parameter(Mandatory)][string]$Ip,
        [Parameter(Mandatory)][int]$Prefixo,
        [string[]]$Excluir = @(),
        [int]$Maximo = 65536
    )

    if ($Prefixo -lt 0 -or $Prefixo -gt 32) { throw ("prefixo invalido: " + $Prefixo) }

    $num   = [uint64](ConvertTo-Ipv4Numero $Ip)
    $todos = [uint64]4294967295
    if ($Prefixo -eq 0) { $mask = [uint64]0 }
    else                { $mask = ($todos -shl (32 - $Prefixo)) -band $todos }

    $rede  = $num -band $mask
    $bcast = $rede -bor (($todos -bxor $mask) -band $todos)

    if ($Prefixo -ge 31) { $primeiro = $rede;     $ultimo = $bcast }
    else                 { $primeiro = $rede + 1; $ultimo = $bcast - 1 }

    $quantos = [int64]($ultimo - $primeiro + 1)
    if ($quantos -gt $Maximo) {
        throw ("faixa " + (ConvertFrom-Ipv4Numero ([uint32]$rede)) + "/" + $Prefixo +
               " tem " + $quantos + " enderecos, acima do maximo de " + $Maximo)
    }

    $fora = @{}
    foreach ($e in $Excluir) {
        if (Test-Ipv4Estrito $e) { $fora[[string][uint64](ConvertTo-Ipv4Numero $e)] = $true }
    }

    $saida = New-Object 'System.Collections.Generic.List[string]'
    for ($i = $primeiro; $i -le $ultimo; $i++) {
        if ($fora.ContainsKey([string]$i)) { continue }
        $saida.Add((ConvertFrom-Ipv4Numero ([uint32]$i)))
    }
    # CONTRATO: esta funcao devolve array CRU e quem chama SEMPRE
    # embrulha em @(). As duas metades existem juntas de proposito.
    #
    # O PowerShell desembrulha colecao no retorno, entao sem o @() do
    # lado de quem chama uma lista de UM item vira escalar - e ai
    # $lista[0] devolve o primeiro CARACTERE do IP em vez do IP.
    # Resolver isso aqui com o idioma consagrado return ,$array troca
    # um bug por outro PIOR, e este custou uma sessao de campo: com a
    # lista VAZIA o valor volta como um objeto que E um array vazio, e
    # @() em cima dele conta 1. A varredura passou a relatar um host
    # vivo onde nao havia nenhum, e o atalho foi sondar um IP de
    # fabrica que nao existia. Zero, um e N precisam funcionar.
    return $saida.ToArray()
}

function Get-FaixaDeTexto {
    param([Parameter(Mandatory)][string]$Texto)

    $t = $Texto.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { throw 'faixa vazia' }

    $ip = $t
    $prefixo = 24
    if ($t.Contains('/')) {
        $partes = $t -split '/', 2
        $ip  = $partes[0].Trim()
        $dir = $partes[1].Trim()
        if ($dir -match '^\d{1,2}$')   { $prefixo = [int]$dir }
        elseif (Test-Ipv4Estrito $dir) { $prefixo = ConvertTo-PrefixoDeMascara $dir }
        else { throw ("prefixo invalido em '" + $Texto + "'") }
    }
    if (-not (Test-Ipv4Estrito $ip))        { throw ("IP invalido em '" + $Texto + "'") }
    if ($prefixo -lt 0 -or $prefixo -gt 32) { throw ("prefixo fora de 0-32 em '" + $Texto + "'") }

    $todos = [uint64]4294967295
    $mask  = [uint64]0
    if ($prefixo -gt 0) { $mask = ($todos -shl (32 - $prefixo)) -band $todos }
    $rede = ([uint64](ConvertTo-Ipv4Numero $ip)) -band $mask
    $redeTexto = ConvertFrom-Ipv4Numero ([uint32]$rede)

    return [pscustomobject]@{
        Ip      = $ip
        Prefixo = $prefixo
        Rede    = $redeTexto
        Chave   = ($redeTexto + '/' + $prefixo)
    }
}

function Resolve-FaixasVarredura {
    param(
        [string]$IpFabrica    = '192.168.1.108',
        [string]$Gateway      = '',
        [array]$LocaisPlaca   = @(),
        [string[]]$Explicitas = @(),
        [int]$Teto            = 1024
    )

    $candidatos = New-Object 'System.Collections.Generic.List[object]'

    if ($null -ne $Explicitas -and $Explicitas.Count -gt 0) {
        foreach ($t in $Explicitas) {
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            $candidatos.Add([pscustomobject]@{
                Faixa  = (Get-FaixaDeTexto $t)
                Motivo = 'faixa informada'
            })
        }
    } else {
        if (Test-Ipv4Estrito $IpFabrica) {
            $candidatos.Add([pscustomobject]@{
                Faixa  = (Get-FaixaDeTexto ($IpFabrica + '/24'))
                Motivo = ('camera de fabrica (' + $IpFabrica + ')')
            })
        }
        if (Test-Ipv4Estrito $Gateway) {
            $candidatos.Add([pscustomobject]@{
                Faixa  = (Get-FaixaDeTexto ($Gateway + '/24'))
                Motivo = ('faixa definitiva (gateway ' + $Gateway + ')')
            })
        }
        foreach ($l in $LocaisPlaca) {
            if ($null -eq $l) { continue }
            if (-not (Test-Ipv4Estrito ([string]$l.Ip))) { continue }
            $pref = 24
            if ($null -ne $l.Prefixo) {
                $tmp = [int]$l.Prefixo
                if ($tmp -ge 0 -and $tmp -le 32) { $pref = $tmp }
            }
            $candidatos.Add([pscustomobject]@{
                Faixa  = (Get-FaixaDeTexto ([string]$l.Ip + '/' + $pref))
                Motivo = ('faixa atual da placa (' + [string]$l.Ip + '/' + $pref + ')')
            })
        }
    }

    $vistas = @{}
    $saida  = New-Object 'System.Collections.Generic.List[object]'
    foreach ($c in $candidatos) {
        if ($vistas.ContainsKey($c.Faixa.Chave)) { continue }
        $vistas[$c.Faixa.Chave] = $true

        $hosts  = Get-HostsNaFaixa $c.Faixa.Prefixo
        $varrer = $true
        $aviso  = ''
        if ($hosts -gt $Teto) {
            $varrer = $false
            $aviso  = ('faixa com ' + $hosts + ' hosts, acima do teto de ' + $Teto +
                       ' hosts; nao varrida (' + $c.Faixa.Rede + '/' + $c.Faixa.Prefixo + ')')
        }

        $saida.Add([pscustomobject]@{
            Rede    = $c.Faixa.Rede
            Prefixo = $c.Faixa.Prefixo
            Chave   = $c.Faixa.Chave
            Hosts   = $hosts
            Motivo  = $c.Motivo
            Varrer  = $varrer
            Aviso   = $aviso
        })
    }
    # CONTRATO: esta funcao devolve array CRU e quem chama SEMPRE
    # embrulha em @(). As duas metades existem juntas de proposito.
    #
    # O PowerShell desembrulha colecao no retorno, entao sem o @() do
    # lado de quem chama uma lista de UM item vira escalar - e ai
    # $lista[0] devolve o primeiro CARACTERE do IP em vez do IP.
    # Resolver isso aqui com o idioma consagrado return ,$array troca
    # um bug por outro PIOR, e este custou uma sessao de campo: com a
    # lista VAZIA o valor volta como um objeto que E um array vazio, e
    # @() em cima dele conta 1. A varredura passou a relatar um host
    # vivo onde nao havia nenhum, e o atalho foi sondar um IP de
    # fabrica que nao existia. Zero, um e N precisam funcionar.
    return $saida.ToArray()
}

function Get-MacNormalizado {
    param([string]$Mac)

    if ([string]::IsNullOrWhiteSpace($Mac)) { return '' }
    return (($Mac -replace '[^0-9A-Fa-f]', '').ToUpperInvariant())
}

function Get-OuiCameras {
    param([string[]]$Extra = @())

    $base = @(
        '98E55B',   # confirmado no inventario: VIP-5460-Z-IA e VIP-3430-D-IA
        '54BAD9',   # confirmado no inventario: VIP-5460-LPR-IA
        'D8365F'    # confirmado em campo: VIP-1230-D-G3 (fw 2.800, 2022)
    )
    foreach ($e in $Extra) {
        $n = Get-MacNormalizado $e
        if ($n.Length -ge 6) { $base += $n.Substring(0, 6) }
    }
    # Idem: devolve array cru, quem chama embrulha em @().
    return @($base | Select-Object -Unique)
}

function Test-OuiConhecido {
    param([string]$Mac, [string[]]$Ouis)

    $n = Get-MacNormalizado $Mac
    if ($n.Length -lt 6) { return $false }
    return ($Ouis -contains $n.Substring(0, 6))
}

function Import-Blacklist {
    param([string]$Caminho)

    $h = @{}
    if ([string]::IsNullOrWhiteSpace($Caminho) -or -not (Test-Path $Caminho)) { return $h }
    foreach ($l in (Get-Content -Path $Caminho -Encoding utf8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($l))  { continue }
        if ($l.TrimStart().StartsWith('#'))    { continue }
        $p   = $l -split ';'
        $mac = Get-MacNormalizado $p[0]
        if ($mac.Length -ne 12) { continue }
        $motivo = ''
        if ($p.Count -ge 3) { $motivo = (($p[2..($p.Count - 1)] -join ';')).Trim() }
        $h[$mac] = $motivo
    }
    return $h
}

function Add-Blacklist {
    param([string]$Caminho, [string]$Mac, [string]$Motivo = '')

    $n = Get-MacNormalizado $Mac
    if ($n.Length -ne 12) { return $false }
    try {
        if (-not (Test-Path $Caminho)) {
            Set-Content -Path $Caminho -Encoding utf8 -ErrorAction Stop -Value @(
                '# MACs verificados que NAO sao camera-alvo. Formato: MAC;data;motivo',
                '# Apague uma linha para o programa testar aquele aparelho de novo.'
            )
        }
        Add-Content -Path $Caminho -Encoding utf8 -ErrorAction Stop -Value (
            $Mac.Trim() + ';' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + ';' + $Motivo)
        return $true
    } catch {
        return $false
    }
}

# --- inicializacao de fabrica (/OutsideCmd, anonimo)

function ConvertFrom-Hex {
    param([string]$Hex)
    $n = [int]($Hex.Length / 2)
    $b = New-Object byte[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $b[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return $b
}

function Get-CamInitStatus {
    param([string]$Ip, [int]$Timeout = 25)

    $r = Invoke-CamRpc -Ip $Ip -Endpoint '/OutsideCmd' `
                       -Corpo '{"method":"DevInit.getStatus","params":null,"id":1}' -Timeout $Timeout
    $o = [pscustomobject]@{ Ok = $false; Init = -1; Find = ''; Bruto = $r }
    if ($r -match '"result"\s*:\s*true') {
        $o.Ok = $true
        $m = [regex]::Match($r, '"Init"\s*:\s*(\d+)')
        if ($m.Success) { $o.Init = [int]$m.Groups[1].Value }
        $m = [regex]::Match($r, '"Find"\s*:\s*"([^"]*)"')
        if ($m.Success) { $o.Find = $m.Groups[1].Value }
    }
    return $o
}

function Get-CamChavePublica {
    param([string]$Ip, [int]$Tentativas = 6)

    $corpo = '{"method":"Security.getEncryptInfo","params":null,"id":1,"session":0}'
    $ultima = ''

    for ($i = 1; $i -le $Tentativas; $i++) {
        $endpoint = if ($i % 2 -eq 1) { '/RPC2' } else { '/OutsideCmd' }
        $r = Invoke-CamRpc -Ip $Ip -Endpoint $endpoint -Corpo $corpo
        $pub = [regex]::Match($r, '"pub"\s*:\s*"([^"]+)"').Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($pub)) {
            if ($i -gt 1) {
                Write-Log ("  chave publica obtida na tentativa " + $i + " (" + $endpoint + ")") 'DarkGray'
            }
            return $pub
        }
        $ultima = $r
        if ($r -match 'NotifyMethod') {
            Write-Log ("  notificacao da camera atravessou a resposta (tentativa " + $i + "/" + $Tentativas + "), repetindo...") 'DarkGray'
        } else {
            Write-Log ("  getEncryptInfo sem chave em " + $endpoint + " (tentativa " + $i + "/" + $Tentativas + "), repetindo...") 'DarkGray'
        }
        Start-Sleep -Seconds 2
    }

    throw ('nao obtive a chave publica RSA de ' + $Ip + ' apos ' + $Tentativas +
           ' tentativas. Ultima resposta: ' + $ultima)
}

function New-CamEnvelope {
    param([string]$Ip, [string]$PayloadJson, [int]$TamChave = 32)

    $pub = Get-CamChavePublica -Ip $Ip
    $nHex = [regex]::Match($pub, 'N:([0-9A-Fa-f]+)').Groups[1].Value
    $eHex = [regex]::Match($pub, 'E:([0-9A-Fa-f]+)').Groups[1].Value

    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $sb  = New-Object Text.StringBuilder
    while ($sb.Length -lt $TamChave) {
        $b4 = New-Object byte[] 4
        $rng.GetBytes($b4)
        [void]$sb.Append([BitConverter]::ToUInt32($b4, 0).ToString())
    }
    $chave = $sb.ToString().Substring(0, $TamChave)

    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    try {
        $par = New-Object Security.Cryptography.RSAParameters
        $par.Modulus  = [byte[]](ConvertFrom-Hex $nHex)
        $par.Exponent = [byte[]](ConvertFrom-Hex $eHex)
        $rsa.ImportParameters($par)
        # $false = PKCS#1 v1.5. Com $true seria OAEP e o aparelho recusa.
        $saltBytes = $rsa.Encrypt([Text.Encoding]::ASCII.GetBytes($chave), $false)
    } finally { $rsa.Dispose() }
    $salt = (($saltBytes | ForEach-Object { $_.ToString('x2') }) -join '')

    $pb = [Text.Encoding]::UTF8.GetBytes($PayloadJson)
    $resto = $pb.Length % 16
    if ($resto -ne 0) {
        $novo = New-Object byte[] ($pb.Length + (16 - $resto))
        [Array]::Copy($pb, $novo, $pb.Length)
        $pb = $novo
    }
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode    = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::None
        $aes.Key     = [Text.Encoding]::ASCII.GetBytes($chave)
        $aes.IV      = [Text.Encoding]::ASCII.GetBytes('0000000000000000')
        $enc = $aes.CreateEncryptor()
        try {
            $content = [Convert]::ToBase64String($enc.TransformFinalBlock($pb, 0, $pb.Length))
        } finally { $enc.Dispose() }
    } finally { $aes.Dispose() }

    return [pscustomobject]@{ Cipher = 'RPAC-256'; Salt = $salt; Content = $content }
}

function Invoke-CamRpcCifrado {
    param([string]$Ip, [string]$Metodo, [string]$PayloadJson, [int]$Id = 9)

    $pacote = New-CamEnvelope -Ip $Ip -PayloadJson $PayloadJson
    $corpo = '{"method":"' + $Metodo + '","params":{"cipher":"' + $pacote.Cipher +
             '","salt":"' + $pacote.Salt + '","content":"' + $pacote.Content +
             '"},"id":' + $Id + '}'
    return Invoke-CamRpc -Ip $Ip -Endpoint '/OutsideCmd' -Corpo $corpo
}

# --- descoberta na rede

# Faixas { Ip; Prefixo } do PC. -IfIndex > 0: so da placa escolhida (e o que
# define "alcancavel": IP na faixa do Wi-Fi nao chega numa camera que esta no
# switch da Ethernet). 0 = todas.
function Get-FaixasDaPlaca {
    param([int]$IfIndex = 0)
    $saida = New-Object 'System.Collections.Generic.List[object]'
    $enderecos = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                   Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and ($IfIndex -le 0 -or [int]$_.InterfaceIndex -eq $IfIndex) })
    foreach ($e in $enderecos) {
        $saida.Add(@{ Ip = [string]$e.IPAddress; Prefixo = [int]$e.PrefixLength; IfIndex = [int]$e.InterfaceIndex })
    }
    return $saida.ToArray()
}

function Invoke-PingSweep {
    param(
        [string[]]$Ips,
        [int]$TimeoutMs = 250,
        [int]$Lote = 256
    )

    $vivos = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Ips -or $Ips.Count -eq 0) { return $vivos.ToArray() }

    for ($i = 0; $i -lt $Ips.Count; $i += $Lote) {
        $fim   = [math]::Min($i + $Lote - 1, $Ips.Count - 1)
        $bloco = @($Ips[$i..$fim])

        $pingers = New-Object 'System.Collections.Generic.List[object]'
        $tarefas = New-Object 'System.Collections.Generic.List[object]'
        foreach ($ip in $bloco) {
            try {
                $p = New-Object System.Net.NetworkInformation.Ping
                $pingers.Add($p)
                $tarefas.Add($p.SendPingAsync($ip, $TimeoutMs))
            } catch {
                $tarefas.Add($null)
            }
        }

        try {
            $arr = [System.Threading.Tasks.Task[]]@($tarefas | Where-Object { $null -ne $_ })
            if ($arr.Count -gt 0) { [void][System.Threading.Tasks.Task]::WaitAll($arr, ($TimeoutMs * 4 + 2000)) }
        } catch {
            # WaitAll estoura AggregateException se qualquer ping falhar por
            # host inalcancavel. Nao e erro nosso: o resultado de cada tarefa
            # e conferido individualmente logo abaixo.
        }

        for ($j = 0; $j -lt $bloco.Count; $j++) {
            $t = $tarefas[$j]
            if ($null -eq $t) { continue }
            try {
                if ($t.IsCompleted -and $null -ne $t.Result -and $t.Result.Status -eq 'Success') {
                    $vivos.Add($bloco[$j])
                }
            } catch { }
        }

        foreach ($p in $pingers) { try { $p.Dispose() } catch { } }
    }
    return $vivos.ToArray()
}

function Get-VizinhosMac {
    param([string[]]$Ips)

    $mapa = @{}
    if ($null -eq $Ips -or $Ips.Count -eq 0) { return $mapa }

    $procurados = @{}
    foreach ($ip in $Ips) { $procurados[$ip] = $true }

    try {
        $vizinhos = @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
                      Where-Object { $_.State -ne 'Unreachable' })
        foreach ($v in $vizinhos) {
            $ip = [string]$v.IPAddress
            if (-not $procurados.ContainsKey($ip)) { continue }
            $mac = Get-MacNormalizado ([string]$v.LinkLayerAddress)
            if ($mac.Length -ne 12) { continue }
            if ($mac -eq '000000000000' -or $mac -eq 'FFFFFFFFFFFF') { continue }
            $mapa[$ip] = $mac
        }
    } catch {
        # Get-NetNeighbor existe do Windows 8 em diante. Se faltar, seguimos
        # sem MAC: a descoberta continua funcionando, so perde a ordenacao
        # por OUI e a blacklist. Degradar e melhor que abortar.
    }
    return $mapa
}

function Read-RespostaInit {
    param([string]$Bruto)

    $o = [pscustomobject]@{
        EhCamera = $false
        Ok       = $false
        Init     = -1
        Find     = ''
        PareceJson = $false
        Bruto    = $Bruto
    }
    if ([string]::IsNullOrWhiteSpace($Bruto)) { return $o }

    # Qualquer resposta com a forma de RPC do firmware ja identifica o
    # aparelho como camera/DVR Dahua, mesmo quando o metodo e recusado.
    # Corpo com chave de objeto ja indica resposta estruturada. Serve de
    # freio para a blacklist: so entra nela quem responde algo que
    # claramente NAO e JSON de RPC - HTML de impressora, por exemplo.
    if ($Bruto.Contains("{")) { $o.PareceJson = $true }

    # NotifyMethod e session entram na lista de proposito. O
    # API-INTELBRAS.md registra que este firmware EMPURRA uma notificacao
    # assincrona que sai como corpo da resposta SEGUINTE, entao um probe
    # pode receber {"NotifyMethod":"1.2"} em vez do getStatus. Sem
    # reconhecer isso, a camera seria classificada como nao-camera e o MAC
    # dela iria para a blacklist - deixando a camera invisivel para as
    # execucoes seguintes, com sintoma nenhum.
    if ($Bruto -match '"(result|error|method|params|session|NotifyMethod)" *:') { $o.EhCamera = $true }

    if ($Bruto -match '"result"\s*:\s*true') { $o.Ok = $true }

    $m = [regex]::Match($Bruto, '"Init"\s*:\s*(\d+)')
    if ($m.Success) { $o.Init = [int]$m.Groups[1].Value; $o.EhCamera = $true }

    $m = [regex]::Match($Bruto, '"Find"\s*:\s*"([^"]*)"')
    if ($m.Success) { $o.Find = $m.Groups[1].Value }

    return $o
}

# -Portas: porta HTTP por IP (do broadcast DHIP); ausente = a registrada em
# Set-CamPortaHttp, senao 80.
function Invoke-ProbeInitLote {
    param(
        [string[]]$Ips,
        [int]$TimeoutSegProbe = 3,
        [int]$Paralelo = 16,
        [hashtable]$Portas = @{}
    )

    $res = @{}
    if ($null -eq $Ips -or $Ips.Count -eq 0) { return $res }

    $pasta = Join-Path $env:TEMP ('probe-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $pasta
    $corpo = Join-Path $pasta 'corpo.json'
    [IO.File]::WriteAllText($corpo, '{"method":"DevInit.getStatus","params":null,"id":1}',
                            (New-Object Text.UTF8Encoding($false)))

    try {
        $emVoo = New-Object 'System.Collections.Generic.List[object]'
        $n = 0
        foreach ($ip in $Ips) {
            $n++
            $saidaArq = Join-Path $pasta ('r' + $n + '.txt')
            $porta = 0
            if ($null -ne $Portas -and $Portas.ContainsKey($ip)) { $porta = [int]$Portas[$ip] }

            $psi = New-Object Diagnostics.ProcessStartInfo
            $psi.FileName = 'curl.exe'
            $psi.Arguments = ('-s -g --max-time ' + $TimeoutSegProbe +
                              ' -H "Content-Type: application/json"' +
                              ' --data "@' + $corpo + '"' +
                              ' -o "' + $saidaArq + '"' +
                              ' ' + (ConvertTo-UrlCam -Ip $ip -Endpoint '/OutsideCmd' -Porta $porta))
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow  = $true

            try {
                $proc = [Diagnostics.Process]::Start($psi)
                $emVoo.Add([pscustomobject]@{ Ip = $ip; Proc = $proc; Arq = $saidaArq })
            } catch {
                $res[$ip] = (Read-RespostaInit '')
                continue
            }

            # Segura a fila no teto de paralelismo. Espera o mais antigo em
            # vez de fazer polling: mais simples e sem espera ocupada.
            while ($emVoo.Count -ge $Paralelo) {
                $primeiro = $emVoo[0]
                try { $null = $primeiro.Proc.WaitForExit(($TimeoutSegProbe + 2) * 1000) } catch { }
                $res[$primeiro.Ip] = (Read-RespostaInit (Get-ConteudoSeExistir $primeiro.Arq))
                try { $primeiro.Proc.Dispose() } catch { }
                $emVoo.RemoveAt(0)
            }
        }

        foreach ($p in $emVoo) {
            try { $null = $p.Proc.WaitForExit(($TimeoutSegProbe + 2) * 1000) } catch { }
            $res[$p.Ip] = (Read-RespostaInit (Get-ConteudoSeExistir $p.Arq))
            try { $p.Proc.Dispose() } catch { }
        }
    } finally {
        Remove-Item $pasta -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $res
}

function Get-ConteudoSeExistir {
    param([string]$Caminho)
    if ([string]::IsNullOrWhiteSpace($Caminho) -or -not (Test-Path $Caminho)) { return '' }
    try { return ([IO.File]::ReadAllText($Caminho)).Trim() } catch { return '' }
}

# --- descoberta DHIP (UDP 37810): a camera responde de qualquer faixa
#
# E o protocolo da ferramenta de busca da Intelbras/Dahua (ConfigTool). O
# PC manda um broadcast e cada aparelho Dahua responde com IP, mascara,
# gateway, MAC, modelo, serial, firmware, porta HTTP e o estado de
# inicializacao - MESMO que esteja em outra faixa de IP (a resposta e UDP
# para o MAC de quem perguntou). Visto ao vivo em 30/09/2026: 35 respostas em
# 3 s, inclusive de 192.168.1.x com o PC em 10.16.251.x. Detalhes no
# API-INTELBRAS.md, "Descoberta DHIP".

# Pacote de busca: cabecalho de 32 bytes (uint32 little-endian: 0x20, "DHIP",
# sessao 0, id, tamanho do JSON, 0, tamanho do JSON, 0) + JSON. Puro.
function New-PacoteDhip {
    param([int]$Id = 1)
    $json = '{"method":"DHDiscover.search","params":{"mac":"","uni":1},"id":' + $Id + '}'
    $corpo = [Text.Encoding]::ASCII.GetBytes($json)
    $cab = New-Object byte[] 32
    $cab[0] = 0x20
    [Array]::Copy([Text.Encoding]::ASCII.GetBytes('DHIP'), 0, $cab, 4, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$Id), 0, $cab, 12, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$corpo.Length), 0, $cab, 16, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$corpo.Length), 0, $cab, 24, 4)
    return [byte[]]($cab + $corpo)
}

# Init normalizado: o DHIP manda um bitmap (3210, 3722, 3734, 3238, 3222 nas
# inicializadas) e o getStatus por HTTP manda 0, 1 ou 2. Os dois bits baixos
# dizem o estado: 1 = de fabrica, 2 = inicializada, 0 = inicializada (firmware
# antigo). -1 = desconhecido. Puro.
function Get-InitNormalizado {
    param($Init)
    $n = 0
    if ($null -eq $Init -or -not [int]::TryParse([string]$Init, [ref]$n) -or $n -lt 0) { return -1 }
    return ($n -band 3)
}

function Test-InitDeFabrica {
    param($Init)
    return ((Get-InitNormalizado $Init) -eq 1)
}

<#
    Le uma resposta do DHIP. -Bytes: datagrama inteiro (cabecalho + JSON);
    -Json: so o JSON. Devolve $null se nao for um client.notifyDevInfo.
    Campos: Ip, Mascara, Gateway, Mac (normalizado), Modelo, Serial,
    Firmware, HttpPort (80 se ausente), Porta (37777), Classe (IPC/NVR/BSC),
    InitBruto, Init (normalizado), Dhcp, Nome, Fabricante, Find, Bruto.
#>
function ConvertFrom-RespostaDhip {
    param([byte[]]$Bytes = $null, [string]$Json = '')

    if ($null -ne $Bytes -and $Bytes.Length -gt 0) {
        if ($Bytes.Length -lt 32) { return $null }
        if ([Text.Encoding]::ASCII.GetString($Bytes, 4, 4) -ne 'DHIP') { return $null }
        $tam = [BitConverter]::ToUInt32($Bytes, 16)
        if ($tam -le 0 -or (32 + $tam) -gt $Bytes.Length) { $tam = $Bytes.Length - 32 }
        $Json = [Text.Encoding]::UTF8.GetString($Bytes, 32, $tam)
    }
    $Json = ([string]$Json).Trim([char]0, ' ', "`r", "`n", "`t")
    if ([string]::IsNullOrWhiteSpace($Json)) { return $null }
    $o = $null
    try { $o = $Json | ConvertFrom-Json } catch { return $null }
    if ($null -eq $o -or [string]$o.method -ne 'client.notifyDevInfo') { return $null }
    $d = $null
    if ($null -ne $o.params) { $d = $o.params.deviceInfo }
    if ($null -eq $d) { return $null }

    function V($Obj, [string]$Nome) { if ($null -ne $Obj -and $null -ne $Obj.PSObject.Properties[$Nome]) { return $Obj.$Nome } return $null }
    $v4 = V $d 'IPv4Address'
    $porta = 80
    $tmp = 0
    if ([int]::TryParse([string](V $d 'HttpPort'), [ref]$tmp) -and $tmp -gt 0) { $porta = $tmp }
    $p37 = 37777
    if ([int]::TryParse([string](V $d 'Port'), [ref]$tmp) -and $tmp -gt 0) { $p37 = $tmp }
    $initBruto = -1
    if ([int]::TryParse([string](V $d 'Init'), [ref]$tmp)) { $initBruto = $tmp }

    return [pscustomobject]@{
        Ip         = [string](V $v4 'IPAddress')
        Mascara    = [string](V $v4 'SubnetMask')
        Gateway    = [string](V $v4 'DefaultGateway')
        Dhcp       = [bool](V $v4 'DhcpEnable')
        Mac        = (Get-MacNormalizado ([string](V $o 'mac')))
        Modelo     = [string](V $d 'DeviceType')
        Serial     = [string](V $d 'SerialNo')
        Firmware   = [string](V $d 'Version')
        HttpPort   = $porta
        Porta      = $p37
        Classe     = [string](V $d 'DeviceClass')
        InitBruto  = $initBruto
        Init       = (Get-InitNormalizado $initBruto)
        Nome       = [string](V $d 'MachineName')
        Fabricante = [string](V $d 'Vendor')
        Find       = [string](V $d 'Find')
        Bruto      = $Json
    }
}

# Um por aparelho: a mesma camera responde a cada interface e a cada
# destino (255.255.255.255, broadcast dirigido, multicast). Por MAC, ou por
# IP quando o MAC nao veio. So IPC, salvo -IncluirOutros (NVR, BSC...).
function Get-AchadosDhipUnicos {
    param([array]$Achados = @(), [switch]$IncluirOutros)
    $vistos = @{}
    $saida = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in @($Achados)) {
        if ($null -eq $a -or -not (Test-Ipv4Estrito ([string]$a.Ip))) { continue }
        if (-not $IncluirOutros -and -not [string]::IsNullOrWhiteSpace($a.Classe) -and [string]$a.Classe -ne 'IPC') { continue }
        $chave = [string]$a.Mac
        if ([string]::IsNullOrWhiteSpace($chave)) { $chave = 'ip:' + $a.Ip }
        if ($vistos.ContainsKey($chave)) { continue }
        $vistos[$chave] = $true
        $saida.Add($a)
    }
    return $saida.ToArray()
}

# Broadcast dirigido da faixa de um IP local (10.16.251.207/22 -> 10.16.251.255).
function Get-BroadcastDaFaixa {
    param([Parameter(Mandatory)][string]$Ip, [Parameter(Mandatory)][int]$Prefixo)
    if ($Prefixo -lt 0 -or $Prefixo -gt 32) { throw ('prefixo invalido: ' + $Prefixo) }
    $n = [uint64](ConvertTo-Ipv4Numero $Ip)
    $hostBits = 32 - $Prefixo
    $mascara = [uint64]0
    if ($Prefixo -gt 0) { $mascara = ([uint64]4294967295 -shl $hostBits) -band [uint64]4294967295 }
    return (ConvertFrom-Ipv4Numero ([uint32](($n -band $mascara) -bor ([uint64]4294967295 -bxor $mascara))))
}

# O PC alcanca o IP direto (sem gateway) se algum endereco local esta na
# mesma rede. -Locais: lista de { Ip; Prefixo } (Get-FaixasDaPlaca).
function Test-IpAlcancavel {
    param([string]$Ip, [array]$Locais = @())
    if (-not (Test-Ipv4Estrito $Ip)) { return $false }
    $alvo = [uint64](ConvertTo-Ipv4Numero $Ip)
    foreach ($l in @($Locais)) {
        if ($null -eq $l -or -not (Test-Ipv4Estrito ([string]$l.Ip))) { continue }
        $pre = 24
        if ($null -ne $l.Prefixo) { $pre = [int]$l.Prefixo }
        if ($pre -lt 0 -or $pre -gt 32) { continue }
        $mascara = [uint64]0
        if ($pre -gt 0) { $mascara = ([uint64]4294967295 -shl (32 - $pre)) -band [uint64]4294967295 }
        if ((([uint64](ConvertTo-Ipv4Numero ([string]$l.Ip))) -band $mascara) -eq ($alvo -band $mascara)) { return $true }
    }
    return $false
}

<#
    IPs candidatos para o PC na rede de uma camera achada fora das faixas
    dele (IP temporario). Generaliza Get-IpLocalSugerido: .220 primeiro,
    depois .200-.249 a partir de um ponto derivado do MAC da placa, todos
    dentro do /24 da camera; numa rede menor que /24 (prefixo > 24), os
    hosts do topo para baixo. Exclui rede, broadcast, a camera, o gateway e
    -Excluir. Puro: quem chama testa ping/uso.
#>
function Get-CandidatosIpLocal {
    param([Parameter(Mandatory)][string]$IpCamera, [string]$Mascara = '255.255.255.0', [string]$Gateway = '',
          [string]$MacPlaca = '', [string[]]$Excluir = @(), [int]$Maximo = 50)

    $prefixo = Get-PrefixoOu24 $Mascara
    if ($prefixo -lt 8 -or $prefixo -gt 30) { $prefixo = 24 }
    $cam = [uint64](ConvertTo-Ipv4Numero $IpCamera)
    $m = ([uint64]4294967295 -shl (32 - $prefixo)) -band [uint64]4294967295
    $rede = $cam -band $m
    $bcast = $rede -bor ([uint64]4294967295 -bxor $m)
    $fora = @{}
    $fora[[string]$cam] = $true; $fora[[string]$rede] = $true; $fora[[string]$bcast] = $true
    if (Test-Ipv4Estrito $Gateway) { $fora[[string]([uint64](ConvertTo-Ipv4Numero $Gateway))] = $true }
    foreach ($e in @($Excluir)) { if (Test-Ipv4Estrito ([string]$e)) { $fora[[string]([uint64](ConvertTo-Ipv4Numero ([string]$e)))] = $true } }

    $lista = New-Object 'System.Collections.Generic.List[string]'
    $add = { param([uint64]$n) if ($n -gt $rede -and $n -lt $bcast -and -not $fora.ContainsKey([string]$n) -and $lista.Count -lt $Maximo) { $ip = ConvertFrom-Ipv4Numero ([uint32]$n); if (-not $lista.Contains($ip)) { $lista.Add($ip) } } }

    if ($prefixo -le 24) {
        $base24 = $cam -band [uint64]4294967040   # /24 da camera
        & $add ($base24 + 220)
        $semente = $MacPlaca
        if ([string]::IsNullOrWhiteSpace($semente)) { $semente = $env:COMPUTERNAME }
        $md5 = [Security.Cryptography.MD5]::Create()
        $h = $md5.ComputeHash([Text.Encoding]::ASCII.GetBytes([string]$semente))
        $inicio = [BitConverter]::ToUInt32($h, 0) % 50
        for ($i = 0; $i -lt 50; $i++) { & $add ($base24 + 200 + (($inicio + $i) % 50)) }
    } else {
        for ($n = $bcast - 1; $n -gt $rede; $n--) { & $add $n }
    }
    return $lista.ToArray()
}

# Porta HTTP por IP: a camera que anuncia HttpPort 8081 no DHIP so responde
# ali. Quem descobre registra; o construtor de URL consulta. Vazio = 80.
function Get-CamPortaHttp {
    param([string]$Ip)
    if ($null -eq $script:PortasHttp) { $script:PortasHttp = @{} }
    if ($script:PortasHttp.ContainsKey($Ip)) { return [int]$script:PortasHttp[$Ip] }
    return 80
}

function Set-CamPortaHttp {
    param([string]$Ip, [int]$Porta)
    if ($null -eq $script:PortasHttp) { $script:PortasHttp = @{} }
    if (-not (Test-Ipv4Estrito $Ip)) { return }
    if ($Porta -le 0 -or $Porta -eq 80) { $script:PortasHttp.Remove($Ip); return }
    $script:PortasHttp[$Ip] = $Porta
}

function ConvertTo-UrlCam {
    param([string]$Ip, [string]$Endpoint = '', [int]$Porta = 0)
    if ($Porta -le 0) { $Porta = Get-CamPortaHttp $Ip }
    $h = $Ip
    if ($Porta -ne 80) { $h += ':' + $Porta }
    return ('http://' + $h + $Endpoint)
}

# Interfaces por onde mandar o broadcast: IPv4 de verdade, com rede (prefixo
# < 31 exclui o /32 do Tailscale e afins). Cada uma com o broadcast dirigido.
# -IfIndex > 0: so a placa escolhida. 0 = todas.
function Get-InterfacesBroadcast {
    param([int]$IfIndex = 0)
    $saida = New-Object 'System.Collections.Generic.List[object]'
    $enderecos = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                   Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and [int]$_.PrefixLength -lt 31 -and ($IfIndex -le 0 -or [int]$_.InterfaceIndex -eq $IfIndex) })
    foreach ($e in $enderecos) {
        $ip = [string]$e.IPAddress; $pre = [int]$e.PrefixLength
        try { $saida.Add(@{ Ip = $ip; Prefixo = $pre; Broadcast = (Get-BroadcastDaFaixa -Ip $ip -Prefixo $pre); IfIndex = [int]$e.InterfaceIndex }) } catch { }
    }
    return $saida.ToArray()
}

<#
    Manda o DHDiscover.search por cada interface (para 255.255.255.255, o
    broadcast dirigido e o multicast 239.255.255.251) e recolhe as respostas
    por -Segundos. Devolve as respostas lidas (com repeticao: quem chama
    passa por Get-AchadosDhipUnicos). Firewall que bloqueia UDP de entrada
    = zero respostas, sem erro.
#>
function Invoke-DescobertaDhip {
    param([int]$Segundos = 2, [array]$Interfaces = $null, [int]$IfIndex = 0)

    if ($null -eq $Interfaces) { $Interfaces = @(Get-InterfacesBroadcast -IfIndex $IfIndex) }
    $pacote = New-PacoteDhip -Id 1
    $clientes = New-Object 'System.Collections.Generic.List[object]'
    $saida = New-Object 'System.Collections.Generic.List[object]'
    try {
        foreach ($i in @($Interfaces)) {
            try {
                $u = New-Object Net.Sockets.UdpClient
                $u.ExclusiveAddressUse = $false
                $u.Client.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket, [Net.Sockets.SocketOptionName]::ReuseAddress, $true)
                $u.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Parse([string]$i.Ip), 0)))
                $u.EnableBroadcast = $true
                $u.Client.ReceiveTimeout = 200
                $clientes.Add($u)
                foreach ($dest in @('255.255.255.255', [string]$i.Broadcast, '239.255.255.251')) {
                    if ([string]::IsNullOrWhiteSpace($dest)) { continue }
                    try { $null = $u.Send($pacote, $pacote.Length, (New-Object Net.IPEndPoint([Net.IPAddress]::Parse($dest), 37810))) } catch { }
                }
            } catch { }
        }
        if ($clientes.Count -eq 0) { return $saida.ToArray() }
        $fim = (Get-Date).AddSeconds($Segundos)
        while ((Get-Date) -lt $fim) {
            $leu = $false
            foreach ($u in $clientes) {
                while ($u.Available -gt 0) {
                    $de = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
                    try {
                        $b = $u.Receive([ref]$de)
                        $r = ConvertFrom-RespostaDhip -Bytes $b
                        if ($null -ne $r) {
                            # A camera responde com o IP dela no JSON; o remetente do
                            # datagrama confirma (e vale quando o JSON vem sem IP).
                            if (-not (Test-Ipv4Estrito $r.Ip)) { $r.Ip = [string]$de.Address }
                            $saida.Add($r)
                        }
                        $leu = $true
                    } catch { break }
                }
            }
            if (-not $leu) { Start-Sleep -Milliseconds 50 }
        }
    } finally {
        foreach ($u in $clientes) { try { $u.Close() } catch { } }
    }
    return $saida.ToArray()
}

<#
    Camera de fabrica achada fora das faixas da placa escolhida: acrescenta
    nela um IP temporario na rede da camera, para configura-la. Mesma trilha
    do preparo (so adiciona; Restore-ConexaoPlaca devolve o DHCP como
    estatico) e o rastro entra na sessao da placa com Para = 'temporario' e a
    camera: o Restaurar DHCP / Encerrar tira.

    Camera cujo IP cai na faixa de OUTRA placa do PC (a bancada num switch
    isolado na Ethernet com IP da faixa do Wi-Fi, 01/10/2026): o Windows
    rotearia pela outra placa e nunca chegaria. Alem do IP temporario, entra
    uma rota de host (<ip>/32 on-link) na placa escolhida, em ActiveStore
    (some no reboot), e ela tambem vai para o rastro (Rotas).
    -Placa: a placa da sessao (Resolve-PlacaSessao). Retorna { Ok; Ip; Sessao }.
#>
function Add-IpTemporarioPlaca {
    param([Parameter(Mandatory)][string]$IpCamera, [string]$Mascara = '255.255.255.0', [string]$GatewayCamera = '',
          $Placa = $null, [switch]$Simular)

    $nao = [pscustomobject]@{ Ok = $false; Ip = ''; Sessao = $null }
    Write-Log ("Camera de fabrica em " + $IpCamera + " fora das faixas da placa escolhida: acrescentando um IP temporario nela.") 'Cyan'
    if (-not (Test-Ipv4Estrito $IpCamera)) { Write-Log ("  ABORTADO: IP da camera invalido: " + $IpCamera) 'Red'; return $nao }
    if (-not $Simular -and -not (Test-EhAdministrador)) { Write-Log "  ABORTADO: precisa de privilegio de Administrador." 'Red'; return $nao }
    $prefixo = Get-PrefixoOu24 $Mascara
    if ($prefixo -lt 8 -or $prefixo -gt 30) { $prefixo = 24; $Mascara = '255.255.255.0' }

    $adaptador = $null
    if (-not $Simular) {
        $adaptador = Resolve-PlacaSessao -Placa $Placa
        if ($null -eq $adaptador) { return $nao }
    }
    $mac = ''; if ($null -ne $adaptador) { $mac = [string]$adaptador.MacAddress }
    # Exclusao global de proposito: um IP que ja e de qualquer placa do PC
    # daria conflito interno.
    $locais = @(Get-IpsLocais)
    $candidatos = @(Get-CandidatosIpLocal -IpCamera $IpCamera -Mascara $Mascara -Gateway $GatewayCamera -MacPlaca $mac -Excluir $locais)
    $escolhido = ''
    foreach ($c in $candidatos) {
        if ($Simular) { $escolhido = $c; break }
        if (Test-IpEmUso -Ip $c) { continue }
        $escolhido = $c; break
    }
    if (-not $escolhido) { Write-Log ("  ABORTADO: nao achei IP livre na rede de " + $IpCamera + "/" + $prefixo) 'Red'; return $nao }
    # A camera esta na faixa de outra placa deste PC? Entao precisa da rota de host.
    $ifEscolhida = 0; if ($null -ne $adaptador) { $ifEscolhida = [int]$adaptador.ifIndex }
    $outras = @(Get-FaixasDaPlaca | Where-Object { [int]$_.IfIndex -ne $ifEscolhida })
    $precisaRota = (Test-IpAlcancavel -Ip $IpCamera -Locais $outras)
    if ($Simular) {
        Write-Log ("  [simular] adicionaria " + $escolhido + "/" + $prefixo + " (temporario, camera em " + $IpCamera + ")") 'DarkGray'
        if ($precisaRota) { Write-Log ("  [simular] adicionaria a rota de host " + $IpCamera + "/32 na placa (a faixa e de outra placa deste PC)") 'DarkGray' }
        return [pscustomobject]@{ Ok = $true; Ip = $escolhido; Sessao = $null }
    }

    Write-Log ("  Placa: " + $adaptador.Name + "; IP temporario: " + $escolhido + "/" + $prefixo) 'White'
    $antes = Get-ConfigIpv4Placa -Placa $adaptador
    $sessao = New-SessaoPlaca -Placa $adaptador -Antes $antes
    $feitos = @()
    $ok = $false
    try {
        $null = New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -IPAddress $escolhido -PrefixLength $prefixo -ErrorAction Stop
        $sessao.Adicionados += @{ Ip = $escolhido; Prefixo = $prefixo; Para = 'temporario'; Camera = $IpCamera }
        $feitos += @{ Msg = ("  ADICIONADO " + $escolhido + "/" + $prefixo + "   (temporario, camera em " + $IpCamera + ")"); Cor = 'Green' }
        $ok = $true
        if ($precisaRota) {
            $feitos += Add-RotaHostPlaca -Placa $adaptador -IpCamera $IpCamera -Sessao $sessao
        }
    } catch {
        $feitos += @{ Msg = ("  FALHOU     " + $escolhido + ": " + $_.Exception.Message); Cor = 'Red' }
    } finally {
        $feitos += Restore-ConexaoPlaca -Placa $adaptador -Antes $antes -Feito $sessao
    }
    foreach ($f in $feitos) { Write-Log $f.Msg $f.Cor }
    Start-Sleep -Seconds 2
    return [pscustomobject]@{ Ok = $ok; Ip = $(if ($ok) { $escolhido } else { '' }); Sessao = $sessao }
}

# Rota de host <ip>/32 on-link na placa escolhida, metrica 1, ActiveStore
# (nao sobrevive ao reboot: e o que se quer). "Ja existe" conta como feita e
# entra no rastro do mesmo jeito. NAO grava log: devolve as mensagens.
function Add-RotaHostPlaca {
    param($Placa, [string]$IpCamera, [hashtable]$Sessao)
    $destino = $IpCamera + '/32'
    $msgs = @()
    try {
        $null = New-NetRoute -InterfaceIndex $Placa.ifIndex -DestinationPrefix $destino -NextHop '0.0.0.0' -RouteMetric 1 -PolicyStore ActiveStore -ErrorAction Stop
        $msgs += @{ Msg = ("  ADICIONADA rota de host " + $destino + " on-link   (a faixa de " + $IpCamera + " e de outra placa deste PC)"); Cor = 'Green' }
    } catch {
        if ($_.Exception.Message -match 'already exists|j. existe|ObjectExists') {
            $msgs += @{ Msg = ("  rota de host " + $destino + " ja existia na placa"); Cor = 'DarkGray' }
        } else {
            $msgs += @{ Msg = ("  FALHOU a rota de host " + $destino + ": " + $_.Exception.Message); Cor = 'Red' }
            return $msgs
        }
    }
    if ($null -ne $Sessao) { $Sessao.Rotas += @{ Destino = $destino; NextHop = '0.0.0.0'; Para = 'temporario'; Camera = $IpCamera } }
    return $msgs
}

function Find-CamerasNaRede {
    param(
        [string]$IpFabrica          = '192.168.1.108',
        [string]$GatewayDestino     = '',
        [string[]]$FaixasExplicitas = @(),
        [int]$Teto                  = 1024,
        [int]$TimeoutPingMs         = 250,
        [int]$TimeoutSegProbe       = 3,
        [int]$Paralelo              = 16,
        [string]$ArquivoBlacklist   = '',
        [string[]]$OuiExtra         = @(),
        [switch]$SemAtalho,
        [switch]$SemBroadcast,
        [switch]$SemVarredura,
        [switch]$IncluirOutros,
        [int]$SegundosBroadcast     = 2,
        [switch]$Silencioso,
        # Placa escolhida: broadcast, alcance e varredura so por ela. 0 = todas.
        [int]$IfIndex               = 0
    )

    $cronometro = [Diagnostics.Stopwatch]::StartNew()
    $ouis  = @(Get-OuiCameras -Extra $OuiExtra)
    $lista = New-Object 'System.Collections.Generic.List[object]'
    $faixasPlaca = @(Get-FaixasDaPlaca -IfIndex $IfIndex)

    # Confirmado: o Init veio do DevInit.getStatus por HTTP (so se age nele).
    # Alcancavel: o PC tem IP na rede da camera. Modelo/Serial/Firmware/
    # Mascara/Gateway/HttpPort/Classe: so o broadcast traz.
    function Add-Achado {
        param($Ip, $Mac, $Init, $EhCamera, $Oui, $Bruto, $Como, $Confirmado = $true, $Alcancavel = $true,
              $Modelo = '', $Serial = '', $Firmware = '', $Mascara = '', $Gateway = '', $HttpPort = 80, $Classe = '')
        $lista.Add([pscustomobject]@{
            Ip            = $Ip
            Mac           = $Mac
            Init          = $Init
            EhCamera      = $EhCamera
            Virgem        = ($Init -eq 1)
            OuiConhecido  = $Oui
            Como          = $Como
            Bruto         = $Bruto
            Confirmado    = [bool]$Confirmado
            Alcancavel    = [bool]$Alcancavel
            Modelo        = [string]$Modelo
            Serial        = [string]$Serial
            Firmware      = [string]$Firmware
            Mascara       = [string]$Mascara
            Gateway       = [string]$Gateway
            HttpPort      = [int]$HttpPort
            Classe        = [string]$Classe
        })
    }
    function Test-JaAchado { param([string]$Ip, [string]$Mac)
        foreach ($a in $lista) { if ($a.Ip -eq $Ip) { return $true }; if ($Mac -and $a.Mac -eq $Mac) { return $true } }
        return $false
    }

    # --- 0. broadcast DHIP ------------------------------------------------
    # Acha a camera em QUALQUER faixa (inclusive fora das do PC). O Init do
    # broadcast e pista: quem o PC alcanca e confirmado por HTTP na hora; quem
    # nao alcanca fica Confirmado=false, e o painel confirma depois de dar um
    # IP temporario a placa.
    if (-not $SemBroadcast) {
        if (-not $Silencioso) { Write-Log ("  broadcast DHIP (UDP 37810) por " + $SegundosBroadcast + " s ...") 'Gray' }
        $brutos = @(Invoke-DescobertaDhip -Segundos $SegundosBroadcast -IfIndex $IfIndex)
        $unicos = @(Get-AchadosDhipUnicos -Achados $brutos -IncluirOutros:$IncluirOutros)
        if (-not $Silencioso) {
            Write-Log ("  " + $brutos.Count + " resposta(s), " + $unicos.Count + " aparelho(s)" +
                       $(if ($IncluirOutros) { '' } else { ' IPC' }) + $(if ($brutos.Count -eq 0) { ' - firewall pode estar barrando UDP' } else { '' })) 'Gray'
        }
        $portas = @{}
        foreach ($u in $unicos) { Set-CamPortaHttp -Ip $u.Ip -Porta $u.HttpPort; if ($u.HttpPort -ne 80) { $portas[$u.Ip] = $u.HttpPort } }
        $alcancaveis = @($unicos | Where-Object { Test-IpAlcancavel -Ip $_.Ip -Locais $faixasPlaca } | ForEach-Object { $_.Ip })
        # So quem o broadcast diz ser de fabrica (ou nao diz) vai ao HTTP: e
        # nessas que o painel age. Sondar 30 cameras ja instaladas a cada
        # tique do vigia prenderia o worker por segundos sem ganho.
        $aConfirmar = @($unicos | Where-Object { ($alcancaveis -contains $_.Ip) -and ($_.Init -eq 1 -or $_.Init -lt 0) } | ForEach-Object { $_.Ip })
        $respostas = @{}
        if ($aConfirmar.Count -gt 0) {
            $respostas = Invoke-ProbeInitLote -Ips $aConfirmar -TimeoutSegProbe $TimeoutSegProbe -Paralelo $Paralelo -Portas $portas
        }
        foreach ($u in $unicos) {
            $alc = ($alcancaveis -contains $u.Ip)
            $init = $u.Init; $conf = $false; $bruto = $u.Bruto
            if ($alc -and $respostas.ContainsKey($u.Ip) -and $null -ne $respostas[$u.Ip] -and $respostas[$u.Ip].EhCamera -and $respostas[$u.Ip].Init -ge 0) {
                # O HTTP manda: se ele diz inicializada, o bit do broadcast nao vale.
                $init = Get-InitNormalizado $respostas[$u.Ip].Init; $conf = $true; $bruto = $respostas[$u.Ip].Bruto
            }
            Add-Achado -Ip $u.Ip -Mac $u.Mac -Init $init -EhCamera $true -Oui (Test-OuiConhecido $u.Mac $ouis) -Bruto $bruto `
                       -Como 'broadcast DHIP' -Confirmado $conf -Alcancavel $alc -Modelo $u.Modelo -Serial $u.Serial -Firmware $u.Firmware `
                       -Mascara $u.Mascara -Gateway $u.Gateway -HttpPort $u.HttpPort -Classe $u.Classe
            if (-not $Silencioso) {
                Write-Log ("  " + $u.Ip + $(if ($u.HttpPort -ne 80) { ':' + $u.HttpPort } else { '' }) + "  " + $u.Modelo + "  " +
                           $(if ($init -eq 1) { 'DE FABRICA' } else { 'inicializada' }) + $(if (-not $alc) { ' (fora das faixas do PC)' } elseif (-not $conf) { ' (nao confirmada por HTTP)' } else { '' })) `
                          $(if ($init -eq 1) { 'Green' } else { 'Gray' })
            }
        }
    }

    # --- 1. atalho no IP de fabrica -----------------------------------------
    # O caso comum e o notebook num injetor isolado, sem DHCP: a camera cai no
    # fallback e resolver isso com um ping evita varrer a rede toda por nada.
    # Continua valendo sem broadcast (firewall barrando UDP).
    if (-not $SemAtalho -and (Test-Ipv4Estrito $IpFabrica) -and -not (Test-JaAchado -Ip $IpFabrica)) {
        if (-not $Silencioso) { Write-Log ("  procurando no IP de fabrica " + $IpFabrica + " ...") 'Gray' }
        $vivo = @(Invoke-PingSweep -Ips @($IpFabrica) -TimeoutMs ($TimeoutPingMs * 4))
        if ($vivo.Count -eq 1) {
            $r = Invoke-ProbeInitLote -Ips @($IpFabrica) -TimeoutSegProbe $TimeoutSegProbe -Paralelo 1
            $resp = $r[$IpFabrica]
            $mac  = ''
            $m = Get-VizinhosMac -Ips @($IpFabrica)
            if ($m.ContainsKey($IpFabrica)) { $mac = $m[$IpFabrica] }

            if ($null -ne $resp -and $resp.Init -eq 1 -and -not (Test-JaAchado -Ip $IpFabrica -Mac $mac)) {
                Add-Achado -Ip $IpFabrica -Mac $mac -Init 1 -EhCamera $true `
                           -Oui (Test-OuiConhecido $mac $ouis) -Bruto $resp.Bruto -Como 'atalho no IP de fabrica'
                $cronometro.Stop()
                if (-not $Silencioso) {
                    Write-Log ("  camera de fabrica em " + $IpFabrica + " (" + $cronometro.ElapsedMilliseconds + " ms, sem varredura)") 'Green'
                }
                return $lista.ToArray()
            }
            if (-not $Silencioso) {
                if ($null -ne $resp -and $resp.EhCamera) {
                    Write-Log ("  " + $IpFabrica + " responde mas nao esta de fabrica (Init=" + $resp.Init + "). Varrendo a rede.") 'Yellow'
                } else {
                    Write-Log ("  " + $IpFabrica + " responde ao ping mas nao e camera. Varrendo a rede.") 'Yellow'
                }
            }
        } elseif (-not $Silencioso) {
            Write-Log ("  nada em " + $IpFabrica + " - e normal quando a rede tem DHCP.") 'Gray'
        }
    }

    # Varredura por ping so quando o broadcast e o atalho nao acharam camera
    # de fabrica: e a rota lenta (ate 1022 hosts) e a reserva para firewall
    # barrando UDP ou camera que nao responde ao DHIP.
    $temVirgem = (@($lista | Where-Object { $_.Virgem }).Count -gt 0)
    if ($SemVarredura -or $temVirgem) {
        $cronometro.Stop()
        if (-not $Silencioso) { Write-Log ("  descoberta levou " + [math]::Round($cronometro.Elapsed.TotalSeconds, 1) + "s" + $(if ($SemVarredura) { ' (sem varredura)' } else { '' })) 'DarkGray' }
        return $lista.ToArray()
    }
    if (-not $Silencioso) { Write-Log "  nenhuma camera de fabrica pelo broadcast nem no IP de fabrica: varrendo por ping." 'Gray' }

    # --- 2. quais faixas varrer ---------------------------------------------
    $faixas = @(Resolve-FaixasVarredura -IpFabrica $IpFabrica -Gateway $GatewayDestino `
                                        -LocaisPlaca $faixasPlaca `
                                        -Explicitas $FaixasExplicitas -Teto $Teto)
    $locais = Get-IpsLocais

    $alvos = New-Object 'System.Collections.Generic.List[string]'
    foreach ($f in $faixas) {
        if (-not $f.Varrer) {
            if (-not $Silencioso) {
                Write-Log ("  PULADA    " + $f.Chave + "  " + $f.Aviso) 'Yellow'
            }
            continue
        }
        if (-not $Silencioso) {
            Write-Log ("  varrendo  " + $f.Chave + "  (" + $f.Hosts + " hosts) - " + $f.Motivo) 'Gray'
        }
        foreach ($ip in @(Expand-Faixa -Ip $f.Rede -Prefixo $f.Prefixo -Excluir $locais)) {
            $alvos.Add($ip)
        }
    }

    if ($alvos.Count -eq 0) {
        if (-not $Silencioso) { Write-Log "  nenhuma faixa varrivel: confira o gateway da sessao e a placa de rede escolhida." 'Yellow' }
        return $lista.ToArray()
    }

    # --- 3. ping em massa e leitura do ARP ----------------------------------
    $vivos = @(Invoke-PingSweep -Ips ($alvos.ToArray()) -TimeoutMs $TimeoutPingMs)
    $macs  = Get-VizinhosMac -Ips $vivos
    if (-not $Silencioso) {
        Write-Log ("  " + $alvos.Count + " enderecos pingados, " + $vivos.Count +
                   " responderam, " + $macs.Count + " com MAC na tabela ARP") 'Gray'
    }
    if ($vivos.Count -eq 0) { return $lista.ToArray() }

    # --- 4. blacklist -------------------------------------------------------
    $bl = Import-Blacklist -Caminho $ArquivoBlacklist
    $candidatos = New-Object 'System.Collections.Generic.List[string]'
    $barrados = 0
    foreach ($ip in $vivos) {
        $mac = ''
        if ($macs.ContainsKey($ip)) { $mac = $macs[$ip] }
        if ($mac -ne '' -and $bl.ContainsKey($mac)) { $barrados++; continue }
        if (Test-JaAchado -Ip $ip -Mac $mac) { continue }   # ja veio pelo broadcast
        $candidatos.Add($ip)
    }
    if ($barrados -gt 0 -and -not $Silencioso) {
        Write-Log ("  " + $barrados + " host(s) ignorado(s) pela blacklist de nao-cameras") 'DarkGray'
    }

    # --- 5. ordenar por OUI: pista, nao porta -------------------------------
    $comOui = New-Object 'System.Collections.Generic.List[string]'
    $semOui = New-Object 'System.Collections.Generic.List[string]'
    foreach ($ip in $candidatos) {
        $mac = ''
        if ($macs.ContainsKey($ip)) { $mac = $macs[$ip] }
        if (Test-OuiConhecido $mac $ouis) { $comOui.Add($ip) } else { $semOui.Add($ip) }
    }
    if (-not $Silencioso) {
        Write-Log ("  " + $comOui.Count + " com OUI de camera, " + $semOui.Count +
                   " de OUI desconhecido (probados depois, nao descartados)") 'Gray'
    }

    $fila = New-Object 'System.Collections.Generic.List[string]'
    foreach ($ip in $comOui) { $fila.Add($ip) }
    foreach ($ip in $semOui) { $fila.Add($ip) }

    # --- 6. probe ------------------------------------------------------------
    $respostas = Invoke-ProbeInitLote -Ips ($fila.ToArray()) `
                                      -TimeoutSegProbe $TimeoutSegProbe -Paralelo $Paralelo
    foreach ($ip in $fila) {
        $resp = $respostas[$ip]
        if ($null -eq $resp) { continue }
        $mac = ''
        if ($macs.ContainsKey($ip)) { $mac = $macs[$ip] }

        if ($resp.EhCamera) {
            Add-Achado -Ip $ip -Mac $mac -Init $resp.Init -EhCamera $true `
                       -Oui (Test-OuiConhecido $mac $ouis) -Bruto $resp.Bruto -Como 'varredura'
            continue
        }

        # Nao e camera. Só entra na blacklist com resposta CONCLUSIVA: se a
        # resposta veio vazia foi timeout, e timeout e ambiguo - e exatamente
        # o sintoma de camera reiniciando. Marcar por timeout excluiria camera
        # boa das proximas execucoes, e o erro seria invisivel.
        if (-not [string]::IsNullOrWhiteSpace($resp.Bruto) -and -not $resp.PareceJson -and
            -not [string]::IsNullOrWhiteSpace($ArquivoBlacklist) -and $mac -ne '') {
            $null = Add-Blacklist -Caminho $ArquivoBlacklist -Mac $mac `
                                  -Motivo ('respondeu em ' + $ip + ' e nao e camera Dahua')
        }
    }

    $cronometro.Stop()
    if (-not $Silencioso) {
        Write-Log ("  descoberta levou " + [math]::Round($cronometro.Elapsed.TotalSeconds, 1) + "s") 'DarkGray'
    }
    return $lista.ToArray()
}

# --- preparo da placa do PC

function Get-IpLocalSugerido {
    param([string]$Faixa, [string]$MacPlaca, [int]$IfIndex = 0)

    $semente = $MacPlaca
    if ([string]::IsNullOrWhiteSpace($semente)) { $semente = $env:COMPUTERNAME }

    $md5 = [Security.Cryptography.MD5]::Create()
    $h = $md5.ComputeHash([Text.Encoding]::ASCII.GetBytes($semente))
    $base = 200 + ([BitConverter]::ToUInt32($h, 0) % 50)

    # "Ja e nosso" so vale na placa escolhida: o mesmo IP no Wi-Fi nao serve.
    $locais = Get-IpsLocais -IfIndex $IfIndex
    # Anda para frente ate achar um numero que ninguem responde. 50 tentativas
    # cobre a faixa inteira; se tudo estiver ocupado, algo esta muito errado.
    for ($i = 0; $i -lt 50; $i++) {
        $n = 200 + ((($base - 200) + $i) % 50)
        $ip = $Faixa + '.' + $n
        if ($locais -contains $ip) { return $ip }   # ja e nosso, serve
        if (-not (Test-IpEmUso -Ip $ip)) { return $ip }
    }
    return ''
}

# Foto da placa antes de mexer. TemLeaseDhcp: DHCP ligado E um endereco que
# veio dele (169.254.x e APIPA = cabo direto na camera, sem servidor DHCP;
# nao ha o que devolver nem renovar). GatewayMetrica: a rota devolvida
# depois leva a mesma metrica, senao vira 256 e muda a preferencia do PC.
function Get-ConfigIpv4Placa {
    param($Placa)

    $foto = @{ Dhcp = $false; TemLeaseDhcp = $false; Enderecos = @(); Gateway = ''; GatewayMetrica = 0; Dns = @() }

    try {
        $iface = Get-NetIPInterface -InterfaceIndex $Placa.ifIndex -AddressFamily IPv4 -ErrorAction Stop
        $foto.Dhcp = ($iface.Dhcp -eq 'Enabled')
    } catch { }

    $foto.Enderecos = @(
        Get-NetIPAddress -InterfaceIndex $Placa.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } |
        ForEach-Object { @{ Ip = $_.IPAddress; Prefixo = $_.PrefixLength; Origem = [string]$_.PrefixOrigin } }
    )
    $foto.TemLeaseDhcp = [bool]($foto.Dhcp -and @($foto.Enderecos | Where-Object { $_.Origem -eq 'Dhcp' }).Count -gt 0)

    $rota = @(Get-NetRoute -InterfaceIndex $Placa.ifIndex -DestinationPrefix '0.0.0.0/0' `
                           -ErrorAction SilentlyContinue | Sort-Object RouteMetric)
    if ($rota.Count -gt 0) { $foto.Gateway = $rota[0].NextHop; $foto.GatewayMetrica = [int]$rota[0].RouteMetric }

    try {
        $d = Get-DnsClientServerAddress -InterfaceIndex $Placa.ifIndex -AddressFamily IPv4 -ErrorAction Stop
        $foto.Dns = @($d.ServerAddresses)
    } catch { }

    return $foto
}

# Placas Ethernet fisicas (ifIndex) que tem rota padrao: e por elas que a
# internet do PC passa. Seam: os testes trocam por uma lista fixa.
function Get-PlacasComRotaPadrao {
    return @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Select-Object -ExpandProperty ifIndex -Unique)
}

# "Tem internet?" pelo mesmo endereco que o Windows usa (NCSI). curl.exe
# ignora o proxy WinINET, entao numa rede corporativa so com proxy o
# resultado e 'sem' mesmo com navegador funcionando: o painel so avisa.
function Test-Internet {
    param([int]$Segundos = 4)
    try {
        $r = & curl.exe -s --max-time $Segundos 'http://www.msftconnecttest.com/connecttest.txt' 2>$null
        if ($LASTEXITCODE -eq 0 -and ([string]$r) -match 'Microsoft Connect Test') { return 'ok' }
    } catch { }
    return 'sem'
}

# Renova o lease DHCP da placa. Seam: nos testes nao roda.
function Invoke-RenovarDhcp {
    param($Placa)
    try { $null = & ipconfig.exe /renew $Placa.Name 2>&1 } catch { }
}

# --- inventario

function Get-ColunasInventario {
    return @('TIPO', 'MODELO', 'MAC-ADRESS', 'IP', 'RACK', 'PORTA SWITCH', 'ANDAR',
             'NVR - GRAVADOR', 'CANAL', 'USUARIO', 'SENHA', 'MASCARA', 'GATEWAY',
             'LOCAL', 'STATUS', 'OBSERVACAO', 'DATA-CONFIG')
}

# ------------------------------------- rede do PC e inicializacao da camera

<#
    Estado das faixas de rede do PC, em forma estruturada para o painel.
    O PC precisa de endereco na faixa de fabrica (para achar e inicializar) e
    na faixa definitiva (para conferir depois da troca de IP).
#>
# Prefixo da mascara da sessao; mascara furada cai para /24 (e o painel ja
# recusou a sessao antes de chegar aqui).
function Get-PrefixoOu24 {
    param([string]$Mascara)
    try { return [int](ConvertTo-PrefixoDeMascara $Mascara) } catch { return 24 }
}

# A camera de fabrica e sempre /24 (192.168.1.x). A rede do gateway segue a
# mascara da sessao: numa /22 o PC precisa de um IP que enxergue os quatro
# /24, senao a conferencia no IP definitivo da timeout.
# Com IpPcFabrica/IpPcCameras (sessao) o PC precisa ter AQUELE IP, nao
# qualquer um da faixa: o operador escolheu por um motivo (reserva no DHCP,
# regra de firewall).
# -IfIndex: so a placa escolhida conta (o IP certo no Wi-Fi nao e "pronta").
function Get-EstadoRedePc {
    param([string]$IpFabrica, [string]$Gateway, [string]$Mascara = '255.255.255.0',
          [string]$IpPcFabrica = '', [string]$IpPcCameras = '', [int]$IfIndex = 0)

    $locais = @(Get-IpsLocais -IfIndex $IfIndex)
    $faltando = @()

    $pFab = Get-Prefixo24 $IpFabrica
    if (Test-Ipv4Estrito $IpPcFabrica) {
        if ($locais -notcontains $IpPcFabrica) { $faltando += ($IpPcFabrica + ' (IP do PC na faixa de fabrica, da sessao)') }
    } elseif (-not ($locais | Where-Object { (Get-Prefixo24 $_) -eq $pFab })) {
        $faltando += ($pFab + '.x (camera de fabrica em ' + $IpFabrica + ')')
    }
    if (Test-Ipv4Estrito $Gateway) {
        $prefixo = Get-PrefixoOu24 $Mascara
        if ($prefixo -eq 24) { $Mascara = '255.255.255.0' }
        if (Test-Ipv4Estrito $IpPcCameras) {
            if ($locais -notcontains $IpPcCameras) { $faltando += ($IpPcCameras + ' (IP do PC na rede das cameras, da sessao)') }
        } else {
            $naRede = @($locais | Where-Object { Test-DestinoNaRede -Ip $_ -Mascara $Mascara -Gateway $Gateway })
            if ($naRede.Count -eq 0) {
                $rede = ConvertFrom-Ipv4Numero ([uint32]((ConvertTo-Ipv4Numero $Gateway) -band (ConvertTo-Ipv4Numero $Mascara)))
                $faltando += ($rede + '/' + $prefixo + ' (conferencia no IP definitivo)')
            }
        }
    }
    return [pscustomobject]@{ Ok = ($faltando.Count -eq 0); Faltando = $faltando; Ips = $locais }
}

function Test-PreRequisitosRede {
    param([string]$IpFabrica, [string]$IpDestino, [string]$Mascara = '255.255.255.0',
          [string]$IpPcFabrica = '', [string]$IpPcCameras = '', [int]$IfIndex = 0, [switch]$Silencioso)

    $e = Get-EstadoRedePc -IpFabrica $IpFabrica -Gateway $IpDestino -Mascara $Mascara -IpPcFabrica $IpPcFabrica -IpPcCameras $IpPcCameras -IfIndex $IfIndex
    if ($e.Ok) { return $true }
    if ($Silencioso) { return $false }

    Write-Log "  ATENCAO: a placa de rede deste PC nao tem endereco nas faixas:" 'Yellow'
    foreach ($f in $e.Faltando) { Write-Log ("    - " + $f) 'Yellow' }
    Write-Log  "  Sem isso a comunicacao com a camera falha por timeout." 'Yellow'
    Write-Log ("  IPs atuais: " + ($e.Ips -join ', ')) 'DarkGray'
    return $false
}

# A contagem publicada e a mesma do limite (so os sleeps): o tempo real e
# maior, porque cada ping sem resposta tambem demora.
function Wait-CamOnline {
    param([string]$Ip, [int]$Segundos)
    $t = 0
    Write-Progresso -Detalhe ('Esperando ' + $Ip + ' voltar na rede: 0 de ' + $Segundos + ' s') -Atual 0 -Total $Segundos
    while ($t -lt $Segundos) {
        if (Test-IpEmUso -Ip $Ip) { return $true }
        Start-Sleep -Seconds 5
        $t += 5
        Write-Log ("    aguardando " + $Ip + " ... " + $t + "s") 'DarkGray'
        Write-Progresso -Detalhe ('Esperando ' + $Ip + ' voltar na rede: ' + $t + ' de ' + $Segundos + ' s') -Atual $t -Total $Segundos
    }
    return $false
}

<#
    POST de JSON cru via curl.exe.

    curl e nao Invoke-WebRequest: o curl nao passa pelo proxy WinINET da rede
    corporativa. O corpo vai por arquivo (a linha de comando do Windows
    estraga aspas de JSON) e a resposta volta por arquivo, lida como UTF-8
    (stdout de processo nativo e decodificado na pagina OEM).

    SaidaCurl: 0 ok; 6/7 nao conectou (NADA foi enviado); 28 timeout;
    52/56 conexao caiu. Depois de um setConfig de rede, 28/52/56 sao o
    esperado: a camera trocou de IP no meio da resposta.
#>
function Invoke-CamHttpJson {
    param([string]$Ip, [string]$Endpoint, [string]$Corpo, [int]$Timeout = 25)

    $base = Join-Path $env:TEMP ('rpc-' + [Guid]::NewGuid().ToString('N'))
    $arqCorpo = $base + '.json'
    $arqResp  = $base + '.resp'
    try {
        [IO.File]::WriteAllText($arqCorpo, $Corpo, (New-Object Text.UTF8Encoding($false)))
        $null = & curl.exe -s -g --max-time $Timeout `
                           -H 'Content-Type: application/json' `
                           --data "@$arqCorpo" -o $arqResp (ConvertTo-UrlCam -Ip $Ip -Endpoint $Endpoint) 2>$null
        $codigo = $LASTEXITCODE
        $resp = ''
        if (Test-Path -LiteralPath $arqResp) { $resp = [IO.File]::ReadAllText($arqResp, [Text.Encoding]::UTF8).Trim() }
        return [pscustomobject]@{ Corpo = $resp; SaidaCurl = $codigo }
    } finally {
        Remove-Item $arqCorpo, $arqResp -Force -ErrorAction SilentlyContinue
    }
}

# POST de JSON cru; devolve so o corpo.
function Invoke-CamRpc {
    param([string]$Ip, [string]$Endpoint, [string]$Corpo, [int]$Timeout = 25)
    return (Invoke-CamHttpJson -Ip $Ip -Endpoint $Endpoint -Corpo $Corpo -Timeout $Timeout).Corpo
}

<#
    Inicializacao completa. Retorna $true se a camera ficou
    utilizavel. Diferencas: -Simular virou parametro e a conferencia final e
    por login RPC2 - a CGI dava 401 em firmware antigo e acusava "falhou"
    numa inicializacao que tinha dado certo.

    A senha NUNCA e escrita no log: so aparece dentro do AES.
#>
function Initialize-Cam {
    param([string]$Ip, [string]$Senha, [string]$Email, [switch]$Simular)

    Write-Log ("--- inicializacao de fabrica em " + $Ip + " ---") 'Cyan'

    if ($Simular) {
        Write-Log "  [simular] DevInit.setProtocolAgree {ProtocolEnable:true}" 'DarkGray'
        Write-Log ("  [simular] DevInit.account {name:admin, pwd:<oculta>, CellPhone:'', Mail:" + $Email + "}") 'DarkGray'
        Write-Log "  [simular] DevInit.access {NetAccess:0, UpgradeCheck:2}" 'DarkGray'
        return $true
    }

    $st = Get-CamInitStatus -Ip $Ip
    if (-not $st.Ok) {
        Write-Log ("  DevInit.getStatus nao respondeu em " + $Ip + ": " + (Get-TrechoSeguro $st.Bruto)) 'Red'
        return $false
    }
    if ($st.Init -ne 1) {
        Write-Log ("  Camera JA inicializada (Init=" + $st.Init + ").") 'Yellow'
        return $true
    }
    Write-Log ("  De fabrica confirmado (Init=1, Find=" + $st.Find + ").") 'Gray'
    if ($st.Find -notmatch 'B') {
        Write-Log ("  AVISO: firmware nao anuncia recuperacao por e-mail (Find=" + $st.Find + ").") 'Yellow'
    }

    # 1/3 - aceite do termo de uso. Construtor 'g': VAI com campo session.
    Write-Progresso -Detalhe 'Inicialização 1 de 3: aceitando o termo de uso'
    $r = Invoke-CamRpc -Ip $Ip -Endpoint '/OutsideCmd' `
         -Corpo '{"method":"DevInit.setProtocolAgree","params":{"ProtocolEnable":true},"id":2,"session":0}'
    if ($r -notmatch '"result"\s*:\s*true') {
        Write-Log ("  [1/3] setProtocolAgree recusado: " + (Get-TrechoSeguro $r)) 'Red'
        return $false
    }
    Write-Log "  [1/3] termo de uso aceito" 'Gray'
    # A camera dispara aqui a notificacao assincrona que atravessaria a
    # resposta do getEncryptInfo logo abaixo. 3s deixam ela sair antes.
    Start-Sleep -Seconds 3

    # 2/3 - cria o admin. CellPhone VAZIO + Mail = recuperacao so por e-mail.
    Write-Progresso -Detalhe 'Inicialização 2 de 3: criando o admin'
    $payload = @{ name = 'admin'; pwd = $Senha; CellPhone = ''; Mail = $Email } |
               ConvertTo-Json -Compress
    $r = Invoke-CamRpcCifrado -Ip $Ip -Metodo 'DevInit.account' -PayloadJson $payload -Id 3
    if ($r -notmatch '"result"\s*:\s*true') {
        Write-Log ("  [2/3] DevInit.account recusado: " + (Get-TrechoSeguro $r)) 'Red'
        return $false
    }
    Write-Log ("  [2/3] admin criado, recuperacao apenas por e-mail (" + $Email + ")") 'Green'
    Start-Sleep -Seconds 2

    # 3/3 - NetAccess=0 deixa P2P/nuvem DESLIGADO; UpgradeCheck=2 nao busca
    #       firmware sozinho. O assistente web tolera falha aqui: nao aborta.
    Write-Progresso -Detalhe 'Inicialização 3 de 3: desligando P2P e nuvem'
    $payload = @{ NetAccess = 0; UpgradeCheck = 2 } | ConvertTo-Json -Compress
    $r = Invoke-CamRpcCifrado -Ip $Ip -Metodo 'DevInit.access' -PayloadJson $payload -Id 4
    if ($r -match '"result"\s*:\s*true') {
        Write-Log "  [3/3] P2P/nuvem desligado, sem busca automatica de firmware" 'Gray'
    } else {
        Write-Log ("  [3/3] DevInit.access recusado (nao critico): " + (Get-TrechoSeguro $r)) 'DarkYellow'
    }
    Start-Sleep -Seconds 2

    # Confere por login RPC2. So repete se a camera nao respondeu: repetir
    # senha recusada gasta tentativa do lockout (~5) a toa.
    Write-Progresso -Detalhe 'Inicialização: conferindo o login com a senha nova'
    for ($i = 1; $i -le 2; $i++) {
        $s = New-CamSessao -Ip $Ip -Senha $Senha
        if ($s.Ok) {
            Close-CamSessao $s
            Write-Log "  OK: login RPC2 aceito com a senha nova." 'Green'
            return $true
        }
        if (-not $s.SemResposta) { break }
        Write-Log "  camera ainda nao responde ao login, esperando 10s..." 'DarkGray'
        Start-Sleep -Seconds 10
    }
    Write-Log ("  Inicializacao enviada, mas o login nao passou: " + $s.Erro) 'Yellow'
    return $false
}

function Get-IpsDaPlaca {
    param($Placa)
    return @(Get-NetIPAddress -InterfaceIndex $Placa.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             ForEach-Object { $_.IPAddress })
}

# --- placa escolhida (a unica via do painel ate as cameras; docs/adr/0003)

<#
    Placas fisicas do PC (Ethernet, tipo 6, e Wi-Fi, tipo 71; Bluetooth PAN
    fora), com o que o passo a passo mostra: cabo, DHCP, rota padrao (= leva a
    internet) e IPs. Seam: os testes trocam os cmdlets. Placa desativada faz o
    Get-NetIPAddress estourar: -ErrorAction SilentlyContinue.
    Cada item: { Nome; IfIndex; Mac; Tipo (ethernet|wifi); Cabo; Status; Dhcp; RotaPadrao; Ips @({Ip;Prefixo;Origem}) }
#>
function Get-PlacasFisicas {
    $comRota = @(Get-PlacasComRotaPadrao)
    $saida = New-Object 'System.Collections.Generic.List[object]'
    $adaptadores = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                     Where-Object { [int]$_.InterfaceType -in @(6, 71) -and [string]$_.InterfaceDescription -notlike '*Bluetooth*' })
    foreach ($a in $adaptadores) {
        $ifIndex = [int]$a.ifIndex
        $dhcp = $false
        try { $dhcp = ((Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction Stop).Dhcp -eq 'Enabled') } catch { }
        $ips = @(Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -notlike '169.254.*' } |
                 ForEach-Object { @{ Ip = [string]$_.IPAddress; Prefixo = [int]$_.PrefixLength; Origem = [string]$_.PrefixOrigin } })
        $saida.Add(@{
            Nome = [string]$a.Name; IfIndex = $ifIndex; Mac = (Get-MacNormalizado ([string]$a.MacAddress))
            Tipo = $(if ([int]$a.InterfaceType -eq 71) { 'wifi' } else { 'ethernet' })
            Cabo = ([string]$a.MediaConnectionState -eq 'Connected'); Status = [string]$a.Status
            Dhcp = $dhcp; RotaPadrao = ($comRota -contains $ifIndex); Ips = $ips
            Descricao = [string]$a.InterfaceDescription; Velocidade = [string]$a.LinkSpeed
        })
    }
    return $saida.ToArray()
}

<#
    Qual placa o passo a passo sugere (puro): so Ethernet; uma com cabo -> ela;
    varias com cabo -> a que ja tem o /24 de fabrica, senao a unica sem rota
    padrao (a outra leva a internet); senao a unica Ethernet que existir.
    Devolve o IfIndex, ou 0 quando nao da para saber (o operador escolhe).
#>
function Select-PlacaSugerida {
    param([array]$Placas = @(), [string]$IpFabrica = '192.168.1.108')
    $eth = @($Placas | Where-Object { $null -ne $_ -and [string]$_.Tipo -eq 'ethernet' })
    if ($eth.Count -eq 0) { return 0 }
    $ligadas = @($eth | Where-Object { [bool]$_.Cabo })
    if ($ligadas.Count -eq 1) { return [int]$ligadas[0].IfIndex }
    if ($ligadas.Count -gt 1) {
        $pFab = Get-Prefixo24 $IpFabrica
        foreach ($l in $ligadas) {
            if (@(@($l.Ips) | Where-Object { (Get-Prefixo24 ([string]$_.Ip)) -eq $pFab }).Count -gt 0) { return [int]$l.IfIndex }
        }
        $semRota = @($ligadas | Where-Object { -not [bool]$_.RotaPadrao })
        if ($semRota.Count -eq 1) { return [int]$semRota[0].IfIndex }
        return 0
    }
    if ($eth.Count -eq 1) { return [int]$eth[0].IfIndex }
    return 0
}

<#
    A placa escolhida na sessao, como objeto do Get-NetAdapter (ifIndex, Name,
    MacAddress, InterfaceDescription, LinkSpeed): casa por IfIndex, depois por
    MAC (o Windows renumera placas USB), depois pelo nome. -Placa: { Nome;
    IfIndex; Mac } da sessao (hashtable ou lido do JSON). Nulo com log
    vermelho quando nao existe mais: o operador escolhe outra em Opcoes.
#>
function Resolve-PlacaSessao {
    param($Placa)
    if ($null -eq $Placa) { Write-Log "  nenhuma placa de rede escolhida na sessao: conclua o passo a passo (ou escolha em Opcoes)." 'Red'; return $null }
    $ifIndex = [int](Get-PropriedadeOuVazio $Placa 'IfIndex' 0)
    $mac = Get-MacNormalizado ([string](Get-PropriedadeOuVazio $Placa 'Mac' ''))
    $nome = [string](Get-PropriedadeOuVazio $Placa 'Nome' '')
    $fisicas = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { [int]$_.InterfaceType -in @(6, 71) })
    $achada = $null; $como = ''
    if ($ifIndex -gt 0) { $achada = $fisicas | Where-Object { [int]$_.ifIndex -eq $ifIndex } | Select-Object -First 1; $como = 'ifIndex ' + $ifIndex }
    if ($null -eq $achada -and $mac) { $achada = $fisicas | Where-Object { (Get-MacNormalizado ([string]$_.MacAddress)) -eq $mac } | Select-Object -First 1; $como = 'MAC ' + (Format-Mac $mac) }
    if ($null -eq $achada -and $nome) { $achada = $fisicas | Where-Object { [string]$_.Name -eq $nome } | Select-Object -First 1; $como = "nome '" + $nome + "'" }
    if ($null -eq $achada) {
        Write-Log ("  a placa escolhida na sessao (" + $nome + ", ifIndex " + $ifIndex + ") nao existe mais neste PC. Disponiveis: " +
                   (($fisicas | ForEach-Object { $_.Name }) -join ', ') + ". Escolha outra em Opcoes.") 'Red'
        return $null
    }
    if ($como -notlike 'ifIndex*') { Write-Log ("  placa da sessao achada por " + $como + ": " + $achada.Name + " (ifIndex " + $achada.ifIndex + ")") 'DarkGray' }
    return $achada
}

<#
    Devolve como estatico o que o DHCP dava, depois que o
    Windows tirou a placa do DHCP ao receber endereco fixo (senao o PC perde
    internet e unidades de rede). NAO grava log: devolve as mensagens.
#>
function Restore-ConexaoPlaca {
    param($Placa, $Antes, [hashtable]$Feito = $null)

    $msgs = @()
    if ($null -eq $Feito) { $Feito = @{} }
    $Feito.Mexida = $false
    $Feito.Devolvidos = @()
    $Feito.Rota = $null
    $Feito.Dns = @()

    $aindaDhcp = $false
    try {
        $iface = Get-NetIPInterface -InterfaceIndex $Placa.ifIndex -AddressFamily IPv4 -ErrorAction Stop
        $aindaDhcp = ($iface.Dhcp -eq 'Enabled')
    } catch { }

    if ($aindaDhcp) {
        $msgs += @{ Msg = "  DHCP da placa intacto - conectividade preservada."; Cor = 'DarkGray' }
        return $msgs
    }
    if (-not $Antes.Dhcp) {
        $msgs += @{ Msg = "  a placa ja era estatica antes; conectividade nao foi alterada."; Cor = 'DarkGray' }
        return $msgs
    }

    $Feito.Mexida = $true
    if (-not $Antes.TemLeaseDhcp) {
        # APIPA: cabo direto na camera, sem servidor DHCP. Nada a devolver;
        # o Restaurar DHCP religa o DHCP no fim.
        $msgs += @{ Msg = "  a placa saiu de DHCP para estatica (nao tinha lease: nada a devolver). O painel religa o DHCP ao encerrar."; Cor = 'DarkGray' }
        return $msgs
    }

    $msgs += @{ Msg = "  a placa saiu de DHCP para estatica ao receber o endereco novo."; Cor = 'Yellow' }
    $msgs += @{ Msg = "  devolvendo como estatico o que o DHCP dava, para nao perder a rede:"; Cor = 'Yellow' }

    $agora = @(Get-NetIPAddress -InterfaceIndex $Placa.ifIndex -AddressFamily IPv4 `
                                -ErrorAction SilentlyContinue |
               Select-Object -ExpandProperty IPAddress)

    foreach ($e in $Antes.Enderecos) {
        if ($e.Origem -ne 'Dhcp')      { continue }
        if ($agora -contains $e.Ip)    { continue }
        try {
            $null = New-NetIPAddress -InterfaceIndex $Placa.ifIndex -IPAddress $e.Ip `
                                     -PrefixLength $e.Prefixo -ErrorAction Stop
            $Feito.Devolvidos += @{ Ip = $e.Ip; Prefixo = $e.Prefixo }
            $msgs += @{ Msg = ("    IP      : " + $e.Ip + "/" + $e.Prefixo + "  recolocado"); Cor = 'Green' }
        } catch {
            $msgs += @{ Msg = ("    FALHOU recolocar " + $e.Ip + ": " + $_.Exception.Message); Cor = 'Red' }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Antes.Gateway)) {
        $temRota = @(Get-NetRoute -InterfaceIndex $Placa.ifIndex -DestinationPrefix '0.0.0.0/0' `
                                  -ErrorAction SilentlyContinue)
        if ($temRota.Count -eq 0) {
            try {
                $metrica = [int]$Antes.GatewayMetrica
                if ($metrica -gt 0) {
                    $null = New-NetRoute -InterfaceIndex $Placa.ifIndex -DestinationPrefix '0.0.0.0/0' `
                                         -NextHop $Antes.Gateway -RouteMetric $metrica -ErrorAction Stop
                } else {
                    $null = New-NetRoute -InterfaceIndex $Placa.ifIndex -DestinationPrefix '0.0.0.0/0' `
                                         -NextHop $Antes.Gateway -ErrorAction Stop
                }
                $Feito.Rota = @{ NextHop = $Antes.Gateway; Metrica = $metrica }
                $msgs += @{ Msg = ("    Gateway : " + $Antes.Gateway + "  recolocado (metrica " + $metrica + ")"); Cor = 'Green' }
            } catch {
                $msgs += @{ Msg = ("    FALHOU recolocar o gateway " + $Antes.Gateway + ": " + $_.Exception.Message); Cor = 'Red' }
            }
        } else {
            $msgs += @{ Msg = ("    Gateway : " + $temRota[0].NextHop + "  ja presente"); Cor = 'DarkGray' }
        }
    }

    if ($Antes.Dns.Count -gt 0) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $Placa.ifIndex `
                                       -ServerAddresses $Antes.Dns -ErrorAction Stop
            $Feito.Dns = @($Antes.Dns)
            $msgs += @{ Msg = ("    DNS     : " + ($Antes.Dns -join ', ') + "  recolocado"); Cor = 'Green' }
        } catch {
            $msgs += @{ Msg = ("    FALHOU recolocar o DNS: " + $_.Exception.Message); Cor = 'Red' }
        }
    }

    $msgs += @{ Msg = "  ao encerrar o painel a placa volta ao DHCP sozinha ('Restaurar DHCP' faz o mesmo antes)."; Cor = 'Cyan' }
    return $msgs
}

# Valor de uma propriedade que pode nao existir, em hashtable (in-process) ou
# PSCustomObject (lido do JSON). Ausente ou nula -> $Padrao.
function Get-PropriedadeOuVazio {
    param($Objeto, [string]$Nome, $Padrao = @())
    if ($null -eq $Objeto) { return $Padrao }
    if ($Objeto -is [System.Collections.IDictionary]) {
        if ($Objeto.Contains($Nome) -and $null -ne $Objeto[$Nome]) { return $Objeto[$Nome] }
        return $Padrao
    }
    $p = $Objeto.PSObject.Properties[$Nome]
    if ($null -ne $p -and $null -ne $p.Value) { return $p.Value }
    return $Padrao
}

# Sessao da placa (RASTRO; nao confundir com a Sessao do passo a passo, que e
# sessao.json): o que o painel fez na placa, para desfazer ao encerrar. Vai
# para placa-sessao.json (servidor). Antes = foto da placa; Adicionados = IPs
# que o painel pos (Para: fabrica | cameras | temporario); Rotas = rotas de
# host /32 que o painel pos (camera na faixa de outra placa); Devolvidos/
# Rota/Dns = o que Restore-ConexaoPlaca recolocou como estatico.
function New-SessaoPlaca {
    param($Placa, $Antes)
    return @{
        Quando = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Placa = [string]$Placa.Name; IfIndex = [int]$Placa.ifIndex
        Antes = $Antes; Adicionados = @(); Rotas = @(); Devolvidos = @(); Rota = $null; Dns = @(); Mexida = $false
    }
}

# Junta uma sessao gravada com uma nova da mesma placa: a foto e o Quando
# sao os da primeira (e o estado de antes do painel), os IPs e as rotas de
# host somam sem repetir, e o que foi devolvido vem de quem devolveu. Puro.
function Merge-SessaoPlaca {
    param($Antiga, $Nova)
    if ($null -eq $Antiga) { return $Nova }
    if ($null -eq $Nova) { return $Antiga }
    if ([string]$Antiga.Placa -ne [string]$Nova.Placa) { return $Nova }
    $r = @{
        Quando = $Antiga.Quando; Placa = $Antiga.Placa; IfIndex = $Antiga.IfIndex; Antes = $Antiga.Antes
        Adicionados = @(); Rotas = @(); Devolvidos = @(); Rota = $Antiga.Rota; Dns = @($Antiga.Dns); Mexida = ([bool]$Antiga.Mexida -or [bool]$Nova.Mexida)
    }
    $vistos = @{}
    foreach ($a in @(@($Antiga.Adicionados) + @($Nova.Adicionados))) {
        if ($null -eq $a -or [string]::IsNullOrWhiteSpace($a.Ip)) { continue }
        if ($vistos.ContainsKey([string]$a.Ip)) { continue }
        $vistos[[string]$a.Ip] = $true
        $r.Adicionados += @{ Ip = [string]$a.Ip; Prefixo = [int]$a.Prefixo; Para = [string]$a.Para; Camera = [string]$a.Camera }
    }
    $vistos = @{}
    foreach ($h in @(@(Get-PropriedadeOuVazio $Antiga 'Rotas') + @(Get-PropriedadeOuVazio $Nova 'Rotas'))) {
        if ($null -eq $h -or [string]::IsNullOrWhiteSpace($h.Destino)) { continue }
        if ($vistos.ContainsKey([string]$h.Destino)) { continue }
        $vistos[[string]$h.Destino] = $true
        $r.Rotas += @{ Destino = [string]$h.Destino; NextHop = [string]$h.NextHop; Para = [string]$h.Para; Camera = [string]$h.Camera }
    }
    $vistos = @{}
    foreach ($d in @(@($Antiga.Devolvidos) + @($Nova.Devolvidos))) {
        if ($null -eq $d -or [string]::IsNullOrWhiteSpace($d.Ip)) { continue }
        if ($vistos.ContainsKey([string]$d.Ip)) { continue }
        $vistos[[string]$d.Ip] = $true
        $r.Devolvidos += @{ Ip = [string]$d.Ip; Prefixo = [int]$d.Prefixo }
    }
    if ($null -ne $Nova.Rota -and -not [string]::IsNullOrWhiteSpace($Nova.Rota.NextHop)) { $r.Rota = @{ NextHop = [string]$Nova.Rota.NextHop; Metrica = [int]$Nova.Rota.Metrica } }
    elseif ($null -ne $r.Rota) { $r.Rota = @{ NextHop = [string]$r.Rota.NextHop; Metrica = [int]$r.Rota.Metrica } }
    if (@($Nova.Dns).Count -gt 0) { $r.Dns = @($Nova.Dns) }
    return $r
}

<#
    Acrescenta na placa escolhida os enderecos que faltam: um na faixa de
    fabrica (IpPcFabrica da sessao, ou .220) e um na rede do gateway
    (IpPcCameras, ou .200-.249 pelo MAC). So ADICIONA. "Ja ok" so conta o que
    esta NA PLACA ESCOLHIDA (o mesmo IP no Wi-Fi nao chega na bancada).
    -Placa: { Nome; IfIndex; Mac } da sessao. Em -Simular sem placa, ifIndex
    0 (todas as placas), como no CLI antigo.
    Retorna { Ok; Sessao }: Ok = no fim a placa tem endereco nas duas faixas;
    Sessao = rastro para desfazer (nula quando nada foi tocado).
#>
function Set-RedeLocalCameras {
    param(
        [string]$IpDestinoLocal = '',
        [Parameter(Mandatory)][string]$Gateway,
        [string]$IpFabrica = '192.168.1.108',
        [string]$Mascara = '255.255.255.0',
        $Placa = $null,
        [string]$IpPcFabrica = '',
        [switch]$Simular
    )

    $FaixaDestino = Get-Prefixo24 $Gateway
    $prefixoDestino = Get-PrefixoOu24 $Mascara
    if ($prefixoDestino -eq 24) { $Mascara = '255.255.255.0' }
    $ipPcCameras = $IpDestinoLocal
    $nao = [pscustomobject]@{ Ok = $false; Sessao = $null }
    Write-Log "Preparando a placa de rede deste PC para configurar cameras." 'Cyan'

    if (-not (Test-EhAdministrador)) {
        Write-Log "  ABORTADO: precisa de privilegio de Administrador." 'Red'
        return $nao
    }

    $adaptador = $null
    if ($null -ne $Placa -or -not $Simular) {
        $adaptador = Resolve-PlacaSessao -Placa $Placa
        if ($null -eq $adaptador) { return $nao }
        Write-Log ("  Placa: " + $adaptador.Name + "  (" + $adaptador.InterfaceDescription + ", " + $adaptador.LinkSpeed + ")") 'White'
    }
    $ifIndex = 0; $macPlaca = ''; $daPlaca = @()
    if ($null -ne $adaptador) { $ifIndex = [int]$adaptador.ifIndex; $macPlaca = [string]$adaptador.MacAddress; $daPlaca = @(Get-IpsDaPlaca $adaptador) }

    # IP explicito (sessao) que ja e de OUTRA placa deste PC (Wi-Fi, por
    # exemplo): adicionar daria conflito interno. Recusa antes de mexer.
    foreach ($exp in @($IpPcFabrica, $IpDestinoLocal)) {
        if ([string]::IsNullOrWhiteSpace($exp)) { continue }
        if (-not (Test-Ipv4Estrito $exp)) { Write-Log ("  ABORTADO: IP do PC invalido na sessao: " + $exp) 'Red'; return $nao }
        if ($daPlaca -notcontains $exp -and (Test-IpLocal -Ip $exp)) {
            Write-Log ("  ABORTADO: " + $exp + " ja e um IP deste PC em outra placa. Troque o IP do PC em Opcoes.") 'Red'
            return $nao
        }
    }

    if ([string]::IsNullOrWhiteSpace($IpDestinoLocal)) {
        $IpDestinoLocal = Get-IpLocalSugerido -Faixa $FaixaDestino -MacPlaca $macPlaca -IfIndex $ifIndex
        if ([string]::IsNullOrWhiteSpace($IpDestinoLocal)) {
            Write-Log ("  ABORTADO: nao achei endereco livre em " + $FaixaDestino + ".200-249.") 'Red'
            return $nao
        }
        Write-Log ("  IP escolhido para este PC: " + $IpDestinoLocal + "  (derivado do MAC da placa)") 'White'
    } else {
        Write-Log ("  IP deste PC na rede das cameras: " + $IpDestinoLocal + "  (da sessao)") 'White'
    }
    if (-not (Test-Ipv4Estrito $IpDestinoLocal)) {
        Write-Log ("  ABORTADO: IP invalido: " + $IpDestinoLocal) 'Red'
        return $nao
    }
    $ipFab = (Get-Prefixo24 $IpFabrica) + '.220'
    if (-not [string]::IsNullOrWhiteSpace($IpPcFabrica)) {
        $ipFab = $IpPcFabrica
        Write-Log ("  IP deste PC na faixa de fabrica: " + $ipFab + "  (da sessao)") 'White'
    }

    # O IP de fabrica e /24; o de conferencia leva o prefixo da mascara da
    # sessao (numa /22, um /24 nao enxergaria as cameras dos outros /24).
    $desejados = @(
        @{ Ip = $ipFab; Prefixo = 24; Gateway = ''; Para = 'falar com a camera de fabrica'; Chave = 'fabrica'; Exato = (-not [string]::IsNullOrWhiteSpace($IpPcFabrica)) },
        @{ Ip = $IpDestinoLocal; Prefixo = $prefixoDestino; Gateway = $Gateway; Para = 'conferir a camera no IP definitivo'; Chave = 'cameras'; Exato = (-not [string]::IsNullOrWhiteSpace($ipPcCameras)) }
    )

    # Decidir ANTES de mexer: Test-IpEmUso depende da rede que vai piscar.
    # IP explicito da sessao: so vale o IP exato (ter outro da faixa nao
    # serve). Automatico: qualquer IP da placa escolhida na faixa ja resolve.
    $aFazer = @()
    $avisos = @()
    foreach ($d in $desejados) {
        if ($d.Exato) {
            $jaTem = @(Get-IpsLocais -IfIndex $ifIndex | Where-Object { $_ -eq $d.Ip })
            $rotulo = $d.Ip
        } elseif ($d.Gateway) {
            $jaTem = @(Get-IpsLocais -IfIndex $ifIndex | Where-Object { Test-DestinoNaRede -Ip $_ -Mascara $Mascara -Gateway $d.Gateway })
            $rotulo = ((Get-Prefixo24 $d.Gateway) + '.x/' + $d.Prefixo)
        } else {
            $pref = Get-Prefixo24 $d.Ip
            $jaTem = @(Get-IpsLocais -IfIndex $ifIndex | Where-Object { (Get-Prefixo24 $_) -eq $pref })
            $rotulo = ($pref + '.x')
        }
        if ($jaTem.Count -gt 0) {
            $avisos += @{ Msg = ("  ja ok      " + $rotulo + "  -> " + ($jaTem -join ', ')); Cor = 'DarkGray' }
            continue
        }
        if (Test-IpEmUso -Ip $d.Ip) {
            $avisos += @{ Msg = ("  PULADO     " + $d.Ip + " responde ao ping, ja usado por outro equipamento." +
                                 $(if ($d.Exato) { ' Troque o IP do PC em Opcoes.' } else { '' })); Cor = 'Red' }
            continue
        }
        if ($Simular) {
            $avisos += @{ Msg = ("  [simular]  adicionaria " + $d.Ip + "/" + $d.Prefixo); Cor = 'DarkGray' }
            continue
        }
        $aFazer += $d
    }

    foreach ($a in $avisos) { Write-Log $a.Msg $a.Cor }

    $pre = @{ IpFabrica = $IpFabrica; IpDestino = $Gateway; Mascara = $Mascara; IpPcFabrica = $IpPcFabrica; IpPcCameras = $ipPcCameras; IfIndex = $ifIndex }
    if ($Simular) { return [pscustomobject]@{ Ok = $true; Sessao = $null } }
    if ($aFazer.Count -eq 0) {
        Write-Log ("  IPs da placa agora: " + ((Get-IpsLocais -IfIndex $ifIndex) -join ', ')) 'White'
        return [pscustomobject]@{ Ok = (Test-PreRequisitosRede @pre -Silencioso); Sessao = $null }
    }

    # Daqui em diante a rede pode cair por alguns segundos. Mensagens ficam em
    # memoria; o finally devolve a conectividade mesmo se algo estourar.
    Write-Log "  ajustando a placa (a rede pode piscar por alguns segundos)..." 'Cyan'
    $antes = Get-ConfigIpv4Placa -Placa $adaptador
    $sessao = New-SessaoPlaca -Placa $adaptador -Antes $antes
    $feitos = @()
    try {
        foreach ($d in $aFazer) {
            try {
                # Sem -DefaultGateway de proposito: nao roubar a rota padrao do PC.
                $null = New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -IPAddress $d.Ip `
                                         -PrefixLength $d.Prefixo -ErrorAction Stop
                $sessao.Adicionados += @{ Ip = $d.Ip; Prefixo = $d.Prefixo; Para = $d.Chave; Camera = '' }
                $feitos += @{ Msg = ("  ADICIONADO " + $d.Ip + "/" + $d.Prefixo + "   (" + $d.Para + ")"); Cor = 'Green' }
            } catch {
                $feitos += @{ Msg = ("  FALHOU     " + $d.Ip + ": " + $_.Exception.Message); Cor = 'Red' }
            }
        }
    } finally {
        $feitos += Restore-ConexaoPlaca -Placa $adaptador -Antes $antes -Feito $sessao
    }

    foreach ($f in $feitos) { Write-Log $f.Msg $f.Cor }

    Start-Sleep -Seconds 2
    Write-Log ("  IPs da placa agora: " + ((Get-IpsLocais -IfIndex $ifIndex) -join ', ')) 'White'
    return [pscustomobject]@{ Ok = (Test-PreRequisitosRede @pre -Silencioso); Sessao = $sessao }
}

# Enderecos manuais da placa que estao na faixa de fabrica (/24) ou na rede
# do gateway (pela mascara), mais os que a sessao diz que o painel pos.
# Puro: recebe a lista de enderecos {Ip; Prefixo; Origem}.
function Get-IpsARemover {
    param($Enderecos, [string]$Gateway, [string]$IpFabrica, [string]$Mascara = '255.255.255.0', $Sessao = $null)
    $pFab = Get-Prefixo24 $IpFabrica
    $daSessao = @(); $deAntes = @(); $devolvidos = @(); $eraDhcp = $true
    if ($null -ne $Sessao) {
        $daSessao = @(@($Sessao.Adicionados) | ForEach-Object { [string]$_.Ip })
        $devolvidos = @(@($Sessao.Devolvidos) | ForEach-Object { [string]$_.Ip })
        if ($null -ne $Sessao.Antes) {
            $eraDhcp = [bool]$Sessao.Antes.Dhcp
            # O que a placa ja tinha antes do painel fica (IP fixo do operador).
            $deAntes = @(@($Sessao.Antes.Enderecos) | Where-Object { [string]$_.Origem -eq 'Manual' } | ForEach-Object { [string]$_.Ip })
        }
    }
    $prefixo = Get-PrefixoOu24 $Mascara
    if ($prefixo -eq 24) { $Mascara = '255.255.255.0' }
    $lista = @()
    foreach ($e in @($Enderecos)) {
        $ip = [string]$e.Ip
        if ($daSessao -contains $ip) { $lista += $ip; continue }
        # O que o DHCP dava e foi recolocado como estatico sai junto quando o
        # DHCP volta (senao fica duplicado com o lease novo).
        if ($eraDhcp -and $devolvidos -contains $ip) { $lista += $ip; continue }
        if ([string]$e.Origem -ne 'Manual') { continue }
        if ($deAntes -contains $ip) { continue }
        if ((Get-Prefixo24 $ip) -eq $pFab) { $lista += $ip; continue }
        if ((Test-Ipv4Estrito $Gateway) -and (Test-DestinoNaRede -Ip $ip -Mascara $Mascara -Gateway $Gateway)) { $lista += $ip }
    }
    return @($lista | Select-Object -Unique)
}

<#
    Devolve a placa ao estado de antes do painel. Com a sessao: remove so o
    que o painel pos (mais enderecos manuais nas faixas de camera) e religa
    o DHCP so se a placa era DHCP antes (placa estatica do operador fica
    como esta, rotas inclusive). Placa que volta ao DHCP perde toda rota
    padrao estatica (a devolvida e qualquer sobra de antes). Sem sessao
    (painel fechado no X): remove as faixas de camera, as rotas e religa o
    DHCP, como antes.
    As rotas de host /32 que o painel pos (camera na faixa de outra placa)
    saem ANTES dos IPs, pelo rastro; sem rastro, toda /32 on-link da placa
    criada por NetMgmt (e como o painel as cria).
    -Placa: { Nome; IfIndex; Mac } da sessao; o rastro (IfIndex/Placa) manda
    sobre ela quando existe.
    Retorna { Ok; Removidos; RotasHostRemovidas; RotaRemovida; DhcpReligado }.
#>
function Reset-RedeLocalCameras {
    param(
        # Vazio vale (sessao de fabrica): o rastro diz o que o painel pos.
        [Parameter(Mandatory)][AllowEmptyString()][string]$Gateway,
        [string]$IpFabrica = '192.168.1.108',
        [string]$Mascara = '255.255.255.0',
        $Placa = $null,
        $Sessao = $null
    )

    $res = [pscustomobject]@{ Ok = $false; Removidos = @(); RotasHostRemovidas = @(); RotaRemovida = ''; DhcpReligado = $false }
    Write-Log "Devolvendo a placa de rede deste PC ao estado de antes." 'Cyan'

    if (-not (Test-EhAdministrador)) {
        Write-Log "  ABORTADO: precisa de privilegio de Administrador." 'Red'
        return $res
    }

    $adaptador = $null
    if ($null -ne $Sessao -and ([int](Get-PropriedadeOuVazio $Sessao 'IfIndex' 0) -gt 0 -or -not [string]::IsNullOrWhiteSpace([string](Get-PropriedadeOuVazio $Sessao 'Placa' '')))) {
        $adaptador = Resolve-PlacaSessao -Placa @{ Nome = [string](Get-PropriedadeOuVazio $Sessao 'Placa' ''); IfIndex = [int](Get-PropriedadeOuVazio $Sessao 'IfIndex' 0); Mac = '' }
    }
    if ($null -eq $adaptador -and $null -ne $Placa) { $adaptador = Resolve-PlacaSessao -Placa $Placa }
    if ($null -eq $adaptador) { return $res }
    Write-Log ("  Placa: " + $adaptador.Name) 'White'

    $foto = Get-ConfigIpv4Placa -Placa $adaptador
    $remover = @(Get-IpsARemover -Enderecos $foto.Enderecos -Gateway $Gateway -IpFabrica $IpFabrica -Mascara $Mascara -Sessao $Sessao)

    # Sem sessao nao da para saber como a placa era: assume DHCP (o caso
    # comum) e nao deixa rota estatica sobrando.
    $eraDhcp = $true; $tinhaLease = $foto.TemLeaseDhcp -or -not $foto.Dhcp
    if ($null -ne $Sessao -and $null -ne $Sessao.Antes) { $eraDhcp = [bool]$Sessao.Antes.Dhcp; $tinhaLease = [bool]$Sessao.Antes.TemLeaseDhcp }

    # Rotas de host: do rastro; sem rastro, as /32 on-link que o painel teria posto.
    $rotasHost = @()
    if ($null -ne $Sessao) {
        $rotasHost = @(@(Get-PropriedadeOuVazio $Sessao 'Rotas') | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace($_.Destino) } | ForEach-Object { [string]$_.Destino })
    } else {
        $rotasHost = @(Get-NetRoute -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                       Where-Object { [string]$_.DestinationPrefix -like '*/32' -and [string]$_.NextHop -eq '0.0.0.0' -and [string]$_.Protocol -eq 'NetMgmt' } |
                       ForEach-Object { [string]$_.DestinationPrefix })
    }

    $msgs = @()
    try {
        foreach ($rh in $rotasHost) {
            try {
                Remove-NetRoute -InterfaceIndex $adaptador.ifIndex -DestinationPrefix $rh -NextHop '0.0.0.0' -Confirm:$false -ErrorAction Stop
                $res.RotasHostRemovidas += $rh
                $msgs += @{ Msg = ("  REMOVIDA   rota de host " + $rh); Cor = 'Green' }
            } catch {
                if ($_.Exception.Message -match 'No matching|n.o encontr|ObjectNotFound') { $msgs += @{ Msg = ("  rota de host " + $rh + " ja nao estava na placa"); Cor = 'DarkGray' } }
                else { $msgs += @{ Msg = ("  FALHOU remover a rota de host " + $rh + ": " + $_.Exception.Message); Cor = 'Red' } }
            }
        }
        foreach ($ip in $remover) {
            try {
                Remove-NetIPAddress -InterfaceIndex $adaptador.ifIndex -IPAddress $ip -Confirm:$false -ErrorAction Stop
                $res.Removidos += $ip
                $msgs += @{ Msg = ("  REMOVIDO   " + $ip); Cor = 'Green' }
            } catch {
                $msgs += @{ Msg = ("  FALHOU remover " + $ip + ": " + $_.Exception.Message); Cor = 'Red' }
            }
        }
        # Rota padrao: placa que volta ao DHCP nao fica com rota estatica
        # nenhuma (a que o painel devolveu, pelo NextHop da sessao, e qualquer
        # outra sobrando de antes: o DHCP poe a dele). Placa estatica do
        # operador: nenhuma rota e tocada.
        $rotas = @()
        if ($eraDhcp) {
            $rotas = @(Get-NetRoute -InterfaceIndex $adaptador.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
        }
        foreach ($r in $rotas) {
            try {
                Remove-NetRoute -InterfaceIndex $adaptador.ifIndex -DestinationPrefix '0.0.0.0/0' -NextHop $r.NextHop -Confirm:$false -ErrorAction Stop
                $res.RotaRemovida = [string]$r.NextHop
                $msgs += @{ Msg = ("  REMOVIDA   rota padrao via " + $r.NextHop); Cor = 'Green' }
            } catch {
                $msgs += @{ Msg = ("  FALHOU remover a rota via " + $r.NextHop + ": " + $_.Exception.Message); Cor = 'Red' }
            }
        }
        if ($eraDhcp) {
            try {
                Set-NetIPInterface -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
                Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
                $res.DhcpReligado = $true
                $msgs += @{ Msg = "  DHCP reativado na placa."; Cor = 'Green' }
            } catch {
                $msgs += @{ Msg = ("  FALHOU reativar o DHCP: " + $_.Exception.Message); Cor = 'Red' }
            }
            # Renovar sem servidor DHCP (cabo direto na camera) so demora.
            if ($tinhaLease) { Invoke-RenovarDhcp -Placa $adaptador }
        } else {
            $msgs += @{ Msg = "  a placa era estatica antes do painel: DHCP nao foi mexido."; Cor = 'DarkGray' }
        }
        $res.Ok = $true
    } finally {
        Start-Sleep -Seconds 3
        foreach ($m in $msgs) { Write-Log $m.Msg $m.Cor }
    }

    Write-Log ("  IPs da placa agora: " + ((Get-IpsLocais -IfIndex ([int]$adaptador.ifIndex)) -join ', ')) 'White'
    return $res
}

# --- versao do painel

# VERSAO.txt fica ao lado do Motor-Cameras.ps1 (fonte\ no repo, {app} no
# instalador). E a unica fonte: o .iss le o mesmo arquivo e a tag do GitHub
# tem que bater com ele. Sem arquivo: '0.0.0' (copia incompleta).
function Get-VersaoPainel {
    param([string]$Pasta = '')
    if ([string]::IsNullOrWhiteSpace($Pasta)) { $Pasta = $PSScriptRoot }
    if ([string]::IsNullOrWhiteSpace($Pasta)) { return '0.0.0' }
    $arq = Join-Path $Pasta 'VERSAO.txt'
    if (-not (Test-Path -LiteralPath $arq)) { return '0.0.0' }
    try { $v = ([IO.File]::ReadAllText($arq)).Trim() } catch { return '0.0.0' }
    if ($null -eq (ConvertTo-VersaoPainel $v)) { return '0.0.0' }
    return $v
}

# '1.2.3', 'v1.2.3' ou '1.2.3.4' -> [version]; nulo se nao for versao. Puro.
function ConvertTo-VersaoPainel {
    param([string]$Texto)
    if ([string]::IsNullOrWhiteSpace($Texto)) { return $null }
    $t = $Texto.Trim()
    if ($t -match '^[vV]') { $t = $t.Substring(1) }
    if ($t -notmatch '^\d+(\.\d+){1,3}$') { return $null }
    try { return [version]$t } catch { return $null }
}

# -1 se A < B, 0 se iguais, 1 se A > B; texto invalido conta como 0.0. Puro.
function Compare-Versao {
    param([string]$A, [string]$B)
    $va = ConvertTo-VersaoPainel $A; if ($null -eq $va) { $va = [version]'0.0' }
    $vb = ConvertTo-VersaoPainel $B; if ($null -eq $vb) { $vb = [version]'0.0' }
    return $va.CompareTo($vb)
}

# --- atualizacao pelo GitHub Releases

<#
    Le o JSON de releases/latest da API do GitHub. Devolve { Versao; Tag;
    Url; Sha256Url; Tamanho; Notas; Publicado; Pagina } ou $null quando nao
    ha o asset ConfigurarCameras-x.y.z-instalador.exe (release sem instalador,
    rascunho, JSON de erro da API). Puro.
#>
function ConvertFrom-ReleaseGitHub {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return $null }
    $o = $null
    try { $o = $Json | ConvertFrom-Json } catch { return $null }
    if ($null -eq $o -or $null -eq $o.PSObject.Properties['tag_name']) { return $null }
    if ([bool]$o.draft) { return $null }
    $v = ConvertTo-VersaoPainel ([string]$o.tag_name)
    if ($null -eq $v) { return $null }
    $exe = $null; $sha = $null
    foreach ($a in @($o.assets)) {
        if ($null -eq $a) { continue }
        $n = [string]$a.name
        if ($n -match '^ConfigurarCameras-\d+\.\d+\.\d+-instalador\.exe$') { $exe = $a }
        elseif ($n -match '^ConfigurarCameras-\d+\.\d+\.\d+-instalador\.exe\.sha256$') { $sha = $a }
    }
    if ($null -eq $exe -or [string]::IsNullOrWhiteSpace($exe.browser_download_url)) { return $null }
    $tam = 0; $null = [long]::TryParse([string]$exe.size, [ref]$tam)
    return [pscustomobject]@{
        Versao    = ([string]$o.tag_name).TrimStart('v', 'V')
        Tag       = [string]$o.tag_name
        Url       = [string]$exe.browser_download_url
        Sha256Url = $(if ($null -ne $sha) { [string]$sha.browser_download_url } else { '' })
        Tamanho   = [long]$tam
        Notas     = [string]$o.body
        Publicado = [string]$o.published_at
        Pagina    = [string]$o.html_url
    }
}

# Hash de um arquivo .sha256 (formato sha256sum: "<hex>  <nome>"): o primeiro
# token de 64 hex, em minusculas; vazio se nao houver. Puro.
function Get-HashDoSha256 {
    param([string]$Texto)
    if ([string]::IsNullOrWhiteSpace($Texto)) { return '' }
    $m = [regex]::Match($Texto, '(?i)\b[0-9a-f]{64}\b')
    if (-not $m.Success) { return '' }
    return $m.Value.ToLowerInvariant()
}

# Checa 1x por dia: sem registro (ou registro ilegivel) checa agora. Puro.
function Test-DeveChecarAtualizacao {
    param([string]$UltimaChecagem = '', [datetime]$Agora, [int]$Horas = 24)
    if ([string]::IsNullOrWhiteSpace($UltimaChecagem)) { return $true }
    $u = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($UltimaChecagem, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$u)) { return $true }
    return (($Agora - $u).TotalHours -ge $Horas)
}

# --- instancia unica e auto-encerrar do painel

# painel.json: { porta; pid; inicio } gravado pelo painel aberto. Nulo se nao
# existe, esta ilegivel ou nao tem porta/pid. Puro (so le o arquivo).
function Read-LockPainel {
    param([Parameter(Mandatory)][string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho)) { return $null }
    try {
        $o = [IO.File]::ReadAllText($Caminho, [Text.Encoding]::UTF8) | ConvertFrom-Json
        # ($PID e variavel automatica do PowerShell: nome diferente aqui.)
        $porta = 0; $idProc = 0
        if ($null -eq $o -or -not [int]::TryParse([string]$o.porta, [ref]$porta) -or -not [int]::TryParse([string]$o.pid, [ref]$idProc)) { return $null }
        if ($porta -le 0 -or $idProc -le 0) { return $null }
        return [pscustomobject]@{ Porta = $porta; Pid = $idProc; Inicio = [string]$o.inicio }
    } catch { return $null }
}

<#
    O painel fecha sozinho quando a pagina sumiu (sem GET /api/estado por
    -LimiteSeg) E nao ha nada em curso: fase fora de configurando/decisao/
    escolher, vigia desligado, worker livre, fila de comandos vazia, sem
    atualizacao. -LimiteSeg 0 desliga. Puro.
#>
function Test-PainelOcioso {
    param([string]$Fase = '', [bool]$VigiaLigado = $false, [bool]$Ocupado = $false, [int]$Comandos = 0,
          [bool]$Atualizando = $false, [datetime]$UltimoPoll, [datetime]$Agora, [int]$LimiteSeg = 180)
    if ($LimiteSeg -le 0) { return $false }
    if ($Fase -in @('configurando', 'decisao', 'escolher')) { return $false }
    if ($VigiaLigado -or $Ocupado -or $Comandos -gt 0 -or $Atualizando) { return $false }
    return (($Agora - $UltimoPoll).TotalSeconds -ge $LimiteSeg)
}

# ------------------------------------------------------------- RPC2: login

function ConvertFrom-JsonSeguro {
    param([string]$Texto)
    if ([string]::IsNullOrWhiteSpace($Texto)) { return $null }
    try { return ($Texto | ConvertFrom-Json) } catch { return $null }
}

function Get-Md5Maiusculo {
    param([string]$Texto)
    $md5 = [Security.Cryptography.MD5]::Create()
    try { $h = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Texto)) } finally { $md5.Dispose() }
    return (([BitConverter]::ToString($h)) -replace '-', '').ToUpperInvariant()
}

# Hash do passo 2 do login: MD5(usuario:random:MD5(usuario:realm:senha)), hex maiusculo.
function Get-HashLoginRpc {
    param([string]$Usuario, [string]$Senha, [string]$Realm, [string]$Random)
    $interno = Get-Md5Maiusculo ($Usuario + ':' + $Realm + ':' + $Senha)
    return (Get-Md5Maiusculo ($Usuario + ':' + $Random + ':' + $interno))
}

<#
    Classifica a recusa do passo 2 do login.
    268632079 e o "login challenge!" do passo 1 (normal). Os codigos de senha
    errada e de conta bloqueada vem da comunidade Dahua e NAO foram vistos
    nesta obra - por isso a mensagem tambem e olhada.
#>
function Get-ClassificacaoErroLogin {
    param($Codigo, [string]$Mensagem = '')
    $c = [string]$Codigo
    if ($c -eq '268632081' -or $Mensagem -match '(?i)lock') { return 'bloqueada' }
    if ($c -eq '268632085' -or $c -eq '268632086' -or $Mensagem -match '(?i)password|passwd|user.*not.*valid|invalid') { return 'senha' }
    return 'outro'
}

<#
    Login RPC2 em dois passos, o mesmo da pagina web da camera:
      1. global.login com senha vazia -> a camera recusa com "login
         challenge!" (e o NORMAL) e devolve realm, random e session.
      2. global.login com o hash, na mesma session -> result true.

    LOCKOUT: o firmware bloqueia a conta depois de ~5 senhas erradas. Esta
    funcao NUNCA repete um login recusado; quem chama so repete quando a falha
    foi falta de resposta (SemResposta).
#>
function New-CamSessao {
    param([string]$Ip, [string]$Senha, [string]$Usuario = 'admin', [int]$Timeout = 10)

    $s = [pscustomobject]@{
        Ip = $Ip; Usuario = $Usuario; Session = $null; Id = 10; Timeout = $Timeout
        Ok = $false; Erro = ''; SemResposta = $false; SenhaErrada = $false; Bloqueada = $false
    }

    $passo1 = @{ method = 'global.login'; id = 1
                 params = @{ userName = $Usuario; password = ''; clientType = 'Web3.0'; loginType = 'Direct' } } |
              ConvertTo-Json -Compress
    $r1 = Invoke-CamHttpJson -Ip $Ip -Endpoint '/RPC2_Login' -Corpo $passo1 -Timeout $Timeout
    $o1 = ConvertFrom-JsonSeguro $r1.Corpo
    if ($null -eq $o1) {
        $s.SemResposta = $true
        $s.Erro = 'sem resposta do login RPC2 em ' + $Ip + ' (curl=' + $r1.SaidaCurl + ')'
        return $s
    }
    if ($null -eq $o1.params -or [string]::IsNullOrEmpty([string]$o1.params.realm) -or
        [string]::IsNullOrEmpty([string]$o1.params.random)) {
        $s.Erro = 'login RPC2 sem desafio (realm/random): ' + (Get-TrechoSeguro $r1.Corpo)
        return $s
    }
    if ($o1.params.encryption -and [string]$o1.params.encryption -ne 'Default') {
        Write-Log ("  AVISO: login RPC2 pede encryption=" + $o1.params.encryption + " (validado so com Default)") 'Yellow'
    }

    $hash = Get-HashLoginRpc -Usuario $Usuario -Senha $Senha `
                             -Realm ([string]$o1.params.realm) -Random ([string]$o1.params.random)
    $passo2 = @{ method = 'global.login'; id = 2; session = $o1.session
                 params = @{ userName = $Usuario; password = $hash; clientType = 'Web3.0'
                             loginType = 'Direct'; authorityType = 'Default' } } |
              ConvertTo-Json -Compress
    $r2 = Invoke-CamHttpJson -Ip $Ip -Endpoint '/RPC2_Login' -Corpo $passo2 -Timeout $Timeout
    $o2 = ConvertFrom-JsonSeguro $r2.Corpo
    if ($null -eq $o2) {
        $s.SemResposta = $true
        $s.Erro = 'sem resposta ao passo 2 do login em ' + $Ip + ' (curl=' + $r2.SaidaCurl + ')'
        return $s
    }
    if ($o2.result -eq $true) {
        $s.Ok = $true
        $s.Session = $o2.session
        if ($null -eq $s.Session) { $s.Session = $o1.session }
        return $s
    }

    $codigo = $null; $msg = ''
    if ($null -ne $o2.error) { $codigo = $o2.error.code; $msg = [string]$o2.error.message }
    switch (Get-ClassificacaoErroLogin -Codigo $codigo -Mensagem $msg) {
        'bloqueada' { $s.Bloqueada   = $true; $s.Erro = 'conta admin BLOQUEADA pela camera (muitas senhas erradas). Espere o desbloqueio antes de tentar de novo.' }
        'senha'     { $s.SenhaErrada = $true; $s.Erro = 'senha recusada pela camera' }
        default     { $s.Erro = 'login recusado' }
    }
    $s.Erro += ' (codigo ' + $codigo + ': ' + $msg + ')'
    if ($null -ne $o2.params -and $null -ne $o2.params.remainLoginTimes) {
        $s.Erro += ' - restam ' + $o2.params.remainLoginTimes + ' tentativa(s)'
    }
    return $s
}

function Invoke-CamRpc2 {
    param($Sessao, [string]$Metodo, $Params = $null, [int]$Timeout = 0)

    if ($Timeout -le 0) { $Timeout = $Sessao.Timeout }
    $Sessao.Id++
    $corpo = ConvertTo-Json -Compress -Depth 30 -InputObject @{
        method = $Metodo; params = $Params; id = $Sessao.Id; session = $Sessao.Session }
    $r = Invoke-CamHttpJson -Ip $Sessao.Ip -Endpoint '/RPC2' -Corpo $corpo -Timeout $Timeout
    $o = ConvertFrom-JsonSeguro $r.Corpo

    $res = [pscustomobject]@{ Ok = $false; Params = $null; Erro = ''; SemResposta = $false
                              SaidaCurl = $r.SaidaCurl; Bruto = $r.Corpo }
    if ($null -eq $o) {
        $res.SemResposta = $true
        $res.Erro = $Metodo + ': sem resposta (curl=' + $r.SaidaCurl + ')'
        return $res
    }
    $res.Params = $o.params
    if ($o.result -eq $true) {
        $res.Ok = $true
    } else {
        $res.Erro = $Metodo + ' recusado'
        if ($null -ne $o.error) { $res.Erro += ' (codigo ' + $o.error.code + ': ' + $o.error.message + ')' }
    }
    return $res
}

function Close-CamSessao {
    param($Sessao)
    if ($null -eq $Sessao -or -not $Sessao.Ok) { return }
    try { $null = Invoke-CamRpc2 -Sessao $Sessao -Metodo 'global.logout' -Timeout 5 } catch { }
    $Sessao.Ok = $false
}

# ------------------------------------------------ RPC2: leitura e gravacao

# Copia profunda por JSON: as transformacoes nunca mexem no que foi lido.
function Copy-ObjetoJson {
    param($Objeto)
    return (ConvertTo-Json -InputObject $Objeto -Depth 30 -Compress | ConvertFrom-Json)
}

function Get-NomeInterfaceRede {
    param($Tabela)
    $nomes = @($Tabela.PSObject.Properties | ForEach-Object { $_.Name })
    $padrao = [string]$Tabela.DefaultInterface
    if ($padrao -ne '' -and $nomes -contains $padrao) { return $padrao }
    if ($nomes -contains 'eth0') { return 'eth0' }
    throw 'tabela Network sem interface eth0 nem DefaultInterface'
}

# Tabela Network -> o que interessa para conferencia e relatorio.
function Get-ResumoRede {
    param($Tabela)
    $e = $Tabela.(Get-NomeInterfaceRede $Tabela)
    return [pscustomobject]@{
        Ip      = [string]$e.IPAddress
        Mascara = [string]$e.SubnetMask
        Gateway = [string]$e.DefaultGateway
        Dhcp    = [string]$e.DhcpEnable
        Mac     = [string]$e.PhysicalAddress
        Dns     = @($e.DnsServers)
    }
}

function Get-CamRedeRpc {
    param($Sessao)
    $r = Invoke-CamRpc2 -Sessao $Sessao -Metodo 'configManager.getConfig' -Params @{ name = 'Network' }
    return [pscustomobject]@{ Ok = ($r.Ok -and $null -ne $r.Params.table); Tabela = $r.Params.table; Erro = $r.Erro }
}


function Get-CamInfoRpc {
    param($Sessao)

    $info = [pscustomobject]@{
        Ok = $false; Erro = ''; Modelo = ''; Serial = ''; Firmware = ''
        Mac = ''; IpAtual = ''; Mascara = ''; Gateway = ''; Dhcp = ''
    }
    $r = Invoke-CamRpc2 -Sessao $Sessao -Metodo 'magicBox.getDeviceType'
    if (-not $r.Ok) { $info.Erro = $r.Erro; return $info }
    $info.Modelo = [string]$r.Params.type

    $r = Invoke-CamRpc2 -Sessao $Sessao -Metodo 'magicBox.getSerialNo'
    if ($r.Ok) { $info.Serial = [string]$r.Params.sn }
    $r = Invoke-CamRpc2 -Sessao $Sessao -Metodo 'magicBox.getSoftwareVersion'
    if ($r.Ok -and $null -ne $r.Params.version) { $info.Firmware = [string]$r.Params.version.Version }

    $rede = Get-CamRedeRpc -Sessao $Sessao
    if (-not $rede.Ok) { $info.Erro = 'leitura da rede: ' + $rede.Erro; return $info }
    $res = Get-ResumoRede $rede.Tabela
    $info.Mac     = $res.Mac
    $info.IpAtual = $res.Ip
    $info.Mascara = $res.Mascara
    $info.Gateway = $res.Gateway
    $info.Dhcp    = $res.Dhcp
    $info.Ok = $true
    return $info
}

function Get-CamEncode {
    param($Sessao)
    $r = Invoke-CamRpc2 -Sessao $Sessao -Metodo 'configManager.getConfig' -Params @{ name = 'Encode' }
    return [pscustomobject]@{ Ok = ($r.Ok -and $null -ne $r.Params.table); Tabela = $r.Params.table; Erro = $r.Erro }
}

# A tabela vai INTEIRA (lida e modificada): foi assim que a escrita validou.
function Set-CamEncode {
    param($Sessao, $Tabela)
    return (Invoke-CamRpc2 -Sessao $Sessao -Metodo 'configManager.setConfig' `
                           -Params @{ name = 'Encode'; table = [object[]]@($Tabela); options = @() })
}

<#
    Grava a rede. Timeout curto de proposito: a camera troca de IP durante a
    resposta, e ficar sem resposta aqui e o NORMAL (Enviou = $true). So
    SaidaCurl 6/7 garante que nada chegou na camera.
#>
function Set-CamRedeRpc {
    param($Sessao, $Tabela)
    $r = Invoke-CamRpc2 -Sessao $Sessao -Metodo 'configManager.setConfig' -Timeout 8 `
                        -Params @{ name = 'Network'; table = $Tabela; options = @() }
    $enviou = -not ($r.SaidaCurl -eq 6 -or $r.SaidaCurl -eq 7)
    return [pscustomobject]@{
        Ok = $r.Ok; Enviou = $enviou; SemResposta = $r.SemResposta
        Recusado = (-not $r.Ok -and -not $r.SemResposta); Erro = $r.Erro
    }
}

# ------------------------------------------------ transformacoes puras

# Resolucoes aceitas nos padroes -> CustomResolutionName do firmware.
# 1080P e D1 foram lidos da camera real; 720P e 4M seguem a nomenclatura Dahua.
function Get-MapaResolucoes {
    return [ordered]@{ '1920x1080' = '1080P'; '1280x720' = '720P'; '704x480' = 'D1'; '2688x1520' = '4M' }
}

# Stream secundario. So D1 foi validada em camera real; CIF e VGA seguem a
# nomenclatura Dahua; 720P foi recusada pela VIP-1230-D-G3 (02/10/2026) e
# fica para outros modelos (Get-CatalogoEncoder marca recusado).
function Get-MapaResolucoesSecundario {
    return [ordered]@{ '352x240' = 'CIF'; '640x480' = 'VGA'; '704x480' = 'D1'; '1280x720' = '720P' }
}

# Valores de Video.Compression aceitos nos padroes. H.264 e H.265 validados no
# stream principal da VIP-1230-D-G3 (29/09/2026) e no secundario (02/10/2026).
function Get-CodecsAceitos { return @('H.264', 'H.265') }

function Set-CampoObrigatorio {
    param($Objeto, [string]$Nome, $Valor, [string]$Onde)
    if ($null -eq $Objeto -or $null -eq $Objeto.PSObject.Properties[$Nome]) {
        throw ('formato inesperado: ' + $Onde + ' sem o campo ' + $Nome)
    }
    $Objeto.$Nome = $Valor
}

<#
    Valores prontos do encoder para a pagina (lista + digitar livre): fps,
    degraus de bitrate do firmware Dahua e, por resolucao, a faixa usual com
    o recomendado em H.264 e em H.265 (~metade). Faixas de referencia, nao
    limite: o limite e o de Test-StreamPadroes.
    testado/recusado: o que a camera de referencia (Modelo) aceitou ou
    recusou, por stream. Atualizar so com teste em camera real.
#>
function Get-CatalogoEncoder {
    $faixa = { param($Min, $Max, $H264, $H265) [ordered]@{ min = $Min; max = $Max; 'H.264' = $H264; 'H.265' = $H265 } }
    return [ordered]@{
        fps      = @(5, 8, 10, 12, 15, 20, 24, 25, 30)
        bitrates = @(64, 96, 128, 192, 256, 320, 384, 448, 512, 640, 768, 896, 1024, 1280, 1536, 1792,
                     2048, 2560, 3072, 4096, 5120, 6144, 8192, 10240, 12288, 16384)
        faixas   = [ordered]@{
            '2688x1520' = (& $faixa 1024 10240 4096 2048)
            '1920x1080' = (& $faixa 1024 8192 4096 2048)
            '1280x720'  = (& $faixa 512 6144 2048 1024)
            '704x480'   = (& $faixa 256 2048 1024 512)
            '640x480'   = (& $faixa 256 2048 768 384)
            '352x240'   = (& $faixa 64 1024 256 128)
        }
        modelo   = 'VIP-1230-D-G3'
        # VIP-1230-D-G3 fw 2.800.00IB003.0.T (29/09 e 02/10/2026). Secundario
        # 1280x720 recusado (268959743) em H.264 e em H.265; 704x480 H.265 aceito.
        testado  = [ordered]@{
            principal  = [ordered]@{ resolucoes = @('1920x1080'); codecs = @('H.264', 'H.265') }
            secundario = [ordered]@{ resolucoes = @('704x480');   codecs = @('H.264', 'H.265') }
        }
        recusado = [ordered]@{
            principal  = [ordered]@{ resolucoes = @(); codecs = @() }
            secundario = [ordered]@{ resolucoes = @('1280x720'); codecs = @() }
        }
    }
}

<#
    Grava um stream dos padroes em todas as entradas de MainFormat[] ou
    ExtraFormat[]: Width, Height, FPS, BitRate, GOP (= 2 x FPS), Compression
    e CustomResolutionName (quando existe). Entrada nula e pulada.
    -SoFormato: so resolucao, fps e codec; BitRate e GOP ficam como vieram
    (passo 1 de Set-CamEncodeEmPassos).
#>
function Set-StreamAjustado {
    param($Formatos, $Stream, $Mapa, [string]$Nome, [switch]$SoFormato)

    $res = [string]$Stream.Resolucao
    if (-not $Mapa.Contains($res)) { throw ('resolucao do ' + $Nome + ' fora da lista: ' + $res) }
    $codec = [string]$Stream.Codec
    if ((Get-CodecsAceitos) -notcontains $codec) { throw ('codec do ' + $Nome + ' fora da lista: ' + $codec) }
    $wh = $res -split 'x'
    $fps = [int]$Stream.Fps

    $i = 0
    foreach ($f in @($Formatos)) {
        if ($null -eq $f) { continue }
        $onde = $Nome + '[' + $i + '].Video'
        Set-CampoObrigatorio $f.Video 'Width'       ([int]$wh[0])          $onde
        Set-CampoObrigatorio $f.Video 'Height'      ([int]$wh[1])          $onde
        Set-CampoObrigatorio $f.Video 'FPS'         $fps                   $onde
        if (-not $SoFormato) {
            Set-CampoObrigatorio $f.Video 'BitRate' ([int]$Stream.BitRate) $onde
            Set-CampoObrigatorio $f.Video 'GOP'     (2 * $fps)             $onde
        }
        Set-CampoObrigatorio $f.Video 'Compression' $codec                 $onde
        if ($null -ne $f.Video.PSObject.Properties['CustomResolutionName']) {
            $f.Video.CustomResolutionName = $Mapa[$res]
        }
        $i++
    }
}

<#
    Ajuste de encoder sobre a tabela Encode lida da camera. Devolve uma COPIA
    com o stream principal gravado em todas as entradas MainFormat[] e o
    secundario em todas as ExtraFormat[] (ver Set-StreamAjustado).
    CBR/VBR, perfil, audio e SnapFormat ficam como vieram.
    -SoFormato: sem BitRate e GOP (ver Set-StreamAjustado).
    Quem chama embrulha o retorno em @().
#>
function ConvertTo-EncodeAjustado {
    param($Tabela, $Padroes, [switch]$SoFormato)

    $copia = @(Copy-ObjetoJson @($Tabela))
    if ($copia.Count -eq 0) { throw 'tabela Encode vazia' }
    $c = 0
    foreach ($canal in $copia) {
        $main = @($canal.MainFormat)
        if ($main.Count -eq 0 -or $null -eq $main[0]) { throw ('Encode canal ' + $c + ' sem MainFormat') }
        Set-StreamAjustado $main $Padroes.Encoder.Principal (Get-MapaResolucoes) 'MainFormat' -SoFormato:$SoFormato
        Set-StreamAjustado @($canal.ExtraFormat) $Padroes.Encoder.Secundario (Get-MapaResolucoesSecundario) 'ExtraFormat' -SoFormato:$SoFormato
        $c++
    }
    return $copia
}

# Leitura de volta de um stream x padroes: acrescenta as divergencias em $Dif.
function Add-DivergenciasStream {
    param($Dif, $Formatos, $Stream, [string]$Nome)

    $fps = [int]$Stream.Fps
    $i = 0
    foreach ($f in @($Formatos)) {
        if ($null -eq $f) { continue }
        $v = $f.Video
        $pre = $Nome + ' [' + $i + ']: '
        $lido = [string]$v.Width + 'x' + [string]$v.Height
        if ($lido -ne [string]$Stream.Resolucao) { $Dif.Add($pre + 'resolucao ' + $lido + ', pedido ' + $Stream.Resolucao) }
        if ([int]$v.FPS -ne $fps) { $Dif.Add($pre + $v.FPS + ' fps, pedido ' + $fps) }
        if ([int]$v.BitRate -ne [int]$Stream.BitRate) { $Dif.Add($pre + $v.BitRate + ' kbps, pedido ' + $Stream.BitRate) }
        if ([int]$v.GOP -ne 2 * $fps) { $Dif.Add($pre + 'GOP ' + $v.GOP + ', pedido ' + (2 * $fps)) }
        if ([string]$v.Compression -ne [string]$Stream.Codec) { $Dif.Add($pre + 'codec ' + $v.Compression + ', pedido ' + $Stream.Codec) }
        $i++
    }
}

# Leitura de volta x padroes. Devolve a lista de divergencias (vazia = ok).
function Compare-EncodeAplicado {
    param($Tabela, $Padroes)

    $dif = New-Object 'System.Collections.Generic.List[string]'
    foreach ($canal in @($Tabela)) {
        Add-DivergenciasStream $dif @($canal.MainFormat) $Padroes.Encoder.Principal 'stream principal'
        Add-DivergenciasStream $dif @($canal.ExtraFormat) $Padroes.Encoder.Secundario 'stream secundario'
    }
    return $dif.ToArray()
}

# O que o relatorio mostra do encoder: a primeira entrada de cada stream.
function Get-ResumoEncode {
    param($Tabela)
    $canal = @($Tabela)[0]
    $m = @($canal.MainFormat)[0].Video
    $o = [pscustomobject]@{
        Resolucao = ([string]$m.Width + 'x' + [string]$m.Height)
        FpsPrincipal = [string]$m.FPS; BitratePrincipal = [string]$m.BitRate
        CodecPrincipal = [string]$m.Compression; GopPrincipal = [string]$m.GOP
        ResolucaoSecundario = ''; FpsSecundario = ''; BitrateSecundario = ''
        CodecSecundario = ''; GopSecundario = ''
    }
    $x = @($canal.ExtraFormat)
    if ($x.Count -gt 0 -and $null -ne $x[0]) {
        $v = $x[0].Video
        $o.ResolucaoSecundario = [string]$v.Width + 'x' + [string]$v.Height
        $o.FpsSecundario = [string]$v.FPS; $o.BitrateSecundario = [string]$v.BitRate
        $o.CodecSecundario = [string]$v.Compression; $o.GopSecundario = [string]$v.GOP
    }
    return $o
}

# Resumo do encoder numa linha, para o log.
function Format-ResumoEncode {
    param($Resumo)
    $r = $Resumo
    return ('stream principal ' + $r.Resolucao + ' ' + $r.FpsPrincipal + ' fps ' + $r.BitratePrincipal + ' kbps ' +
            $r.CodecPrincipal + ' GOP ' + $r.GopPrincipal + '; secundario ' + $r.ResolucaoSecundario + ' ' +
            $r.FpsSecundario + ' fps ' + $r.BitrateSecundario + ' kbps ' + $r.CodecSecundario + ' GOP ' + $r.GopSecundario)
}

# O que cada passo de Set-CamEncodeEmPassos grava, para o log e o erro.
function Format-PassoEncoder {
    param($Padroes, [int]$Passo)
    $p = $Padroes.Encoder.Principal; $s = $Padroes.Encoder.Secundario
    if ($Passo -eq 1) {
        return ('formato: principal ' + $p.Resolucao + ' ' + $p.Fps + ' fps ' + $p.Codec +
                '; secundario ' + $s.Resolucao + ' ' + $s.Fps + ' fps ' + $s.Codec)
    }
    return ('taxa e GOP: principal ' + $p.BitRate + ' kbps GOP ' + (2 * [int]$p.Fps) +
            '; secundario ' + $s.BitRate + ' kbps GOP ' + (2 * [int]$s.Fps))
}

<#
    Encoder em 2 gravacoes. Em 01/10/2026 a VIP-1230-D-G3 recusou a gravacao
    unica que trocava formato, taxa e GOP juntos; em 29/09, em 2 gravacoes,
    aceitou. Passo 1: resolucao, fps e codec, com taxa e GOP como lidos
    (pulado se a camera ja esta nesse formato). Passo 2: tabela completa
    (pulado se ja esta igual). Le de volta no fim; a conferencia e de quem chama.
    Devolve { Ok; Passo (passo que falhou; 0 = leitura, 3 = leitura de volta);
    Erro; Recusa (valor recusado: Tentar de novo nao adianta); Lido; Volta;
    Gravacoes }.
#>
function Set-CamEncodeEmPassos {
    param($Sessao, $Padroes, [int]$Espera = 1)

    $res = [pscustomobject]@{ Ok = $false; Passo = 0; Erro = ''; Recusa = $false; Lido = $null; Volta = $null; Gravacoes = 0 }
    $igual = { param($A, $B) (ConvertTo-Json -InputObject @($A) -Depth 30 -Compress) -eq (ConvertTo-Json -InputObject @($B) -Depth 30 -Compress) }

    $lido = Get-CamEncode -Sessao $Sessao
    if (-not $lido.Ok) { $res.Erro = 'leitura do encoder: ' + $lido.Erro; return $res }
    $res.Lido = $lido.Tabela
    Write-Log ("  lido: " + (Format-ResumoEncode (Get-ResumoEncode $lido.Tabela))) 'Gray'
    $base = $lido.Tabela

    foreach ($passo in 1, 2) {
        $res.Passo = $passo
        try { $novo = @(ConvertTo-EncodeAjustado -Tabela $base -Padroes $Padroes -SoFormato:($passo -eq 1)) }
        catch { $res.Erro = $_.Exception.Message; $res.Recusa = $true; return $res }
        $oque = Format-PassoEncoder $Padroes $passo
        if (& $igual $novo $base) {
            Write-Log ("  passo " + $passo + " pulado: a camera ja esta assim (" + $oque + ")") 'DarkGray'
            continue
        }
        $gr = Set-CamEncode -Sessao $Sessao -Tabela $novo
        $res.Gravacoes++
        if (-not $gr.Ok) {
            $res.Erro = 'camera recusou o encoder no passo ' + $passo + ' (' + $oque + '): ' + $gr.Erro
            $res.Recusa = -not $gr.SemResposta
            return $res
        }
        Write-Log ("  passo " + $passo + " gravado (" + $oque + ")") 'Gray'
        if ($Espera -gt 0) { Start-Sleep -Seconds $Espera }
        $relido = Get-CamEncode -Sessao $Sessao
        if (-not $relido.Ok) { $res.Erro = 'leitura do encoder depois do passo ' + $passo + ': ' + $relido.Erro; return $res }
        $base = $relido.Tabela
    }
    $res.Passo = 3
    $res.Volta = $base
    $res.Ok = $true
    return $res
}

# Tabela Network lida -> copia com IP fixo. DHCP desligado, DNS dos padroes.
function ConvertTo-NetworkAjustado {
    param($Tabela, [string]$Ip, [string]$Mascara, [string]$Gateway, [string]$Dns1, [string]$Dns2)

    $copia = Copy-ObjetoJson $Tabela
    $nome = Get-NomeInterfaceRede $copia
    $e = $copia.$nome
    $onde = 'Network.' + $nome
    Set-CampoObrigatorio $e 'IPAddress'      $Ip      $onde
    Set-CampoObrigatorio $e 'SubnetMask'     $Mascara $onde
    Set-CampoObrigatorio $e 'DefaultGateway' $Gateway $onde
    Set-CampoObrigatorio $e 'DhcpEnable'     $false   $onde
    Set-CampoObrigatorio $e 'DnsServers'     ([object[]]@($Dns1, $Dns2)) $onde
    return $copia
}

# Mesmo segmento: (ip AND mascara) = (gateway AND mascara), e ip <> gateway.
function Test-DestinoNaRede {
    param([string]$Ip, [string]$Mascara, [string]$Gateway)
    if (-not (Test-Ipv4Estrito $Ip) -or -not (Test-Ipv4Estrito $Gateway)) { return $false }
    try { $null = ConvertTo-PrefixoDeMascara $Mascara } catch { return $false }
    $m = [uint64](ConvertTo-Ipv4Numero $Mascara)
    $i = [uint64](ConvertTo-Ipv4Numero $Ip)
    $g = [uint64](ConvertTo-Ipv4Numero $Gateway)
    return ((($i -band $m) -eq ($g -band $m)) -and $i -ne $g)
}

# ------------------------------------------------------------------ sessao
#
# A Sessao e o conjunto montado no passo a passo ao abrir o painel e editado
# em Opcoes: placa escolhida, rede das cameras, faixa de fabrica, camera
# (e-mail, encoder) e a ultima fila. Vive em sessao.json (ProgramData); a
# ultima fica guardada e volta como sugestao na proxima abertura. A senha
# NUNCA faz parte dela (so memoria do worker). Substitui os Padroes
# (padroes.json) e a ultima fila (ultima-fila.json) das versoes ate a 1.1.1:
# Import-SessaoLegada converte uma vez.
#
# Etapa (0..7) = ate onde o passo a passo chegou: 1 senha, 2 placa, 3 rede
# das cameras, 4 faixa de fabrica, 5 camera, 6 fila, 7 resumo/concluida.
# Os nomes de campo sao os mesmos dos Padroes: Invoke-ConfiguracaoCamera e o
# relatorio continuam lendo -Padroes.

function Get-SessaoFabrica {
    return [pscustomobject]@{
        Versao           = 1
        Etapa            = 0
        Quando           = ''
        Placa            = $null   # { Nome; IfIndex; Mac; Tipo } escolhida no passo 2
        Mascara          = '255.255.255.0'
        Gateway          = ''      # da obra: o operador preenche no passo a passo
        Dns1             = '8.8.8.8'
        Dns2             = '8.8.4.4'
        # IPs que a placa recebe ao preparar: vazio = automatico
        # (.220 da faixa de fabrica; .200-.249 da rede do gateway pelo MAC).
        IpPcCameras      = ''
        IpFabrica        = '192.168.1.108'
        IpPcFabrica      = ''
        EmailRecuperacao = ''      # idem
        Encoder = [pscustomobject]@{
            Principal  = [pscustomobject]@{ Resolucao = '1920x1080'; Fps = 20; BitRate = 1596; Codec = 'H.264' }
            Secundario = [pscustomobject]@{ Resolucao = '704x480'; Fps = 12; BitRate = 512; Codec = 'H.264' }
        }
        Fila             = $null   # { Inicio; Fim; Local; Rack; Andar; Quando } da ultima fila montada
    }
}

<#
    Converte o que veio do painel (JSON) ou do disco para a forma canonica.
    Campo que nao e numero continua texto, para Test-Sessao apontar o erro.
    Campo AUSENTE (ou nulo) herda o valor de fabrica; Placa e Fila ausentes
    ficam nulas (= ainda nao escolhidas). Campo presente e vazio continua
    vazio (erro). IfIndex/Etapa viram [int] (o JSON traz int64).
#>
function ConvertTo-Sessao {
    param($Entrada)

    function Num($v) { $n = 0; if ([int]::TryParse(([string]$v).Trim(), [ref]$n)) { return $n }; return [string]$v }
    function Val($Obj, [string]$Nome, $Padrao) {
        if ($null -eq $Obj) { return $Padrao }
        if ($Obj -is [System.Collections.IDictionary]) { if ($Obj.Contains($Nome) -and $null -ne $Obj[$Nome]) { return $Obj[$Nome] }; return $Padrao }
        if ($null -ne $Obj.PSObject.Properties[$Nome] -and $null -ne $Obj.$Nome) { return $Obj.$Nome }
        return $Padrao
    }
    function Txt($Obj, [string]$Nome, $Padrao) { return ([string](Val $Obj $Nome $Padrao)).Trim() }
    function Stream($Obj, $Fab) {
        return [pscustomobject]@{
            Resolucao = (Txt $Obj 'Resolucao' $Fab.Resolucao)
            Fps       = (Num (Val $Obj 'Fps' $Fab.Fps))
            BitRate   = (Num (Val $Obj 'BitRate' $Fab.BitRate))
            Codec     = (Txt $Obj 'Codec' $Fab.Codec)
        }
    }

    $f = Get-SessaoFabrica
    $e = $Entrada
    $enc = Val $e 'Encoder' $null
    $placa = $null
    $pIn = Val $e 'Placa' $null
    if ($null -ne $pIn) {
        $ifIndex = 0; [void][int]::TryParse(([string](Val $pIn 'IfIndex' 0)).Trim(), [ref]$ifIndex)
        $placa = [pscustomobject]@{ Nome = (Txt $pIn 'Nome' ''); IfIndex = $ifIndex; Mac = (Get-MacNormalizado (Txt $pIn 'Mac' '')); Tipo = (Txt $pIn 'Tipo' 'ethernet') }
    }
    $fila = $null
    $fIn = Val $e 'Fila' $null
    if ($null -ne $fIn) {
        $fila = [pscustomobject]@{ Inicio = (Txt $fIn 'Inicio' ''); Fim = (Txt $fIn 'Fim' ''); Local = (Txt $fIn 'Local' '')
                                   Rack = (Txt $fIn 'Rack' ''); Andar = (Txt $fIn 'Andar' ''); Quando = (Txt $fIn 'Quando' '') }
    }
    $etapa = 0; [void][int]::TryParse(([string](Val $e 'Etapa' 0)).Trim(), [ref]$etapa)
    if ($etapa -lt 0) { $etapa = 0 }; if ($etapa -gt 7) { $etapa = 7 }
    return [pscustomobject]@{
        Versao           = 1
        Etapa            = $etapa
        Quando           = (Txt $e 'Quando' '')
        Placa            = $placa
        Mascara          = (Txt $e 'Mascara' $f.Mascara)
        Gateway          = (Txt $e 'Gateway' $f.Gateway)
        Dns1             = (Txt $e 'Dns1' $f.Dns1)
        Dns2             = (Txt $e 'Dns2' $f.Dns2)
        IpPcCameras      = (Txt $e 'IpPcCameras' $f.IpPcCameras)
        IpFabrica        = (Txt $e 'IpFabrica' $f.IpFabrica)
        IpPcFabrica      = (Txt $e 'IpPcFabrica' $f.IpPcFabrica)
        EmailRecuperacao = (Txt $e 'EmailRecuperacao' $f.EmailRecuperacao)
        Encoder = [pscustomobject]@{
            Principal  = (Stream (Val $enc 'Principal' $null) $f.Encoder.Principal)
            Secundario = (Stream (Val $enc 'Secundario' $null) $f.Encoder.Secundario)
        }
        Fila             = $fila
    }
}

<#
    Aplica uma entrada PARCIAL (uma secao do passo a passo ou de Opcoes) sobre
    a sessao atual: so as propriedades presentes mudam; Encoder, Placa e Fila
    sao trocadas inteiras quando vem. Etapa = a maior das duas (o passo a
    passo nunca "volta" por salvar uma secao anterior). Puro: devolve nova.
#>
function Merge-Sessao {
    param($Atual, $Entrada)
    if ($null -eq $Atual) { $Atual = Get-SessaoFabrica }
    $base = Copy-ObjetoJson (ConvertTo-Sessao $Atual)
    if ($null -eq $Entrada) { return (ConvertTo-Sessao $base) }
    $nomes = @()
    if ($Entrada -is [System.Collections.IDictionary]) { $nomes = @($Entrada.Keys) }
    else { $nomes = @($Entrada.PSObject.Properties | ForEach-Object { $_.Name }) }
    $etapaMax = [int]$base.Etapa
    foreach ($n in $nomes) {
        $v = $null
        if ($Entrada -is [System.Collections.IDictionary]) { $v = $Entrada[$n] } else { $v = $Entrada.$n }
        switch ($n) {
            'Etapa'  { $x = 0; if ([int]::TryParse(([string]$v).Trim(), [ref]$x) -and $x -gt $etapaMax) { $etapaMax = $x } }
            'Versao' { }
            'Quando' { }
            default  {
                if ($null -eq $base.PSObject.Properties[$n]) { continue }
                $base.$n = $v
            }
        }
    }
    $base.Etapa = $etapaMax
    return (ConvertTo-Sessao $base)
}

# So o que a camera recebeu, para o registro (Aplicado): sem placa, fila,
# etapa. Copia solta do objeto da sessao.
function Get-AplicadoDaSessao {
    param($Sessao)
    return Copy-ObjetoJson ([pscustomobject]@{
        Mascara = [string]$Sessao.Mascara; Gateway = [string]$Sessao.Gateway; Dns1 = [string]$Sessao.Dns1; Dns2 = [string]$Sessao.Dns2
        IpFabrica = [string]$Sessao.IpFabrica; EmailRecuperacao = [string]$Sessao.EmailRecuperacao; Encoder = $Sessao.Encoder })
}

<#
    Erros de um stream (resolucao da lista, fps, bitrate, codec).
    -Campos: nome do campo no formulario do painel para cada item, na ordem
    resolucao, fps, bitrate, codec.
#>
function Test-StreamPadroes {
    param($Stream, $Mapa, [string]$Nome, [string[]]$Campos)
    $erros = New-Object 'System.Collections.Generic.List[object]'
    $s = $Stream
    if (-not $Mapa.Contains([string]$s.Resolucao)) {
        $erros.Add([pscustomobject]@{ campo = $Campos[0]; msg = ('Resolução do ' + $Nome + ' fora da lista: ' + $s.Resolucao + ' (aceitas: ' + (@($Mapa.Keys) -join ', ') + ').') })
    }
    if (-not ($s.Fps -is [int]) -or $s.Fps -lt 1 -or $s.Fps -gt 60) {
        $erros.Add([pscustomobject]@{ campo = $Campos[1]; msg = ('Quadros por segundo do ' + $Nome + ' fora de 1 a 60: ' + $s.Fps + '.') })
    }
    if (-not ($s.BitRate -is [int]) -or $s.BitRate -lt 64 -or $s.BitRate -gt 16384) {
        $erros.Add([pscustomobject]@{ campo = $Campos[2]; msg = ('Bitrate do ' + $Nome + ' fora de 64 a 16384 kbps: ' + $s.BitRate + '.') })
    }
    if ((Get-CodecsAceitos) -notcontains [string]$s.Codec) {
        $erros.Add([pscustomobject]@{ campo = $Campos[3]; msg = ('Codec do ' + $Nome + ' fora da lista: ' + $s.Codec + ' (aceitos: ' + ((Get-CodecsAceitos) -join ', ') + ').') })
    }
    return $erros.ToArray()
}

<#
    Erros da sessao, um por item: { campo; msg }. campo = nome do campo no
    formulario do painel, para o erro aparecer embaixo dele. Lista vazia =
    sessao valida (a placa pode faltar: isso e "incompleta", nao erro; veja
    Test-SessaoCompleta). O texto vai para a tela: com acento.
#>
function Test-SessaoPorCampo {
    param($Sessao)

    $erros = New-Object 'System.Collections.Generic.List[object]'
    $p = $Sessao
    $add = { param($Campo, $Msg) $erros.Add([pscustomobject]@{ campo = $Campo; msg = $Msg }) }

    # Placa presente tem que ser uma placa de verdade (IfIndex > 0 e nome).
    if ($null -ne $p.Placa) {
        $ifx = [int](Get-PropriedadeOuVazio $p.Placa 'IfIndex' 0)
        if ($ifx -le 0 -or [string]::IsNullOrWhiteSpace([string](Get-PropriedadeOuVazio $p.Placa 'Nome' ''))) {
            & $add 'Placa' 'Escolha uma placa de rede da lista.'
        }
    }

    if (-not (Test-Ipv4Estrito $p.Mascara)) { & $add 'Mascara' ('Máscara inválida: ' + $p.Mascara + '. Use o formato 255.255.255.0.') }
    else {
        try {
            $pre = ConvertTo-PrefixoDeMascara $p.Mascara
            if ($pre -lt 8 -or $pre -gt 30) { & $add 'Mascara' ('Máscara /' + $pre + ' fora de /8 a /30.') }
        } catch { & $add 'Mascara' ('Máscara inválida: ' + $_.Exception.Message) }
    }
    foreach ($c in @(@('Gateway', 'Gateway'), @('Dns1', 'DNS 1'), @('Dns2', 'DNS 2'))) {
        if ($c[0] -eq 'Gateway' -and -not ([string]$p.Gateway).Trim()) { & $add 'Gateway' 'Informe o gateway da rede das câmeras.'; continue }
        if (-not (Test-Ipv4Estrito $p.($c[0]))) { & $add $c[0] ($c[1] + ' inválido: ' + $p.($c[0]) + '. Use quatro números de 0 a 255.') }
    }
    if (-not ([string]$p.EmailRecuperacao).Trim()) {
        & $add 'EmailRecuperacao' 'Informe o e-mail de recuperação gravado nas câmeras.'
    } elseif ([string]$p.EmailRecuperacao -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        & $add 'EmailRecuperacao' ('E-mail de recuperação inválido: ' + $p.EmailRecuperacao + '.')
    }

    # O PC fala com a camera de fabrica por <prefixo /24 do IP de fabrica>.220
    # (ou pelo IpPcFabrica da sessao) e com as instaladas pela rede do
    # gateway: as duas faixas nao podem se misturar.
    $ipf = [string]$p.IpFabrica
    $ipPcF = [string]$p.IpPcFabrica
    $ipPcC = [string]$p.IpPcCameras
    if (-not (Test-Ipv4Estrito $ipf)) { & $add 'IpFabrica' ('IP de fábrica inválido: ' + $ipf + '. Use quatro números de 0 a 255.') }
    else {
        $oct = [int]($ipf -split '\.')[3]
        if ($oct -in @(0, 255)) { & $add 'IpFabrica' ('IP de fábrica não pode terminar em .' + $oct + '.') }
        elseif ($oct -eq 220 -and [string]::IsNullOrWhiteSpace($ipPcF)) { & $add 'IpFabrica' ('IP de fábrica não pode terminar em .220 (é o IP que o PC usa nessa faixa). Ou informe outro IP do PC na faixa de fábrica.') }
        if ((Test-Ipv4Estrito $p.Gateway) -and (Test-Ipv4Estrito $p.Mascara)) {
            $m = [uint64](ConvertTo-Ipv4Numero $p.Mascara)
            $mesma = ((([uint64](ConvertTo-Ipv4Numero $ipf)) -band $m) -eq (([uint64](ConvertTo-Ipv4Numero $p.Gateway)) -band $m))
            if ($mesma -or (Get-Prefixo24 $ipf) -eq (Get-Prefixo24 $p.Gateway)) {
                & $add 'IpFabrica' ('IP de fábrica ' + $ipf + ' está dentro da rede do gateway ' + $p.Gateway + ': as duas faixas precisam ser diferentes.')
            }
        }
    }

    # IPs do PC (opcionais). Na faixa de fabrica: mesmo /24 do IP de fabrica e
    # diferente dele. Na rede das cameras: dentro da rede do gateway, sem ser
    # o gateway, a rede ou o broadcast.
    if (-not [string]::IsNullOrWhiteSpace($ipPcF)) {
        if (-not (Test-Ipv4Estrito $ipPcF)) { & $add 'IpPcFabrica' ('IP do PC na faixa de fábrica inválido: ' + $ipPcF + '. Use quatro números de 0 a 255, ou deixe vazio.') }
        elseif (Test-Ipv4Estrito $ipf) {
            $o = [int]($ipPcF -split '\.')[3]
            if ((Get-Prefixo24 $ipPcF) -ne (Get-Prefixo24 $ipf)) { & $add 'IpPcFabrica' ('IP do PC na faixa de fábrica precisa estar na faixa ' + (Get-Prefixo24 $ipf) + '.x do IP de fábrica ' + $ipf + '.') }
            elseif ($ipPcF -eq $ipf) { & $add 'IpPcFabrica' ('IP do PC na faixa de fábrica não pode ser o próprio IP de fábrica ' + $ipf + '.') }
            elseif ($o -in @(0, 255)) { & $add 'IpPcFabrica' ('IP do PC na faixa de fábrica não pode terminar em .' + $o + '.') }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ipPcC)) {
        if (-not (Test-Ipv4Estrito $ipPcC)) { & $add 'IpPcCameras' ('IP do PC na rede das câmeras inválido: ' + $ipPcC + '. Use quatro números de 0 a 255, ou deixe vazio.') }
        elseif ((Test-Ipv4Estrito $p.Gateway) -and (Test-Ipv4Estrito $p.Mascara)) {
            try {
                $null = ConvertTo-PrefixoDeMascara $p.Mascara
                $m = [uint64](ConvertTo-Ipv4Numero $p.Mascara)
                $n = [uint64](ConvertTo-Ipv4Numero $ipPcC)
                $rede = ([uint64](ConvertTo-Ipv4Numero $p.Gateway)) -band $m
                if ($ipPcC -eq $p.Gateway) { & $add 'IpPcCameras' ('IP do PC na rede das câmeras não pode ser o gateway ' + $p.Gateway + '.') }
                elseif (($n -band $m) -ne $rede) { & $add 'IpPcCameras' ('IP do PC na rede das câmeras ' + $ipPcC + ' está fora da rede do gateway ' + $p.Gateway + ' com a máscara ' + $p.Mascara + '.') }
                elseif ($n -eq $rede -or $n -eq ($rede -bor ([uint64]4294967295 -bxor $m))) { & $add 'IpPcCameras' ('IP do PC na rede das câmeras ' + $ipPcC + ' é o endereço de rede ou o broadcast.') }
            } catch { }
        }
    }

    foreach ($x in @(Test-StreamPadroes $p.Encoder.Principal (Get-MapaResolucoes) 'stream principal' @('Resolucao', 'FpsPrincipal', 'BitRate', 'CodecPrincipal'))) { $erros.Add($x) }
    foreach ($x in @(Test-StreamPadroes $p.Encoder.Secundario (Get-MapaResolucoesSecundario) 'stream secundário' @('ResolucaoSecundario', 'FpsSecundario', 'BitRateSecundario', 'CodecSecundario'))) { $erros.Add($x) }

    # Fila (opcional): IPs validos, inicio <= fim, dentro da rede do gateway.
    if ($null -ne $p.Fila) {
        $fi = [string](Get-PropriedadeOuVazio $p.Fila 'Inicio' ''); $ff = [string](Get-PropriedadeOuVazio $p.Fila 'Fim' '')
        $formato = ' Use quatro números de 0 a 255, como 10.70.20.50.'
        if (-not (Test-Ipv4Estrito $fi)) { & $add 'FilaInicio' ('Primeiro IP inválido: ' + $fi + '.' + $formato) }
        if (-not (Test-Ipv4Estrito $ff)) { & $add 'FilaFim' ('Último IP inválido: ' + $ff + '.' + $formato) }
        if ((Test-Ipv4Estrito $fi) -and (Test-Ipv4Estrito $ff)) {
            if ([uint64](ConvertTo-Ipv4Numero $fi) -gt [uint64](ConvertTo-Ipv4Numero $ff)) { & $add 'FilaInicio' ('Faixa invertida: ' + $fi + ' vem depois de ' + $ff + '. Troque o primeiro e o último IP.') }
            elseif ((Test-Ipv4Estrito $p.Gateway) -and (Test-Ipv4Estrito $p.Mascara) -and -not (Test-FilaCabeNaRede -Inicio $fi -Fim $ff -Mascara $p.Mascara -Gateway $p.Gateway)) {
                & $add 'FilaInicio' ('A faixa ' + $fi + ' a ' + $ff + ' fica fora da rede do gateway ' + $p.Gateway + ' com a máscara ' + $p.Mascara + '.')
            }
        }
    }

    return $erros.ToArray()
}

# So o texto dos erros (vazia = sessao valida).
function Test-Sessao {
    param($Sessao)
    return @(@(Test-SessaoPorCampo $Sessao) | ForEach-Object { $_.msg })
}

<#
    Erros que impedem GRAVAR uma secao: os de Test-SessaoPorCampo, menos o
    gateway e o e-mail vazios quando a secao enviada (-Enviados: nomes dos
    campos que vieram) nao os traz. A sessao de fabrica vem sem os dois e o
    passo a passo so os pede nos passos 3 e 5. Concluir e Test-SessaoCompleta
    continuam exigindo os dois.
#>
function Test-SessaoParaGravar {
    param($Sessao, [string[]]$Enviados = @())
    return @(@(Test-SessaoPorCampo $Sessao) | Where-Object {
        -not ($_.campo -in @('Gateway', 'EmailRecuperacao') -and
              -not ([string]$Sessao.($_.campo)).Trim() -and $Enviados -notcontains $_.campo) })
}

# Sessao pronta para trabalhar: placa escolhida, sem erro em campo nenhum e o
# passo a passo concluido (Etapa 7). Fila e opcional. Sem isso o painel abre
# no passo a passo.
function Test-SessaoCompleta {
    param($Sessao)
    if ($null -eq $Sessao -or $null -eq $Sessao.Placa) { return $false }
    if ([int](Get-PropriedadeOuVazio $Sessao.Placa 'IfIndex' 0) -le 0) { return $false }
    if (@(Test-SessaoPorCampo $Sessao).Count -gt 0) { return $false }
    return ([int]$Sessao.Etapa -eq 7)
}

# Campos que, trocados, obrigam a devolver e preparar a placa de novo (e
# remontar ou descartar a fila). Puro; devolve os nomes.
function Get-CamposRedeAlterados {
    param($Antes, $Depois)
    $mudou = @()
    if ($null -eq $Antes -or $null -eq $Depois) { return $mudou }
    $ifA = 0; if ($null -ne $Antes.Placa) { $ifA = [int](Get-PropriedadeOuVazio $Antes.Placa 'IfIndex' 0) }
    $ifD = 0; if ($null -ne $Depois.Placa) { $ifD = [int](Get-PropriedadeOuVazio $Depois.Placa 'IfIndex' 0) }
    if ($ifA -ne $ifD) { $mudou += 'Placa' }
    foreach ($c in @('Mascara', 'Gateway', 'IpFabrica', 'IpPcFabrica', 'IpPcCameras')) {
        if ([string]$Antes.$c -ne [string]$Depois.$c) { $mudou += $c }
    }
    return $mudou
}

# O resto que mudou (encoder, DNS, e-mail), para o log "Sessao salva": nao
# mexe na placa. Puro; textos curtos ("secundario 704x480 -> 1280x720").
function Get-MudancasSessao {
    param($Antes, $Depois)
    $mudou = @()
    if ($null -eq $Antes -or $null -eq $Depois) { return $mudou }
    foreach ($c in @('Dns1', 'Dns2')) {
        if ([string]$Antes.$c -ne [string]$Depois.$c) { $mudou += ($c + ' ' + $Antes.$c + ' -> ' + $Depois.$c) }
    }
    if ([string]$Antes.EmailRecuperacao -ne [string]$Depois.EmailRecuperacao) { $mudou += 'e-mail de recuperacao' }
    if ($null -eq $Antes.Encoder -or $null -eq $Depois.Encoder) { return $mudou }
    foreach ($st in @(@('Principal', 'principal'), @('Secundario', 'secundario'))) {
        $a = $Antes.Encoder.($st[0]); $d = $Depois.Encoder.($st[0])
        if ($null -eq $a -or $null -eq $d) { continue }
        foreach ($c in @(@('Resolucao', ''), @('Fps', ' fps'), @('BitRate', ' kbps'), @('Codec', ''))) {
            if ([string]$a.($c[0]) -ne [string]$d.($c[0])) { $mudou += ($st[1] + ' ' + $a.($c[0]) + $c[1] + ' -> ' + $d.($c[0]) + $c[1]) }
        }
    }
    return $mudou
}

# A faixa inicio-fim esta inteira dentro da rede do gateway (pela mascara)?
# Puro: a fila ainda vale depois de trocar a rede em Opcoes.
function Test-FilaCabeNaRede {
    param([string]$Inicio, [string]$Fim, [string]$Mascara, [string]$Gateway)
    if (-not (Test-Ipv4Estrito $Inicio) -or -not (Test-Ipv4Estrito $Fim)) { return $false }
    if (-not (Test-Ipv4Estrito $Mascara) -or -not (Test-Ipv4Estrito $Gateway)) { return $false }
    try { $null = ConvertTo-PrefixoDeMascara $Mascara } catch { return $false }
    $m = [uint64](ConvertTo-Ipv4Numero $Mascara)
    $rede = ([uint64](ConvertTo-Ipv4Numero $Gateway)) -band $m
    foreach ($ip in @($Inicio, $Fim)) {
        if ((([uint64](ConvertTo-Ipv4Numero $ip)) -band $m) -ne $rede) { return $false }
    }
    return $true
}

# ------------------------------------------ estado persistente (ProgramData)

function Get-PastaDados {
    $p = Join-Path $env:ProgramData 'ConfigurarCameras'
    if (-not (Test-Path -LiteralPath $p)) { $null = New-Item -ItemType Directory -Force -Path $p }
    return $p
}

<#
    Grava JSON de forma atomica: escreve num .tmp e troca com
    [IO.File]::Replace, que guarda a versao anterior em .bak. O registro e a
    UNICA copia do que foi feito (o relatorio e so saida), entao uma queda de
    energia no meio da escrita nao pode deixar o arquivo pela metade.
#>
function Save-JsonAtomico {
    param([Parameter(Mandatory)][string]$Caminho, $Objeto)

    $pasta = Split-Path -Parent $Caminho
    if (-not (Test-Path -LiteralPath $pasta)) { $null = New-Item -ItemType Directory -Force -Path $pasta }
    $json = ConvertTo-Json -InputObject $Objeto -Depth 30
    $tmp = $Caminho + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Caminho) {
        [IO.File]::Replace($tmp, $Caminho, ($Caminho + '.bak'))
    } else {
        [IO.File]::Move($tmp, $Caminho)
    }
}

<#
    Le JSON. Arquivo ausente -> $null. Corrompido -> tenta o .bak; se o .bak
    tambem falhar, ESTOURA: comecar vazio e gravar por cima apagaria a unica
    copia do registro.
#>
function Read-JsonArquivo {
    param([Parameter(Mandatory)][string]$Caminho)

    if (-not (Test-Path -LiteralPath $Caminho)) { return $null }
    foreach ($arq in @($Caminho, ($Caminho + '.bak'))) {
        if (-not (Test-Path -LiteralPath $arq)) { continue }
        try {
            $o = [IO.File]::ReadAllText($arq, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($null -ne $o) {
                if ($arq -ne $Caminho) { Write-Log ("  AVISO: " + $Caminho + " ilegivel; usando a copia " + $arq) 'Yellow' }
                return $o
            }
        } catch { }
    }
    throw ($Caminho + ' esta corrompido e o .bak tambem. Nada foi sobrescrito; recupere o arquivo antes de continuar.')
}

# Sessao gravada; NULA quando o arquivo nao existe (e isso que dispara o
# passo a passo no painel). Corrompido com .bak tambem: estoura (Read-JsonArquivo).
function Read-Sessao {
    param([Parameter(Mandatory)][string]$Caminho)
    $o = Read-JsonArquivo $Caminho
    if ($null -eq $o) { return $null }
    return (ConvertTo-Sessao $o)
}

# Grava a sessao (atomico), carimbando Quando. Devolve a sessao gravada.
function Save-Sessao {
    param([Parameter(Mandatory)][string]$Caminho, $Sessao)
    $s = ConvertTo-Sessao $Sessao
    $s.Quando = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-JsonAtomico -Caminho $Caminho -Objeto $s
    return $s
}

<#
    Primeira abertura depois da 1.1.1: converte padroes.json (+ ultima-fila.json
    como Fila) em sessao.json, uma vez, e renomeia os antigos para .migrado
    (apagar sessao.json de proposito NAO reimporta). NomePlaca dos Padroes e
    resolvido pelo nome nas placas fisicas: achou -> Etapa 7 (o painel abre
    direto no "Usar a sessao de..."); nao achou (ou vazio) -> Etapa 0, e o
    passo a passo pede a placa. Devolve a sessao (nula quando nao ha nada).
#>
function Import-SessaoLegada {
    param([Parameter(Mandatory)][string]$CaminhoSessao, [string]$CaminhoPadroes = '', [string]$CaminhoUltimaFila = '')
    if (Test-Path -LiteralPath $CaminhoSessao) { return (Read-Sessao -Caminho $CaminhoSessao) }
    if ([string]::IsNullOrWhiteSpace($CaminhoPadroes) -or -not (Test-Path -LiteralPath $CaminhoPadroes)) { return $null }
    $antigo = $null
    try { $antigo = Read-JsonArquivo $CaminhoPadroes } catch { Write-Log ("  padroes.json ilegivel; nao migrado: " + $_.Exception.Message) 'Yellow'; return $null }
    if ($null -eq $antigo) { return $null }
    $s = ConvertTo-Sessao $antigo
    $nomePlaca = ''
    if ($null -ne $antigo.PSObject.Properties['NomePlaca']) { $nomePlaca = ([string]$antigo.NomePlaca).Trim() }
    if ($nomePlaca) {
        $achada = @(Get-PlacasFisicas) | Where-Object { [string]$_.Nome -eq $nomePlaca } | Select-Object -First 1
        if ($null -ne $achada) {
            $s.Placa = [pscustomobject]@{ Nome = [string]$achada.Nome; IfIndex = [int]$achada.IfIndex; Mac = [string]$achada.Mac; Tipo = [string]$achada.Tipo }
            $s.Etapa = 7
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($CaminhoUltimaFila) -and (Test-Path -LiteralPath $CaminhoUltimaFila)) {
        try {
            $u = Read-JsonArquivo $CaminhoUltimaFila
            if ($null -ne $u -and (Test-Ipv4Estrito ([string]$u.Inicio)) -and (Test-Ipv4Estrito ([string]$u.Fim))) {
                $s.Fila = [pscustomobject]@{ Inicio = [string]$u.Inicio; Fim = [string]$u.Fim; Local = [string]$u.Local; Rack = [string]$u.Rack; Andar = [string]$u.Andar; Quando = [string]$u.Quando }
            }
        } catch { }
    }
    $s = Save-Sessao -Caminho $CaminhoSessao -Sessao $s
    foreach ($arq in @($CaminhoPadroes, $CaminhoUltimaFila)) {
        if ([string]::IsNullOrWhiteSpace($arq) -or -not (Test-Path -LiteralPath $arq)) { continue }
        try { Move-Item -LiteralPath $arq -Destination ($arq + '.migrado') -Force -ErrorAction Stop } catch { }
        Remove-Item -LiteralPath ($arq + '.bak') -Force -ErrorAction SilentlyContinue
    }
    Write-Log ("Padroes e ultima fila da versao anterior viraram a sessao (" + (Split-Path -Leaf $CaminhoSessao) + ")" +
               $(if ($null -ne $s.Placa) { '; placa ' + $s.Placa.Nome + ' reconhecida' } else { '; a placa de rede sera pedida no passo a passo' }) + '.') 'Cyan'
    return $s
}

function New-Registro { return [pscustomobject]@{ Versao = 1; Cameras = @() } }

function Read-Registro {
    param([Parameter(Mandatory)][string]$Caminho)
    $o = Read-JsonArquivo $Caminho
    if ($null -eq $o) { return (New-Registro) }
    if ($null -eq $o.Cameras) { $o | Add-Member -NotePropertyName Cameras -NotePropertyValue @() -Force }
    $o.Cameras = @($o.Cameras | Where-Object { $null -ne $_ })
    return $o
}

function Find-CameraRegistro {
    param($Registro, [string]$Mac)
    $n = Get-MacNormalizado $Mac
    if ($n -eq '') { return $null }
    return (@($Registro.Cameras) | Where-Object { (Get-MacNormalizado $_.Mac) -eq $n } | Select-Object -First 1)
}

function New-EntradaRegistro {
    param([string]$Mac, [string]$Ip)
    return [pscustomobject]@{
        Mac = (Get-MacNormalizado $Mac); Ip = $Ip
        Modelo = ''; Serial = ''; Firmware = ''
        Etapa = ''; Status = 'Em andamento'; Erro = ''; Data = ''
        Local = ''; Rack = ''; Andar = ''; Porta = ''; Canal = ''; Observacao = ''
        Aplicado = $null; Encoder = $null
    }
}

# Upsert por MAC. Mesmo MAC = mesma camera: a entrada anterior (camera que
# voltou de fabrica pelo botao fisico ou pela tela dela) e SUBSTITUIDA, sem
# historico.
function Set-CameraRegistro {
    param($Registro, $Entrada)
    $n = Get-MacNormalizado $Entrada.Mac
    if ($n -eq '') { throw 'entrada de registro sem MAC' }
    $Entrada.Mac = $n
    $outros = @(@($Registro.Cameras) | Where-Object { (Get-MacNormalizado $_.Mac) -ne $n })
    $Registro.Cameras = [object[]]($outros + @($Entrada))
}

# ------------------------------------------------------- fila e relatorio

<#
    Fila a partir de uma faixa inicio-fim. Sai 'pulada', com o motivo visivel
    no painel: IP ja presente no registro e, com -Mascara/-Gateway, IP fora da
    rede do gateway, o proprio gateway, e enderecos de rede e broadcast.
    Quem chama confere o ping de cada posicao na hora de usa-la, nao aqui: a
    fila pode esperar horas.
#>
function New-FilaDeFaixa {
    param([string]$Inicio, [string]$Fim, $Registro = $null, [int]$Maximo = 254,
          [string]$Mascara = '', [string]$Gateway = '')

    # Texto vai direto para o aviso do painel: com acento e com o que fazer.
    $formato = ' Use quatro números de 0 a 255, como 10.70.20.50.'
    if (-not (Test-Ipv4Estrito $Inicio)) { throw ('Primeiro IP inválido: ' + $Inicio + '.' + $formato) }
    if (-not (Test-Ipv4Estrito $Fim))    { throw ('Último IP inválido: ' + $Fim + '.' + $formato) }
    $a = [uint64](ConvertTo-Ipv4Numero $Inicio)
    $b = [uint64](ConvertTo-Ipv4Numero $Fim)
    if ($a -gt $b) { throw ('Faixa invertida: ' + $Inicio + ' vem depois de ' + $Fim + '. Troque o primeiro e o último IP.') }
    if (($b - $a + 1) -gt $Maximo) { throw ('A faixa tem ' + ($b - $a + 1) + ' IPs, acima do máximo de ' + $Maximo + '. Divida em faixas menores.') }

    # 'Resetada' (status que versoes ate a 1.1.1 gravavam pelo reset do
    # painel) nao ocupa IP: a camera voltou de fabrica e a posicao esta livre.
    # 'Falhou' tambem nao: a camera nao ficou instalada; se ficou no IP, o
    # ping na hora de usar a posicao pula.
    $usados = @{}
    if ($null -ne $Registro) {
        foreach ($c in @($Registro.Cameras)) { if ($c.Ip -and $c.Status -notin @('Resetada', 'Falhou')) { $usados[[string]$c.Ip] = $c } }
    }

    $comRede = ((Test-Ipv4Estrito $Mascara) -and (Test-Ipv4Estrito $Gateway))
    if ($comRede) {
        $m = [uint64](ConvertTo-Ipv4Numero $Mascara)
        $rede = ([uint64](ConvertTo-Ipv4Numero $Gateway)) -band $m
        $bcast = $rede -bor ([uint64]4294967295 -bxor $m)
    }

    $fila = New-Object 'System.Collections.Generic.List[object]'
    $pos = 1
    for ($n = $a; $n -le $b; $n++) {
        $ip = ConvertFrom-Ipv4Numero ([uint32]$n)
        $o = [pscustomobject]@{ Posicao = $pos; Ip = $ip; Estado = 'pendente'; Motivo = ''; Mac = '' }
        if ($comRede -and -not (Test-DestinoNaRede -Ip $ip -Mascara $Mascara -Gateway $Gateway)) {
            $o.Estado = 'pulada'
            if ($ip -eq $Gateway) { $o.Motivo = 'e o gateway' } else { $o.Motivo = 'fora da rede do gateway' }
        } elseif ($comRede -and ($n -eq $rede -or $n -eq $bcast)) {
            $o.Estado = 'pulada'; $o.Motivo = 'endereco de rede/broadcast'
        } elseif ($usados.ContainsKey($ip)) {
            $o.Estado = 'pulada'; $o.Motivo = 'ja no registro (' + $usados[$ip].Status + ')'
        }
        $fila.Add($o)
        $pos++
    }
    return $fila.ToArray()
}

function Format-Mac {
    param([string]$Mac)
    $n = (Get-MacNormalizado $Mac).ToLowerInvariant()
    if ($n.Length -ne 12) { return $n }
    return (($n -split '(..)' | Where-Object { $_ }) -join ':')
}

function Get-ColunasRelatorio {
    return @((Get-ColunasInventario) + @('FIRMWARE', 'SERIAL', 'RESOLUCAO', 'FPS-PRINCIPAL',
                                         'BITRATE-PRINCIPAL', 'FPS-SECUNDARIO', 'CODEC-PRINCIPAL',
                                         'RESOLUCAO-SECUNDARIO', 'BITRATE-SECUNDARIO', 'CODEC-SECUNDARIO'))
}

<#
    Soma 1 ao ULTIMO numero do texto, mantendo o resto e os zeros a esquerda:
    '15' -> '16', 'Gi1/0/15' -> 'Gi1/0/16', '09' -> '10'. Sem numero (ou
    vazio), devolve como esta. Usado pelo vigia para a porta e o canal.
#>
function Step-Rotulo {
    param([string]$Texto)
    $t = [string]$Texto
    $m = [regex]::Match($t, '\d+(?!.*\d)')
    if (-not $m.Success) { return $t }
    $n = ([Numerics.BigInteger]::Parse($m.Value) + 1).ToString().PadLeft($m.Length, '0')
    return ($t.Substring(0, $m.Index) + $n + $t.Substring($m.Index + $m.Length))
}

<#
    Relatorio CSV (';', com aspas) a partir do registro. Mesmas 17 colunas do
    inventario antigo mais as do encoder. SENHA sempre vazia. Ordenado por IP.
    Devolve o texto; quem grava poe o BOM (o Excel precisa dele para acento).
#>
function ConvertTo-RelatorioCsv {
    param($Registro)

    $linhas = foreach ($c in @($Registro.Cameras)) {
        $status = [string]$c.Status
        if ($status -eq 'Falhou') { $status = 'Falhou em ' + $c.Etapa + ': ' + $c.Erro }
        $ap = $c.Aplicado
        $en = $c.Encoder
        $o = [ordered]@{
            'TIPO' = 'CFTV'; 'MODELO' = [string]$c.Modelo; 'MAC-ADRESS' = (Format-Mac $c.Mac)
            'IP' = [string]$c.Ip; 'RACK' = [string]$c.Rack; 'PORTA SWITCH' = [string]$c.Porta
            'ANDAR' = [string]$c.Andar; 'NVR - GRAVADOR' = ''; 'CANAL' = [string]$c.Canal
            'USUARIO' = 'admin'; 'SENHA' = ''
            'MASCARA' = $(if ($ap) { [string]$ap.Mascara } else { '' })
            'GATEWAY' = $(if ($ap) { [string]$ap.Gateway } else { '' })
            'LOCAL' = [string]$c.Local; 'STATUS' = $status; 'OBSERVACAO' = [string]$c.Observacao
            'DATA-CONFIG' = [string]$c.Data; 'FIRMWARE' = [string]$c.Firmware; 'SERIAL' = [string]$c.Serial
            'RESOLUCAO' = $(if ($en) { [string]$en.Resolucao } else { '' })
            'FPS-PRINCIPAL' = $(if ($en) { [string]$en.FpsPrincipal } else { '' })
            'BITRATE-PRINCIPAL' = $(if ($en) { [string]$en.BitratePrincipal } else { '' })
            'FPS-SECUNDARIO' = $(if ($en) { [string]$en.FpsSecundario } else { '' })
            'CODEC-PRINCIPAL' = $(if ($en) { [string]$en.CodecPrincipal } else { '' })
            'RESOLUCAO-SECUNDARIO' = $(if ($en) { [string]$en.ResolucaoSecundario } else { '' })
            'BITRATE-SECUNDARIO' = $(if ($en) { [string]$en.BitrateSecundario } else { '' })
            'CODEC-SECUNDARIO' = $(if ($en) { [string]$en.CodecSecundario } else { '' })
        }
        $chave = 0
        if (Test-Ipv4Estrito $c.Ip) { $chave = [uint64](ConvertTo-Ipv4Numero $c.Ip) }
        [pscustomobject]@{ Chave = $chave; Linha = [pscustomobject]$o }
    }

    $ordenadas = @($linhas | Sort-Object Chave | ForEach-Object { $_.Linha })
    if ($ordenadas.Count -eq 0) {
        return ((Get-ColunasRelatorio | ForEach-Object { '"' + $_ + '"' }) -join ';')
    }
    return ((@($ordenadas | ConvertTo-Csv -Delimiter ';' -NoTypeInformation)) -join "`r`n")
}

# ------------------------------------------ configuracao: maquina de estados

function Get-EtapasConfiguracao { return @('inicializada', 'encoder', 'rede', 'conferida') }

# Etapa concluida -> proxima ('' = nada falta).
function Get-ProximaEtapa {
    param([string]$Concluida)
    $e = Get-EtapasConfiguracao
    if ([string]::IsNullOrWhiteSpace($Concluida)) { return $e[0] }
    $i = [array]::IndexOf($e, $Concluida)
    if ($i -lt 0) { throw ('etapa desconhecida: ' + $Concluida) }
    if ($i -ge $e.Count - 1) { return '' }
    return $e[$i + 1]
}

<#
    Decide de onde a configuracao continua, sem tocar na rede.
      Estado da camera: 'fabrica' (Init=1), 'inicializada' (Init<>1),
      'destino' (so responde no IP de destino) ou 'muda' (nao responde).
    Devolve { Acao = 'configurar' | 'recusar'; Concluida; Ip; Motivo }.
#>
function Get-PlanoRetomada {
    param($Entrada, [string]$EstadoCamera, [string]$IpOrigem, [string]$Destino)

    $o = [pscustomobject]@{ Acao = 'configurar'; Concluida = ''; Ip = $IpOrigem; Motivo = '' }

    switch ($EstadoCamera) {
        'fabrica' {
            # De fabrica recomeca do zero, com ou sem registro: se havia
            # registro, a camera foi resetada e a entrada sera substituida.
            if ($null -ne $Entrada) { $o.Motivo = 'camera voltou de fabrica (reset): registro anterior sera substituido' }
            return $o
        }
        'inicializada' {
            if ($null -ne $Entrada -and $Entrada.Status -eq 'Instalada') {
                $o.Acao = 'recusar'
                $o.Motivo = 'camera ja instalada em ' + $Entrada.Ip + ' (' + $Entrada.Data + '). A configuracao e feita uma vez so; para refazer, resete a camera.'
                return $o
            }
            $o.Concluida = 'inicializada'
            if ($null -ne $Entrada -and $Entrada.Etapa) { $o.Concluida = [string]$Entrada.Etapa }
            if ($o.Concluida -eq 'rede' -or $o.Concluida -eq 'conferida') { $o.Concluida = 'encoder' }
            $o.Motivo = 'retomando depois da etapa ' + $o.Concluida
            return $o
        }
        'destino' {
            # Sem registro nao ha como saber se quem responde no destino e esta
            # camera ou outro equipamento que ja usa o IP.
            if ($null -eq $Entrada) {
                $o.Acao = 'recusar'
                $o.Motivo = 'camera nao responde em ' + $IpOrigem + ', e ' + $Destino + ' ja e usado por outro equipamento'
                return $o
            }
            if ($Entrada.Status -eq 'Instalada') {
                $o.Acao = 'recusar'
                $o.Motivo = 'camera ja instalada em ' + $Entrada.Ip + '. A configuracao e feita uma vez so.'
                return $o
            }
            # Responde so no destino: a rede ja foi gravada, falta conferir.
            $o.Concluida = 'rede'
            $o.Ip = $Destino
            $o.Motivo = 'camera ja responde no destino ' + $Destino + ': falta a conferencia'
            return $o
        }
        default {
            $o.Acao = 'recusar'
            $o.Motivo = 'camera nao responde em ' + $IpOrigem + ' nem em ' + $Destino
            return $o
        }
    }
}

# Ping antes do getStatus: IP morto custaria o timeout inteiro do curl (25s).
function Get-EstadoCamera {
    param([string]$IpOrigem, [string]$Destino)
    if (Test-IpEmUso -Ip $IpOrigem) {
        $st = Get-CamInitStatus -Ip $IpOrigem
        if ($st.Ok) { if ($st.Init -eq 1) { return 'fabrica' } else { return 'inicializada' } }
    }
    if ($Destino -and $Destino -ne $IpOrigem -and (Test-IpEmUso -Ip $Destino)) {
        $st = Get-CamInitStatus -Ip $Destino
        if ($st.Ok -and $st.Init -ne 1) { return 'destino' }
    }
    return 'muda'
}

# LoginRecusado: a camera recusou a senha da sessao (SenhaErrada ou Bloqueada).
# Repetir sem trocar a senha gasta tentativa do lockout (~5): o painel trava
# o "Tentar de novo" ate uma senha nova. Bloqueada: a camera ja trancou o admin.
function New-ResultadoConfiguracao {
    return [pscustomobject]@{ Ok = $false; Etapa = ''; Falhou = ''; Erro = ''; Recusa = $false
                              LoginRecusado = $false; Bloqueada = $false
                              Mac = ''; Ip = ''; Entrada = $null }
}

<#
    Configura UMA camera, de onde ela estiver ate instalada.

    -Contexto: IpOrigem (onde a camera esta agora), Destino, Mac (se a
    descoberta leu), Local, Rack, Andar, Porta, Canal.
    Cada etapa concluida e gravada no registro na hora - e isso que permite
    retomar depois de qualquer falha, inclusive com o painel fechado.

    -Simular nao envia nada e usa -CaminhoRegistro separado (o servidor
    passa outro arquivo). -FalharEm forca falha numa etapa, so em simulacao.
#>
function Invoke-ConfiguracaoCamera {
    param(
        [Parameter(Mandatory)]$Contexto,
        [Parameter(Mandatory)]$Padroes,
        [string]$Senha,
        [Parameter(Mandatory)][string]$CaminhoRegistro,
        [switch]$Simular,
        [string]$FalharEm = '',
        [int]$EsperaBootSeg = 120
    )

    $res = New-ResultadoConfiguracao
    $ctx = $Contexto
    $destino = ([string]$ctx.Destino).Trim()
    $res.Ip = $destino
    $origem = ([string]$ctx.IpOrigem).Trim()
    $mac = Get-MacNormalizado $ctx.Mac
    $simTxt = ''
    if ($Simular) { $simTxt = ' [SIMULACAO]' }
    # Porta HTTP fora do padrao (do broadcast DHIP): vale na origem e, depois
    # da troca de IP, no destino - a camera leva a porta junto.
    $portaHttp = 80
    if ($null -ne $ctx.PSObject.Properties['HttpPort'] -and [int]$ctx.HttpPort -gt 0) { $portaHttp = [int]$ctx.HttpPort }
    if ($portaHttp -ne 80) {
        Set-CamPortaHttp -Ip $origem -Porta $portaHttp
        if (Test-Ipv4Estrito $destino) { Set-CamPortaHttp -Ip $destino -Porta $portaHttp }
    }
    Write-Log ""
    Write-Log ("=== camera em " + $origem + $(if ($portaHttp -ne 80) { ':' + $portaHttp } else { '' }) + " -> " + $destino + $simTxt + " ===") 'Cyan'

    # --- validacoes que nao dependem da camera ------------------------------
    if (-not (Test-Ipv4Estrito $destino)) { $res.Falhou = 'rede'; $res.Erro = 'IP de destino invalido: ' + $destino; return $res }
    if (-not (Test-DestinoNaRede -Ip $destino -Mascara $Padroes.Mascara -Gateway $Padroes.Gateway)) {
        $res.Falhou = 'rede'
        $res.Erro = $destino + ' nao esta na rede do gateway ' + $Padroes.Gateway + ' com mascara ' + $Padroes.Mascara
        return $res
    }
    if (-not $Simular -and (Test-IpLocal -Ip $destino)) {
        $res.Falhou = 'rede'; $res.Erro = $destino + ' e um endereco DESTE PC'; return $res
    }

    $reg = Read-Registro -Caminho $CaminhoRegistro
    $ent = $null
    if ($mac) { $ent = Find-CameraRegistro $reg $mac }

    # --- onde a camera esta e de onde continuar ----------------------------
    if ($Simular) {
        $estado = 'fabrica'
        if ($null -ne $ent -and $ent.Status -ne 'Instalada' -and $ent.Etapa) { $estado = 'inicializada' }
        if ($null -ne $ent -and $ent.Etapa -eq 'rede') { $estado = 'destino' }
        if ($null -ne $ent -and $ent.Status -eq 'Instalada') { $estado = 'inicializada' }
    } else {
        $estado = Get-EstadoCamera -IpOrigem $origem -Destino $destino
    }
    $plano = Get-PlanoRetomada -Entrada $ent -EstadoCamera $estado -IpOrigem $origem -Destino $destino
    if ($plano.Motivo) { Write-Log ("  " + $plano.Motivo) 'Yellow' }
    if ($plano.Acao -eq 'recusar') {
        $res.Falhou = (Get-ProximaEtapa ([string]$(if ($ent) { $ent.Etapa } else { '' })))
        if (-not $res.Falhou) { $res.Falhou = 'inicializada' }
        $res.Erro = $plano.Motivo
        return $res
    }
    if ($estado -eq 'fabrica') { $ent = $null }
    $feita = $plano.Concluida
    $ipCam = $plano.Ip

    # --- persistencia de cada etapa ----------------------------------------
    $salvar = {
        param([string]$Etapa, [string]$Status, [string]$Erro)
        if ($null -eq $ent) { return }
        $ent.Ip = $destino
        if ($Etapa) { $ent.Etapa = $Etapa }
        $ent.Status = $Status
        $ent.Erro = $Erro
        $ent.Data = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        foreach ($c in @('Local', 'Rack', 'Andar', 'Porta', 'Canal')) {
            if (-not [string]::IsNullOrWhiteSpace([string]$ctx.$c)) { $ent.$c = [string]$ctx.$c }
        }
        Set-CameraRegistro -Registro $reg -Entrada $ent
        Save-JsonAtomico -Caminho $CaminhoRegistro -Objeto $reg
    }
    $falhar = {
        param([string]$Etapa, [string]$Erro, [bool]$Recusa = $false, [bool]$Login = $false, [bool]$Bloqueada = $false)
        $res.Falhou = $Etapa; $res.Erro = $Erro; $res.Recusa = $Recusa; $res.Etapa = $feita
        $res.LoginRecusado = $Login; $res.Bloqueada = $Bloqueada
        Write-Log ("  FALHOU (" + $Etapa + "): " + $Erro) 'Red'
        & $salvar '' 'Falhou' ($Etapa + ': ' + $Erro)
    }
    $simularFalha = {
        param([string]$Etapa)
        return ($Simular -and $FalharEm -eq $Etapa)
    }

    $sessao = $null
    try {
        # --- 1. inicializacao ----------------------------------------------
        if ((Get-ProximaEtapa $feita) -eq 'inicializada') {
            Write-Progresso 'inicializada'
            if (& $simularFalha 'inicializada') { & $falhar 'inicializada' 'falha simulada'; return $res }
            if (-not (Initialize-Cam -Ip $ipCam -Senha $Senha -Email $Padroes.EmailRecuperacao -Simular:$Simular)) {
                & $falhar 'inicializada' ('inicializacao falhou em ' + $ipCam + ' (detalhes no log)')
                return $res
            }
            $feita = 'inicializada'
        }

        # --- identidade: login, MAC, modelo ---------------------------------
        if ((Get-ProximaEtapa $feita) -in @('encoder', 'rede')) {
            if ($Simular) {
                $info = [pscustomobject]@{ Ok = $true; Modelo = 'SIMULADA'; Serial = 'SIM'; Firmware = '-'; Mac = $mac }
                if (-not $info.Mac) { $info.Mac = 'AA0000' + ('{0:X6}' -f ([uint32](ConvertTo-Ipv4Numero $destino) -band 0xFFFFFF)) }
            } else {
                $sessao = New-CamSessao -Ip $ipCam -Senha $Senha
                if (-not $sessao.Ok) {
                    & $falhar (Get-ProximaEtapa $feita) ('login em ' + $ipCam + ': ' + $sessao.Erro) `
                              -Login ($sessao.SenhaErrada -or $sessao.Bloqueada) -Bloqueada $sessao.Bloqueada
                    return $res
                }
                $info = Get-CamInfoRpc -Sessao $sessao
                if (-not $info.Ok) {
                    & $falhar (Get-ProximaEtapa $feita) ('leitura da camera: ' + $info.Erro)
                    return $res
                }
            }
            $macLido = Get-MacNormalizado $info.Mac
            if ($mac -and $macLido -and $mac -ne $macLido) {
                & $falhar (Get-ProximaEtapa $feita) ('MAC lido (' + (Format-Mac $macLido) + ') nao e o da camera escolhida (' + (Format-Mac $mac) + '). Nada foi alterado.')
                return $res
            }
            if ($macLido) { $mac = $macLido }
            if (-not $mac) { & $falhar (Get-ProximaEtapa $feita) 'nao consegui ler o MAC da camera'; return $res }
            $res.Mac = $mac

            if ($null -eq $ent) {
                $ent = Find-CameraRegistro $reg $mac
                if ($null -ne $ent -and $ent.Status -eq 'Instalada' -and $estado -ne 'fabrica') {
                    $res.Falhou = 'encoder'
                    $res.Erro = 'camera ja instalada em ' + $ent.Ip + '. A configuracao e feita uma vez so.'
                    Write-Log ("  " + $res.Erro) 'Red'
                    return $res
                }
                # Camera conhecida que voltou de fabrica (botao fisico ou tela
                # dela): a entrada antiga e substituida pela nova configuracao.
                if ($null -ne $ent -and $estado -eq 'fabrica') {
                    Write-Log ("  MAC " + (Format-Mac $mac) + " ja estava no registro em " + $ent.Ip + " (" + $ent.Status + "); voltou de fabrica, a entrada sera substituida.") 'Yellow'
                }
                if ($null -eq $ent -or $estado -eq 'fabrica') { $ent = New-EntradaRegistro -Mac $mac -Ip $destino }
            }
            $ent.Modelo = [string]$info.Modelo; $ent.Serial = [string]$info.Serial; $ent.Firmware = [string]$info.Firmware
            Write-Log ("  " + $info.Modelo + "  MAC " + (Format-Mac $mac) + "  fw " + $info.Firmware) 'White'
            & $salvar $feita 'Em andamento' ''
        }

        # --- 2. encoder ------------------------------------------------------
        if ((Get-ProximaEtapa $feita) -eq 'encoder') {
            Write-Progresso 'encoder'
            Write-Log "--- ajuste de encoder ---" 'Cyan'
            if (& $simularFalha 'encoder') { & $falhar 'encoder' 'falha simulada: camera recusou o valor' $true; return $res }
            $p = $Padroes.Encoder
            $ent.Aplicado = Get-AplicadoDaSessao $Padroes
            if ($Simular) {
                $ent.Encoder = [pscustomobject]@{
                    Resolucao = [string]$p.Principal.Resolucao; FpsPrincipal = [string]$p.Principal.Fps
                    BitratePrincipal = [string]$p.Principal.BitRate; CodecPrincipal = [string]$p.Principal.Codec
                    GopPrincipal = [string](2 * [int]$p.Principal.Fps)
                    ResolucaoSecundario = [string]$p.Secundario.Resolucao; FpsSecundario = [string]$p.Secundario.Fps
                    BitrateSecundario = [string]$p.Secundario.BitRate; CodecSecundario = [string]$p.Secundario.Codec
                    GopSecundario = [string](2 * [int]$p.Secundario.Fps)
                }
                Write-Log ("  [simular] " + (Format-ResumoEncode $ent.Encoder)) 'DarkGray'
            } else {
                $gr = Set-CamEncodeEmPassos -Sessao $sessao -Padroes $Padroes
                if (-not $gr.Ok) { & $falhar 'encoder' $gr.Erro $gr.Recusa; return $res }
                $dif = @(Compare-EncodeAplicado -Tabela $gr.Volta -Padroes $Padroes)
                if ($dif.Count -gt 0) {
                    & $falhar 'encoder' ('a camera gravou outro valor: ' + ($dif -join '; ')) $true
                    return $res
                }
                $ent.Encoder = Get-ResumoEncode $gr.Volta
                Write-Log ("  conferido: " + (Format-ResumoEncode $ent.Encoder)) 'Green'
            }
            $feita = 'encoder'
            & $salvar 'encoder' 'Em andamento' ''
        }

        # --- 3. rede ---------------------------------------------------------
        if ((Get-ProximaEtapa $feita) -eq 'rede') {
            Write-Progresso 'rede'
            Write-Log "--- rede ---" 'Cyan'
            if (& $simularFalha 'rede') { & $falhar 'rede' 'falha simulada: sem resposta'; return $res }
            $ent.Aplicado = Get-AplicadoDaSessao $Padroes
            if ($destino -ne $ipCam -and -not $Simular -and (Test-IpEmUso -Ip $destino)) {
                & $falhar 'rede' ($destino + ' JA RESPONDE na rede. IP duplicado derruba os dois equipamentos.')
                return $res
            }
            Write-Log ("  " + $destino + " / " + $Padroes.Mascara + "  gw " + $Padroes.Gateway +
                       "  dns " + $Padroes.Dns1 + ", " + $Padroes.Dns2 + "  (DHCP desligado)") 'Gray'
            if (-not $Simular) {
                $lida = Get-CamRedeRpc -Sessao $sessao
                if (-not $lida.Ok) { & $falhar 'rede' ('leitura da rede: ' + $lida.Erro); return $res }
                try {
                    $nova = ConvertTo-NetworkAjustado -Tabela $lida.Tabela -Ip $destino -Mascara $Padroes.Mascara `
                                                      -Gateway $Padroes.Gateway -Dns1 $Padroes.Dns1 -Dns2 $Padroes.Dns2
                } catch { & $falhar 'rede' $_.Exception.Message $true; return $res }
                $gr = Set-CamRedeRpc -Sessao $sessao -Tabela $nova
                if ($gr.Recusado) { & $falhar 'rede' ('camera recusou a rede: ' + $gr.Erro) $true; return $res }
                if (-not $gr.Enviou) { & $falhar 'rede' ('nada foi enviado: ' + $gr.Erro); return $res }
                if ($gr.SemResposta) { Write-Log "  (sem resposta ao setConfig: esperado, a camera trocou de IP)" 'DarkGray' }
                # A sessao morreu junto com o IP antigo: nao tenta logout.
                $sessao.Ok = $false
            } else {
                Write-Log "  [simular] configManager.setConfig Network" 'DarkGray'
            }
            $feita = 'rede'
            & $salvar 'rede' 'Em andamento' ''
        }

        # --- 4. conferencia no IP definitivo ---------------------------------
        if ((Get-ProximaEtapa $feita) -eq 'conferida') {
            Write-Progresso 'conferida'
            Write-Log ("--- conferencia em " + $destino + " ---") 'Cyan'
            if (& $simularFalha 'conferida') { & $falhar 'conferida' ('falha simulada: ' + $destino + ' nao respondeu'); return $res }
            if (-not $Simular) {
                if ($null -ne $sessao) { Close-CamSessao $sessao; $sessao = $null }
                if (-not (Wait-CamOnline -Ip $destino -Segundos $EsperaBootSeg)) {
                    & $falhar 'conferida' ($destino + ' nao respondeu em ' + $EsperaBootSeg + 's. Confira mascara/gateway e o cabo.')
                    return $res
                }
                Write-Progresso -Detalhe ('Conferindo ' + $destino + ': login e leitura da rede')
                Start-Sleep -Seconds 3
                for ($i = 1; $i -le 2; $i++) {
                    $sessao = New-CamSessao -Ip $destino -Senha $Senha
                    if ($sessao.Ok -or -not $sessao.SemResposta) { break }
                    Start-Sleep -Seconds 10
                }
                if (-not $sessao.Ok) {
                    & $falhar 'conferida' ('login em ' + $destino + ': ' + $sessao.Erro) `
                              -Login ($sessao.SenhaErrada -or $sessao.Bloqueada) -Bloqueada $sessao.Bloqueada
                    return $res
                }
                $info = Get-CamInfoRpc -Sessao $sessao
                if (-not $info.Ok) { & $falhar 'conferida' ('leitura: ' + $info.Erro); return $res }
                $macLido = Get-MacNormalizado $info.Mac
                if ($macLido -and $ent.Mac -and $macLido -ne (Get-MacNormalizado $ent.Mac)) {
                    & $falhar 'conferida' ('quem responde em ' + $destino + ' e outro aparelho (MAC ' + (Format-Mac $macLido) + ')')
                    return $res
                }
                $dif = @()
                if ($info.IpAtual -ne $destino)          { $dif += ('IP ' + $info.IpAtual) }
                if ($info.Mascara -ne $Padroes.Mascara)  { $dif += ('mascara ' + $info.Mascara) }
                if ($info.Gateway -ne $Padroes.Gateway)  { $dif += ('gateway ' + $info.Gateway) }
                if ($dif.Count -gt 0) { & $falhar 'conferida' ('divergente na camera: ' + ($dif -join ', ')) $true; return $res }
                if ($null -eq $ent.Encoder) {
                    $enc = Get-CamEncode -Sessao $sessao
                    if ($enc.Ok) { $ent.Encoder = Get-ResumoEncode $enc.Tabela }
                }
                Write-Log ("  IP " + $info.IpAtual + "  mascara " + $info.Mascara + "  gateway " + $info.Gateway + "  OK") 'Green'
            } else {
                Write-Log "  [simular] login e leitura no IP novo" 'DarkGray'
            }
            $feita = 'conferida'
            & $salvar 'conferida' 'Instalada' ''
        }

        $res.Ok = $true
        $res.Etapa = $feita
        $res.Entrada = $ent
        # Retomada direto na conferencia nao passa pela leitura de identidade.
        if (-not $res.Mac -and $null -ne $ent) { $res.Mac = Get-MacNormalizado $ent.Mac }
        Write-Log ("RESULTADO: instalada em " + $destino) 'Green'
        return $res
    } finally {
        if ($null -ne $sessao) { Close-CamSessao $sessao }
    }
}
