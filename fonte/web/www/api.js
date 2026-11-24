// Costura com o servidor (direcao.md, secao 7.2). Unico modulo que faz fetch.
// Dois adaptadores com a mesma forma { status, corpo }: transporteFetch (este
// painel) e o falso do prototipo (docs/design/2026-11-ux/prototipo/api-falsa.js).
import { HTTP } from './constantes.js';

// Sucesso: { ok: true, dados }. Erro normalizado: { ok: false, codigo, mensagem, detalhe, semResposta }.
export function criarApi(transporte) {
  async function chamar(metodo, caminho, corpo) {
    try {
      const r = await transporte(metodo, caminho, corpo);
      if (r.status >= HTTP.OK && r.status < HTTP.REDIRECIONAMENTO) return { ok: true, dados: r.corpo };
      return { ok: false, codigo: r.status, mensagem: (r.corpo && r.corpo.erro) || '', detalhe: r.corpo, semResposta: false };
    } catch (e) {
      return { ok: false, codigo: 0, mensagem: '', detalhe: String(e && e.message ? e.message : e), semResposta: true };
    }
  }
  return {
    estado: (desde) => chamar('GET', '/api/estado?desde=' + desde),
    registro: () => chamar('GET', '/api/registro'),
    sessao: () => chamar('GET', '/api/sessao'),
    placas: () => chamar('GET', '/api/placas'),
    salvarSessao: (parcial) => chamar('PUT', '/api/sessao', parcial),
    tema: (tema) => chamar('PUT', '/api/tema', { tema }),
    comando: (rota, corpo) => chamar('POST', rota, corpo || {}),
  };
}

// Adaptador do painel. Resposta sem corpo JSON vira corpo null.
export function transporteFetch() {
  return async (metodo, caminho, corpo) => {
    const opcoes = { method: metodo };
    if (corpo !== undefined) {
      opcoes.headers = { 'content-type': 'application/json' };
      opcoes.body = JSON.stringify(corpo);
    }
    const r = await fetch(caminho, opcoes);
    let dados = null;
    try { dados = await r.json(); } catch (_) { /* resposta sem corpo */ }
    return { status: r.status, corpo: dados };
  };
}
