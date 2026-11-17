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
                   Etapa, Falha, GeracaoLogin, Motivo }
                 Indice é o número da posição (0 = ainda sem posição);
                 Motivo diz por que a câmera continua em espera
      Posicoes   cópia da fila ({ Posicao, Ip, Estado, Motivo, Mac }, o
                 formato de New-FilaDeFaixa). Além dos estados da fila,
                 'reservada' = presa a uma câmera em curso (Mac preenchido)
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
    posições e avisados são clonados; os campos das câmeras são escalares,
    menos Falha, que os Steps trocam inteira e nunca alteram por dentro.
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
            Fase = 'espera'; Etapa = ''; Falha = $null; GeracaoLogin = 0; Motivo = ''
        }
    }

    if ($novas.Count -gt 0) { $novo.Cameras = @($novo.Cameras) + $novas }

    return @{ Estado = $novo; Acoes = $acoes }
}

<#
    Step-Admissao: a primeira câmera em espera (ordem de chegada) entra no
    portão quando tudo abaixo vale ao mesmo tempo:
      - portão livre (1 vaga sempre, D2);
      - Admitindo (depois de "encerrar" ninguém entra);
      - vaga: Max 0 = sem limite; senão, câmeras em 'portao' + 'conferindo'
        abaixo de Max (decisão não ocupa vaga, D6);
      - posição livre: a primeira posição 'pendente' da fila (D10).
    IpsOcupados (dado de entrada: o servidor pinga, o orquestrador não toca
    a rede) pula a posição como Invoke-Conectada faz hoje: 'pulada', motivo
    "IP já responde na rede", e tenta a seguinte. Só pula quando há câmera
    para admitir. Sem posição livre, todas as câmeras em espera ficam com o
    motivo "sem posição livre" e nada sai.
    Na entrada: Indice = número da posição, fase 'portao', Portao = MAC,
    posição 'reservada' com o MAC, e as ações 'prender' (MAC no IP de origem)
    e 'despachar' com AteEtapa 'rede', Posicao e Destino. Admite no máximo
    uma por chamada, porque o portão tem uma vaga.
#>
function Step-Admissao {
    param(
        [Parameter(Mandatory = $true)]$Estado,
        $IpsOcupados = @()
    )

    $novo = Copy-EstadoParalelo -Estado $Estado
    $acoes = @()
    $nada = @{ Estado = $novo; Acoes = $acoes }

    if ($null -ne $novo.Portao -or -not $novo.Admitindo) { return $nada }

    $cameras = @($novo.Cameras)
    if ($novo.Max -gt 0) {
        $emCurso = @($cameras | Where-Object { $_.Fase -eq 'portao' -or $_.Fase -eq 'conferindo' }).Count
        if ($emCurso -ge $novo.Max) { return $nada }
    }

    $camera = $null
    foreach ($c in $cameras) { if ($c.Fase -eq 'espera') { $camera = $c; break } }
    if ($null -eq $camera) { return $nada }

    $ocupados = @{}
    foreach ($ip in @($IpsOcupados)) { if ($null -ne $ip) { $ocupados[([string]$ip).Trim()] = $true } }

    $posicao = $null
    foreach ($p in @($novo.Posicoes)) {
        if ($p.Estado -ne 'pendente') { continue }
        if ($ocupados.ContainsKey([string]$p.Ip)) {
            $p.Estado = 'pulada'
            $p.Motivo = 'IP já responde na rede'
            continue
        }
        $posicao = $p
        break
    }

    if ($null -eq $posicao) {
        foreach ($c in $cameras) { if ($c.Fase -eq 'espera') { $c.Motivo = 'sem posição livre' } }
        return $nada
    }

    $posicao.Estado = 'reservada'
    $posicao.Mac = [string]$camera.Mac
    $camera.Indice = [int]$posicao.Posicao
    $camera.Fase = 'portao'
    $camera.Motivo = ''
    $novo.Portao = [string]$camera.Mac

    $acoes += @{ Tipo = 'prender'; Mac = [string]$camera.Mac; Ip = [string]$camera.IpOrigem }
    $acoes += @{
        Tipo = 'despachar'; Mac = [string]$camera.Mac; AteEtapa = 'rede'
        Posicao = [int]$posicao.Posicao; Destino = [string]$posicao.Ip
    }

    return @{ Estado = $novo; Acoes = $acoes }
}

<#
    Step-FimDoJob: o job de uma câmera terminou. Resultado vem no formato de
    Invoke-ConfiguracaoCamera (Ok, Etapa = última feita, Falhou, Erro,
    Recusa, LoginRecusado, Bloqueada e, da frente motor, MacTrocado e
    MacLido). Geracao é a geração da senha da sessão usada no job: o servidor
    conhece a senha, o orquestrador só guarda o número.
    O ramo sai da fase da câmera, não do resultado:
      - portão com Ok: 'soltar' e 'despachar' da conferência (AteEtapa vazio,
        mesma Posicao e Destino), fase 'conferindo', portão livre;
      - conferência com Ok: fase 'feita' e a posição 'feita' com o MAC;
      - falha: fase 'decisao' só daquele MAC (D6), com 'soltar' e portão
        livre se estava no portão. Falha guarda etapa, erro, recusa, login
        recusado, bloqueada e geração; login recusado grava a geração em
        GeracaoLogin, para o "Tentar de novo" não repetir a mesma senha.
        A posição continua reservada para o cartão de decisão;
      - MacTrocado (D7): 'soltar' se estava no portão; a câmera escolhida
        volta para espera sem posição nem falha, a posição volta a
        'pendente' e não há decisão. O MAC lido volta para espera se já é
        conhecido e está em espera (fica no lugar dele da fila). MAC lido
        desconhecido não entra: só o DHIP diz se ele é de fábrica (D8).
    Evento de MAC desconhecido ou de câmera fora de 'portao'/'conferindo'
    (job atrasado) não muda nada. Admitindo nunca muda aqui.
#>
function Step-FimDoJob {
    param(
        [Parameter(Mandatory = $true)]$Estado,
        [Parameter(Mandatory = $true)]$Mac,
        [Parameter(Mandatory = $true)]$Resultado,
        [int]$Geracao = 0
    )

    $novo = Copy-EstadoParalelo -Estado $Estado
    $acoes = @()
    $nada = @{ Estado = $novo; Acoes = $acoes }

    $chave = Get-ChaveMac $Mac
    if ($chave -eq '') { return $nada }

    $camera = $null
    foreach ($c in @($novo.Cameras)) { if ((Get-ChaveMac $c.Mac) -eq $chave) { $camera = $c; break } }
    if ($null -eq $camera) { return $nada }

    $faseAntes = [string]$camera.Fase
    if ($faseAntes -ne 'portao' -and $faseAntes -ne 'conferindo') { return $nada }

    $posicao = $null
    foreach ($p in @($novo.Posicoes)) {
        if ([int]$p.Posicao -eq [int]$camera.Indice -and (Get-ChaveMac $p.Mac) -eq $chave) { $posicao = $p; break }
    }

    $estavaNoPortao = ($faseAntes -eq 'portao')
    if ($estavaNoPortao) {
        $acoes += @{ Tipo = 'soltar'; Mac = [string]$camera.Mac }
        if ((Get-ChaveMac $novo.Portao) -eq $chave) { $novo.Portao = $null }
    }

    if ([bool]$Resultado.MacTrocado) {
        $camera.Fase = 'espera'
        $camera.Indice = 0
        $camera.Etapa = ''
        $camera.Falha = $null
        $camera.Motivo = ''
        if ($null -ne $posicao) {
            $posicao.Estado = 'pendente'
            $posicao.Mac = ''
            $posicao.Motivo = ''
        }
        $chaveLida = Get-ChaveMac $Resultado.MacLido
        foreach ($c in @($novo.Cameras)) {
            if ($chaveLida -ne '' -and $chaveLida -ne $chave -and (Get-ChaveMac $c.Mac) -eq $chaveLida -and $c.Fase -eq 'espera') {
                $c.Motivo = ''
            }
        }
        return @{ Estado = $novo; Acoes = $acoes }
    }

    $camera.Etapa = [string]$Resultado.Etapa

    if ([bool]$Resultado.Ok) {
        if ($estavaNoPortao) {
            $camera.Fase = 'conferindo'
            $destino = ''
            if ($null -ne $posicao) { $destino = [string]$posicao.Ip }
            $acoes += @{
                Tipo = 'despachar'; Mac = [string]$camera.Mac; AteEtapa = ''
                Posicao = [int]$camera.Indice; Destino = $destino
            }
        } else {
            $camera.Fase = 'feita'
            if ($null -ne $posicao) { $posicao.Estado = 'feita' }
        }
        return @{ Estado = $novo; Acoes = $acoes }
    }

    $camera.Fase = 'decisao'
    $camera.Falha = @{
        Etapa = [string]$Resultado.Falhou; Erro = [string]$Resultado.Erro; Recusa = [bool]$Resultado.Recusa
        LoginRecusado = [bool]$Resultado.LoginRecusado; Bloqueada = [bool]$Resultado.Bloqueada; Geracao = $Geracao
    }
    if ([bool]$Resultado.LoginRecusado) { $camera.GeracaoLogin = $Geracao }

    return @{ Estado = $novo; Acoes = $acoes }
}
