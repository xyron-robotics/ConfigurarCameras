// Transicao: sai nas frentes 3 a 5 do redesenho.
// As 6 secoes da sessao (senha, placa, rede, fabrica, camera, fila): leitura,
// escrita, erros de campo, listas do encoder, placas, resumo e senha. Um
// exemplar de cada formulario, movido entre o passo e Opcoes pela navegacao.
import { h } from './dom.js';
import { t } from './textos.js';
import { numero, dataCurta, hora, ipParaNumero, resolucao } from './formato.js';
import {
  HTTP, SECOES_ORDEM, SESSAO_PADRAO, ESPERA_SESSAO_MS, CONSULTA_APOS_COMANDO_MS,
  FILA_MAX_ENDERECOS, PASSO_SENHA, PASSO_RESUMO,
} from './constantes.js';
import {
  S, ganchos, $, exigir, senhaOk, passoDe, mostrarAviso, aplicarOcupado, esperarEstado,
  ipValido, conferirCampoIp, textoStream,
} from './legado-estado.js';

export const STREAMS = {
  principal: { nome: t('encoder.stream-principal'), res: 'Resolucao', fps: 'FpsPrincipal', br: 'BitRate', codec: 'CodecPrincipal', faixa: 'faixa-principal' },
  secundario: { nome: t('encoder.stream-secundario'), res: 'ResolucaoSecundario', fps: 'FpsSecundario', br: 'BitRateSecundario', codec: 'CodecSecundario', faixa: 'faixa-secundario' },
};

const SECOES = {
  senha: {
    ler() { return null; },
    escrever() { },
  },
  placa: {
    ler(form) {
      const r = form.querySelector('input[name="placa"]:checked');
      if (!r) return { erro: [{ campo: 'placa', msg: t('placas.escolha') }] };
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
      n.textContent = t('fila.ultima', { inicio: u.Inicio, fim: u.Fim, quando: u.Quando ? dataCurta(u.Quando) : '' });
      n.hidden = false;
      desenharPrevia();
    },
  },
};

// GET /api/sessao: preenche as listas (uma vez) e os formularios nao sujos.
export function carregarSessao(forcar) {
  if (S.carregandoSessao) return S.carregandoSessao;
  if (S.sessaoCache && !forcar) { preencherFormularios(); return Promise.resolve(S.sessaoCache); }
  S.carregandoSessao = (async () => {
    try {
      const d = await exigir(S.api.sessao());
      if (!S.listasCarregadas) {
        const el = $('form-camera').elements;
        const opcoes = (sel, lista, texto) => sel.replaceChildren(...lista.map((v) => h('option', { value: v }, texto(v))));
        S.catalogo = d.catalogo;
        const marca = (stream, tipo, fn) => (v) => fn(v) + marcaTestado(stream, tipo, v);
        opcoes(el.Resolucao, d.resolucoes, marca('principal', 'resolucoes', resolucao));
        opcoes(el.ResolucaoSecundario, d.resolucoesSecundario, marca('secundario', 'resolucoes', resolucao));
        opcoes(el.CodecPrincipal, d.codecs, marca('principal', 'codecs', String));
        opcoes(el.CodecSecundario, d.codecs, marca('secundario', 'codecs', String));
        for (const s of Object.values(STREAMS)) montarListaValor(listaDoCampo(s.fps), S.catalogo.fps);
        S.listasCarregadas = true;
      }
      // Sem arquivo ainda: os campos ficam com o que o servidor considera fabrica.
      S.sessaoCache = d.sessao || structuredClone(SESSAO_PADRAO);
      S.ipFabrica = S.sessaoCache.IpFabrica;
      preencherFormularios();
      if (S.passoAtual === PASSO_RESUMO) desenharResumo();
      if (S.passoAtual === PASSO_SENHA) ganchos.montarPasso(PASSO_SENHA);
    } catch (e) { mostrarAviso(e.message); }
    return S.sessaoCache;
  })().finally(() => { S.carregandoSessao = null; });
  return S.carregandoSessao;
}

function preencherFormularios() {
  if (!S.sessaoCache) return;
  for (const secao of SECOES_ORDEM) {
    if (S.sujo[secao]) continue;
    const form = $('form-' + secao);
    SECOES[secao].escrever(form, S.sessaoCache);
    for (const c of form.querySelectorAll('input[data-ip]')) conferirCampoIp(c);
    limparErrosCampo(form);
  }
}

// O "vazio = ..." dos IPs do PC segue o IP de fabrica e o gateway digitados.
export function atualizarPlaceholdersPc() {
  const rede = $('form-rede').elements;
  const fab = $('form-fabrica').elements;
  const ipf = fab.IpFabrica.value.trim();
  const gw = rede.Gateway.value.trim();
  fab.IpPcFabrica.placeholder = t('opcoes.exemplo-pc-fabrica', { ip: ipValido(ipf) ? ipf.replace(/\.\d+$/, '.220') : '' });
  rede.IpPcCameras.placeholder = t('opcoes.exemplo-pc-cameras', { inicio: ipValido(gw) ? gw.replace(/\.\d+$/, '.200') : '' });
}

export function limparErrosCampo(form) {
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
    const lista = marcados > 0 ? [t('form.nada-salvo', { marcados }), ...soltos] : soltos;
    ul.replaceChildren(...lista.map((texto) => h('li', null, texto)));
    ul.hidden = !lista.length;
  }
  if (primeiro && primeiro.focus) primeiro.focus();
}

function recusadoNaReferencia(stream, tipo, v) {
  return !!S.catalogo && S.catalogo.recusado[stream][tipo].includes(v);
}

function marcaTestado(stream, tipo, v) {
  if (!S.catalogo) return '';
  if (recusadoNaReferencia(stream, tipo, v)) return t('encoder.recusado-na', { modelo: S.catalogo.modelo });
  return S.catalogo.testado[stream][tipo].includes(v) ? t('encoder.testado') : t('encoder.nao-testado');
}

// Faixa usual do bitrate para a resolucao e o codec escolhidos no stream.
function faixaDoStream(stream) {
  const f = $('form-camera').elements;
  const s = STREAMS[stream];
  const fx = S.catalogo && S.catalogo.faixas[f[s.res].value];
  return fx ? { min: fx.min, max: fx.max, rec: fx[f[s.codec].value], res: f[s.res].value, codec: f[s.codec].value } : null;
}

// Degraus de bitrate dentro da faixa, com o recomendado marcado.
function desenharBitrates(stream) {
  if (!S.catalogo) return;
  const s = STREAMS[stream];
  const fx = faixaDoStream(stream);
  const valores = fx ? S.catalogo.bitrates.filter((v) => v >= fx.min && v <= fx.max) : S.catalogo.bitrates;
  montarListaValor(listaDoCampo(s.br), valores, (v) => (fx && v === fx.rec ? t('encoder.recomendado', { v }) : String(v)));
  $(s.faixa).textContent = fx
    ? t('encoder.faixa', { res: resolucao(fx.res), codec: fx.codec, min: numero(fx.min), max: numero(fx.max), rec: numero(fx.rec) })
    : '';
}

export function desenharEncoder() {
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
  sel.replaceChildren(...valores.map((v) => h('option', { value: String(v) }, rotulo ? rotulo(v) : String(v))),
    h('option', { value: OUTRO_VALOR }, t('encoder.outro-valor')));
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

export function escolherListaValor(sel) {
  const campo = $('form-camera').elements[sel.dataset.para];
  if (sel.value === OUTRO_VALOR) { campo.hidden = false; campo.focus(); campo.select(); return; }
  campo.value = sel.value;
  campo.hidden = true;
}

// Nao bloqueiam o salvamento: so chamam a atencao.
export function desenharAvisosCamera() {
  const f = $('form-camera').elements;
  const lista = [];
  for (const stream of Object.keys(STREAMS)) {
    const s = STREAMS[stream];
    const fx = faixaDoStream(stream);
    const br = Number(f[s.br].value);
    if (fx && f[s.br].value !== '' && (br < fx.min || br > fx.max)) {
      lista.push(t('encoder.aviso-fora-da-faixa', { stream: s.nome, br: numero(br), res: resolucao(fx.res), codec: fx.codec, min: numero(fx.min), max: numero(fx.max) }));
    }
    for (const [tipo, campo, texto] of [['resolucoes', s.res, resolucao], ['codecs', s.codec, String]]) {
      if (recusadoNaReferencia(stream, tipo, f[campo].value)) {
        lista.push(t('encoder.aviso-recusado', { modelo: S.catalogo.modelo, valor: texto(f[campo].value), stream: s.nome }));
      }
    }
  }
  if (Number(f.BitRateSecundario.value) > Number(f.BitRate.value)) lista.push(t('encoder.aviso-bitrate-secundario'));
  if (Number(f.FpsSecundario.value) > Number(f.FpsPrincipal.value)) lista.push(t('encoder.aviso-fps-secundario'));
  const ul = $('camera-avisos');
  ul.replaceChildren(...lista.map((texto) => h('li', null, texto)));
  ul.hidden = !lista.length;
}

function marcarSalvo(form, texto) {
  const ok = form.querySelector('[data-ok]');
  if (!ok) return;
  ok.textContent = t('form.salvo-as', { texto: texto || t('form.salvo'), hora: hora(new Date()) });
  ok.hidden = false;
}

// PUT /api/sessao com a secao: 400 marca os campos; 409 precisaConfirmar
// pergunta e reenvia; 409 "aguarde" vira aviso neutro. Devolve true se gravou.
export async function salvarSecao(secao, opcoes) {
  const o = opcoes || {};
  const form = $('form-' + secao);
  limparErrosCampo(form);
  const lido = SECOES[secao].ler(form);
  if (lido && lido.erro) { mostrarErrosCampo(form, lido.erro); return false; }
  const corpo = lido || {};
  if (o.etapa) corpo.etapa = o.etapa;
  if (secao === 'placa') {
    const r = form.querySelector('input[name="placa"]:checked');
    if (r && r.dataset.rota === '1' && !confirm(t('placas.confirmar-internet', { nome: r.dataset.nome }))) return false;
  }
  const g = (S.estado && S.estado.sessao && S.estado.sessao.geracao) || 0;
  // Limpa antes, nao depois: o worker pode avisar algo durante a gravacao
  // (fila descartada) e esse aviso tem que ficar na tela.
  mostrarAviso('');
  for (let tentativa = 0; tentativa < 2; tentativa++) {
    try {
      aplicarOcupado(true);
      await exigir(S.api.salvarSessao(corpo));
      await esperarEstado((e) => e.sessao && e.sessao.geracao > g, ESPERA_SESSAO_MS);
      S.sujo[secao] = false;
      await carregarSessao(true);
      marcarSalvo(form, secao === 'fila' ? t('fila.faixa-guardada') : t('form.salvo'));
      return true;
    } catch (e) {
      if (e.status === HTTP.CONFLITO && e.dados && e.dados.precisaConfirmar && tentativa === 0) {
        if (!confirm(e.dados.erro)) return false;
        corpo.confirmar = true;
        continue;
      }
      if (e.status === HTTP.REQUISICAO_INVALIDA && e.dados && e.dados.campos) { mostrarErrosCampo(form, e.dados.campos); return false; }
      if (e.status === HTTP.REQUISICAO_INVALIDA) { mostrarErrosCampo(form, [], e.dados.erros || [e.message]); return false; }
      mostrarAviso(e.message, null, { neutro: e.status === HTTP.CONFLITO });
      return false;
    } finally { aplicarOcupado(!!(S.estado && S.estado.ocupado)); }
  }
  return false;
}

// ------------------------------------------------------------------ placas
export function carregarPlacas(forcar) {
  if (S.placasPedido) return S.placasPedido;
  if (S.placasCache && !forcar) { desenharPlacas(); return Promise.resolve(S.placasCache); }
  S.placasPedido = (async () => {
    try {
      S.placasCache = await exigir(S.api.placas());
      desenharPlacas();
    } catch (e) { mostrarAviso(e.message); }
    return S.placasCache;
  })().finally(() => { S.placasPedido = null; });
  return S.placasPedido;
}

function desenharPlacas() {
  const ul = $('placas');
  if (!S.placasCache) { ul.replaceChildren(h('li', { class: 'apoio' }, t('placas.lendo'))); return; }
  const escolhidaAntes = ul.querySelector('input[name="placa"]:checked');
  const naSessao = S.sessaoCache && S.sessaoCache.Placa ? Number(S.sessaoCache.Placa.IfIndex) : 0;
  const marcar = escolhidaAntes ? Number(escolhidaAntes.value) : (naSessao || S.placasCache.sugerida || 0);
  const placas = S.placasCache.placas || [];
  if (!placas.length) {
    ul.replaceChildren(h('li', { class: 'apoio' }, t('placas.nenhuma')));
    $('placas-nota').hidden = true;
    return;
  }
  ul.replaceChildren(...placas.map((p) => {
    const wifi = p.tipo === 'wifi';
    const detalhes = [wifi ? t('placas.wifi') : t('placas.ethernet'),
      p.cabo ? (wifi ? t('placas.conectada') : t('placas.cabo-conectado')) : (wifi ? t('placas.desconectada') : t('placas.sem-cabo')),
      p.ips && p.ips.length ? p.ips.join(', ') : t('placas.sem-ip'), p.dhcp ? t('placas.dhcp') : t('placas.ip-fixo')].filter(Boolean).join(t('geral.separador'));
    const input = h('input', { type: 'radio', name: 'placa', value: String(p.ifIndex), 'data-nome': p.nome, 'data-mac': p.mac || '', 'data-tipo': p.tipo,
      'data-rota': p.rotaPadrao ? '1' : '0' });
    if (p.ifIndex === marcar) input.checked = true;
    return h('li', null, h('label', { class: 'placa-item' + (p.sugerida ? ' sugerida' : '') }, [input,
      h('span', { class: 'placa-corpo' }, [
        h('span', { class: 'placa-nome' }, [p.nome,
          p.sugerida ? h('span', { class: 'selo' }, t('placas.selo-sugerida')) : null,
          p.rotaPadrao ? h('span', { class: 'selo internet' }, t('placas.selo-internet')) : null,
          p.ifIndex === naSessao ? h('span', { class: 'selo' }, t('placas.selo-sessao')) : null]),
        h('span', { class: 'placa-detalhe' }, detalhes + (p.descricao ? t('geral.separador') + p.descricao : ''))])]));
  }));
  const nota = $('placas-nota');
  const temWifiSo = placas.length && placas.every((p) => p.tipo === 'wifi');
  nota.hidden = !temWifiSo;
  if (temWifiSo) nota.textContent = t('placas.so-wifi');
}

// ------------------------------------------------------------------ resumo
export function desenharResumo() {
  const box = $('resumo');
  const s = S.sessaoCache;
  const estado = S.estado;
  const es = (estado && estado.sessao) || {};
  if (!s) { box.replaceChildren(h('p', { class: 'apoio' }, t('resumo.carregando'))); return; }
  const cartao = (n, titulo, linhas) => h('div', { class: 'resumo-secao' }, [
    h('div', { class: 'resumo-cabeca' }, [h('h3', null, titulo), n ? h('a', { href: '#inicio/' + n }, t('resumo.alterar')) : null]),
    h('dl', null, linhas.filter(([, v]) => v !== undefined && v !== null && v !== '').flatMap(([k, v]) => [h('dt', null, k), h('dd', null, String(v))]))]);
  const placa = s.Placa
    ? t('resumo.placa-valor', { nome: s.Placa.Nome, tipo: s.Placa.Tipo === 'wifi' ? t('placas.wifi') : t('placas.ethernet'), ifIndex: s.Placa.IfIndex })
    : t('resumo.placa-nao-escolhida');
  const pr = s.Encoder.Principal; const se = s.Encoder.Secundario;
  const fila = s.Fila && s.Fila.Inicio ? t('resumo.faixa-valor', { inicio: s.Fila.Inicio, fim: s.Fila.Fim }) : '';
  const senha = senhaOk()
    ? (estado.simular && !estado.senhaDefinida ? t('resumo.senha-simulacao') : t('resumo.senha-definida'))
    : t('resumo.senha-nao-definida');
  box.replaceChildren(
    cartao(passoDe('senha'), t('inicio.passo1.titulo'), [[t('resumo.senha'), senha]]),
    cartao(passoDe('placa'), t('inicio.passo2.titulo'), [[t('resumo.placa'), placa]]),
    cartao(passoDe('rede'), t('inicio.passo3.titulo'), [[t('resumo.gateway'), s.Gateway], [t('resumo.mascara'), s.Mascara],
      [t('resumo.dns'), s.Dns1 + ', ' + s.Dns2], [t('resumo.ip-pc'), s.IpPcCameras || t('resumo.ip-pc-cameras-auto')]]),
    cartao(passoDe('fabrica'), t('inicio.passo4.titulo'), [[t('resumo.ip-fabrica'), s.IpFabrica], [t('resumo.ip-pc'), s.IpPcFabrica || t('resumo.ip-pc-fabrica-auto')]]),
    cartao(passoDe('camera'), t('inicio.passo5.titulo'), [[t('resumo.email'), s.EmailRecuperacao],
      [t('resumo.stream-principal'), textoStream(pr.Resolucao, pr.Fps, pr.BitRate, pr.Codec, 2 * Number(pr.Fps))],
      [t('resumo.stream-secundario'), textoStream(se.Resolucao, se.Fps, se.BitRate, se.Codec, 2 * Number(se.Fps))]]),
    cartao(passoDe('fila'), t('inicio.passo6.titulo'), [[t('resumo.faixa'), fila || t('resumo.faixa-depois')], [t('resumo.local'), s.Fila && s.Fila.Local],
      [t('resumo.rack'), s.Fila && s.Fila.Rack], [t('resumo.andar'), s.Fila && s.Fila.Andar]]));
  $('resumo-montar-rotulo').hidden = !fila;
  $('btn-comecar').textContent = estado && estado.simular ? t('inicio.comecar-simulacao') : t('inicio.btn-comecar');
  if (!es.placa && !s.Placa) $('btn-comecar').disabled = true;
}

// Previa da faixa enquanto o IP e digitado.
export function desenharPrevia() {
  const f = $('form-fila').elements;
  const p = $('fila-previa');
  const a = f.inicio.value.trim();
  const b = f.fim.value.trim();
  p.hidden = !(ipValido(a) && ipValido(b));
  if (p.hidden) return;
  const n = ipParaNumero(b) - ipParaNumero(a) + 1;
  if (n <= 0) p.textContent = t('fila.previa-invertida');
  else if (n > FILA_MAX_ENDERECOS) p.textContent = t('fila.previa-acima', { n: numero(n) });
  else p.textContent = t('fila.previa', { n, quantos: numero(n), inicio: a, fim: b });
}

// ------------------------------------------------------------------ senha
export function mostrarSenha(ligado) {
  const f = $('form-senha').elements;
  f.senha.type = f.senha2.type = ligado ? 'text' : 'password';
  const b = $('btn-senha-mostrar');
  b.setAttribute('aria-pressed', String(ligado));
  b.textContent = ligado ? t('senha.ocultar') : t('opcoes.btn-senha-mostrar');
}

// POST /api/senha. Em simulacao, campos vazios = sem senha (nao precisa).
export async function enviarSenha(form) {
  const f = form.elements;
  $('senha-erro').hidden = true;
  if (!f.senha.value && !f.senha2.value && S.estado && S.estado.simular) return true;
  if (!f.senha.value) { f.senha.focus(); mostrarErrosCampo(form, [{ campo: 'senha', msg: t('senha.digite') }]); return false; }
  if (f.senha.value !== f.senha2.value) {
    $('senha-erro').hidden = false;
    f.senha2.value = '';
    f.senha2.focus();
    return false;
  }
  try {
    await exigir(S.api.comando('/api/senha', { senha: f.senha.value }));
    form.reset();
    mostrarSenha(false);
    limparErrosCampo(form);
    marcarSalvo(form, t('senha.definida'));
    mostrarAviso('');
    setTimeout(ganchos.buscarEstado, CONSULTA_APOS_COMANDO_MS);
    return true;
  } catch (e) { mostrarAviso(e.message); return false; }
}

export function notaSenhaInstaladas() {
  // Trocar a senha no meio da fila: as ja instaladas ficam com a anterior.
  const estado = S.estado;
  const feitas = estado && estado.fila ? (estado.fila.itens || []).filter((i) => i.Estado === 'feita').length : 0;
  const nota = $('senha-instaladas');
  nota.hidden = !(feitas && estado.senhaDefinida);
  nota.textContent = t('senha.instaladas', { feitas });
}

// "Montar fila" em Opcoes troca a fila em memoria: com posicoes, confirma
// dizendo quantas saem. Sem fila, devolve '' e confirm nao e chamado.
export function textoTrocarFila() {
  const itens = (S.estado && S.estado.fila && S.estado.fila.itens) || [];
  if (!itens.length) return '';
  const pend = itens.filter((i) => i.Estado === 'pendente').length;
  return t('fila.confirmar-troca', { inicio: itens[0].Ip, fim: itens[itens.length - 1].Ip, total: itens.length, pend });
}

export function textoDaEscolha(s) {
  const partes = [t('escolha.ultima', { quando: dataCurta(s.quando) })];
  if (s.placa) partes.push(t('escolha.placa', { nome: s.placa.nome }));
  const c = S.sessaoCache;
  if (c) partes.push(t('escolha.rede', { gateway: c.Gateway, mascara: c.Mascara, fabrica: c.IpFabrica }));
  if (s.fila) partes.push(t('escolha.fila', { inicio: s.fila.inicio, fim: s.fila.fim, local: s.fila.local }));
  else partes.push(t('escolha.sem-fila'));
  partes.push(t('escolha.explica'));
  return partes.join(' ');
}
