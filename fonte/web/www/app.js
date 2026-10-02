// Painel ConfigurarCameras. JS puro, sem dependencia.
// O servidor e a fonte de verdade: a pagina busca o estado por polling e so
// desenha. Texto vindo da camera ou do log entra sempre por textContent.
//
// Dois modos: o PASSO A PASSO (#inicio/N), enquanto a sessao nao esta
// completa e iniciada, e o modo normal (Painel, Ferramentas, Opcoes). Os
// formularios das 6 secoes (senha, placa, rede, fabrica, camera, fila) sao
// um exemplar so: vivem em Opcoes e sao movidos para o passo correspondente
// enquanto o passo a passo esta na tela.
'use strict';

const $ = (id) => document.getElementById(id);
const ETAPAS = ['inicializada', 'encoder', 'rede', 'conferida'];
const NOME_ETAPA = { inicializada: 'inicialização', encoder: 'encoder', rede: 'rede', conferida: 'conferência' };
// Secao de cada passo (o 7 e o resumo).
const SECOES_ORDEM = ['senha', 'placa', 'rede', 'fabrica', 'camera', 'fila'];
const NOME_SECAO = { senha: 'Senha', placa: 'Placa de rede', rede: 'Rede das câmeras', fabrica: 'Faixa de fábrica', camera: 'Câmera', fila: 'Fila' };

let cursorLog = 0;
let estado = null;
let ultimaFase = '';
let ipFabrica = '';
let vigiaLigadoAntes = false;
let filaDoVigia = '';
// Leitor de tela: so as transicoes (instalada, falhou, escolher, fim).
let ultimoVisto = null;
let focarTentar = false;
// Motivos que o servidor publica ao desligar o vigia sozinho.
const MOTIVO_VIGIA = {
  'fila concluida': 'fila concluída', 'fila encerrada': 'fila encerrada', 'fila nova': 'fila nova', 'sem fila': 'sem fila',
  'senha da sessao apagada': 'senha da sessão apagada', 'escolha cancelada': 'escolha cancelada', 'erro interno': 'erro interno (veja o log)',
  '5 tentativas sem configurar': '5 tentativas seguidas sem configurar; resolva o aviso e ligue de novo',
  'rede da sessao alterada': 'a rede da sessão mudou', 'sessao incompleta': 'sessão incompleta', 'passo a passo reaberto': 'passo a passo reaberto',
};
// Valores prontos do encoder (GET /api/sessao): fps, degraus de bitrate,
// faixa por resolucao e o que a camera de referencia aceitou ou recusou.
let catalogo = null;
const STREAMS = {
  principal: { nome: 'principal', res: 'Resolucao', fps: 'FpsPrincipal', br: 'BitRate', codec: 'CodecPrincipal', faixa: 'faixa-principal' },
  secundario: { nome: 'secundário', res: 'ResolucaoSecundario', fps: 'FpsSecundario', br: 'BitRateSecundario', codec: 'CodecSecundario', faixa: 'faixa-secundario' },
};
const ESTADO_NA_FITA = { feita: 'instalada', falhou: 'falhou', pulada: 'pulada' };

function h(tag, props, ...filhos) {
  const el = document.createElement(tag);
  if (props) {
    for (const [k, v] of Object.entries(props)) {
      if (v === undefined || v === null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    }
  }
  for (const f of filhos.flat()) {
    if (f === null || f === undefined || f === false) continue;
    el.append(f instanceof Node ? f : document.createTextNode(String(f)));
  }
  return el;
}

async function api(metodo, caminho, corpo) {
  const opcoes = { method: metodo, headers: {} };
  if (corpo !== undefined) {
    opcoes.headers['Content-Type'] = 'application/json';
    opcoes.body = JSON.stringify(corpo);
  }
  const r = await fetch(caminho, opcoes);
  let dados = {};
  try { dados = await r.json(); } catch (_) { /* resposta sem corpo */ }
  if (!r.ok) {
    const erro = new Error(dados.erro || ('HTTP ' + r.status));
    erro.dados = dados;
    erro.status = r.status;
    throw erro;
  }
  return dados;
}

// Espera o estado publicado satisfazer a condicao (ate -ms); devolve true se deu.
async function esperarEstado(cond, ms) {
  const fim = Date.now() + (ms || 6000);
  while (Date.now() < fim) {
    await buscarEstado();
    if (estado && cond(estado)) return true;
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

// ------------------------------------------------------------------ avisos
// O aviso aparece junto do formulario que o causou (data-aviso-de); se ele
// nao estiver na tela, na faixa do topo.
const ORIGEM_DA_ROTA = {
  '/api/fila': 'fila', '/api/fila/conectada': 'conectada', '/api/escolher': 'conectada', '/api/escolher/cancelar': 'conectada',
  '/api/decisao': 'conectada', '/api/vigia': 'vigia', '/api/sondar': 'sondar', '/api/descobrir': 'descobrir',
  '/api/verificar': 'verificar', '/api/rede/restaurar': 'painel', '/api/sessao/refazer': 'painel',
};
const ORIGEM_DO_COMANDO = {
  fila: 'fila', conectada: 'conectada', escolher: 'conectada', 'cancelar-escolha': 'conectada', decisao: 'conectada',
  vigia: 'vigia', sondar: 'sondar', descobrir: 'descobrir', verificar: 'verificar',
  'rede-restaurar': 'painel', 'sessao-refazer': 'painel', 'sessao-concluir': 'concluir',
};
// Rotas que o servidor aceita mesmo ocupado: nao travam os botoes.
const ROTA_SEMPRE = ['/api/senha', '/api/vigia'];
let avisoN = -1;
let avisoDoServidor = false;
let timerAviso = 0;

function naTela(el) {
  for (let n = el; n; n = n.parentElement) if (n.hidden) return false;
  return true;
}

function mostrarAviso(texto, origem, opcoes) {
  const o = opcoes || {};
  clearTimeout(timerAviso);
  avisoDoServidor = !!(texto && o.servidor);
  for (const a of [$('aviso'), ...document.querySelectorAll('[data-aviso-de]')]) { a.hidden = true; a.textContent = ''; }
  if (!texto) return;
  const slot = origem ? document.querySelector('[data-aviso-de="' + origem + '"]') : null;
  const a = slot && naTela(slot) ? slot : $('aviso');
  a.textContent = texto;
  a.classList.toggle('neutro', !!o.neutro);
  a.hidden = false;
  if (o.neutro) timerAviso = setTimeout(() => { a.hidden = true; }, 4000);
}

async function comando(caminho, corpo) {
  const origem = ORIGEM_DA_ROTA[caminho];
  // Trava otimista: o estado "ocupado" so chega no proximo polling.
  if (!ROTA_SEMPRE.includes(caminho)) aplicarOcupado(true);
  try {
    await api('POST', caminho, corpo || {});
    mostrarAviso('');
  } catch (e) {
    if (e.status === 409) mostrarAviso(e.message, origem, { neutro: true });
    else mostrarAviso(e.message, origem);
  }
  setTimeout(buscarEstado, 150);
}

// Botoes de trabalho ficam desligados enquanto o worker trabalha. Encerrar o
// painel e o vigia (desligar vale no meio de uma camera) ficam sempre ativos.
function aplicarOcupado(ocupado) {
  const simular = !!(estado && estado.simular);
  const sel = '#view-ferramentas .btn, #btn-preparar, #btn-restaurar, #btn-refazer, #form-conectada .btn, ' +
              '[data-decisao], #escolha-lista .btn, #btn-escolha-cancelar, #btn-avancar, #btn-comecar, #btn-montar-depois, ' +
              '#btn-usar-sessao, #btn-revisar-sessao, .secao-form .btn[type="submit"]';
  for (const b of document.querySelectorAll(sel)) {
    b.disabled = ocupado || (simular && b.hasAttribute('data-so-real'));
  }
}

// ------------------------------------------------------------------ navegacao
// Hash: #inicio/N (passo a passo), #painel, #ferramentas, #opcoes[/secao].
// Os antigos #fila e #registro caem no painel; #padroes em opcoes.
const VIEWS = ['painel', 'ferramentas', 'opcoes'];
let modoAtual = '';
let passoAtual = 0;
let sugeridoAntes = 0;
// Sessao completa ao abrir: "Usar" (vai ao resumo) ou "Revisar" (passo 2).
let escolhaSessao = '';
let trocarSenhaAberta = false;

function rota() {
  const partes = (location.hash || '').slice(1).split('/');
  const mapa = { fila: 'painel', registro: 'painel', padroes: 'opcoes', '': 'painel' };
  const v = mapa[partes[0]] !== undefined ? mapa[partes[0]] : partes[0];
  return { view: v, sub: partes[1] || '' };
}

function senhaOk() { return !!(estado && (estado.senhaDefinida || estado.simular)); }

// O passo a passo fica na tela enquanto faltar senha, sessao completa ou o
// "comecar" (iniciada).
function precisaInicio() {
  if (!estado || !estado.fase) return false;
  const s = estado.sessao || {};
  return !senhaOk() || !s.completa || !s.iniciada;
}

// Ate onde o passo a passo deixa ir: a primeira coisa que falta.
function passoSugerido() {
  const s = (estado && estado.sessao) || {};
  if (!senhaOk()) return 1;
  if (s.completa && !escolhaSessao) return 1;
  if (escolhaSessao === 'usar') return 7;
  if (!s.placa) return 2;
  return Math.min(7, Math.max(2, (s.etapa || 0) + 1));
}

function irPara(n) {
  location.hash = '#inicio/' + n;
}

function trocarView() {
  if (!estado || !estado.fase) return;
  const inicio = precisaInicio();
  document.body.classList.toggle('no-inicio', inicio);
  let r = rota();
  if (inicio) {
    const sug = passoSugerido();
    let n = parseInt(r.sub, 10);
    if (r.view !== 'inicio' || !(n >= 1)) n = sug;
    n = Math.min(Math.max(1, n), sug);
    if (r.view !== 'inicio' || String(n) !== r.sub) history.replaceState(null, '', '#inicio/' + n);
    for (const s of document.querySelectorAll('.view')) s.hidden = s.id !== 'inicio';
    montarPasso(n);
    $('log-bloco').open = false;
    return;
  }
  if (!VIEWS.includes(r.view)) { history.replaceState(null, '', '#painel'); r = { view: 'painel', sub: '' }; }
  montarOpcoes();
  for (const s of document.querySelectorAll('.view')) s.hidden = s.id !== 'view-' + r.view;
  for (const a of document.querySelectorAll('.menu a')) a.classList.toggle('ativo', a.dataset.view === r.view);
  // O log so interessa no painel; nas outras abas ele empurra o conteudo.
  $('log-bloco').open = r.view === 'painel';
  if (r.view === 'painel') carregarRegistro();
  if (r.view === 'opcoes') {
    carregarSessao();
    carregarPlacas();
    if (r.sub) {
      const sec = document.querySelector('#view-opcoes .secao[data-secao="' + r.sub + '"]');
      if (sec) { sec.scrollIntoView({ block: 'start' }); const c = sec.querySelector('input, select, button'); if (c) c.focus({ preventScroll: true }); }
    }
  }
}

// Modo ou passo sugerido mudaram entre dois pollings (senha informada,
// secao salva, "comecar", "refazer"): a tela acompanha.
function desenharModo() {
  const modo = precisaInicio() ? 'inicio' : 'normal';
  const sug = modo === 'inicio' ? passoSugerido() : 0;
  if (modo !== modoAtual || sug !== sugeridoAntes) {
    if (modo === 'inicio' && modoAtual === 'normal') { escolhaSessao = ''; }
    modoAtual = modo; sugeridoAntes = sug;
    trocarView();
  }
}

// Formulario de uma secao: um so exemplar, movido entre o passo e Opcoes.
function slotDe(secao, noInicio) {
  return noInicio
    ? document.querySelector('#inicio .passo[data-passo="' + (SECOES_ORDEM.indexOf(secao) + 1) + '"] .slot')
    : document.querySelector('#view-opcoes .secao[data-secao="' + secao + '"] .slot');
}

function montarPasso(n) {
  passoAtual = n;
  const sug = passoSugerido();
  for (const p of document.querySelectorAll('#inicio .passo')) p.hidden = Number(p.dataset.passo) !== n;
  for (const li of document.querySelectorAll('#passos li')) {
    const k = Number(li.dataset.passo);
    li.className = k < n ? 'feito' : (k === n ? 'agora' : '');
    li.querySelector('button').disabled = k > sug;
    if (k === n) li.setAttribute('aria-current', 'step'); else li.removeAttribute('aria-current');
  }
  SECOES_ORDEM.forEach((secao, i) => {
    const form = $('form-' + secao);
    const alvo = slotDe(secao, i + 1 === n);
    if (form.parentElement !== alvo) alvo.append(form);
  });
  $('passo-n').textContent = 'Passo ' + n + ' de 7';
  $('btn-voltar').hidden = n === 1;
  $('btn-montar-depois').hidden = n !== 6;
  $('btn-comecar').hidden = n !== 7;
  $('btn-avancar').hidden = n === 7;
  $('btn-avancar').textContent = n === 1 ? 'Usar esta senha e avançar' : (n === 6 ? 'Montar a fila e avançar' : 'Avançar');

  if (n === 1) {
    const s = estado.sessao || {};
    const temEscolha = senhaOk() && s.completa && !escolhaSessao;
    $('passo-escolha').hidden = !temEscolha;
    if (temEscolha) $('escolha-texto').textContent = textoDaEscolha(s);
    $('senha-definida').hidden = !senhaOk();
    $('form-senha').hidden = senhaOk() && !trocarSenhaAberta;
    $('btn-avancar').hidden = senhaOk() && !trocarSenhaAberta;
  }
  if (n === 2) carregarPlacas();
  if (n >= 2 && n <= 6) carregarSessao();
  if (n === 7) { carregarSessao(); desenharResumo(); }
  const foco = document.querySelector('#inicio .passo:not([hidden]) input:not([type="hidden"]):not([disabled]), #inicio .passo:not([hidden]) select');
  if (foco && !temFocoEmCampo()) foco.focus({ preventScroll: true });
}

function temFocoEmCampo() {
  const a = document.activeElement;
  return a && (a.tagName === 'INPUT' || a.tagName === 'SELECT' || a.tagName === 'TEXTAREA');
}

function montarOpcoes() {
  passoAtual = 0;
  for (const secao of SECOES_ORDEM) {
    const form = $('form-' + secao);
    const alvo = slotDe(secao, false);
    if (form.parentElement !== alvo) alvo.append(form);
  }
  $('form-senha').hidden = false;
}

function dataCurta(q) {
  const t = String(q || '');
  return t.length >= 16 ? t.slice(8, 10) + '/' + t.slice(5, 7) + ' ' + t.slice(11, 16) : t;
}

function textoDaEscolha(s) {
  const partes = ['Última sessão de ' + dataCurta(s.quando) + ':'];
  if (s.placa) partes.push('placa ' + s.placa.nome + ';');
  if (sessaoCache) partes.push('rede ' + sessaoCache.Gateway + ' / ' + sessaoCache.Mascara + '; fábrica ' + sessaoCache.IpFabrica + ';');
  if (s.fila) partes.push('fila ' + s.fila.inicio + ' a ' + s.fila.fim + (s.fila.local ? ' (' + s.fila.local + ')' : '') + '.');
  else partes.push('sem fila guardada.');
  partes.push('Usar vai ao resumo; Revisar passa por cada tela já preenchida.');
  return partes.join(' ');
}

function anunciar(texto) {
  const a = $('anuncio');
  a.textContent = '';
  if (texto) setTimeout(() => { a.textContent = texto; }, 60);
}

function barraProgresso(p, rotulo) {
  return h('progress', { value: p.atual, max: p.total, 'aria-label': rotulo || 'Progresso' });
}

// ------------------------------------------------------------------ estado
// Atualizacao em curso: o servidor some no meio (fecha para instalar) e isso
// nao e erro; a tela de "atualizando" fica.
let atualizando = false;
let geracaoVista = -1;
let buscando = null;

function buscarEstado() {
  if (buscando) return buscando;
  buscando = (async () => {
    let dados;
    try {
      dados = await api('GET', '/api/estado?desde=' + cursorLog);
    } catch (e) {
      if (atualizando) { $('atualizando').hidden = false; return; }
      $('placa-texto').textContent = 'Painel sem resposta';
      $('placa-luz').className = 'luz falta';
      return;
    }
    estado = dados.estado;
    // Comando na fila do worker ainda nao virou "ocupado": trata como ocupado.
    if (estado && dados.comandos > 0) estado.ocupado = true;
    if (dados.versao) $('versao-painel').textContent = 'Painel v' + dados.versao;
    desenharAtualizacao(dados.atualizacao || {}, estado || {});
    anexarLog(dados.log || []);
    cursorLog = dados.cursor;
    desenhar();
  })().finally(() => { buscando = null; });
  return buscando;
}

function anexarLog(linhas) {
  // Duas buscas em voo podem trazer a mesma linha: so entra o que e mais novo que o cursor.
  linhas = linhas.filter((l) => !(l.n <= cursorLog));
  if (!linhas.length) return;
  const caixa = $('log');
  const noFim = caixa.scrollHeight - caixa.scrollTop - caixa.clientHeight < 30;
  for (const l of linhas) {
    caixa.append(h('div', { class: l.cor }, h('span', { class: 'ts', text: String(l.ts).slice(11) }), l.msg));
  }
  while (caixa.childElementCount > 1500) caixa.firstElementChild.remove();
  if (noFim) caixa.scrollTop = caixa.scrollHeight;
}

function desenhar() {
  const e = estado;
  if (!e || !e.fase) return;

  // topo
  $('faixa-simular').hidden = !e.simular;
  document.title = (e.simular ? '[Simulação] ' : '') + 'Configurar câmeras';
  for (const n of document.querySelectorAll('[data-nota-simular]')) n.hidden = !e.simular;
  $('faixa-falha').textContent = e.simular && e.falharEm ? 'Falha forçada na etapa ' + NOME_ETAPA[e.falharEm] + '.' : '';
  desenharPlaca(e.rede || {});
  desenharInternet(e.internet || {}, e.rede || {});

  // Sessao regravada (secao salva, fila montada): os formularios recarregam.
  const g = (e.sessao && e.sessao.geracao) || 0;
  if (g !== geracaoVista) { const primeira = geracaoVista < 0; geracaoVista = g; if (!primeira) carregarSessao(true); }

  desenharModo();
  $('btn-preparar').hidden = modoAtual !== 'normal' || !!(e.rede && (e.rede.ok || e.rede.semSessao));

  desenharFila(e);
  desenharFerramenta(e.ferramenta, e);
  if (passoAtual === 1) montarPasso(1);

  const falas = [];
  if (ultimoVisto !== null && e.ultimo && e.ultimo !== ultimoVisto) falas.push(e.ultimo);
  ultimoVisto = e.ultimo || '';
  if (ultimaFase && ultimaFase !== e.fase) {
    if (rota().view === 'painel' && modoAtual === 'normal') carregarRegistro();
    if (e.fase === 'escolher') falas.push('Mais de uma câmera de fábrica na rede. Escolha pelo MAC da etiqueta.');
    else if (e.fase === 'decisao' && e.falha) { falas.push($('decisao-titulo').textContent + '. ' + e.falha.erro); focarTentar = true; }
    else if (e.fase === 'concluida') falas.push('Fila concluída.');
    else if (e.fase === 'encerrada') falas.push('Fila encerrada.');
  }
  if (falas.length) anunciar(falas.join(' '));
  ultimaFase = e.fase;

  aplicarOcupado(!!e.ocupado);
  // Senha recusada: "Tentar de novo" fica travado ate uma senha mais nova
  // (o servidor tambem recusa; repetir gastaria o lockout da camera).
  const tentar = document.querySelector('[data-decisao="tentar"]');
  if (e.fase === 'decisao' && e.falha && e.falha.loginRecusado && e.falha.geracao === e.senhaGeracao) tentar.disabled = true;
  // O foco vai para "Tentar de novo" quando o botao ja estiver ativo.
  if (e.fase !== 'decisao') focarTentar = false;
  if (focarTentar && !tentar.disabled && naTela(tentar)) { tentar.focus(); focarTentar = false; }

  // O slot do aviso depende de qual bloco esta na tela.
  if (e.avisoN !== avisoN) {
    avisoN = e.avisoN;
    if (e.aviso) mostrarAviso(e.aviso, ORIGEM_DO_COMANDO[e.avisoOrigem], { servidor: true });
    // Aviso que manda retomar: abre o bloco que ele cita.
    if (e.aviso && e.aviso.includes('Retomar câmera já inicializada')) $('retomar').open = true;
  } else if (!e.aviso && avisoDoServidor) {
    mostrarAviso('');
  }
}

// Barra da placa: so a placa escolhida conta.
function desenharPlaca(rede) {
  const luz = $('placa-luz');
  const txt = $('placa-texto');
  if (rede.semSessao) { luz.className = 'luz'; txt.textContent = 'Placa de rede: escolhida no passo a passo'; return; }
  const nome = rede.placa && rede.placa.nome ? rede.placa.nome : 'placa';
  luz.className = 'luz ' + (rede.ok ? 'ok' : 'falta');
  if (rede.placa && rede.placa.presente === false) {
    txt.textContent = 'Placa ' + nome + ' não está mais neste PC: escolha outra em Opções';
    return;
  }
  txt.textContent = rede.ok
    ? 'Placa ' + nome + ' pronta (' + (rede.ips || []).join(', ') + ')'
    : 'Placa ' + nome + ' sem as faixas: ' + (rede.faltando || []).join('; ');
  if (rede.placa && rede.placa.cabo === false) txt.textContent += ' · sem cabo';
  // Preparada pelo painel: volta ao DHCP ao encerrar (ou em Restaurar DHCP).
  if (rede.preparada) txt.textContent += ' · preparada pelo painel';
  if (rede.temporarios && rede.temporarios.length) {
    txt.textContent += ' · IP temporário: ' + rede.temporarios.map((t) => t.ip + (t.camera ? ' (câmera em ' + t.camera + ')' : '')).join(', ');
  }
  if (rede.rotas && rede.rotas.length) txt.textContent += ' · rota de host: ' + rede.rotas.map((r) => r.destino).join(', ');
  if (estado && estado.pastaDadosAlternativa) txt.textContent += '. Dados em ' + estado.pastaDados + ' (sem permissão de escrita em ProgramData)';
}

// Faixa de atualizacao: aparece com versao nova conhecida; o botao so ativa
// com o painel parado (o servidor tambem recusa com 409 e diz o motivo).
function desenharAtualizacao(a, e) {
  const faixa = $('atualizacao');
  const txt = $('atualizacao-texto');
  const btn = $('btn-atualizar');
  const notas = $('atualizacao-notas');
  const estadoA = a.estado || 'nenhuma';
  atualizando = ['baixando', 'verificando', 'instalando'].includes(estadoA);
  if (estadoA === 'instalando') { $('atualizando').hidden = false; }
  if (!['disponivel', 'baixando', 'verificando', 'instalando', 'erro'].includes(estadoA)) { faixa.hidden = true; return; }
  faixa.hidden = false;
  faixa.classList.toggle('erro', estadoA === 'erro');
  notas.hidden = !a.pagina;
  if (a.pagina) notas.href = a.pagina;
  let motivo = '';
  if (e.ocupado) motivo = 'Aguarde: o painel está terminando a operação atual.';
  else if (['configurando', 'decisao', 'escolher'].includes(e.fase)) motivo = 'Termine a câmera atual (ou encerre a fila) antes de atualizar.';
  else if (e.vigia && e.vigia.ligado) motivo = 'Desligue o vigia antes de atualizar.';
  else if (e.admin === false) motivo = 'Atualizar exige o painel aberto como Administrador.';
  if (estadoA === 'disponivel') {
    txt.textContent = 'Versão ' + a.versao + ' disponível (esta é a ' + a.versaoAtual + ').';
    btn.textContent = 'Atualizar';
  } else if (estadoA === 'erro') {
    txt.textContent = 'A atualização para a ' + a.versao + ' falhou: ' + (a.erro || 'erro') + '. Nada foi instalado.';
    btn.textContent = 'Tentar de novo';
  } else {
    txt.textContent = { baixando: 'Baixando a versão ' + a.versao + '…', verificando: 'Conferindo o instalador (SHA-256)…',
      instalando: 'Instalando a versão ' + a.versao + '…' }[estadoA];
    motivo = 'Em andamento.';
  }
  btn.disabled = !!motivo;
  btn.title = motivo;
}

// Luz da internet: verde ok, vermelha "caiu depois do preparo" (culpa do
// painel), cinza quando ja estava sem antes ou ainda nao foi testada.
function desenharInternet(net, rede) {
  const luz = $('internet-luz');
  const txt = $('internet-texto');
  if (net.agora === 'ok') { luz.className = 'luz ok'; txt.textContent = 'Internet ok'; return; }
  if (net.agora === 'sem') {
    if (net.antes === 'ok' && rede.preparada) {
      luz.className = 'luz falta';
      txt.textContent = 'Sem internet desde o preparo da placa: use Restaurar DHCP (Opções) se precisar dela agora';
    } else {
      luz.className = 'luz';
      txt.textContent = net.antes === 'sem' ? 'Sem internet (já estava assim ao abrir)' : 'Sem internet';
    }
    return;
  }
  luz.className = 'luz';
  txt.textContent = 'Internet: não testada';
}

// ------------------------------------------------------------------ painel (fila)
function desenharFila(e) {
  const fila = e.fila;
  const temFila = !!(fila && fila.itens && fila.itens.length);
  $('painel-sem-fila').hidden = temFila;
  $('fita-bloco').hidden = !temFila;
  $('bancada').hidden = !temFila;
  const ult = $('ultimo');
  // Na falha e na escolha, a "ultima instalada" so distrai da decisao.
  ult.hidden = !e.ultimo || e.fase === 'decisao' || e.fase === 'escolher';
  ult.textContent = e.ultimo || '';
  if (!temFila) { desenharVigia(e, false); return; }

  const itens = fila.itens;
  const pendentes = itens.filter((i) => i.Estado === 'pendente');
  const feitas = itens.filter((i) => i.Estado === 'feita').length;
  const proxima = pendentes.length ? pendentes[0] : null;
  // Posicoes que contam para "N de M": as puladas na montagem (gateway, fora
  // da rede, com camera instalada) nao sao lugar para camera nenhuma.
  const usavel = (i) => i.Estado !== 'pulada' || /operador|responde/.test(i.Motivo || '');
  const usaveis = itens.filter(usavel);
  const livres = usaveis.length;

  $('fita-titulo').textContent = 'Fila ' + itens[0].Ip + ' a ' + itens[itens.length - 1].Ip;
  $('fita-resumo').textContent = feitas + ' instalada(s), ' + pendentes.length + ' pendente(s)' +
    [fila.local, fila.rack, fila.andar].filter(Boolean).map((t) => ', ' + t).join('');

  const fita = $('fita');
  fita.replaceChildren(...itens.map((i, idx) => {
    const cls = [i.Estado];
    // Estado em palavra, nao so na cor.
    let palavra = ESTADO_NA_FITA[i.Estado] || '';
    if (idx === e.atual && e.fase !== 'fila') { cls.push('atual'); if (i.Estado !== 'falhou') palavra = 'agora'; }
    else if (proxima && i === proxima && e.fase === 'fila') { cls.push('proxima'); palavra = 'próxima'; }
    // Mesma numeracao da bancada: so as posicoes usaveis contam.
    const n = usaveis.indexOf(i);
    const rotulo = n >= 0 ? 'câmera ' + (n + 1) : '';
    return h('li', { class: cls.join(' '), title: i.Motivo || null },
      h('span', { class: 'pos' }, rotulo, palavra ? h('span', { class: 'estado', text: (rotulo ? ' ' : '') + palavra }) : null),
      h('span', { text: i.Ip }),
      i.Motivo ? h('span', { class: 'motivo', text: i.Motivo }) : null);
  }));

  const blocos = { pronta: false, trabalho: false, escolha: false, decisao: false, fim: false };
  const posAtual = e.atual >= 0 ? itens[e.atual] : null;
  const ordinal = (item) => 'Câmera ' + (usaveis.indexOf(item) + 1) + ' de ' + livres;

  if (e.fase === 'configurando' || (e.ocupado && e.trabalho && e.fase === 'fila')) {
    blocos.trabalho = true;
    $('trabalho-titulo').textContent = posAtual ? ordinal(posAtual) + ' → ' + posAtual.Ip : (e.trabalho || 'Trabalhando');
    $('trabalho-texto').textContent = e.trabalho || '';
    const barra = $('trabalho-progresso');
    barra.hidden = !e.progresso;
    if (e.progresso) {
      barra.max = e.progresso.total;
      barra.value = e.progresso.atual;
      barra.setAttribute('aria-label', e.trabalho || 'Progresso');
    }
    const i = ETAPAS.indexOf(e.etapa);
    for (const li of $('etapas').children) {
      const j = ETAPAS.indexOf(li.dataset.etapa);
      li.className = e.fase !== 'configurando' ? '' : (j < i ? 'feita' : (j === i ? 'agora' : ''));
    }
  } else if (e.fase === 'escolher') {
    blocos.escolha = true;
    $('escolha-lista').replaceChildren(...(e.escolha || []).map((c) =>
      h('li', null, h('button', { type: 'button', class: 'btn', onclick: () => comando('/api/escolher', { ip: c.ip }) },
        h('span', { text: c.ip + (c.httpPort && c.httpPort !== 80 ? ':' + c.httpPort : '') + (c.mascara ? ' / ' + c.mascara : '') }),
        h('span', { text: 'MAC ' + (c.mac || 'não lido') }),
        c.modelo ? h('span', { text: c.modelo }) : null,
        c.alcancavel === false ? h('span', { text: 'fora das faixas da placa: ela recebe um IP temporário' }) : null,
        c.ouiConhecido || c.modelo ? null : h('span', { text: 'fabricante desconhecido' })))));
  } else if (e.fase === 'decisao' && e.falha) {
    blocos.decisao = true;
    $('decisao-titulo').textContent = 'Falhou na etapa ' + (NOME_ETAPA[e.falha.etapa] || e.falha.etapa) +
      (posAtual ? ' (' + posAtual.Ip + ')' : '');
    $('decisao-erro').textContent = e.falha.erro;
    $('decisao-apoio').textContent = textoDaFalha(e.falha, posAtual);
  } else if (e.fase === 'concluida' || e.fase === 'encerrada' || !proxima) {
    blocos.fim = true;
    $('fim-titulo').textContent = e.fase === 'encerrada' ? 'Fila encerrada' : 'Fila concluída';
    const motivo = e.vigia && !e.vigia.ligado && e.vigia.motivo;
    $('fim-texto').textContent = 'O registro abaixo tem cada câmera; Exportar relatório gera o CSV.' +
      (motivo ? ' O vigia foi desligado: ' + (MOTIVO_VIGIA[motivo] || motivo) + '.' : '');
  } else {
    const vigiando = !!(e.vigia && e.vigia.ligado);
    blocos.pronta = true;
    $('bancada-pos').textContent = 'Conecte a ' + ordinal(proxima).replace('Câmera', 'câmera');
    $('bancada-destino').textContent = proxima.Ip;
    $('bancada-apoio').textContent = vigiando
      ? 'O vigia configura sozinho. Câmera conectada fica para retomar uma câmera já inicializada, pelo bloco abaixo.'
      : 'Ligue uma câmera só no cabo e confirme. A câmera de fábrica é encontrada sozinha pela placa escolhida.';
    // Uma acao principal por vez: com o vigia ligado, o destaque e dele.
    $('btn-conectada').className = vigiando ? 'btn' : 'btn acento';
  }
  for (const [k, v] of Object.entries(blocos)) $('bancada-' + k).hidden = !v;
  desenharVigia(e, !blocos.fim, {
    fila: itens[0].Ip + '|' + itens[itens.length - 1].Ip + '|' + (fila.rack || ''),
    proxima: proxima ? ordinal(proxima) + ' (destino ' + proxima.Ip + ')' : '',
    feitas,
  });
}

// O que a camera ja recebeu e o que "Tentar de novo" faz, por etapa. Espelha
// Get-PlanoRetomada: a nova tentativa olha onde a camera esta antes de agir.
function textoDaFalha(f, pos) {
  if (f.loginRecusado) {
    return f.bloqueada
      ? 'A câmera bloqueou o admin por senhas erradas. Espere alguns minutos, confirme a senha certa em Opções e só então tente de novo.'
      : 'A câmera recusou a senha da sessão. Troque a senha (Opções, seção Senha) antes de tentar de novo: cada tentativa com a senha errada conta para o bloqueio da câmera.';
  }
  if (f.recusa) {
    return 'A câmera recusou um valor. Confira a seção Câmera em Opções antes de tentar de novo; o que já foi concluído fica registrado.';
  }
  const destino = pos ? pos.Ip : 'o destino';
  return {
    inicializada: 'A câmera pode ter ficado com o admin já criado. Tentar de novo confere o estado dela: ' +
      'se continuar de fábrica, recomeça; se já tiver a senha desta sessão, segue para o encoder.',
    encoder: 'A câmera já está inicializada com a senha desta sessão e continua no IP de origem. Tentar de novo faz login e refaz o encoder.',
    rede: 'A câmera já tem a senha e o encoder. Tentar de novo grava a rede; se ela já tiver mudado para ' + destino + ', só confere.',
    conferida: 'A rede já foi gravada: a câmera deve estar reiniciando em ' + destino + '. Tentar de novo espera ela responder lá e confere. ' +
      'Se ela não voltar, confira o cabo e a máscara e o gateway da sessão (Opções).',
  }[f.etapa] || 'O que foi concluído fica registrado. Tentar de novo continua da etapa que falhou.';
}

const RE_IP = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;
const ipValido = (t) => RE_IP.test(String(t).trim());

function conferirCampoIp(campo) {
  const v = campo.value.trim();
  campo.setCustomValidity(v && !ipValido(v) ? 'Use quatro números de 0 a 255, como 192.168.1.108.' : '');
}

// Previa da faixa enquanto o IP e digitado.
function desenharPrevia() {
  const f = $('form-fila').elements;
  const p = $('fila-previa');
  const a = f.inicio.value.trim();
  const b = f.fim.value.trim();
  p.hidden = !(ipValido(a) && ipValido(b));
  if (p.hidden) return;
  const n = numIp(b) - numIp(a) + 1;
  if (n <= 0) p.textContent = 'O primeiro IP vem depois do último: troque os dois.';
  else if (n > 254) p.textContent = n + ' endereços: acima do máximo de 254. Divida em faixas menores.';
  else p.textContent = (n === 1 ? '1 endereço: ' + a : n + ' endereços, de ' + a + ' a ' + b) + '.';
}

function desenharVigia(e, visivel, ctx) {
  $('vigia').hidden = !visivel;
  const v = e.vigia || {};
  const f = $('form-vigia').elements;
  const filaNova = !!ctx && ctx.fila !== filaDoVigia;
  if (ctx) filaDoVigia = ctx.fila;
  if (filaNova) {
    // Porta/canal da fila anterior nao valem para outro rack.
    f.porta.value = ''; f.canal.value = '';
  } else if (vigiaLigadoAntes && !v.ligado && e.fase === 'fila') {
    // Desligado no meio da fila: os campos ficam com a porta/canal da proxima camera, e religar continua dali.
    f.porta.value = v.porta || ''; f.canal.value = v.canal || '';
  }
  vigiaLigadoAntes = !!v.ligado;
  if (!visivel) return;

  const ip = ipFabrica || 'o IP de fábrica';
  $('vigia-luz').className = 'luz' + (v.ligado ? ' ok' : '');
  $('vigia-estado').textContent = v.ligado ? 'ligado' : 'desligado';
  $('btn-vigia').textContent = v.ligado ? 'Desligar vigia' : 'Ligar vigia';
  $('vigia-rotulo-porta').textContent = v.ligado ? 'Porta da próxima câmera' : 'Porta inicial';
  $('vigia-rotulo-canal').textContent = v.ligado ? 'Canal da próxima câmera' : 'Canal inicial';
  f.porta.disabled = f.canal.disabled = f.broadcast.disabled = !!v.ligado;
  if (v.ligado) { f.porta.value = v.porta || ''; f.canal.value = v.canal || ''; f.broadcast.checked = !!v.broadcast; }
  const onde = v.ligado && v.broadcast ? 'qualquer faixa (broadcast) e ' + ip : ip;

  let texto;
  if (!v.ligado) {
    texto = (v.motivo ? 'Desligado: ' + (MOTIVO_VIGIA[v.motivo] || v.motivo) + '. ' : '') +
      'Ligado, o painel observa ' + ip + ' e configura sozinho cada câmera de fábrica que aparecer, na próxima posição livre. ' +
      'Com a caixa marcada, aceita também câmera de fábrica em qualquer faixa (broadcast): só com a bancada isolada da rede do escritório. ' +
      'Porta e canal somam 1 a cada câmera instalada: ligue as câmeras na ordem do cabeamento.';
  } else if (e.fase === 'escolher' || e.fase === 'decisao') {
    texto = 'Em pausa até você resolver a câmera atual.';
  } else if (e.fase === 'configurando' || e.ocupado) {
    texto = 'Configurando. Não desligue o cabo. Depois volta a observar ' + onde + '.';
  } else {
    texto = 'Observando ' + onde + '. ' + (ctx.feitas ? 'Tire a câmera anterior e ligue a ' : 'Ligue a ') +
      ctx.proxima.replace('Câmera', 'câmera') + ' na porta ' + (v.porta || 'não informada') +
      ', canal ' + (v.canal || 'não informado') + '.';
  }
  $('vigia-texto').textContent = texto;
}

// Uma linha por stream: "1920 × 1080, 20 fps, 1596 kbps, H.264", sem os campos vazios.
function textoStream(res, fps, kbps, codec, gop) {
  return [res ? String(res).replace('x', ' × ') : '', fps ? fps + ' fps' : '', kbps ? kbps + ' kbps' : '', codec || '',
    gop ? 'GOP ' + gop : ''].filter(Boolean).join(', ');
}

function streamsEncoder(en, comGop) {
  if (!en) return null;
  return {
    principal: textoStream(en.Resolucao, en.FpsPrincipal, en.BitratePrincipal, en.CodecPrincipal, comGop && en.GopPrincipal),
    secundario: textoStream(en.ResolucaoSecundario, en.FpsSecundario, en.BitrateSecundario, en.CodecSecundario, comGop && en.GopSecundario),
  };
}

// ------------------------------------------------------------------ ferramentas
let ferramentaChave = '';
function desenharFerramenta(f, e) {
  const caixa = $('resultado-ferramenta');
  if (!f) { caixa.hidden = true; ferramentaChave = ''; return; }
  // So redesenha quando muda: o polling nao pode apagar o que esta na tela.
  const chave = JSON.stringify(f) + (f.emCurso ? '|' + (e.trabalho || '') + '|' + JSON.stringify(e.progresso || null) : '');
  if (chave === ferramentaChave) return;
  ferramentaChave = chave;
  caixa.hidden = false;
  if (f.emCurso) {
    const titulo = { sondar: 'Sondando ' + f.ip, descobrir: 'Procurando câmeras na rede', verificar: 'Verificando câmeras instaladas' }[f.tipo] || 'Trabalhando';
    caixa.replaceChildren(h('h3', { text: titulo }), h('p', { class: 'apoio', text: e.trabalho || '' }),
      e.progresso ? barraProgresso(e.progresso, e.trabalho) : null);
    return;
  }
  const titulo = { sondar: 'Sondagem de ' + f.ip, descobrir: 'Câmeras encontradas', verificar: 'Verificação' }[f.tipo] || f.tipo;
  const partes = [h('h3', { text: titulo + ' às ' + f.quando })];

  if (f.tipo === 'sondar') {
    const enc = streamsEncoder(f.encoder, true);
    const campos = [
      ['Ping', f.ping ? 'responde' : 'não responde'],
      ['Estado', f.fabrica ? 'de fábrica' : (f.init === -1 ? 'não respondeu' : 'inicializada')],
      ['Modelo', f.modelo], ['Serial', f.serial], ['Firmware', f.firmware], ['MAC', f.mac], ['Rede', f.rede],
      ['Stream principal', enc && enc.principal], ['Stream secundário', enc && enc.secundario],
      ['Erro', f.erro],
    ].filter(([, v]) => v !== undefined && v !== null && v !== '');
    partes.push(h('dl', null, campos.flatMap(([k, v]) => [h('dt', { text: k }), h('dd', { text: String(v) })])));
  } else if (f.tipo === 'descobrir') {
    const itens = f.itens || [];
    if (!itens.length) {
      partes.push(h('p', { class: 'apoio', text: 'Nada encontrado. Nenhum aparelho respondeu ao broadcast DHIP (UDP 37810) nem ao ping nas faixas da placa escolhida. ' +
        'Confira o cabo e o PoE; um firewall que barra UDP de entrada também silencia o broadcast.' }));
    } else {
      partes.push(h('p', { class: 'apoio', text: f.broadcast + ' pelo broadcast, ' + (f.varredura || 0) + ' pela varredura. ' +
        'Estado "de fábrica" só é certeza quando confirmado por HTTP; fora das faixas da placa é o que a câmera anunciou.' }));
      const cab = ['IP', 'Máscara', 'MAC', 'Modelo', 'Serial', 'Firmware', 'Estado'];
      const estadoDe = (i) => {
        let t = i.fabrica ? 'de fábrica' : (i.init === -1 ? 'desconhecido' : 'inicializada');
        if (i.classe && i.classe !== 'IPC') t += ' (' + i.classe + ')';
        if (!i.alcancavel) t += ', fora das faixas da placa';
        else if (i.fabrica && !i.confirmado) t += ', não confirmado por HTTP';
        return t;
      };
      const linhas = itens.map((i) => [i.ip + (i.httpPort && i.httpPort !== 80 ? ':' + i.httpPort : ''), i.mascara || '', i.mac || 'não lido',
        i.modelo || '', i.serial || '', i.firmware || '', estadoDe(i)]);
      partes.push(h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' },
        h('thead', null, h('tr', null, cab.map((c) => h('th', { text: c })))),
        h('tbody', null, linhas.map((l) => h('tr', null, l.map((c, n) => h('td', { class: n < 3 || n === 4 ? 'mono' : null, text: String(c ?? '') }))))))));
    }
  } else if (f.tipo === 'verificar') {
    const itens = f.itens || [];
    if (!itens.length) partes.push(h('p', { class: 'apoio', text: 'Nenhuma câmera instalada no registro.' }));
    else {
      const cab = ['IP', 'MAC', 'Resultado', 'Detalhe'];
      const linhas = itens.map((i) => [i.ip, i.mac, i.ok ? 'ok' : (i.ping ? (i.login ? 'divergente' : 'login falhou') : 'sem ping'), i.detalhe]);
      partes.push(h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' },
        h('thead', null, h('tr', null, cab.map((c) => h('th', { text: c })))),
        h('tbody', null, linhas.map((l) => h('tr', null, l.map((c, n) => h('td', { class: n < 2 ? 'mono' : null, text: String(c ?? '') }))))))));
    }
  }
  caixa.replaceChildren(...partes);
}

// ------------------------------------------------------------------ sessao (secoes)
// sessaoCache = o que esta em sessao.json; sujo[secao] = o operador mexeu e
// ainda nao salvou (o polling nao escreve por cima).
let sessaoCache = null;
let listasCarregadas = false;
let carregandoSessao = null;
const sujo = {};
let placasCache = null;
let placasPedido = null;

const SECOES = {
  senha: {
    ler() { return null; },
    escrever() { },
  },
  placa: {
    ler(form) {
      const r = form.querySelector('input[name="placa"]:checked');
      if (!r) return { erro: [{ campo: 'placa', msg: 'Escolha uma placa de rede da lista.' }] };
      return { Placa: { Nome: r.dataset.nome, IfIndex: Number(r.value), Mac: r.dataset.mac, Tipo: r.dataset.tipo } };
    },
    escrever() { desenharPlacas(); },
  },
  rede: {
    ler(form) {
      const f = form.elements;
      return { Mascara: f.Mascara.value, Gateway: f.Gateway.value, Dns1: f.Dns1.value, Dns2: f.Dns2.value, IpPcCameras: f.IpPcCameras.value };
    },
    escrever(form, s) {
      const f = form.elements;
      f.Mascara.value = s.Mascara; f.Gateway.value = s.Gateway; f.Dns1.value = s.Dns1; f.Dns2.value = s.Dns2;
      f.IpPcCameras.value = s.IpPcCameras || '';
      atualizarPlaceholdersPc();
    },
  },
  fabrica: {
    ler(form) { const f = form.elements; return { IpFabrica: f.IpFabrica.value, IpPcFabrica: f.IpPcFabrica.value }; },
    escrever(form, s) {
      const f = form.elements;
      f.IpFabrica.value = s.IpFabrica; f.IpPcFabrica.value = s.IpPcFabrica || '';
      atualizarPlaceholdersPc();
    },
  },
  camera: {
    ler(form) {
      const f = form.elements;
      return {
        EmailRecuperacao: f.EmailRecuperacao.value,
        Encoder: {
          Principal: { Resolucao: f.Resolucao.value, Fps: f.FpsPrincipal.value, BitRate: f.BitRate.value, Codec: f.CodecPrincipal.value },
          Secundario: { Resolucao: f.ResolucaoSecundario.value, Fps: f.FpsSecundario.value, BitRate: f.BitRateSecundario.value, Codec: f.CodecSecundario.value },
        },
      };
    },
    escrever(form, s) {
      const f = form.elements;
      const pr = s.Encoder.Principal; const se = s.Encoder.Secundario;
      f.EmailRecuperacao.value = s.EmailRecuperacao;
      f.Resolucao.value = pr.Resolucao; f.FpsPrincipal.value = pr.Fps; f.BitRate.value = pr.BitRate; f.CodecPrincipal.value = pr.Codec;
      f.ResolucaoSecundario.value = se.Resolucao; f.FpsSecundario.value = se.Fps; f.BitRateSecundario.value = se.BitRate; f.CodecSecundario.value = se.Codec;
      desenharEncoder();
    },
  },
  fila: {
    ler(form) {
      const f = form.elements;
      if (!f.inicio.value.trim() && !f.fim.value.trim()) return { Fila: null };
      return { Fila: { Inicio: f.inicio.value, Fim: f.fim.value, Local: f.local.value, Rack: f.rack.value, Andar: f.andar.value } };
    },
    escrever(form, s) {
      const f = form.elements;
      const u = s.Fila;
      const n = $('fila-ultima');
      if (!u || !u.Inicio) { n.hidden = true; desenharPrevia(); return; }
      f.inicio.value = u.Inicio; f.fim.value = u.Fim; f.local.value = u.Local || ''; f.rack.value = u.Rack || ''; f.andar.value = u.Andar || '';
      n.textContent = 'Última fila: ' + u.Inicio + ' a ' + u.Fim + (u.Quando ? ' em ' + dataCurta(u.Quando) : '') + '. Confira antes de montar; posições com câmera instalada ficam de fora.';
      n.hidden = false;
      desenharPrevia();
    },
  },
};

// GET /api/sessao: preenche as listas (uma vez) e os formularios nao sujos.
function carregarSessao(forcar) {
  if (carregandoSessao) return carregandoSessao;
  if (sessaoCache && !forcar) { preencherFormularios(); return Promise.resolve(sessaoCache); }
  carregandoSessao = (async () => {
    try {
      const d = await api('GET', '/api/sessao');
      if (!listasCarregadas) {
        const el = $('form-camera').elements;
        const opcoes = (sel, lista, texto) => sel.replaceChildren(...lista.map((v) => h('option', { value: v, text: texto(v) })));
        catalogo = d.catalogo;
        const marca = (stream, tipo, t) => (v) => t(v) + marcaTestado(stream, tipo, v);
        opcoes(el.Resolucao, d.resolucoes, marca('principal', 'resolucoes', resolucaoLegivel));
        opcoes(el.ResolucaoSecundario, d.resolucoesSecundario, marca('secundario', 'resolucoes', resolucaoLegivel));
        opcoes(el.CodecPrincipal, d.codecs, marca('principal', 'codecs', String));
        opcoes(el.CodecSecundario, d.codecs, marca('secundario', 'codecs', String));
        for (const s of Object.values(STREAMS)) montarListaValor(listaDoCampo(s.fps), catalogo.fps);
        listasCarregadas = true;
      }
      sessaoCache = d.sessao || null;
      if (!sessaoCache) {
        // Sem arquivo ainda: os campos ficam com o que o servidor considera fabrica.
        sessaoCache = { Mascara: '255.255.255.0', Gateway: '', Dns1: '8.8.8.8', Dns2: '8.8.4.4', IpPcCameras: '', IpFabrica: '192.168.1.108', IpPcFabrica: '',
          EmailRecuperacao: '', Encoder: { Principal: { Resolucao: '1920x1080', Fps: 20, BitRate: 1596, Codec: 'H.264' },
            Secundario: { Resolucao: '704x480', Fps: 12, BitRate: 512, Codec: 'H.264' } }, Placa: null, Fila: null, Etapa: 0 };
      }
      ipFabrica = sessaoCache.IpFabrica;
      preencherFormularios();
      if (passoAtual === 7) desenharResumo();
      if (passoAtual === 1) montarPasso(1);
    } catch (e) { mostrarAviso(e.message); }
    return sessaoCache;
  })().finally(() => { carregandoSessao = null; });
  return carregandoSessao;
}

function preencherFormularios() {
  if (!sessaoCache) return;
  for (const secao of SECOES_ORDEM) {
    if (sujo[secao]) continue;
    const form = $('form-' + secao);
    SECOES[secao].escrever(form, sessaoCache);
    for (const c of form.querySelectorAll('input[data-ip]')) conferirCampoIp(c);
    limparErrosCampo(form);
  }
}

// O "vazio = ..." dos IPs do PC segue o IP de fabrica e o gateway digitados.
function atualizarPlaceholdersPc() {
  const rede = $('form-rede').elements;
  const fab = $('form-fabrica').elements;
  const ipf = fab.IpFabrica.value.trim();
  const gw = rede.Gateway.value.trim();
  fab.IpPcFabrica.placeholder = 'vazio = ' + (ipValido(ipf) ? ipf.replace(/\.\d+$/, '.220') : '.220 da faixa de fábrica');
  rede.IpPcCameras.placeholder = 'vazio = ' + (ipValido(gw) ? gw.replace(/\.\d+$/, '.200') + ' a .249' : '.200 a .249') + ', pelo MAC';
}

function limparErrosCampo(form) {
  for (const s of form.querySelectorAll('.erro-campo')) s.remove();
  for (const c of form.querySelectorAll('[aria-invalid]')) {
    c.removeAttribute('aria-invalid');
    // Tira so o erro: a faixa do bitrate continua descrevendo o campo.
    const resto = (c.getAttribute('aria-describedby') || '').split(' ').filter((id) => id && !id.startsWith('erro-')).join(' ');
    if (resto) c.setAttribute('aria-describedby', resto); else c.removeAttribute('aria-describedby');
  }
  const ul = form.querySelector('ul.erros');
  if (ul) { ul.hidden = true; ul.replaceChildren(); }
}

// Nomes de campo que o servidor usa e que nao batem com o name do input.
const CAMPO_NO_FORM = { FilaInicio: 'inicio', FilaFim: 'fim', Placa: 'placa' };

// Erro embaixo do campo; o que nao tem campo vai para a lista do formulario.
function mostrarErrosCampo(form, campos, soltosExtra) {
  const soltos = [...(soltosExtra || [])];
  let primeiro = null;
  for (const c of campos) {
    const nome = CAMPO_NO_FORM[c.campo] || c.campo;
    let campo = form.elements[nome];
    if (campo && campo.length !== undefined && !campo.tagName) campo = campo[0];
    if (!campo) { soltos.push(c.msg); continue; }
    // Valor da lista com o campo escondido: quem recebe a marca e a lista.
    if (campo.hidden) campo = form.querySelector('select.lista-valor[data-para="' + nome + '"]') || campo;
    const id = 'erro-' + form.id + '-' + nome;
    let s = $(id);
    if (!s) {
      s = h('span', { class: 'erro-campo', id });
      const alvo = campo.closest('label') || campo;
      alvo.after(s);
      campo.setAttribute('aria-invalid', 'true');
      campo.setAttribute('aria-describedby', [campo.getAttribute('aria-describedby'), id].filter(Boolean).join(' '));
    }
    s.textContent = s.textContent ? s.textContent + ' ' + c.msg : c.msg;
    primeiro = primeiro || campo;
  }
  const ul = form.querySelector('ul.erros');
  if (ul) {
    const marcados = campos.length - (soltos.length - (soltosExtra || []).length);
    const lista = marcados > 0 ? ['Nada foi salvo: corrija ' + (marcados === 1 ? 'o campo marcado' : 'os ' + marcados + ' campos marcados') + '.', ...soltos] : soltos;
    ul.replaceChildren(...lista.map((t) => h('li', { text: t })));
    ul.hidden = !lista.length;
  }
  if (primeiro && primeiro.focus) primeiro.focus();
}

const resolucaoLegivel = (r) => r.replace('x', ' × ');

function recusadoNaReferencia(stream, tipo, v) {
  return !!catalogo && catalogo.recusado[stream][tipo].includes(v);
}

function marcaTestado(stream, tipo, v) {
  if (!catalogo) return '';
  if (recusadoNaReferencia(stream, tipo, v)) return ' (recusado na ' + catalogo.modelo + ')';
  return catalogo.testado[stream][tipo].includes(v) ? ' (testado)' : ' (não testado em câmera)';
}

// Faixa usual do bitrate para a resolucao e o codec escolhidos no stream.
function faixaDoStream(stream) {
  const f = $('form-camera').elements;
  const s = STREAMS[stream];
  const fx = catalogo && catalogo.faixas[f[s.res].value];
  return fx ? { min: fx.min, max: fx.max, rec: fx[f[s.codec].value], res: f[s.res].value, codec: f[s.codec].value } : null;
}

// Degraus de bitrate dentro da faixa, com o recomendado marcado.
function desenharBitrates(stream) {
  if (!catalogo) return;
  const s = STREAMS[stream];
  const fx = faixaDoStream(stream);
  const valores = fx ? catalogo.bitrates.filter((v) => v >= fx.min && v <= fx.max) : catalogo.bitrates;
  montarListaValor(listaDoCampo(s.br), valores, (v) => (fx && v === fx.rec ? v + ' (recomendado)' : String(v)));
  $(s.faixa).textContent = fx
    ? 'Bitrate usual para ' + resolucaoLegivel(fx.res) + ' em ' + fx.codec + ': ' + fx.min + ' a ' + fx.max + ' kbps; recomendado ' + fx.rec + '.'
    : '';
}

function desenharEncoder() {
  desenharBitrates('principal');
  desenharBitrates('secundario');
  for (const s of Object.values(STREAMS)) sincronizarListaValor(listaDoCampo(s.fps));
  desenharAvisosCamera();
}

// Quadros e bitrate: lista de valores prontos ligada ao campo numerico do
// mesmo stream. O campo guarda o valor; so aparece em "Outro valor...".
const OUTRO_VALOR = 'outro';

function listaDoCampo(nome) {
  return $('form-camera').querySelector('select.lista-valor[data-para="' + nome + '"]');
}

function montarListaValor(sel, valores, rotulo) {
  sel.replaceChildren(...valores.map((v) => h('option', { value: String(v), text: rotulo ? rotulo(v) : String(v) })),
    h('option', { value: OUTRO_VALOR, text: 'Outro valor…' }));
  sincronizarListaValor(sel);
}

// Valor do campo na lista: seleciona e esconde o campo; fora dela: "Outro valor".
function sincronizarListaValor(sel) {
  const campo = $('form-camera').elements[sel.dataset.para];
  const v = campo.value.trim();
  const opcao = v === '' ? null : [...sel.options].find((o) => o.value !== OUTRO_VALOR && Number(o.value) === Number(v));
  sel.value = opcao ? opcao.value : OUTRO_VALOR;
  campo.hidden = !!opcao;
}

function escolherListaValor(sel) {
  const campo = $('form-camera').elements[sel.dataset.para];
  if (sel.value === OUTRO_VALOR) { campo.hidden = false; campo.focus(); campo.select(); return; }
  campo.value = sel.value;
  campo.hidden = true;
}

// Nao bloqueiam o salvamento: so chamam a atencao.
function desenharAvisosCamera() {
  const f = $('form-camera').elements;
  const lista = [];
  for (const stream of Object.keys(STREAMS)) {
    const s = STREAMS[stream];
    const fx = faixaDoStream(stream);
    const br = Number(f[s.br].value);
    if (fx && f[s.br].value !== '' && (br < fx.min || br > fx.max)) {
      lista.push('O bitrate do stream ' + s.nome + ' (' + br + ' kbps) fica fora da faixa usual para ' + resolucaoLegivel(fx.res) + ' em ' + fx.codec +
        ' (' + fx.min + ' a ' + fx.max + ' kbps). Confira se é isso mesmo.');
    }
    for (const [tipo, campo, texto] of [['resolucoes', s.res, resolucaoLegivel], ['codecs', s.codec, String]]) {
      if (recusadoNaReferencia(stream, tipo, f[campo].value)) {
        lista.push('A ' + catalogo.modelo + ' recusou ' + texto(f[campo].value) + ' no stream ' + s.nome + '. Outra câmera pode aceitar; se recusar, a fila para nessa câmera.');
      }
    }
  }
  if (Number(f.BitRateSecundario.value) > Number(f.BitRate.value)) {
    lista.push('O bitrate do stream secundário passa o do principal. Confira se é isso mesmo.');
  }
  if (Number(f.FpsSecundario.value) > Number(f.FpsPrincipal.value)) {
    lista.push('O stream secundário tem mais quadros por segundo que o principal. Confira se é isso mesmo.');
  }
  const ul = $('camera-avisos');
  ul.replaceChildren(...lista.map((t) => h('li', { text: t })));
  ul.hidden = !lista.length;
}

function marcarSalvo(form, texto) {
  const ok = form.querySelector('[data-ok]');
  if (!ok) return;
  const agora = new Date().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  ok.textContent = (texto || 'Salvo') + ' às ' + agora + '.';
  ok.hidden = false;
}

// PUT /api/sessao com a secao: 400 marca os campos; 409 precisaConfirmar
// pergunta e reenvia; 409 "aguarde" vira aviso neutro. Devolve true se gravou.
async function salvarSecao(secao, opcoes) {
  const o = opcoes || {};
  const form = $('form-' + secao);
  limparErrosCampo(form);
  const lido = SECOES[secao].ler(form);
  if (lido && lido.erro) { mostrarErrosCampo(form, lido.erro); return false; }
  const corpo = lido || {};
  if (o.etapa) corpo.etapa = o.etapa;
  if (secao === 'placa') {
    const r = form.querySelector('input[name="placa"]:checked');
    if (r && r.dataset.rota === '1' && !confirm('A placa ' + r.dataset.nome + ' é a que leva este PC à internet.\n\n' +
        'O painel acrescenta dois endereços nela e copia o que o DHCP deu como estático: a rede pisca por alguns segundos e a internet é testada depois. ' +
        'Ao encerrar, ela volta ao DHCP.\n\nUsar essa placa mesmo assim?')) return false;
  }
  const g = (estado && estado.sessao && estado.sessao.geracao) || 0;
  // Limpa antes, nao depois: o worker pode avisar algo durante a gravacao
  // (fila descartada) e esse aviso tem que ficar na tela.
  mostrarAviso('');
  for (let tentativa = 0; tentativa < 2; tentativa++) {
    try {
      aplicarOcupado(true);
      await api('PUT', '/api/sessao', corpo);
      await esperarEstado((e) => e.sessao && e.sessao.geracao > g, 8000);
      sujo[secao] = false;
      await carregarSessao(true);
      marcarSalvo(form, secao === 'fila' ? 'Faixa guardada' : 'Salvo');
      return true;
    } catch (e) {
      if (e.status === 409 && e.dados && e.dados.precisaConfirmar && tentativa === 0) {
        if (!confirm(e.dados.erro)) return false;
        corpo.confirmar = true;
        continue;
      }
      if (e.status === 400 && e.dados && e.dados.campos) { mostrarErrosCampo(form, e.dados.campos); return false; }
      if (e.status === 400) { mostrarErrosCampo(form, [], e.dados.erros || [e.message]); return false; }
      mostrarAviso(e.message, null, { neutro: e.status === 409 });
      return false;
    } finally { aplicarOcupado(!!(estado && estado.ocupado)); }
  }
  return false;
}

// ------------------------------------------------------------------ placas
function carregarPlacas(forcar) {
  if (placasPedido) return placasPedido;
  if (placasCache && !forcar) { desenharPlacas(); return Promise.resolve(placasCache); }
  placasPedido = (async () => {
    try {
      const d = await api('GET', '/api/placas');
      placasCache = d;
      desenharPlacas();
    } catch (e) { mostrarAviso(e.message); }
    return placasCache;
  })().finally(() => { placasPedido = null; });
  return placasPedido;
}

function desenharPlacas() {
  const ul = $('placas');
  if (!placasCache) { ul.replaceChildren(h('li', { class: 'apoio', text: 'Lendo as placas de rede…' })); return; }
  const escolhidaAntes = ul.querySelector('input[name="placa"]:checked');
  const naSessao = sessaoCache && sessaoCache.Placa ? Number(sessaoCache.Placa.IfIndex) : 0;
  const marcar = escolhidaAntes ? Number(escolhidaAntes.value) : (naSessao || placasCache.sugerida || 0);
  const placas = placasCache.placas || [];
  if (!placas.length) {
    ul.replaceChildren(h('li', { class: 'apoio', text: 'Nenhuma placa de rede física encontrada. Conecte um adaptador (USB-Ethernet serve) e clique em Atualizar lista.' }));
  }
  ul.replaceChildren(...placas.map((p) => {
    const detalhes = [p.tipo === 'wifi' ? 'Wi-Fi' : 'Ethernet', p.cabo ? (p.tipo === 'wifi' ? 'conectada' : 'cabo conectado') : (p.tipo === 'wifi' ? 'desconectada' : 'sem cabo'),
      p.ips && p.ips.length ? p.ips.join(', ') : 'sem IP', p.dhcp ? 'DHCP' : 'IP fixo'].filter(Boolean).join(' · ');
    const input = h('input', { type: 'radio', name: 'placa', value: String(p.ifIndex), 'data-nome': p.nome, 'data-mac': p.mac || '', 'data-tipo': p.tipo,
      'data-rota': p.rotaPadrao ? '1' : '0' });
    if (p.ifIndex === marcar) input.checked = true;
    return h('li', null, h('label', { class: 'placa-item' + (p.sugerida ? ' sugerida' : '') }, input,
      h('span', { class: 'placa-corpo' },
        h('span', { class: 'placa-nome' }, p.nome,
          p.sugerida ? h('span', { class: 'selo', text: 'sugerida' }) : null,
          p.rotaPadrao ? h('span', { class: 'selo internet', text: 'leva à internet' }) : null,
          p.ifIndex === naSessao ? h('span', { class: 'selo', text: 'na sessão' }) : null),
        h('span', { class: 'placa-detalhe', text: detalhes + (p.descricao ? ' · ' + p.descricao : '') }))));
  }));
  const nota = $('placas-nota');
  const temWifiSo = placas.length && placas.every((p) => p.tipo === 'wifi');
  nota.hidden = !temWifiSo;
  if (temWifiSo) nota.textContent = 'Só há Wi-Fi neste PC. Dá para usar, mas a bancada precisa estar na mesma rede do Wi-Fi; um adaptador USB-Ethernet é mais simples.';
}

// ------------------------------------------------------------------ resumo
function desenharResumo() {
  const box = $('resumo');
  const s = sessaoCache;
  const es = (estado && estado.sessao) || {};
  if (!s) { box.replaceChildren(h('p', { class: 'apoio', text: 'Carregando…' })); return; }
  const cartao = (n, titulo, linhas) => h('div', { class: 'resumo-secao' },
    h('div', { class: 'resumo-cabeca' }, h('h3', { text: titulo }), n ? h('a', { href: '#inicio/' + n, text: 'Alterar' }) : null),
    h('dl', null, linhas.filter(([, v]) => v !== undefined && v !== null && v !== '').flatMap(([k, v]) => [h('dt', { text: k }), h('dd', { text: String(v) })])));
  const placa = s.Placa ? s.Placa.Nome + ' (' + (s.Placa.Tipo === 'wifi' ? 'Wi-Fi' : 'Ethernet') + ', ifIndex ' + s.Placa.IfIndex + ')' : 'não escolhida';
  const pr = s.Encoder.Principal; const se = s.Encoder.Secundario;
  const fila = s.Fila && s.Fila.Inicio ? s.Fila.Inicio + ' a ' + s.Fila.Fim : '';
  box.replaceChildren(
    cartao(1, 'Senha das câmeras', [['Senha', senhaOk() ? (estado.simular && !estado.senhaDefinida ? 'não precisa em simulação' : 'definida (só na memória)') : 'não definida']]),
    cartao(2, 'Placa de rede', [['Placa', placa]]),
    cartao(3, 'Rede das câmeras', [['Gateway', s.Gateway], ['Máscara', s.Mascara], ['DNS', s.Dns1 + ', ' + s.Dns2], ['IP do PC', s.IpPcCameras || 'automático (.200 a .249)']]),
    cartao(4, 'Faixa de fábrica', [['IP de fábrica', s.IpFabrica], ['IP do PC', s.IpPcFabrica || 'automático (.220)']]),
    cartao(5, 'Câmera', [['E-mail de recuperação', s.EmailRecuperacao],
      ['Stream principal', textoStream(pr.Resolucao, pr.Fps, pr.BitRate, pr.Codec, 2 * Number(pr.Fps))],
      ['Stream secundário', textoStream(se.Resolucao, se.Fps, se.BitRate, se.Codec, 2 * Number(se.Fps))]]),
    cartao(6, 'Fila', [['Faixa', fila || 'montar depois (Opções, seção Fila)'], ['Local', s.Fila && s.Fila.Local], ['Rack', s.Fila && s.Fila.Rack], ['Andar', s.Fila && s.Fila.Andar]]));
  $('resumo-montar-rotulo').hidden = !fila;
  $('btn-comecar').textContent = estado && estado.simular ? 'Começar' : 'Preparar placa e começar';
  if (!es.placa && !s.Placa) $('btn-comecar').disabled = true;
}

// ------------------------------------------------------------------ passo a passo (acoes)
async function avancar() {
  const n = passoAtual;
  if (n === 1) {
    const ok = await enviarSenha($('form-senha'));
    if (!ok) return;
    trocarSenhaAberta = false;
    await esperarEstado((e) => e.senhaDefinida, 6000);
    const s = (estado && estado.sessao) || {};
    if (s.completa && !escolhaSessao) { montarPasso(1); return; }
    irPara(passoSugerido());
    return;
  }
  if (n >= 2 && n <= 6) {
    if (n === 6 && !$('form-fila').elements.inicio.value.trim() && !$('form-fila').elements.fim.value.trim()) { montarDepois(); return; }
    const ok = await salvarSecao(SECOES_ORDEM[n - 1], { etapa: n });
    if (ok) irPara(n + 1);
  }
}

async function montarDepois() {
  const g = (estado && estado.sessao && estado.sessao.geracao) || 0;
  try {
    await api('PUT', '/api/sessao', { etapa: 6 });
    await esperarEstado((e) => e.sessao && e.sessao.geracao > g, 8000);
    sujo.fila = false;
    await carregarSessao(true);
    irPara(7);
  } catch (e) { mostrarAviso(e.message, null, { neutro: e.status === 409 }); }
}

async function comecar() {
  const montar = !$('resumo-montar-rotulo').hidden && $('resumo-montar').checked;
  try {
    aplicarOcupado(true);
    await api('POST', '/api/sessao/concluir', { montarFila: montar });
    mostrarAviso('');
    await esperarEstado((e) => e.sessao && e.sessao.iniciada && !e.ocupado, 60000);
    history.replaceState(null, '', '#painel');
    desenharModo();
    trocarView();
  } catch (e) {
    mostrarAviso(e.message, 'concluir', { neutro: e.status === 409 });
    aplicarOcupado(!!(estado && estado.ocupado));
  }
}

// ------------------------------------------------------------------ registro
async function carregarRegistro() {
  try {
    const d = await api('GET', '/api/registro');
    const cams = (d.cameras || []).slice().sort((a, b) => numIp(a.Ip) - numIp(b.Ip));
    $('registro-titulo').textContent = d.simulado ? 'Registro da simulação' : 'Registro';
    $('registro-vazio').hidden = cams.length > 0;
    $('registro-corpo').replaceChildren(...cams.map((c) => {
      const enc = streamsEncoder(c.Encoder, false);
      const detalhe = c.Status === 'Instalada' ? '' : (c.Erro || (c.Etapa ? 'concluiu: ' + NOME_ETAPA[c.Etapa] : ''));
      return h('tr', null,
        h('td', { class: 'mono', text: c.Ip }),
        h('td', { class: 'mono', text: formatarMac(c.Mac) }),
        h('td', { text: c.Modelo || '' }),
        h('td', null, h('span', { class: 'sit ' + c.Status, text: c.Status }), detalhe ? h('span', { class: 'sit-detalhe', text: detalhe }) : null),
        h('td', { class: 'mono' }, enc ? [h('div', { text: 'Principal: ' + enc.principal }), h('div', { class: 'enc-sec', text: 'Secundário: ' + enc.secundario })] : null),
        h('td', { text: c.Local || '' }),
        h('td', { text: [c.Rack, c.Porta].filter(Boolean).join(' / ') }),
        h('td', { class: 'mono', text: c.Data || '' }));
    }));
  } catch (e) { mostrarAviso(e.message); }
}

function numIp(ip) {
  const p = String(ip || '').split('.').map(Number);
  return p.length === 4 ? ((p[0] * 256 + p[1]) * 256 + p[2]) * 256 + p[3] : 0;
}

function formatarMac(m) {
  const n = String(m || '').toLowerCase().replace(/[^0-9a-f]/g, '');
  return n.length === 12 ? n.match(/../g).join(':') : n;
}

// ------------------------------------------------------------------ senha
function mostrarSenha(ligado) {
  const f = $('form-senha').elements;
  f.senha.type = f.senha2.type = ligado ? 'text' : 'password';
  const b = $('btn-senha-mostrar');
  b.setAttribute('aria-pressed', String(ligado));
  b.textContent = ligado ? 'Ocultar' : 'Mostrar';
}

// POST /api/senha. Em simulacao, campos vazios = sem senha (nao precisa).
async function enviarSenha(form) {
  const f = form.elements;
  $('senha-erro').hidden = true;
  if (!f.senha.value && !f.senha2.value && estado && estado.simular) return true;
  if (!f.senha.value) { f.senha.focus(); mostrarErrosCampo(form, [{ campo: 'senha', msg: 'Digite a senha.' }]); return false; }
  if (f.senha.value !== f.senha2.value) {
    $('senha-erro').hidden = false;
    f.senha2.value = '';
    f.senha2.focus();
    return false;
  }
  try {
    await api('POST', '/api/senha', { senha: f.senha.value });
    form.reset();
    mostrarSenha(false);
    limparErrosCampo(form);
    marcarSalvo(form, 'Senha definida');
    mostrarAviso('');
    setTimeout(buscarEstado, 150);
    return true;
  } catch (e) { mostrarAviso(e.message); return false; }
}

function notaSenhaInstaladas() {
  // Trocar a senha no meio da fila: as ja instaladas ficam com a anterior.
  const feitas = estado && estado.fila ? (estado.fila.itens || []).filter((i) => i.Estado === 'feita').length : 0;
  const nota = $('senha-instaladas');
  nota.hidden = !(feitas && estado.senhaDefinida);
  nota.textContent = (feitas === 1 ? 'A câmera já instalada nesta fila continua' : 'As ' + feitas + ' câmeras já instaladas nesta fila continuam') +
    ' com a senha atual. Só as próximas recebem a nova.';
}

// ------------------------------------------------------------------ ligacoes
function ligar() {
  window.addEventListener('hashchange', trocarView);

  // Passo a passo.
  $('btn-avancar').addEventListener('click', avancar);
  $('btn-voltar').addEventListener('click', () => { if (passoAtual > 1) irPara(passoAtual - 1); });
  $('btn-montar-depois').addEventListener('click', montarDepois);
  $('btn-comecar').addEventListener('click', comecar);
  $('btn-usar-sessao').addEventListener('click', () => { escolhaSessao = 'usar'; sugeridoAntes = 0; irPara(7); });
  $('btn-revisar-sessao').addEventListener('click', () => { escolhaSessao = 'revisar'; sugeridoAntes = 0; irPara(2); });
  $('btn-trocar-senha').addEventListener('click', () => { trocarSenhaAberta = true; montarPasso(1); $('form-senha').elements.senha.focus(); });
  for (const b of document.querySelectorAll('#passos .passo-botao')) {
    b.addEventListener('click', () => { const n = Number(b.closest('li').dataset.passo); if (n <= passoSugerido()) irPara(n); });
  }
  // Enter num campo do passo avanca (sem submit do formulario).
  for (const secao of SECOES_ORDEM) {
    const form = $('form-' + secao);
    form.addEventListener('submit', (ev) => {
      ev.preventDefault();
      if (passoAtual > 0) { avancar(); return; }
      if (secao === 'senha') { enviarSenha(form).then((ok) => { if (ok) notaSenhaInstaladas(); }); return; }
      if (secao === 'fila') {
        const f = form.elements;
        comando('/api/fila', { inicio: f.inicio.value, fim: f.fim.value, local: f.local.value, rack: f.rack.value, andar: f.andar.value });
        sujo.fila = false;
        return;
      }
      salvarSecao(secao);
    });
    form.addEventListener('input', (ev) => {
      sujo[secao] = true;
      const ok = form.querySelector('[data-ok]'); if (ok) ok.hidden = true;
      if (secao === 'rede' || secao === 'fabrica') atualizarPlaceholdersPc();
      // Lista de bitrates so muda com resolucao ou codec.
      if (secao === 'camera') {
        if (ev.target.matches('select.lista-valor')) { escolherListaValor(ev.target); desenharAvisosCamera(); }
        else if (ev.target.tagName === 'SELECT') desenharEncoder();
        else desenharAvisosCamera();
      }
      if (secao === 'fila') desenharPrevia();
      if (secao === 'senha') $('senha-erro').hidden = true;
    });
  }
  for (const c of document.querySelectorAll('input[data-ip]')) c.addEventListener('input', () => conferirCampoIp(c));
  $('btn-placas-atualizar').addEventListener('click', () => carregarPlacas(true));
  $('btn-senha-mostrar').addEventListener('click', () => {
    mostrarSenha($('btn-senha-mostrar').getAttribute('aria-pressed') !== 'true');
  });

  // Painel.
  $('form-conectada').addEventListener('submit', (ev) => {
    ev.preventDefault();
    const f = ev.target.elements;
    comando('/api/fila/conectada', { porta: f.porta.value, canal: f.canal.value, ip: f.ip.value });
    f.porta.value = ''; f.canal.value = ''; f.ip.value = '';
    $('retomar').open = false;
  });
  $('form-vigia').addEventListener('submit', (ev) => {
    ev.preventDefault();
    const f = ev.target.elements;
    const ligado = !(estado && estado.vigia && estado.vigia.ligado);
    comando('/api/vigia', { ligado, porta: f.porta.value, canal: f.canal.value, broadcast: f.broadcast.checked });
  });
  for (const b of document.querySelectorAll('[data-decisao]')) {
    b.addEventListener('click', () => {
      const acao = b.dataset.decisao;
      const itens = (estado && estado.fila && estado.fila.itens) || [];
      if (acao === 'pular' && !confirm('Pular esta posição? A câmera fica como está agora, registrada como Falhou e fora das ' +
                                       'instaladas. A fila segue para a próxima posição.')) return;
      if (acao === 'encerrar') {
        const pend = itens.filter((i) => i.Estado === 'pendente').length;
        const resto = pend === 0 ? 'Não há outras posições pendentes.'
          : (pend === 1 ? 'A posição pendente fica sem câmera.' : 'As ' + pend + ' posições pendentes ficam sem câmera.');
        if (!confirm('Encerrar a fila? A câmera atual fica registrada como Falhou. ' + resto)) return;
      }
      comando('/api/decisao', { acao });
    });
  }
  $('btn-escolha-cancelar').addEventListener('click', () => comando('/api/escolher/cancelar'));
  $('btn-registro-atualizar').addEventListener('click', carregarRegistro);

  // Ferramentas.
  $('form-sondar').addEventListener('submit', (ev) => { ev.preventDefault(); comando('/api/sondar', { ip: ev.target.elements.ip.value }); });
  $('btn-descobrir').addEventListener('click', () => comando('/api/descobrir'));
  $('btn-verificar').addEventListener('click', () => comando('/api/verificar'));

  // Topo e Opcoes > Painel.
  $('btn-preparar').addEventListener('click', () => comando('/api/rede/preparar'));
  $('btn-restaurar').addEventListener('click', () => {
    if (confirm('Devolver a placa de rede ao estado de antes do painel? Os endereços das faixas de câmera e as rotas de host saem da placa e o DHCP volta.')) comando('/api/rede/restaurar');
  });
  $('btn-refazer').addEventListener('click', () => {
    const temFila = !!(estado && estado.fila && estado.fila.itens && estado.fila.itens.length);
    if (!confirm('Refazer o passo a passo? As telas iniciais voltam com tudo preenchido; a senha continua na memória.' +
                 (temFila ? '\n\nA fila atual fica em memória e volta ao terminar.' : ''))) return;
    escolhaSessao = '';
    comando('/api/sessao/refazer');
  });

  $('btn-atualizar').addEventListener('click', async () => {
    let texto = 'Atualizar o painel agora? Ele baixa o instalador do GitHub, confere o SHA-256, fecha e reabre sozinho na versão nova.';
    const temFila = !!(estado && estado.fila && estado.fila.itens && estado.fila.itens.length);
    texto += temFila ? '\n\nA fila em memória se perde; o registro e a sessão ficam.' : '\n\nO registro e a sessão ficam.';
    if (!confirm(texto)) return;
    try { await api('POST', '/api/atualizar', {}); mostrarAviso(''); } catch (e) { mostrarAviso(e.message, null, { neutro: e.status === 409 }); }
    setTimeout(buscarEstado, 300);
  });

  $('btn-encerrar').addEventListener('click', async () => {
    let texto = 'Encerrar o painel? A fila em memória se perde; o registro e a sessão ficam salvos.';
    if (estado && estado.fase === 'configurando') {
      texto = 'Há uma câmera sendo configurada agora. Encerrar no meio pode deixá-la sem o IP definitivo, ' +
              'e ela vai precisar ser retomada depois.\n\nEncerrar o painel mesmo assim?';
    } else if (estado && estado.ocupado) {
      texto = 'Há uma operação em andamento e ela será interrompida. A fila em memória se perde; o registro fica salvo.\n\n' +
              'Encerrar o painel mesmo assim?';
    }
    if (estado && estado.rede && estado.rede.preparada) texto += '\n\nA placa de rede volta ao DHCP sozinha.';
    if (!confirm(texto)) return;
    let r = {};
    try { r = await api('POST', '/api/encerrar', {}); } catch (_) { /* o servidor fecha junto */ }
    if (r.restaurando) $('encerrado-texto').textContent = 'Painel encerrado. A placa de rede está voltando ao DHCP (leva alguns segundos). Pode fechar esta janela.';
    $('encerrado').hidden = false;
  });
}

async function ciclo() {
  await buscarEstado();
  const rapido = estado && (estado.ocupado || estado.fase === 'configurando');
  setTimeout(ciclo, rapido ? 600 : 1500);
}

ligar();
carregarSessao();
ciclo();
