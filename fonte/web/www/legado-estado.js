// Transicao: sai nas frentes 4 e 5 do redesenho.
// Base dos modulos legado-*: o estado mutavel compartilhado (so aqui, no
// objeto S), a ponte com a api.js e os ajudantes que todos usam. Nao importa
// nenhum outro legado-*: o que precisa de modulo de cima passa por ganchos.
import { h } from './dom.js';
import { t } from './textos.js';
import {
  HTTP, RE_IP, ESPERA_ESTADO_MS, ESPERA_ESTADO_PASSO_MS,
  AVISO_NEUTRO_MS, ANUNCIO_ATRASO_MS, CONSULTA_APOS_COMANDO_MS,
} from './constantes.js';

export const S = {
  api: null,
  cursorLog: 0,
  estado: null,
  ultimaFase: '',
  // Leitor de tela: so as transicoes (instalada, falhou, fim).
  ultimoVisto: null,
  avisoN: -1,
  avisoDoServidor: false,
  timerAviso: 0,
  modoAtual: '',
  // Atualizacao em curso: o servidor some no meio (fecha para instalar) e isso
  // nao e erro; a tela de "atualizando" fica.
  atualizando: false,
  buscando: null,
  ferramentaChave: '',
};

// Funcoes dos modulos de cima, registradas pelo app.js.
export const ganchos = {
  buscarEstado: () => Promise.resolve(),
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
// O aviso aparece junto do formulario que o causou (o primeiro data-aviso-de
// dele que estiver na tela); se nenhum estiver, na faixa do topo.
const ORIGEM_DA_ROTA = {
  '/api/fila': 'fila', '/api/fila/conectada': 'conectada',
  '/api/decisao': 'conectada', '/api/vigia': 'vigia', '/api/sondar': 'sondar', '/api/descobrir': 'descobrir',
  '/api/verificar': 'verificar',
};
export const ORIGEM_DO_COMANDO = {
  fila: 'fila', conectada: 'conectada', decisao: 'conectada',
  vigia: 'vigia', sondar: 'sondar', descobrir: 'descobrir', verificar: 'verificar',
  'sessao-concluir': 'concluir',
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
  const slot = origem ? [...document.querySelectorAll('[data-aviso-de="' + origem + '"]')].find(naTela) : null;
  const a = slot || $('aviso');
  a.textContent = texto;
  a.classList.toggle('neutro', !!o.neutro);
  a.hidden = false;
  if (o.neutro) S.timerAviso = setTimeout(() => { a.hidden = true; }, AVISO_NEUTRO_MS);
}

// Devolve true se o servidor aceitou. -opcoes.semTrava: quem chama trava os
// proprios botoes (decisao de uma linha nao trava as outras linhas).
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
// ficam sempre ativos; o Configurar sem vigia trava pelo modelo (tela-painel.js). Os botoes de decisao das linhas da tabela tambem ficam
// fora: o servidor aceita decisao com o worker ocupado, e cada linha trava os seus.
export function aplicarOcupado(ocupado) {
  const simular = !!(S.estado && S.estado.simular);
  const sel = '#view-ferramentas .btn';
  for (const b of document.querySelectorAll(sel)) {
    b.disabled = ocupado || (simular && b.hasAttribute('data-so-real'));
  }
}

// urgente: a regiao assertive (falha nova de camera, P3); o resto vai na polite.
export function anunciar(texto, urgente) {
  const a = $(urgente ? 'anuncio-urgente' : 'anuncio');
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
