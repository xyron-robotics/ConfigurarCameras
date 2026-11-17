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
