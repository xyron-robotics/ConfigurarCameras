// Modulo profundo do painel (direcao.md, secao 7.2): do estado bruto do GET
// /api/estado ao modelo que as telas novas desenham (decisao N1). Funcao pura:
// nao busca, nao guarda e nao toca no DOM. As regras de placa, internet,
// simulacao e "falta o passo a passo" moram so aqui; as telas leem o modelo.
// Cresce com o uso (decisao N2): contagens, etapa e falha chegam na frente 4.

export function derivar(bruto) {
  const e = (bruto && bruto.estado) || {};
  const sessao = e.sessao || {};
  const carregado = !!e.fase;
  return {
    carregado,
    simular: !!e.simular,
    // Etapa onde a simulacao forca a falha (texto do servidor); vazio fora da simulacao.
    falhaForcada: e.simular && e.falharEm ? e.falharEm : '',
    // Na simulacao a senha nao faz falta: as cameras sao de mentira.
    senhaOk: !!(e.senhaDefinida || e.simular),
    sessaoCompleta: !!sessao.completa,
    sessaoIniciada: !!sessao.iniciada,
    // O passo a passo fica na tela enquanto faltar senha, sessao completa ou o "comecar".
    inicio: carregado && (!(e.senhaDefinida || e.simular) || !sessao.completa || !sessao.iniciada),
    fase: e.fase || '',
    // Comando na fila do servidor ainda nao virou "ocupado": ja conta como ocupado.
    ocupado: !!e.ocupado || !!(bruto && bruto.comandos > 0),
    versao: (bruto && bruto.versao) || '',
    pastaAlternativa: e.pastaDadosAlternativa ? (e.pastaDados || '') : '',
    placa: derivarPlaca(e),
    internet: derivarInternet(e),
  };
}

// Chip da placa (direcao 5.9): neutro na simulacao e sem sessao concluida;
// alarme so quando pede acao (sem as faixas, ausente, sem cabo); pronta so
// preparada pelo painel e com as faixas.
function derivarPlaca(e) {
  const r = e.rede || {};
  const placa = r.placa || {};
  const sessao = e.sessao || {};
  const base = {
    nome: placa.nome || '',
    ifIndex: placa.ifIndex || '',
    ips: r.ips || [],
    faltando: r.faltando || [],
    temporarios: (r.temporarios || []).map((x) => ({ ip: x.ip, camera: x.camera || '' })),
    rotas: (r.rotas || []).map((x) => x.destino),
    preparada: !!r.preparada,
    // Preparar so faz sentido fora da simulacao, com sessao e sem as faixas.
    podePreparar: !e.simular && !r.semSessao && !r.ok,
    podeRestaurar: !e.simular && !r.semSessao,
  };
  if (e.simular) return { ...base, nivel: 'neutro', motivo: 'simulacao' };
  if (r.semSessao || !sessao.completa || !sessao.iniciada) return { ...base, nivel: 'neutro', motivo: 'sem-sessao' };
  if (placa.presente === false) return { ...base, nivel: 'alarme', motivo: 'ausente' };
  if (placa.cabo === false) return { ...base, nivel: 'alarme', motivo: 'sem-cabo' };
  if (!r.ok) return { ...base, nivel: 'alarme', motivo: 'nao-preparada' };
  if (r.preparada) return { ...base, nivel: 'pronta', motivo: 'pronta' };
  return { ...base, nivel: 'neutro', motivo: 'com-faixas' };
}

// Chip da internet: alarme so quando caiu depois de o painel preparar a placa
// (culpa do painel, pede Restaurar o DHCP); "ja estava sem" e so informacao.
function derivarInternet(e) {
  const i = e.internet || {};
  const r = e.rede || {};
  const agora = i.agora || 'nao-testado';
  let motivo = agora === 'ok' ? 'ok' : 'nao-testado';
  if (agora === 'sem') {
    if (i.antes === 'ok' && r.preparada) motivo = 'caiu';
    else motivo = i.antes === 'sem' ? 'ja-sem' : 'sem';
  }
  return { nivel: motivo === 'caiu' ? 'alarme' : 'neutro', semResposta: agora === 'sem', motivo, quando: i.quando || '' };
}
