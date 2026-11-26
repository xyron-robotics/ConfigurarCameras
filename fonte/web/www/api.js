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
  // Arquivo pedido por POST (CSV da selecao, G7): o corpo vai em JSON e a
  // resposta volta em Blob. Sucesso: { ok: true, blob, nome } (nome do
  // Content-Disposition, '' sem ele). Erro: o mesmo formato de chamar.
  async function baixar(caminho, corpo) {
    try {
      const r = await transporte('POST', caminho, corpo || {}, { arquivo: true });
      if (r.status >= HTTP.OK && r.status < HTTP.REDIRECIONAMENTO && r.blob) return { ok: true, blob: r.blob, nome: r.nome || '' };
      return { ok: false, codigo: r.status, mensagem: (r.corpo && r.corpo.erro) || '', detalhe: r.corpo, semResposta: false };
    } catch (e) {
      return { ok: false, codigo: 0, mensagem: '', detalhe: String(e && e.message ? e.message : e), semResposta: true };
    }
  }
  return {
    estado: (desde) => chamar('GET', '/api/estado?desde=' + desde),
    registro: () => chamar('GET', '/api/registro'),
    copias: () => chamar('GET', '/api/registro/copias'),
    sessao: () => chamar('GET', '/api/sessao'),
    placas: () => chamar('GET', '/api/placas'),
    salvarSessao: (parcial) => chamar('PUT', '/api/sessao', parcial),
    tema: (tema) => chamar('PUT', '/api/tema', { tema }),
    comando: (rota, corpo) => chamar('POST', rota, corpo || {}),
    baixar,
  };
}

// Nome do anexo em 'attachment; filename="x.csv"'; '' sem ele.
const RE_NOME_ANEXO = /filename="([^"]+)"/;

// Adaptador do painel. Resposta sem corpo JSON vira corpo null. Com
// extra.arquivo, a resposta de sucesso vem em { blob, nome } (o erro segue em JSON).
export function transporteFetch() {
  return async (metodo, caminho, corpo, extra) => {
    const opcoes = { method: metodo };
    if (corpo !== undefined) {
      opcoes.headers = { 'content-type': 'application/json' };
      opcoes.body = JSON.stringify(corpo);
    }
    const r = await fetch(caminho, opcoes);
    if (extra && extra.arquivo && r.ok) {
      const anexo = RE_NOME_ANEXO.exec(r.headers.get('content-disposition') || '');
      return { status: r.status, corpo: null, blob: await r.blob(), nome: anexo ? anexo[1] : '' };
    }
    let dados = null;
    try { dados = await r.json(); } catch (_) { /* resposta sem corpo */ }
    return { status: r.status, corpo: dados };
  };
}
