// Rotas por hash (direcao.md, secao 7.2): #/inicio/<passo>, #/conferir, #/painel,
// #/painel/registro, #/sessao/<secao>, #/ferramentas. Sem servidor: funciona em file://.

export function lerRota() {
  const partes = (location.hash || '').replace(/^#\/?/, '').split('/').filter(Boolean);
  return { tela: partes[0] || '', parte: partes[1] || '' };
}

export function ir(rota) {
  if (location.hash === rota) window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = rota;
}

export function aoMudarRota(funcao) {
  window.addEventListener('hashchange', () => funcao(lerRota()));
}
