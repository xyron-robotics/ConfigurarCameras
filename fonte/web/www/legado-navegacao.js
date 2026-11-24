// Transicao: sai nas frentes 3 a 5 do redesenho.
// Navegacao (passo a passo, Painel, Ferramentas, Sessao) e o desenho geral a
// cada estado recebido. A consulta e o ciclo moram no app.js; o formato do
// hash, no rotas.js. iniciar() registra o gancho montarPasso.
import { t } from './textos.js';
import {
  SECOES_ORDEM, PASSO_SENHA, PASSO_PLACA, PASSO_FILA, PASSO_RESUMO, TOTAL_PASSOS,
  ESPERA_SESSAO_MS, ESPERA_COMECAR_MS, HTTP, BASE_DECIMAL,
} from './constantes.js';
import { lerRota, hashDe, corrigir, rotaDoPasso, ir, ROTA_INICIAL } from './rotas.js';
import { derivar } from './estado.js';
import {
  S, ganchos, $, exigir, senhaOk, passoDe, irPara, esperarEstado, ORIGEM_DO_COMANDO, naTela,
  mostrarAviso, aplicarOcupado, anunciar, mostrarTelaFim, temFocoEmCampo,
} from './legado-estado.js';
import {
  carregarSessao, carregarPlacas, desenharResumo, enviarSenha, salvarSecao, textoDaEscolha,
} from './legado-formularios.js';
import {
  anexarLog, desenharAtualizacao, desenharFila, desenharFerramenta, carregarRegistro,
} from './legado-painel.js';

// Aba do topo -> view da marcacao de hoje (a Sessao ainda e a view de Opcoes).
const VIEW_DA_TELA = Object.freeze({ painel: 'painel', sessao: 'opcoes', ferramentas: 'ferramentas' });

// O passo a passo fica na tela enquanto faltar senha, sessao completa ou o
// "comecar" (iniciada): a regra mora no estado.js, a mesma que esconde o topo.
function precisaInicio() {
  return derivar({ estado: S.estado }).inicio;
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
  let r = lerRota();
  if (inicio) {
    const sug = passoSugerido();
    let n = r.tela === 'conferir' ? PASSO_RESUMO : parseInt(r.parte, BASE_DECIMAL);
    if ((r.tela !== 'inicio' && r.tela !== 'conferir') || !(n >= 1)) n = sug;
    n = Math.min(Math.max(1, n), sug);
    corrigir(rotaDoPasso(n));
    for (const s of document.querySelectorAll('.view')) s.hidden = s.id !== 'inicio';
    montarPasso(n);
    $('log-bloco').open = false;
    return;
  }
  if (!VIEW_DA_TELA[r.tela]) r = { tela: 'painel', parte: '' };
  // Apelido antigo (#opcoes/fila) ou tela desconhecida: a URL mostra a rota de hoje.
  corrigir(hashDe(r));
  const view = VIEW_DA_TELA[r.tela];
  montarOpcoes();
  for (const s of document.querySelectorAll('.view')) s.hidden = s.id !== 'view-' + view;
  // O log so interessa no painel; nas outras abas ele empurra o conteudo.
  $('log-bloco').open = view === 'painel';
  if (view === 'painel') {
    carregarRegistro();
    if (r.parte === 'registro') $('registro-bloco').scrollIntoView({ block: 'start' });
  }
  if (view === 'opcoes') {
    carregarSessao();
    carregarPlacas();
    if (r.parte) {
      const sec = document.querySelector('#view-opcoes .secao[data-secao="' + r.parte + '"]');
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
// O app.js consulta (GET /api/estado) e entrega a resposta aqui.
export function receberEstado(dados) {
  S.estado = dados.estado;
  // Comando na fila do worker ainda nao virou "ocupado": trata como ocupado.
  if (S.estado && dados.comandos > 0) S.estado.ocupado = true;
  if (dados.versao) $('versao-painel').textContent = t('topo.versao', { versao: dados.versao });
  desenharAtualizacao(dados.atualizacao || {}, S.estado || {});
  anexarLog(dados.log || []);
  S.cursorLog = dados.cursor;
  desenhar();
}

// Sem resposta no meio da atualizacao: o painel esta reabrindo.
export function semResposta() {
  if (S.atualizando) mostrarTelaFim('atualizando');
}

function desenhar() {
  const e = S.estado;
  if (!e || !e.fase) return;

  for (const n of document.querySelectorAll('[data-nota-simular]')) n.hidden = !e.simular;

  // Sessao regravada (secao salva, fila montada): os formularios recarregam.
  const g = (e.sessao && e.sessao.geracao) || 0;
  if (g !== S.geracaoVista) { const primeira = S.geracaoVista < 0; S.geracaoVista = g; if (!primeira) carregarSessao(true); }

  desenharModo();

  desenharFila(e);
  desenharFerramenta(e.ferramenta, e);
  if (S.passoAtual === PASSO_SENHA) montarPasso(PASSO_SENHA);

  const falas = [];
  if (S.ultimoVisto !== null && e.ultimo && e.ultimo !== S.ultimoVisto) falas.push(e.ultimo);
  S.ultimoVisto = e.ultimo || '';
  if (S.ultimaFase && S.ultimaFase !== e.fase) {
    if (lerRota().tela === 'painel' && S.modoAtual === 'normal') carregarRegistro();
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
    // O passo a passo sai do historico: voltar nao reabre o Conferir.
    corrigir(ROTA_INICIAL);
    desenharModo();
    ir(ROTA_INICIAL);
  } catch (e) {
    mostrarAviso(e.message, 'concluir', { neutro: e.status === HTTP.CONFLITO });
    aplicarOcupado(!!(S.estado && S.estado.ocupado));
  }
}

export function iniciar() {
  ganchos.montarPasso = montarPasso;
}
