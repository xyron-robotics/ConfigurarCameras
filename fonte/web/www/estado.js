// Modulo profundo do painel (direcao.md, secao 7.2): do estado bruto do GET
// /api/estado, mais a sessao, as placas e o registro que o app.js carrega, ao
// modelo que as telas novas desenham (decisao N1). Funcao pura: nao busca, nao
// guarda e nao toca no DOM. As regras de placa, internet, simulacao, passo do
// passo a passo e conflito da fila com o registro moram so aqui; as telas leem o
// modelo. Cresce com o uso (decisao N2): contagens, etapa e falha chegam na frente 4.
import { PASSOS, ETAPA_DO_PASSO, SESSAO_PADRAO, FILA_MAX_ENDERECOS, OCTETO_MAX, OCTETO_MAX_FILA, RE_IP } from './constantes.js';
import { ipParaNumero, numeroParaIp } from './formato.js';

// extras (do app.js): { sessao: dados do GET /api/sessao, placas: { dados, erro, lendo },
// registro: cameras do GET /api/registro }. Sem extras, o modelo sai sem essas partes.
export function derivar(bruto, extras) {
  const e = (bruto && bruto.estado) || {};
  const sessao = e.sessao || {};
  const x = extras || {};
  const carregado = !!e.fase;
  const senhaOk = !!(e.senhaDefinida || e.simular);
  const etapa = Number(sessao.etapa) || 0;
  const passoMax = passoMaximo(senhaOk, !!sessao.completa, etapa);
  const dadosSessao = x.sessao || null;
  const valores = (dadosSessao && dadosSessao.sessao) || JSON.parse(JSON.stringify(SESSAO_PADRAO));
  const instaladas = (x.registro || []).filter((c) => c.Status === 'Instalada').map((c) => c.Ip);
  const fila = valores.Fila;
  return {
    carregado,
    simular: !!e.simular,
    // Etapa onde a simulacao forca a falha (texto do servidor); vazio fora da simulacao.
    falhaForcada: e.simular && e.falharEm ? e.falharEm : '',
    // Na simulacao a senha nao faz falta: as cameras sao de mentira.
    senhaOk,
    senhaDefinida: !!e.senhaDefinida,
    sessaoCompleta: !!sessao.completa,
    sessaoIniciada: !!sessao.iniciada,
    // Sobe a cada gravacao da sessao pelo worker: quem salvou espera por ela.
    geracao: Number(sessao.geracao) || 0,
    etapa,
    // O passo a passo fica na tela enquanto faltar senha, sessao completa ou o "comecar".
    inicio: carregado && (!senhaOk || !sessao.completa || !sessao.iniciada),
    // Passo mais adiante que a trilha deixa abrir, e onde o passo a passo abre.
    passoMax,
    passoSugerido: e.simular && !sessao.completa && etapa < 1 ? PASSOS[0] : passoMax,
    sessaoCarregada: !!dadosSessao,
    sessao: valores,
    catalogo: dadosSessao ? {
      resolucoes: dadosSessao.resolucoes || [],
      resolucoesSecundario: dadosSessao.resolucoesSecundario || [],
      codecs: dadosSessao.codecs || [],
      ...(dadosSessao.catalogo || {}),
    } : null,
    placas: derivarPlacas(x.placas),
    registroCarregado: Array.isArray(x.registro),
    instaladas,
    conflito: fila ? conflitoDaFaixa(fila.Inicio, fila.Fim, instaladas) : null,
    fase: e.fase || '',
    // Comando na fila do servidor ainda nao virou "ocupado": ja conta como ocupado.
    ocupado: !!e.ocupado || !!(bruto && bruto.comandos > 0),
    versao: (bruto && bruto.versao) || '',
    pastaAlternativa: e.pastaDadosAlternativa ? (e.pastaDados || '') : '',
    placa: derivarPlaca(e),
    internet: derivarInternet(e),
    // Fila na memoria do servidor (null sem fila): a Sessao pergunta antes de troca-la.
    fila: derivarFila(e.fila),
    // Ultimo aviso do servidor; n sobe a cada aviso novo (quem mandou o comando compara).
    aviso: { texto: e.aviso || '', n: Number(e.avisoN) || 0, origem: e.avisoOrigem || '' },
    atualizacao: derivarAtualizacao(bruto && bruto.atualizacao),
  };
}

function derivarFila(f) {
  const itens = (f && f.itens) || [];
  if (!itens.length) return null;
  return {
    total: itens.length,
    pendentes: itens.filter((i) => i.Estado === 'pendente').length,
    inicio: f.inicio || '',
    fim: f.fim || '',
  };
}

// Procura automatica de versao nova (o servidor procura uma vez por dia).
function derivarAtualizacao(a) {
  const x = a || {};
  return { estado: x.estado || 'nenhuma', versao: x.versao || '', ultimaChecagem: x.ultimaChecagem || '' };
}

// Sessao completa: o Conferir (a senha que faltar entra na linha dele). Sem
// senha, so o passo da senha. Antes disso, o passo seguinte ao ultimo salvo.
function passoMaximo(senhaOk, completa, etapa) {
  if (completa) return 'conferir';
  if (!senhaOk) return 'senha';
  const salvos = Object.keys(ETAPA_DO_PASSO).filter((p) => etapa >= ETAPA_DO_PASSO[p]);
  const ultimo = salvos.length ? PASSOS.indexOf(salvos[salvos.length - 1]) : 0;
  return PASSOS[ultimo + 1];
}

function derivarPlacas(p) {
  const d = (p && p.dados) || null;
  return {
    lista: (d && d.placas) || [],
    sugerida: (d && d.sugerida) || null,
    erro: (p && p.erro) || '',
    lendo: !!(p && p.lendo),
    carregadas: !!d,
  };
}

// Quantas posicoes da faixa ja estao no registro como instaladas e a faixa
// seguinte do mesmo tamanho (so se couber na mesma rede /24, sem o .255).
// IP invalido, faixa invertida ou grande demais: null.
export function conflitoDaFaixa(inicio, fim, instaladas) {
  if (!RE_IP.test(String(inicio || '')) || !RE_IP.test(String(fim || ''))) return null;
  const a = ipParaNumero(inicio);
  const b = ipParaNumero(fim);
  const total = b - a + 1;
  if (total < 1 || total > FILA_MAX_ENDERECOS) return null;
  const ocupados = new Set((instaladas || []).map(ipParaNumero));
  let n = 0;
  for (let ip = a; ip <= b; ip += 1) if (ocupados.has(ip)) n += 1;
  const bloco = OCTETO_MAX + 1;
  const fim2 = b + total;
  const cabe = Math.floor(fim2 / bloco) === Math.floor(a / bloco) && fim2 % bloco <= OCTETO_MAX_FILA;
  return {
    total,
    instaladas: n,
    todas: n === total,
    seguinte: cabe ? { inicio: numeroParaIp(b + 1), fim: numeroParaIp(fim2) } : null,
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
