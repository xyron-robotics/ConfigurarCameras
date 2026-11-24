// Rotas por hash (direcao.md, secao 2.1): #/inicio/<passo>, #/conferir, #/painel,
// #/painel/registro, #/sessao/<secao>, #/ferramentas. Um lugar so sabe o formato
// do hash: quem navega chama ir() e quem desenha le lerRota().
import { PASSO_RESUMO } from './constantes.js';

// Abas do topo, na ordem em que aparecem.
export const ABAS = Object.freeze(['painel', 'sessao', 'ferramentas']);
export const ROTA_INICIAL = '#/painel';

// Hash de antes do redesenho (#painel, #opcoes/fila, #inicio/3): favorito ou
// link antigo cai na tela de hoje.
const APELIDOS = Object.freeze({ opcoes: 'sessao', padroes: 'sessao', fila: 'painel', registro: 'painel' });

export function lerRota() {
  const partes = (location.hash || '').replace(/^#\/?/, '').split('/').filter(Boolean);
  const tela = partes[0] || '';
  return { tela: APELIDOS[tela] || tela, parte: partes[1] || '' };
}

export function hashDe(rota) {
  return '#/' + rota.tela + (rota.parte ? '/' + rota.parte : '');
}

// Passo 7 do passo a passo e o Conferir.
export function rotaDoPasso(n) {
  return n === PASSO_RESUMO ? '#/conferir' : '#/inicio/' + n;
}

// Navega com entrada no historico; a mesma rota redesenha (o hashchange nao viria).
export function ir(hash) {
  if (location.hash === hash) window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = hash;
}

// Corrige a rota sem entrada nova no historico (apelido antigo, passo adiante do permitido).
export function corrigir(hash) {
  if (location.hash !== hash) history.replaceState(null, '', hash);
}

export function aoMudarRota(funcao) {
  window.addEventListener('hashchange', () => funcao(lerRota()));
}
