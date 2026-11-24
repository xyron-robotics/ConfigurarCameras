// Transicao: sai nas frentes 3 a 5 do redesenho.
// Navegacao (passo a passo, Painel, Ferramentas, Opcoes), consulta do estado,
// desenho geral e o ciclo de consulta. iniciar() registra os ganchos que os
// modulos de baixo usam para chamar buscarEstado e montarPasso.
import { t, nomeEtapa } from './textos.js';
import {
  SECOES_ORDEM, PASSO_SENHA, PASSO_PLACA, PASSO_FILA, PASSO_RESUMO, TOTAL_PASSOS,
  CONSULTA_MS, CONSULTA_RAPIDA_MS, ESPERA_SESSAO_MS, ESPERA_COMECAR_MS, HTTP, BASE_DECIMAL,
} from './constantes.js';
import {
  S, ganchos, $, exigir, senhaOk, passoDe, irPara, esperarEstado, ORIGEM_DO_COMANDO, naTela,
  mostrarAviso, aplicarOcupado, anunciar, mostrarTelaFim, temFocoEmCampo,
} from './legado-estado.js';
import {
  carregarSessao, carregarPlacas, desenharResumo, enviarSenha, salvarSecao, textoDaEscolha,
} from './legado-formularios.js';
import {
  anexarLog, desenharPlaca, desenharAtualizacao, desenharInternet, desenharFila, desenharFerramenta,
  carregarRegistro,
} from './legado-painel.js';

// Hash: #inicio/N (passo a passo), #painel, #ferramentas, #opcoes[/secao].
// Os antigos #fila e #registro caem no painel; #padroes em opcoes.
const VIEWS = ['painel', 'ferramentas', 'opcoes'];

export function rota() {
  const partes = (location.hash || '').slice(1).split('/');
  const mapa = { fila: 'painel', registro: 'painel', padroes: 'opcoes', '': 'painel' };
  const v = mapa[partes[0]] !== undefined ? mapa[partes[0]] : partes[0];
  return { view: v, sub: partes[1] || '' };
}

// O passo a passo fica na tela enquanto faltar senha, sessao completa ou o
// "comecar" (iniciada).
function precisaInicio() {
  if (!S.estado || !S.estado.fase) return false;
  const s = S.estado.sessao || {};
  return !senhaOk() || !s.completa || !s.iniciada;
}

// Ate onde o passo a passo deixa ir: a primeira coisa que falta.
export function passoSugerido() {
  const s = (S.estado && S.estado.sessao) || {};
  if (!senhaOk()) return PASSO_SENHA;
  if (s.completa && !S.escolhaSessao) return PASSO_SENHA;
  if (S.escolhaSessao === 'usar') return PASSO_RESUMO;
  if (!s.placa) return PASSO_PLACA;
  return Math.min(TOTAL_PASSOS, Math.max(PASSO_PLACA, (s.etapa || 0) + 1));
}

export function trocarView() {
  if (!S.estado || !S.estado.fase) return;
  const inicio = precisaInicio();
  document.body.classList.toggle('no-inicio', inicio);
  let r = rota();
  if (inicio) {
    const sug = passoSugerido();
    let n = parseInt(r.sub, BASE_DECIMAL);
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
  for (const a of document.querySelectorAll('.menu a')) {
    const ativo = a.dataset.view === r.view;
    a.classList.toggle('ativo', ativo);
    if (ativo) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
  }
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
  if (modo !== S.modoAtual || sug !== S.sugeridoAntes) {
    if (modo === 'inicio' && S.modoAtual === 'normal') { S.escolhaSessao = ''; }
    S.modoAtual = modo; S.sugeridoAntes = sug;
    trocarView();
  }
}

// Formulario de uma secao: um so exemplar, movido entre o passo e Opcoes.
function slotDe(secao, noInicio) {
  return noInicio
    ? document.querySelector('#inicio .passo[data-passo="' + passoDe(secao) + '"] .slot')
    : document.querySelector('#view-opcoes .secao[data-secao="' + secao + '"] .slot');
}

export function montarPasso(n) {
  S.passoAtual = n;
  const sug = passoSugerido();
  for (const p of document.querySelectorAll('#inicio .passo')) p.hidden = Number(p.dataset.passo) !== n;
  for (const li of document.querySelectorAll('#passos li')) {
    const k = Number(li.dataset.passo);
    li.className = k < n ? 'feito' : (k === n ? 'agora' : '');
    li.querySelector('button').disabled = k > sug;
    if (k === n) li.setAttribute('aria-current', 'step'); else li.removeAttribute('aria-current');
  }
  for (const secao of SECOES_ORDEM) {
    const form = $('form-' + secao);
    const alvo = slotDe(secao, passoDe(secao) === n);
    if (form.parentElement !== alvo) alvo.append(form);
  }
  $('passo-n').textContent = t('inicio.passo-n', { n, total: TOTAL_PASSOS });
  $('btn-voltar').hidden = n === PASSO_SENHA;
  $('btn-montar-depois').hidden = n !== PASSO_FILA;
  $('btn-comecar').hidden = n !== PASSO_RESUMO;
  $('btn-avancar').hidden = n === PASSO_RESUMO;
  $('btn-avancar').textContent = n === PASSO_SENHA ? t('inicio.avancar-senha')
    : (n === PASSO_FILA ? t('inicio.avancar-fila') : t('inicio.btn-avancar'));

  if (n === PASSO_SENHA) {
    const s = S.estado.sessao || {};
    const temEscolha = senhaOk() && s.completa && !S.escolhaSessao;
    $('passo-escolha').hidden = !temEscolha;
    if (temEscolha) $('escolha-texto').textContent = textoDaEscolha(s);
    $('senha-definida').hidden = !senhaOk();
    $('form-senha').hidden = senhaOk() && !S.trocarSenhaAberta;
    // Senha ja definida e sem a escolha da sessao: o rodape ainda avanca
    // (sem ele o passo 1 so tinha saida pelas abas).
    const senhaFechada = senhaOk() && !S.trocarSenhaAberta;
    $('btn-avancar').hidden = senhaFechada && temEscolha;
    if (senhaFechada) $('btn-avancar').textContent = t('inicio.btn-avancar');
  }
  if (n === PASSO_PLACA) carregarPlacas();
  if (n >= PASSO_PLACA && n <= PASSO_FILA) carregarSessao();
  if (n === PASSO_RESUMO) { carregarSessao(); desenharResumo(); }
  const foco = document.querySelector('#inicio .passo:not([hidden]) input:not([type="hidden"]):not([disabled]), #inicio .passo:not([hidden]) select');
  if (foco && !temFocoEmCampo()) foco.focus({ preventScroll: true });
}

function montarOpcoes() {
  S.passoAtual = 0;
  for (const secao of SECOES_ORDEM) {
    const form = $('form-' + secao);
    const alvo = slotDe(secao, false);
    if (form.parentElement !== alvo) alvo.append(form);
  }
  $('form-senha').hidden = false;
}

// ------------------------------------------------------------------ estado
export function buscarEstado() {
  if (S.buscando) return S.buscando;
  S.buscando = (async () => {
    let dados;
    try {
      dados = await exigir(S.api.estado(S.cursorLog));
    } catch (e) {
      if (S.atualizando) { mostrarTelaFim('atualizando'); return; }
      $('placa-texto').textContent = t('barra.sem-resposta');
      $('placa-luz').className = 'luz falta';
      return;
    }
    S.estado = dados.estado;
    // Comando na fila do worker ainda nao virou "ocupado": trata como ocupado.
    if (S.estado && dados.comandos > 0) S.estado.ocupado = true;
    if (dados.versao) $('versao-painel').textContent = t('topo.versao', { versao: dados.versao });
    desenharAtualizacao(dados.atualizacao || {}, S.estado || {});
    anexarLog(dados.log || []);
    S.cursorLog = dados.cursor;
    desenhar();
  })().finally(() => { S.buscando = null; });
  return S.buscando;
}

function desenhar() {
  const e = S.estado;
  if (!e || !e.fase) return;

  // topo
  $('faixa-simular').hidden = !e.simular;
  document.title = (e.simular ? t('topo.prefixo-simulacao') : '') + t('topo.marca');
  for (const n of document.querySelectorAll('[data-nota-simular]')) n.hidden = !e.simular;
  $('faixa-falha').textContent = e.simular && e.falharEm ? t('topo.falha-forcada', { etapa: nomeEtapa(e.falharEm) }) : '';
  desenharPlaca(e.rede || {});
  desenharInternet(e.internet || {}, e.rede || {});

  // Sessao regravada (secao salva, fila montada): os formularios recarregam.
  const g = (e.sessao && e.sessao.geracao) || 0;
  if (g !== S.geracaoVista) { const primeira = S.geracaoVista < 0; S.geracaoVista = g; if (!primeira) carregarSessao(true); }

  desenharModo();
  $('btn-preparar').hidden = S.modoAtual !== 'normal' || !!(e.rede && (e.rede.ok || e.rede.semSessao));

  desenharFila(e);
  desenharFerramenta(e.ferramenta, e);
  if (S.passoAtual === PASSO_SENHA) montarPasso(PASSO_SENHA);

  const falas = [];
  if (S.ultimoVisto !== null && e.ultimo && e.ultimo !== S.ultimoVisto) falas.push(e.ultimo);
  S.ultimoVisto = e.ultimo || '';
  if (S.ultimaFase && S.ultimaFase !== e.fase) {
    if (rota().view === 'painel' && S.modoAtual === 'normal') carregarRegistro();
    // Falha de camera do cartao: quem anuncia e a linha de estado do cartao.
    if (e.fase === 'decisao' && e.falha && !$('bancada-decisao').hidden) {
      falas.push($('decisao-titulo').textContent + '. ' + e.falha.erro);
      S.focarTentar = true;
    }
    else if (e.fase === 'concluida') falas.push(t('anuncio.fila-concluida'));
    else if (e.fase === 'encerrada') falas.push(t('anuncio.fila-encerrada'));
  }
  if (falas.length) anunciar(falas.join(' '));
  S.ultimaFase = e.fase;

  aplicarOcupado(!!e.ocupado);
  // Senha recusada: "Tentar de novo" fica travado ate uma senha mais nova
  // (o servidor tambem recusa; repetir gastaria o lockout da camera).
  const tentar = document.querySelector('[data-decisao="tentar"]');
  if (e.fase === 'decisao' && e.falha && e.falha.loginRecusado && e.falha.geracao === e.senhaGeracao) tentar.disabled = true;
  // O foco vai para "Tentar de novo" quando o botao ja estiver ativo.
  if (e.fase !== 'decisao') S.focarTentar = false;
  if (S.focarTentar && !tentar.disabled && naTela(tentar)) { tentar.focus(); S.focarTentar = false; }

  // O slot do aviso depende de qual bloco esta na tela.
  if (e.avisoN !== S.avisoN) {
    S.avisoN = e.avisoN;
    if (e.aviso) mostrarAviso(e.aviso, ORIGEM_DO_COMANDO[e.avisoOrigem], { servidor: true });
    // Aviso que manda retomar: abre o bloco que ele cita.
    if (e.aviso && e.aviso.includes(t('painel.retomar.abrir'))) $('retomar').open = true;
  } else if (!e.aviso && S.avisoDoServidor) {
    mostrarAviso('');
  }
}

// ------------------------------------------------------------------ passo a passo (acoes)
export async function avancar() {
  const n = S.passoAtual;
  if (n === PASSO_SENHA) {
    if (senhaOk() && !S.trocarSenhaAberta) { irPara(PASSO_PLACA); return; }
    const ok = await enviarSenha($('form-senha'));
    if (!ok) return;
    S.trocarSenhaAberta = false;
    await esperarEstado((e) => e.senhaDefinida);
    const s = (S.estado && S.estado.sessao) || {};
    if (s.completa && !S.escolhaSessao) { montarPasso(PASSO_SENHA); return; }
    irPara(passoSugerido());
    return;
  }
  if (n >= PASSO_PLACA && n <= PASSO_FILA) {
    const fila = $('form-fila').elements;
    if (n === PASSO_FILA && !fila.inicio.value.trim() && !fila.fim.value.trim()) { montarDepois(); return; }
    const ok = await salvarSecao(SECOES_ORDEM[n - 1], { etapa: n });
    if (ok) irPara(n + 1);
  }
}

export async function montarDepois() {
  const g = (S.estado && S.estado.sessao && S.estado.sessao.geracao) || 0;
  try {
    await exigir(S.api.salvarSessao({ etapa: PASSO_FILA }));
    await esperarEstado((e) => e.sessao && e.sessao.geracao > g, ESPERA_SESSAO_MS);
    S.sujo.fila = false;
    await carregarSessao(true);
    irPara(PASSO_RESUMO);
  } catch (e) { mostrarAviso(e.message, null, { neutro: e.status === HTTP.CONFLITO }); }
}

export async function comecar() {
  const montar = !$('resumo-montar-rotulo').hidden && $('resumo-montar').checked;
  try {
    aplicarOcupado(true);
    await exigir(S.api.comando('/api/sessao/concluir', { montarFila: montar }));
    mostrarAviso('');
    await esperarEstado((e) => e.sessao && e.sessao.iniciada && !e.ocupado, ESPERA_COMECAR_MS);
    history.replaceState(null, '', '#painel');
    desenharModo();
    trocarView();
  } catch (e) {
    mostrarAviso(e.message, 'concluir', { neutro: e.status === HTTP.CONFLITO });
    aplicarOcupado(!!(S.estado && S.estado.ocupado));
  }
}

export async function ciclo() {
  await buscarEstado();
  const rapido = S.estado && (S.estado.ocupado || S.estado.fase === 'configurando');
  setTimeout(ciclo, rapido ? CONSULTA_RAPIDA_MS : CONSULTA_MS);
}

export function iniciar() {
  ganchos.buscarEstado = buscarEstado;
  ganchos.montarPasso = montarPasso;
}
