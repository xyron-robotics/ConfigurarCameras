// Costura com o servidor (direcao.md, secao 7.2). Unico modulo que fala com o transporte.
// Dois adaptadores: transporteFetch (produto) e criarTransporteFalso (prototipo, api-falsa.js).
import { HTTP } from './constantes.js';

// Erro normalizado: { ok: false, codigo, mensagem, detalhe, semResposta }.
export function criarApi(transporte) {
  async function chamar(metodo, caminho, corpo) {
    try {
      const r = await transporte(metodo, caminho, corpo);
      if (r.status >= HTTP.OK && r.status < HTTP.REQUISICAO_INVALIDA) return { ok: true, dados: r.corpo };
      return { ok: false, codigo: r.status, mensagem: (r.corpo && r.corpo.erro) || '', detalhe: r.corpo, semResposta: false };
    } catch (e) {
      return { ok: false, codigo: 0, mensagem: '', detalhe: String(e && e.message ? e.message : e), semResposta: true };
    }
  }
  return {
    estado: () => chamar('GET', '/api/estado'),
    registro: () => chamar('GET', '/api/registro'),
    sessao: () => chamar('GET', '/api/sessao'),
    placas: () => chamar('GET', '/api/placas'),
    salvarSessao: (parcial) => chamar('PUT', '/api/sessao', parcial),
    tema: (tema) => chamar('PUT', '/api/tema', { tema }),
    comando: (rota, corpo) => chamar('POST', rota, corpo || {}),
  };
}

// Adaptador do produto. O prototipo nunca o chama (abre por file://, sem servidor).
export function transporteFetch() {
  return async (metodo, caminho, corpo) => {
    const opcoes = { method: metodo };
    if (corpo !== undefined) {
      opcoes.headers = { 'content-type': 'application/json' };
      opcoes.body = JSON.stringify(corpo);
    }
    const r = await fetch(caminho, opcoes);
    const texto = await r.text();
    return { status: r.status, corpo: texto ? JSON.parse(texto) : null };
  };
}
