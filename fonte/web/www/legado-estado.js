// Transicao: sai nas frentes 3 a 5 do redesenho.
// Base dos modulos legado-*: o estado mutavel compartilhado (so aqui, no
// objeto S), a ponte com a api.js e os ajudantes que todos usam. Nao importa
// nenhum outro legado-*: o que precisa de modulo de cima passa por ganchos.
import { h } from './dom.js';
import { t } from './textos.js';
import { numero } from './formato.js';
import { ir, rotaDoPasso } from './rotas.js';
import {
  HTTP, NBSP, RE_IP, SECOES_ORDEM, ESPERA_ESTADO_MS, ESPERA_ESTADO_PASSO_MS,
  AVISO_NEUTRO_MS, ANUNCIO_ATRASO_MS, CONSULTA_APOS_COMANDO_MS,
} from './constantes.js';

export const S = {
  api: null,
  cursorLog: 0,
  estado: null,
  ultimaFase: '',
  ipFabrica: '',
  // Leitor de tela: so as transicoes (instalada, falhou, fim).
  ultimoVisto: null,
  focarTentar: false,
  avisoN: -1,
  avisoDoServidor: false,
  timerAviso: 0,
  modoAtual: '',
  passoAtual: 0,
  sugeridoAntes: 0,
  // Sessao completa ao abrir: "Usar" (vai ao resumo) ou "Revisar" (passo 2).
  escolhaSessao: '',
  trocarSenhaAberta: false,
  // Atualizacao em curso: o servidor some no meio (fecha para instalar) e isso
  // nao e erro; a tela de "atualizando" fica.
  atualizando: false,
  geracaoVista: -1,
  buscando: null,
  // Valores prontos do encoder (GET /api/sessao): fps, degraus de bitrate,
  // faixa por resolucao e o que a camera de referencia aceitou ou recusou.
  catalogo: null,
  // sessaoCache = o que esta em sessao.json; sujo[secao] = o operador mexeu e
  // ainda nao salvou (o polling nao escreve por cima).
  sessaoCache: null,
  listasCarregadas: false,
  carregandoSessao: null,
  sujo: {},
  placasCache: null,
  placasPedido: null,
  ferramentaChave: '',
  // Um cartao por camera de cameras[], chave no MAC.
  cartoes: new Map(),
};

// Funcoes dos modulos de cima, registradas por legado-navegacao.iniciar().
export const ganchos = {
  buscarEstado: () => Promise.resolve(),
  montarPasso: () => {},
};

export const $ = (id) => document.getElementById(id);

export function usarApi(api) {
  S.api = api;
}

// Resultado da api.js no formato que o codigo legado espera: devolve os dados
// ou lanca Error com a mensagem do servidor, .status e .dados.
export async function exigir(pedido) {
  const r = await pedido;
  if (r.ok) return r.dados || {};
  if (r.semResposta) throw new Error(r.detalhe);
  const erro = new Error(r.mensagem || t('erro.http', { codigo: r.codigo }));
  erro.dados = r.detalhe || {};
  erro.status = r.codigo;
  throw erro;
}

export function senhaOk() { return !!(S.estado && (S.estado.senhaDefinida || S.estado.simular)); }

export function passoDe(secao) { return SECOES_ORDEM.indexOf(secao) + 1; }

export function irPara(n) {
  ir(rotaDoPasso(n));
}

// Espera o estado publicado satisfazer a condicao (ate -ms); devolve true se deu.
export async function esperarEstado(cond, ms) {
  const fim = Date.now() + (ms || ESPERA_ESTADO_MS);
  while (Date.now() < fim) {
    await ganchos.buscarEstado();
    if (S.estado && cond(S.estado)) return true;
    await new Promise((r) => setTimeout(r, ESPERA_ESTADO_PASSO_MS));
  }
  return false;
}

// ------------------------------------------------------------------ avisos
// O aviso aparece junto do formulario que o causou (data-aviso-de); se ele
// nao estiver na tela, na faixa do topo.
const ORIGEM_DA_ROTA = {
  '/api/fila': 'fila', '/api/fila/conectada': 'conectada',
  '/api/decisao': 'conectada', '/api/vigia': 'vigia', '/api/sondar': 'sondar', '/api/descobrir': 'descobrir',
  '/api/verificar': 'verificar', '/api/rede/restaurar': 'painel', '/api/sessao/refazer': 'painel',
};
export const ORIGEM_DO_COMANDO = {
  fila: 'fila', conectada: 'conectada', decisao: 'conectada',
  vigia: 'vigia', sondar: 'sondar', descobrir: 'descobrir', verificar: 'verificar',
  'rede-restaurar': 'painel', 'sessao-refazer': 'painel', 'sessao-concluir': 'concluir',
};
// Rotas que o servidor aceita mesmo ocupado: nao travam os botoes.
const ROTA_SEMPRE = ['/api/senha', '/api/vigia', '/api/camera'];

export function naTela(el) {
  for (let n = el; n; n = n.parentElement) if (n.hidden) return false;
  return true;
}

export function mostrarAviso(texto, origem, opcoes) {
  const o = opcoes || {};
  clearTimeout(S.timerAviso);
  S.avisoDoServidor = !!(texto && o.servidor);
  for (const a of [$('aviso'), ...document.querySelectorAll('[data-aviso-de]')]) { a.hidden = true; a.textContent = ''; }
  if (!texto) return;
  const slot = origem ? document.querySelector('[data-aviso-de="' + origem + '"]') : null;
  const a = slot && naTela(slot) ? slot : $('aviso');
  a.textContent = texto;
  a.classList.toggle('neutro', !!o.neutro);
  a.hidden = false;
  if (o.neutro) S.timerAviso = setTimeout(() => { a.hidden = true; }, AVISO_NEUTRO_MS);
}

// Devolve true se o servidor aceitou. -opcoes.semTrava: quem chama trava os
// proprios botoes (decisao de um cartao nao trava os outros cartoes).
export async function comando(caminho, corpo, opcoes) {
  const origem = ORIGEM_DA_ROTA[caminho];
  // Trava otimista: o estado "ocupado" so chega no proximo polling.
  if (!ROTA_SEMPRE.includes(caminho) && !(opcoes && opcoes.semTrava)) aplicarOcupado(true);
  let ok = false;
  try {
    await exigir(S.api.comando(caminho, corpo));
    mostrarAviso('');
    ok = true;
  } catch (e) {
    if (e.status === HTTP.CONFLITO) mostrarAviso(e.message, origem, { neutro: true });
    else mostrarAviso(e.message, origem);
  }
  setTimeout(ganchos.buscarEstado, CONSULTA_APOS_COMANDO_MS);
  return ok;
}

// Botoes de trabalho ficam desligados enquanto o worker trabalha. Encerrar o
// painel, encerrar a fila e o vigia (desligar vale no meio de uma camera)
// ficam sempre ativos. Os botoes de decisao dos cartoes tambem ficam fora: o
// servidor aceita decisao com o worker ocupado, e cada cartao trava os seus.
export function aplicarOcupado(ocupado) {
  const simular = !!(S.estado && S.estado.simular);
  const sel = '#view-ferramentas .btn, #btn-restaurar, #btn-refazer, #form-conectada .btn, ' +
              '[data-decisao], #btn-avancar, #btn-comecar, #btn-montar-depois, ' +
              '#btn-usar-sessao, #btn-revisar-sessao, .secao-form .btn[type="submit"]';
  for (const b of document.querySelectorAll(sel)) {
    b.disabled = ocupado || (simular && b.hasAttribute('data-so-real'));
  }
}

export function anunciar(texto) {
  const a = $('anuncio');
  a.textContent = '';
  if (texto) setTimeout(() => { a.textContent = texto; }, ANUNCIO_ATRASO_MS);
}

// Tela de fim (#encerrado, #atualizando): mostra e leva o foco so na primeira
// vez, para o poll seguinte nao roubar o foco de novo.
export function mostrarTelaFim(id) {
  const el = $(id);
  if (!el.hidden) return;
  el.hidden = false;
  el.focus();
}

export function temFocoEmCampo() {
  const a = document.activeElement;
  return a && (a.tagName === 'INPUT' || a.tagName === 'SELECT' || a.tagName === 'TEXTAREA');
}

export function barraProgresso(p, rotulo) {
  return h('progress', { value: p.atual, max: p.total, 'aria-label': rotulo || t('geral.progresso') });
}

export const ipValido = (v) => RE_IP.test(String(v).trim());

export function conferirCampoIp(campo) {
  const v = campo.value.trim();
  campo.setCustomValidity(v && !ipValido(v) ? t('campo.ip-invalido') : '');
}

// Uma linha por stream: "1920 × 1080, 20 fps, 1596 kbps, H.264", sem os campos vazios.
export function textoStream(res, fps, kbps, codec, gop) {
  return [res ? String(res).replace('x', t('formato.vezes')) : '', fps ? numero(fps) + NBSP + t('unidade.fps') : '',
    kbps ? numero(kbps) + NBSP + t('unidade.kbps') : '', codec || '',
    gop ? t('encoder.gop', { gop }) : ''].filter(Boolean).join(', ');
}

export function streamsEncoder(en, comGop) {
  if (!en) return null;
  return {
    principal: textoStream(en.Resolucao, en.FpsPrincipal, en.BitratePrincipal, en.CodecPrincipal, comGop && en.GopPrincipal),
    secundario: textoStream(en.ResolucaoSecundario, en.FpsSecundario, en.BitrateSecundario, en.CodecSecundario, comGop && en.GopSecundario),
  };
}
