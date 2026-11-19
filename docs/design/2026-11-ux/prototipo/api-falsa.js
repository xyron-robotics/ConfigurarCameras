// PROTOTIPO. Transporte falso que imita o Servidor-Painel.ps1 sem rede (direcao.md, secao 7.2).
// So existe no prototipo: a fase B usa o transporteFetch de api.js. Dados todos ficticios
// (IPs 192.0.2.x e 192.168.1.108, MACs AA:00:00:00:00:0x, seriais SIM-x, "Obra exemplo").
// Formato do estado conferido contra o servidor: fonte/web/Servidor-Painel.ps1 (Publicar, rotas)
// e fonte/Coordenador-Cameras.ps1 (cameras[], fila.itens, paralelo).
// Este arquivo fica fora das regras de numero solto: e dado de cenario, nao codigo do painel.

import { ipParaNumero, numeroParaIp } from './formato.js';

export const CENARIOS = [
  { id: 'primeira', rota: '#/inicio/senha' },
  { id: 'sessao-salva', rota: '#/conferir' },
  { id: 'vazio', rota: '#/painel' },
  { id: 'painel', rota: '#/painel' },
  { id: 'falha', rota: '#/painel' },
  { id: 'concluida', rota: '#/painel' },
  { id: 'dezesseis', rota: '#/painel' },
  { id: 'reserva', rota: '#/painel' },
  { id: 'perdida', rota: '#/painel' },
];

const MODELO = 'VIP 3230 B';
const ETAPAS = ['inicializada', 'encoder', 'rede', 'conferida'];

function macFicticio(n) {
  return `AA:00:00:00:00:${n.toString(16).toUpperCase().padStart(2, '0')}`;
}

function sessaoPadrao() {
  return {
    Senha: { definida: true },
    Placa: { nome: 'Ethernet 2', ifIndex: 12 },
    Rede: { mascara: '255.255.255.0', gateway: '192.0.2.1', dns: '192.0.2.1', ipPc: '192.0.2.250' },
    Fabrica: { ipFabrica: '192.168.1.108', ipPc: '192.168.1.220' },
    Camera: {
      email: 'tecnico@exemplo.example',
      principal: { resolucao: '1080p', bitrate: 4096, fps: 15, codec: 'H.265' },
      secundario: { resolucao: 'D1', bitrate: 512, fps: 15, codec: 'H.265' },
    },
    Fila: { inicio: '192.0.2.10', fim: '192.0.2.12', local: 'Obra exemplo', rack: '2', andar: '2' },
    Broadcast: false,
  };
}

const CATALOGO = {
  principal: { resolucoes: ['1080p', '720p'], bitrates: [1024, 2048, 3072, 4096, 6144, 8192], recomendado: { '1080p': 4096, '720p': 2048 } },
  secundario: { resolucoes: ['D1', 'VGA', 'CIF'], bitrates: [256, 384, 512, 768, 1024], recomendado: { D1: 512, VGA: 384, CIF: 256 } },
  codecs: ['H.265', 'H.264'],
  fps: [10, 12, 15, 20, 25, 30],
};

const PLACAS = [
  { nome: 'Ethernet 2', ifIndex: 12, tipo: 'Ethernet', cabo: true, rotaPadrao: false, sugerida: true, descricao: 'Adaptador USB 3.0 Gigabit', velocidade: '1 Gbps' },
  { nome: 'Wi-Fi', ifIndex: 7, tipo: 'Wi-Fi', cabo: true, rotaPadrao: true, sugerida: false, descricao: 'Wi-Fi interno', velocidade: '300 Mbps' },
  { nome: 'Ethernet', ifIndex: 4, tipo: 'Ethernet', cabo: false, rotaPadrao: false, sugerida: false, descricao: 'Ethernet da placa-mae', velocidade: '' },
];

function montarItens(inicio, fim) {
  const a = ipParaNumero(inicio);
  const b = ipParaNumero(fim);
  const itens = [];
  for (let n = a, p = 1; n <= b; n += 1, p += 1) itens.push({ Posicao: p, Ip: numeroParaIp(n), Estado: 'pendente', Motivo: '', Mac: '' });
  return itens;
}

function novaCamera(n, item, fase, etapa) {
  return {
    mac: macFicticio(n), serial: `SIM-${n}`, modelo: MODELO, ipOrigem: '192.168.1.108',
    indice: item ? item.Posicao - 1 : -1, posicao: item ? item.Posicao : 0, destino: item ? item.Ip : '',
    porta: '', canal: '', fase, etapa: etapa || '', progresso: null, trabalho: '', aviso: '', falha: null,
  };
}

function linhaRegistro(cam, quando) {
  return {
    Mac: cam.mac.replace(/:/g, '').toLowerCase(), Ip: cam.destino, Modelo: cam.modelo, Serial: cam.serial, Firmware: '2.800.0000000.1.R',
    Etapa: 'conferida', Status: 'Instalada', Erro: '', Data: `2026-11-19 ${quando}`, Local: 'Obra exemplo', Rack: '2', Andar: '2',
    Porta: cam.porta, Canal: cam.canal, Observacao: '', Aplicado: '', Encoder: null,
  };
}

function estadoBase() {
  return {
    senhaDefinida: true, senhaGeracao: 1, simular: true, falharEm: '', falharEmCameras: null,
    fase: 'ocioso', trabalho: '', etapa: '', progresso: null,
    fila: null, atual: -1, camera: null, falha: null, cameras: [], portao: null, paralelo: null,
    ferramenta: null, aviso: '', avisoOrigem: '', avisoN: 0, ultimo: '',
    rede: {
      ok: true, semSessao: false, faltando: [], ips: ['192.0.2.250/24', '192.168.1.220/24'], gateway: '192.0.2.1',
      placa: { nome: 'Ethernet 2', ifIndex: 12, tipo: 'Ethernet', presente: true, cabo: true },
      preparada: true, placaPreparada: true, mexida: true, temporarios: [], rotas: [],
    },
    ocupado: false, admin: true,
    internet: { agora: 'ok', antes: 'ok', quando: '14:02:10' },
    sessao: { existe: true, completa: true, iniciada: true, etapa: 6, geracao: 3, placa: { nome: 'Ethernet 2', ifIndex: 12, mac: '', tipo: 'Ethernet' }, fila: null, quando: '2026-11-19 13:58' },
    vigia: { ligado: false, porta: '', canal: '', motivo: '', broadcast: false },
    pastaDados: '', pastaDadosAlternativa: false,
  };
}

function montarCenario(id) {
  const s = estadoBase();
  const sessao = sessaoPadrao();
  let registro = [];
  let semResposta = false;
  const comFila = (inicio, fim) => {
    s.fila = { itens: montarItens(inicio, fim), local: 'Obra exemplo', rack: '2', andar: '2', inicio, fim };
    s.paralelo = { max: 4, admitindo: true, dhip: 'ok', emCurso: 0 };
    s.fase = 'fila';
    sessao.Fila = { inicio, fim, local: 'Obra exemplo', rack: '2', andar: '2' };
    s.sessao.fila = { ...sessao.Fila, quando: '2026-11-19 13:58' };
  };
  const instalar = (item, n, quando, porta, canal) => {
    const cam = novaCamera(n, item, 'feita', 'conferida');
    cam.porta = porta; cam.canal = canal;
    item.Estado = 'feita'; item.Mac = cam.mac;
    s.cameras.push(cam);
    registro.push(linhaRegistro(cam, quando));
  };
  const emCurso = (item, n, fase, etapa) => {
    const cam = novaCamera(n, item, fase, etapa);
    const i = ETAPAS.indexOf(etapa);
    cam.progresso = { atual: i + 1, total: ETAPAS.length };
    item.Estado = 'reservada'; item.Mac = cam.mac;
    s.cameras.push(cam);
    return cam;
  };
  const falhar = (cam, etapa, erro, extra) => {
    cam.fase = 'decisao'; cam.etapa = etapa;
    cam.falha = { etapa, erro, recusa: false, loginRecusado: false, bloqueada: false, geracao: 1, ...extra };
    s.fase = 'decisao';
  };

  switch (id) {
    case 'primeira':
      s.senhaDefinida = false;
      s.sessao = { existe: false, completa: false, iniciada: false, etapa: 0, geracao: 0, placa: null, fila: null, quando: '' };
      s.rede = { ok: false, semSessao: true, faltando: ['conclua o passo a passo'], ips: [], gateway: '', placa: null, preparada: false, placaPreparada: false, mexida: false, temporarios: [], rotas: [] };
      sessao.Camera.email = '';
      sessao.Fila = { inicio: '', fim: '', local: '', rack: '', andar: '' };
      sessao.Senha.definida = false;
      break;
    case 'sessao-salva':
      s.senhaDefinida = false;
      sessao.Senha.definida = false;
      sessao.Fila = { inicio: '192.0.2.10', fim: '192.0.2.12', local: 'Obra exemplo', rack: '2', andar: '2' };
      s.sessao.fila = { ...sessao.Fila, quando: '2026-11-18 17:40' };
      registro = ['10', '11', '12'].map((final, i) => linhaRegistro(novaCamera(i + 1, { Posicao: i + 1, Ip: `192.0.2.${final}` }, 'feita'), `0${i + 8}:1${i}`));
      break;
    case 'vazio':
      comFila('192.0.2.13', '192.0.2.15');
      break;
    case 'painel':
    case 'reserva':
    case 'perdida':
      comFila('192.0.2.10', '192.0.2.12');
      instalar(s.fila.itens[0], 1, '14:05', '3', '1');
      emCurso(s.fila.itens[1], 2, 'portao', 'encoder');
      emCurso(s.fila.itens[2], 3, 'conferindo', 'conferida');
      s.vigia.ligado = true; s.fase = 'configurando'; s.paralelo.emCurso = 2;
      if (id === 'reserva') s.paralelo.dhip = 'sem-resposta';
      if (id === 'perdida') semResposta = true;
      break;
    case 'falha': {
      comFila('192.0.2.10', '192.0.2.12');
      instalar(s.fila.itens[0], 1, '14:05', '3', '1');
      const c2 = emCurso(s.fila.itens[1], 2, 'portao', 'encoder');
      emCurso(s.fila.itens[2], 3, 'conferindo', 'conferida');
      falhar(c2, 'encoder', 'valor recusado pela camera: BitratePrincipal=4096', { recusa: true });
      s.vigia.ligado = true; s.paralelo.emCurso = 2;
      break;
    }
    case 'concluida':
      comFila('192.0.2.10', '192.0.2.12');
      instalar(s.fila.itens[0], 1, '14:05', '3', '1');
      instalar(s.fila.itens[1], 2, '14:07', '4', '2');
      instalar(s.fila.itens[2], 3, '14:08', '5', '3');
      s.fase = 'concluida'; s.vigia.motivo = 'fila concluida';
      s.ultimo = 'Camera instalada em 192.0.2.12 (MAC AA:00:00:00:00:03).';
      break;
    case 'dezesseis': {
      comFila('192.0.2.10', '192.0.2.25');
      for (let i = 0; i < 7; i += 1) instalar(s.fila.itens[i], i + 1, `14:${10 + i}`, String(3 + i), String(1 + i));
      emCurso(s.fila.itens[7], 8, 'portao', 'encoder');
      const c9 = emCurso(s.fila.itens[8], 9, 'portao', 'encoder');
      falhar(c9, 'encoder', 'valor recusado pela camera: BitratePrincipal=4096', { recusa: true });
      emCurso(s.fila.itens[9], 10, 'conferindo', 'conferida');
      emCurso(s.fila.itens[10], 11, 'portao', 'rede');
      s.cameras.push(novaCamera(17, null, 'espera', ''));
      s.vigia.ligado = true; s.paralelo.emCurso = 3;
      break;
    }
    default:
      break;
  }
  return { s, sessao, registro, semResposta };
}

// Transporte: (metodo, caminho, corpo) -> Promise<{ status, corpo }>, igual ao transporteFetch.
export function criarTransporteFalso(cenarioId) {
  const m = montarCenario(cenarioId);
  let tema = 'sistema';
  let encerrado = false;
  let proximoMac = 20;
  let consultas = 0;
  const log = [
    { n: 1, ts: '2026-11-19 13:58:02', msg: 'Painel aberto em simulacao.', cor: 'Gray' },
    { n: 2, ts: '2026-11-19 14:02:10', msg: 'Internet ok pela Wi-Fi.', cor: 'Gray' },
  ];

  const ok = (corpo) => ({ status: 202, corpo: corpo || { ok: true } });
  const erro = (status, texto) => ({ status, corpo: { erro: texto } });
  const escrever = (msg, cor) => log.push({ n: log.length + 1, ts: `2026-11-19 ${new Date().toTimeString().slice(0, 8)}`, msg, cor: cor || 'Gray' });

  function recalcularFase() {
    const s = m.s;
    if (!s.fila) { s.fase = 'ocioso'; return; }
    if (s.paralelo && !s.paralelo.admitindo) { s.fase = 'encerrada'; return; }
    if (s.cameras.some((c) => c.fase === 'decisao')) { s.fase = 'decisao'; return; }
    if (s.cameras.some((c) => c.fase === 'portao' || c.fase === 'conferindo')) { s.fase = 'configurando'; return; }
    if (!s.fila.itens.some((i) => i.Estado === 'pendente' || i.Estado === 'reservada')) {
      s.fase = 'concluida';
      if (s.vigia.ligado) { s.vigia.ligado = false; s.vigia.motivo = 'fila concluida'; }
      return;
    }
    s.fase = 'fila';
  }

  // Um passo do tempo: cada camera em curso avanca uma etapa; o vigia admite a proxima posicao.
  function avancar() {
    const s = m.s;
    if (!s.fila) return;
    for (const cam of s.cameras) {
      if (cam.fase === 'portao') {
        const i = ETAPAS.indexOf(cam.etapa);
        if (i + 1 >= ETAPAS.length - 1) { cam.fase = 'conferindo'; cam.etapa = 'conferida'; } else { cam.etapa = ETAPAS[i + 1]; }
        cam.progresso = { atual: ETAPAS.indexOf(cam.etapa) + 1, total: ETAPAS.length };
      } else if (cam.fase === 'conferindo') {
        cam.fase = 'feita'; cam.progresso = null;
        const item = s.fila.itens[cam.indice];
        item.Estado = 'feita';
        m.registro.push(linhaRegistro(cam, new Date().toTimeString().slice(0, 5)));
        s.ultimo = `Camera instalada em ${cam.destino} (MAC ${cam.mac}).`;
        escrever(s.ultimo, 'Green');
      }
    }
    const emCurso = s.cameras.filter((c) => c.fase === 'portao' || c.fase === 'conferindo' || c.fase === 'decisao').length;
    if (s.vigia.ligado && s.paralelo.admitindo && emCurso < s.paralelo.max) {
      const item = s.fila.itens.find((i) => i.Estado === 'pendente');
      if (item) {
        proximoMac += 1;
        const cam = novaCamera(proximoMac, item, 'portao', 'inicializada');
        cam.progresso = { atual: 1, total: ETAPAS.length };
        item.Estado = 'reservada'; item.Mac = cam.mac;
        s.cameras.push(cam);
      }
    }
    s.paralelo.emCurso = s.cameras.filter((c) => c.fase === 'portao' || c.fase === 'conferindo').length;
    recalcularFase();
  }

  const rotas = {
    'GET /api/estado': () => ok({ estado: m.s, log, cursor: log.length, comandos: 0, versao: '1.3.0', atualizacao: { estado: 'nenhuma' } }),
    'GET /api/registro': () => ok({ cameras: m.registro, simulado: true }),
    'GET /api/sessao': () => ok({ sessao: m.sessao, existe: m.s.sessao.existe, completa: m.s.sessao.completa, etapa: m.s.sessao.etapa, catalogo: CATALOGO }),
    'GET /api/placas': () => ok({ placas: PLACAS, sugerida: 12 }),
    'PUT /api/tema': (c) => { tema = c.tema; return ok({ tema }); },
    'POST /api/senha': () => { m.s.senhaDefinida = true; m.sessao.Senha.definida = true; return ok(); },
    'PUT /api/sessao': (c) => {
      for (const [secao, valores] of Object.entries(c)) {
        m.sessao[secao] = typeof valores === 'object' && valores !== null ? { ...m.sessao[secao], ...valores } : valores;
      }
      m.s.sessao.existe = true;
      return ok({ ok: true, aplicarRede: false, etapa: m.s.sessao.etapa });
    },
    'POST /api/sessao/concluir': (c) => {
      m.s.sessao = { ...m.s.sessao, existe: true, completa: true, iniciada: true, etapa: 6 };
      m.s.rede = { ...estadoBase().rede };
      if (c.montarFila) {
        const f = m.sessao.Fila;
        m.s.fila = { itens: montarItens(f.inicio, f.fim), local: f.local, rack: f.rack, andar: f.andar, inicio: f.inicio, fim: f.fim };
        m.s.paralelo = { max: 4, admitindo: true, dhip: 'ok', emCurso: 0 };
        m.s.vigia.motivo = '';
      }
      recalcularFase();
      return ok();
    },
    'POST /api/sessao/refazer': () => { m.s.sessao = { ...m.s.sessao, completa: false, etapa: 0 }; return ok(); },
    'POST /api/vigia': (c) => {
      if (c.ligado && !m.s.fila) return erro(409, 'Monte a fila antes de ligar o vigia.');
      m.s.vigia.ligado = !!c.ligado; m.s.vigia.motivo = '';
      if (c.ligado) avancar();
      return ok();
    },
    'POST /api/fila': (c) => {
      m.s.fila = { itens: montarItens(c.inicio, c.fim), local: c.local, rack: c.rack, andar: c.andar, inicio: c.inicio, fim: c.fim };
      m.s.cameras = m.s.cameras.filter((x) => x.fase === 'espera');
      m.s.paralelo = { max: 4, admitindo: true, dhip: m.s.paralelo ? m.s.paralelo.dhip : 'ok', emCurso: 0 };
      m.sessao.Fila = { ...c };
      m.s.vigia.motivo = '';
      recalcularFase();
      return ok();
    },
    'POST /api/decisao': (c) => {
      if (c.acao === 'encerrar') {
        m.s.paralelo.admitindo = false; m.s.vigia.ligado = false; m.s.vigia.motivo = 'fila encerrada';
        recalcularFase();
        return ok();
      }
      const cam = m.s.cameras.find((x) => x.mac === c.mac);
      if (!cam || cam.fase !== 'decisao') return erro(409, 'Camera nao esta em decisao.');
      if (c.acao === 'tentar') {
        cam.fase = 'portao'; cam.etapa = cam.falha.etapa; cam.falha = null;
        cam.progresso = { atual: ETAPAS.indexOf(cam.etapa) + 1, total: ETAPAS.length };
      } else if (c.acao === 'pular') {
        cam.fase = 'pulada'; cam.falha = null;
        m.s.fila.itens[cam.indice].Estado = 'pulada';
        m.s.fila.itens[cam.indice].Motivo = 'pulada pelo operador';
      }
      recalcularFase();
      return ok();
    },
    'POST /api/camera': (c) => {
      const cam = m.s.cameras.find((x) => x.mac === c.mac);
      if (cam) { cam.porta = c.porta; cam.canal = c.canal; }
      return ok();
    },
    'POST /api/rede/preparar': () => { m.s.rede.preparada = true; m.s.rede.ok = true; return ok(); },
    'POST /api/rede/restaurar': () => { m.s.rede.preparada = false; m.s.rede.ok = false; return ok(); },
    'POST /api/internet/testar': () => { m.s.internet = { agora: 'ok', antes: 'ok', quando: new Date().toTimeString().slice(0, 8) }; return ok(); },
    'POST /api/sondar': (c) => {
      m.s.ferramenta = { tipo: 'sondar', ip: c.ip, quando: new Date().toTimeString().slice(0, 8), ping: true, init: true, fabrica: false, login: true, modelo: MODELO, serial: 'SIM-1', firmware: '2.800.0000000.1.R', mac: macFicticio(1) };
      return ok();
    },
    'POST /api/verificar': () => {
      m.s.ferramenta = { tipo: 'verificar', quando: new Date().toTimeString().slice(0, 8), itens: m.registro.map((r) => ({ ip: r.Ip, mac: r.Mac, ping: true, login: true, ok: true, detalhe: '' })) };
      return ok();
    },
    'POST /api/descobrir': () => erro(409, 'Procurar cameras so funciona no uso real.'),
    'POST /api/encerrar': () => { encerrado = true; return ok({ ok: true, restaurando: true }); },
  };

  const transporte = async (metodo, caminho, corpo) => {
    // "perdida": a primeira consulta responde; as seguintes nao.
    if (caminho === '/api/estado') consultas += 1;
    if (encerrado || (m.semResposta && caminho === '/api/estado' && consultas > 1)) throw new Error('sem resposta do servidor');
    const rota = rotas[`${metodo} ${caminho}`];
    if (!rota) return erro(404, `rota desconhecida: ${metodo} ${caminho}`);
    const r = rota(corpo || {});
    return JSON.parse(JSON.stringify(r));
  };
  transporte.avancar = avancar;
  return transporte;
}
