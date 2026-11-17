<#
    Orquestrador-Cameras.ps1
    Máquina de estado pura do paralelo: decide qual câmera entra no portão,
    qual vai para a conferência e o que o operador precisa saber. Não chama
    rede, placa nem disco e não executa nada ao carregar: quem executa as
    ações é o servidor (Servidor-Painel.ps1), e os testes carregam este
    arquivo por dot-source (Testes-Orquestrador.ps1).

    CONTRATO
      Todo Step-* recebe o estado mais um evento (ou tique) e devolve
        @{ Estado = <novo estado>; Acoes = @(<ação>, ...) }
      com ação @{ Tipo = 'prender'|'soltar'|'despachar'|'publicar'|'avisar';
      Mac = ...; ... }. 'despachar' leva AteEtapa ('rede' no portão, vazio na
      conferência); 'avisar' leva Texto. O estado de entrada nunca é mutado:
      o Step devolve cópia.

    ESTADO (plano docs/plans/2026-11-17-frente-orquestrador-plan.md)
      Cameras    câmeras por MAC, na ordem do primeiro aparecimento no DHIP:
                 { Mac, Serial, Modelo, IpOrigem, HttpPort, Indice,
                   Fase: espera|portao|conferindo|decisao|feita|pulada,
                   Etapa, Falha, GeracaoLogin }
      Posicoes   cópia da fila ({ Posicao, Ip, Estado, Motivo, Mac }, o
                 formato de New-FilaDeFaixa)
      Portao     MAC da câmera presa no IP de fábrica, ou $null (1 vaga)
      Max        0 = sem limite (padrão); 1 = uma por vez (reserva sem DHIP)
      Admitindo  $false depois de "encerrar": quem está em curso termina
      Avisados   MACs que já receberam o aviso único
#>

<#
    Estado inicial do paralelo. As posições são copiadas: o chamador pode
    continuar usando a fila dele sem que o orquestrador a altere.
#>
function New-EstadoParalelo {
    param($Posicoes = @(), [int]$Max = 0)

    if ($Max -lt 0) { throw ('Máximo inválido: ' + $Max + '. Use 0 para sem limite ou um número positivo.') }

    $copia = @()
    foreach ($p in @($Posicoes)) {
        if ($null -eq $p) { continue }
        $copia += @{
            Posicao = [int]$p.Posicao; Ip = [string]$p.Ip; Estado = [string]$p.Estado
            Motivo = [string]$p.Motivo; Mac = [string]$p.Mac
        }
    }

    return @{
        Cameras   = @()
        Posicoes  = $copia
        Portao    = $null
        Max       = $Max
        Admitindo = $true
        Avisados  = @{}
    }
}

<#
    Resumo para o painel e para os testes: contagem por fase (todas as fases,
    zero incluído), total, portão e admitindo. Fase fora da lista é erro de
    programação e para aqui, em vez de sumir da contagem.
#>
function Get-Resumo {
    param([Parameter(Mandatory = $true)]$Estado)

    $fases = [ordered]@{}
    foreach ($f in @('espera', 'portao', 'conferindo', 'decisao', 'feita', 'pulada')) { $fases[$f] = 0 }

    $total = 0
    foreach ($c in @($Estado.Cameras)) {
        if ($null -eq $c) { continue }
        $f = [string]$c.Fase
        if (-not $fases.Contains($f)) { throw ('Fase desconhecida: ' + $f + ' (câmera ' + $c.Mac + ').') }
        $fases[$f] = $fases[$f] + 1
        $total++
    }

    return @{
        Fases     = $fases
        Total     = $total
        Portao    = $Estado.Portao
        Admitindo = [bool]$Estado.Admitindo
        Max       = [int]$Estado.Max
    }
}

# ------------------------------------------------------------ apoio dos Steps

# Marcas da família DHIP (Intelbras/Dahua, D11). Comparação sem caixa.
$script:MarcasDhip = @('Intelbras', 'Dahua')

<#
    Chave de comparação de MAC: só os dígitos hexadecimais, em maiúscula.
    'AA:00:00:00:00:01', 'aa-00-00-00-00-01' e 'AA0000000001' são a mesma
    câmera. Vazio quando não há MAC.
#>
function Get-ChaveMac {
    param($Mac)
    if ($null -eq $Mac) { return '' }
    return (([string]$Mac) -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
}

<#
    Init do DHIP na mesma regra do motor (Get-InitNormalizado): ausente ou
    negativo = -1 (desconhecido); senão os 2 bits baixos, e 1 = de fábrica.
    Repetido aqui para o orquestrador carregar sozinho, sem o motor.
#>
function Get-InitOrquestrador {
    param($Init)
    $n = 0
    if ($null -eq $Init -or -not [int]::TryParse([string]$Init, [ref]$n) -or $n -lt 0) { return -1 }
    return ($n -band 3)
}

<#
    Cópia do estado para o Step devolver sem mutar a entrada: câmeras,
    posições e avisados são clonados; os campos das câmeras são escalares.
#>
function Copy-EstadoParalelo {
    param([Parameter(Mandatory = $true)]$Estado)

    $cameras = @()
    foreach ($c in @($Estado.Cameras)) { if ($null -ne $c) { $cameras += $c.Clone() } }
    $posicoes = @()
    foreach ($p in @($Estado.Posicoes)) { if ($null -ne $p) { $posicoes += $p.Clone() } }
    $avisados = @{}
    if ($null -ne $Estado.Avisados) { $avisados = $Estado.Avisados.Clone() }

    return @{
        Cameras   = $cameras
        Posicoes  = $posicoes
        Portao    = $Estado.Portao
        Max       = [int]$Estado.Max
        Admitindo = [bool]$Estado.Admitindo
        Avisados  = $avisados
    }
}

# ------------------------------------------------------------------- Steps

<#
    Step-Descoberta: achados DHIP de um tique ({ Mac, Serial, Modelo, Ip,
    HttpPort, Init, Marca }) viram câmeras em espera.
      - deduplica por MAC (no mesmo tique e entre tiques; grafia do MAC não
        importa) e ignora achado sem MAC, porque o portão prende por MAC;
      - MAC já conhecido, em qualquer fase (espera, portão, conferindo,
        decisão, feita, pulada), é ignorado: a câmera não volta para a fila;
      - Marca preenchida fora da família DHIP: 'avisar' "Marca não suportada:
        não tocada.", uma vez por MAC (Avisados), e a câmera não entra.
        Marca vazia conta como família DHIP: o achado veio do broadcast DHIP;
      - Init de fábrica (1) entra em espera, na ordem de chegada, com Indice 0
        (a posição é atribuída na entrada do portão, D10);
      - Init inicializada ou desconhecido não entra em espera e não gera ação
        aqui: é o Step-JaInicializada (Task 5 do plano) que trata.
    Nunca gera 'prender' nem 'despachar': isso é da admissão.
#>
function Step-Descoberta {
    param(
        [Parameter(Mandatory = $true)]$Estado,
        $Achados = @()
    )

    $novo = Copy-EstadoParalelo -Estado $Estado
    $acoes = @()

    $conhecidos = @{}
    foreach ($c in @($novo.Cameras)) { $conhecidos[(Get-ChaveMac $c.Mac)] = $true }

    $novas = @()
    foreach ($a in @($Achados)) {
        if ($null -eq $a) { continue }
        $chave = Get-ChaveMac $a.Mac
        if ($chave -eq '') { continue }
        if ($conhecidos.ContainsKey($chave)) { continue }

        $marca = [string]$a.Marca
        if (-not [string]::IsNullOrWhiteSpace($marca) -and -not ($script:MarcasDhip -contains $marca.Trim())) {
            if (-not $novo.Avisados.ContainsKey($chave)) {
                $novo.Avisados[$chave] = 'marca'
                $acoes += @{ Tipo = 'avisar'; Mac = [string]$a.Mac; Texto = 'Marca não suportada: não tocada.' }
            }
            continue
        }

        if ((Get-InitOrquestrador $a.Init) -ne 1) { continue }

        $porta = 0
        if (-not [int]::TryParse([string]$a.HttpPort, [ref]$porta) -or $porta -le 0) { $porta = 80 }

        $conhecidos[$chave] = $true
        $novas += @{
            Mac = [string]$a.Mac; Serial = [string]$a.Serial; Modelo = [string]$a.Modelo
            IpOrigem = [string]$a.Ip; HttpPort = $porta; Indice = 0
            Fase = 'espera'; Etapa = ''; Falha = $null; GeracaoLogin = 0
        }
    }

    if ($novas.Count -gt 0) { $novo.Cameras = @($novo.Cameras) + $novas }

    return @{ Estado = $novo; Acoes = $acoes }
}
