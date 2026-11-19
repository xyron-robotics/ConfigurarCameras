// Modulo profundo do painel (direcao.md, secao 7.2): do estado bruto do servidor ao modelo que as
// telas desenham. Funcao pura: contagens, posicao da falha, etapa real, placa, vigia, reserva,
// conexao perdida e conflito da fila com o registro. Telas nao leem o estado bruto.
import { ETAPAS, TOTAL_ETAPAS, FALHAS_ATE_PERDER_CONEXAO } from './constantes.js';
import { ipParaNumero, numeroParaIp, mac as formatarMac } from './formato.js';

const EM_CURSO = ['portao', 'conferindo'];

export function derivar(bruto, extras) {
  const x = extras || {};
  const e = (bruto && bruto.estado) || {};
  const sessaoServidor = e.sessao || {};
  const sessaoValores = (x.sessao && x.sessao.sessao) || {};
  const conexao = x.conexao || { falhas: 0, ultima: null };

  const modelo = {
    conexaoPerdida: conexao.falhas >= FALHAS_ATE_PERDER_CONEXAO,
    ultimaResposta: conexao.ultima,
    simular: !!e.simular,
    senhaDefinida: !!e.senhaDefinida,
    sessaoExiste: !!sessaoServidor.existe,
    sessaoCompleta: !!sessaoServidor.completa,
    sessao: sessaoValores,
    catalogo: (x.sessao && x.sessao.catalogo) || null,
    placas: x.placas || null,
    versao: (bruto && bruto.versao) || '',
    atualizacao: (bruto && bruto.atualizacao) || { estado: 'nenhuma' },
    fase: e.fase || 'ocioso',
    ultimo: e.ultimo || '',
    log: (bruto && bruto.log) || [],
    ferramenta: e.ferramenta || null,
    placa: derivarPlaca(e),
    internet: derivarInternet(e),
    vigia: derivarVigia(e),
    fila: null,
    espera: [],
    pedeVoce: [],
    registro: x.registro || null,
    registroErro: !!x.registroErro,
    conflito: null,
  };

  const cameras = Array.isArray(e.cameras) ? e.cameras : [];
  modelo.espera = cameras.filter((c) => c.fase === 'espera' || (c.posicao === 0 && c.fase !== 'ignorada'))
    .map((c) => ({ mac: formatarMac(c.mac), serial: c.serial, modelo: c.modelo }));

  if (e.fila && Array.isArray(e.fila.itens)) modelo.fila = derivarFila(e, cameras);
  if (modelo.fila) {
    modelo.pedeVoce = modelo.fila.posicoes.filter((p) => p.estado === 'falha').map((p) => ({
      posicao: p.posicao, ip: p.ip, mac: p.camera.mac, etapa: p.falha.etapa,
      tipo: p.falha.tipo, erroCru: p.falha.erro, bloqueiaTentar: p.falha.bloqueiaTentar,
    }));
  }
  modelo.conflito = derivarConflito(sessaoValores.Fila, x.registro);
  return modelo;
}

function derivarPlaca(e) {
  const r = e.rede || {};
  const placa = r.placa || {};
  const base = { nome: placa.nome || '', ips: r.ips || [], ifIndex: placa.ifIndex, preparada: !!r.preparada };
  if (e.simular || !(e.sessao && e.sessao.completa)) return { ...base, nivel: 'neutro', motivo: 'normal' };
  if (placa.presente === false) return { ...base, nivel: 'alarme', motivo: 'ausente' };
  if (placa.cabo === false) return { ...base, nivel: 'alarme', motivo: 'sem-cabo' };
  if (!r.ok || !r.preparada) return { ...base, nivel: 'alarme', motivo: 'nao-preparada' };
  return { ...base, nivel: 'pronta', motivo: 'pronta' };
}

function derivarInternet(e) {
  const i = e.internet || {};
  return { nivel: i.agora === 'sem' ? 'alarme' : 'neutro', agora: i.agora || 'nao-testado', quando: i.quando || '' };
}

function derivarVigia(e) {
  const v = e.vigia || {};
  const p = e.paralelo || {};
  return { ligado: !!v.ligado, reserva: !!v.ligado && p.dhip === 'sem-resposta', broadcast: !!v.broadcast, motivo: v.motivo || '' };
}

function tipoFalha(f) {
  if (f.loginRecusado || f.bloqueada) return 'senha';
  if (f.recusa) return 'recusa';
  return 'outro';
}

function derivarFila(e, cameras) {
  const f = e.fila;
  const porMac = new Map(cameras.map((c) => [c.mac, c]));
  const admitindo = !e.paralelo || e.paralelo.admitindo !== false;
  let proximaMarcada = false;

  const posicoes = f.itens.map((item) => {
    const cam = item.Mac ? porMac.get(item.Mac) : cameras.find((c) => c.indice === item.Posicao - 1);
    const p = { posicao: item.Posicao, ip: item.Ip, estado: 'aguardando', fase: '', etapa: '', etapaN: 0, camera: null, falha: null, motivo: item.Motivo || '' };
    if (cam) p.camera = { mac: formatarMac(cam.mac), macBruto: cam.mac, serial: cam.serial, modelo: cam.modelo, porta: cam.porta, canal: cam.canal };
    if (item.Estado === 'feita') {
      p.estado = 'instalada';
    } else if (item.Estado === 'pulada') {
      p.estado = 'pulada';
    } else if (item.Estado === 'reservada' && cam) {
      if (cam.fase === 'decisao' && cam.falha) {
        p.estado = 'falha';
        p.falha = { etapa: cam.falha.etapa || cam.etapa, erro: cam.falha.erro || '', tipo: tipoFalha(cam.falha), bloqueiaTentar: !!(cam.falha.loginRecusado || cam.falha.bloqueada) };
      } else if (EM_CURSO.includes(cam.fase)) {
        p.estado = 'curso';
        p.fase = cam.fase;
        p.etapa = cam.etapa;
        p.etapaN = cam.progresso && cam.progresso.atual ? cam.progresso.atual : ETAPAS.indexOf(cam.etapa) + 1;
      }
    } else if (item.Estado === 'pendente' && admitindo && !proximaMarcada) {
      p.estado = 'proxima';
      proximaMarcada = true;
    }
    return p;
  });

  const contagem = { instalada: 0, falha: 0, curso: 0, proxima: 0, aguardando: 0, pulada: 0 };
  for (const p of posicoes) contagem[p.estado] += 1;

  return {
    local: f.local || '', rack: f.rack || '', andar: f.andar || '', inicio: f.inicio, fim: f.fim,
    total: posicoes.length, totalEtapas: TOTAL_ETAPAS, posicoes, contagem,
    concluida: e.fase === 'concluida',
    encerrada: e.fase === 'encerrada' || !admitindo,
    semCamera: contagem.aguardando + contagem.proxima,
  };
}

function derivarConflito(filaSessao, registro) {
  if (!filaSessao || !filaSessao.inicio || !filaSessao.fim || !Array.isArray(registro)) return null;
  const a = ipParaNumero(filaSessao.inicio);
  const b = ipParaNumero(filaSessao.fim);
  if (a === null || b === null || b < a) return null;
  const instaladosIp = new Set(registro.filter((r) => r.Status === 'Instalada').map((r) => r.Ip));
  let instaladas = 0;
  for (let n = a; n <= b; n += 1) if (instaladosIp.has(numeroParaIp(n))) instaladas += 1;
  const total = b - a + 1;
  if (instaladas === 0) return { instaladas, total, todas: false, seguinte: null };
  return { instaladas, total, todas: instaladas === total, seguinte: { inicio: numeroParaIp(b + 1), fim: numeroParaIp(b + total) } };
}
