// Uma definicao por secao da sessao (direcao.md, secao 7.2; UX-37): a mesma no passo a passo,
// em Sessao e no painel lateral. montarFormulario devolve { el, coletar }; coletar valida e
// devolve { ok, parcial } com a secao pronta para PUT /api/sessao.
import { h, novoId } from './dom.js';
import { campo } from './componentes.js';
import { icone } from './icones.js';
import { t } from './textos.js';
import { ipParaNumero, numeroParaIp } from './formato.js';
import { SENHA_MIN } from './constantes.js';

const OUTRO = 'outro';

function validarIp(c) {
  if (ipParaNumero(c.valor()) === null) { c.mostrarErro(t('fila.erro.ip')); return false; }
  c.limparErro();
  return true;
}

function obrigatorio(c) {
  if (!c.valor()) { c.mostrarErro(t('erro.campo.obrigatorio')); return false; }
  c.limparErro();
  return true;
}

function senha(modelo) {
  if (modelo.simular) {
    return { el: h('p', { class: 'nota-neutra' }, [icone('simulacao'), h('span', null, t('senha.simulacao'))]), coletar: () => ({ ok: true, parcial: null }) };
  }
  const a = campo({ rotulo: t('senha.campo'), tipo: 'password', ajuda: t('senha.ajuda'), autocomplete: 'new-password' });
  const b = campo({ rotulo: t('senha.repetir'), tipo: 'password', autocomplete: 'new-password' });
  const el = h('div', { class: 'form-grade' }, [a.el, b.el]);
  return {
    el,
    coletar() {
      const v = a.valor();
      if (v.length < SENHA_MIN || !/[a-z]/i.test(v) || !/\d/.test(v)) { a.mostrarErro(t('senha.erro.curta')); a.entrada.focus(); return { ok: false }; }
      a.limparErro();
      if (v !== b.valor()) { b.mostrarErro(t('senha.erro.diferente')); b.entrada.focus(); return { ok: false }; }
      b.limparErro();
      return { ok: true, senha: v, parcial: null };
    },
  };
}

function placa(modelo) {
  const atual = (modelo.sessao.Placa && modelo.sessao.Placa.ifIndex) || null;
  const placas = modelo.placas || [];
  if (!placas.length) return { el: h('p', { class: 'apoio' }, t('placa.lendo')), coletar: () => ({ ok: false }) };
  const nome = novoId('placa');
  const linhas = placas.map((p) => {
    const id = novoId('placa-op');
    const marcada = atual ? p.ifIndex === atual : p.sugerida;
    const nota = h('p', { class: 'placa-nota', hidden: !(marcada && p.rotaPadrao) }, [icone('informacao'), h('span', null, t('placa.notaInternet'))]);
    const radio = h('input', { type: 'radio', id, name: nome, value: String(p.ifIndex), checked: marcada, class: 'placa-radio' });
    return { p, radio, nota, el: h('div', { class: 'placa-linha' }, [
      radio,
      h('label', { for: id, class: 'placa-rotulo' }, [
        h('span', { class: 'placa-nome' }, p.nome),
        h('span', { class: 'placa-desc apoio' }, [p.descricao, p.velocidade ? `, ${p.velocidade}` : '']),
        p.sugerida ? h('span', { class: 'chip chip-neutro' }, t('placa.sugerida')) : null,
        !p.cabo ? h('span', { class: 'chip chip-atencao' }, [icone('atencao'), h('span', null, t('placa.semCabo'))]) : null,
      ]),
      nota,
    ]) };
  });
  const grupo = h('fieldset', { class: 'placa-lista' }, [h('legend', { class: 'campo-rotulo' }, t('placa.lista')), linhas.map((l) => l.el)]);
  grupo.addEventListener('change', () => { for (const l of linhas) l.nota.hidden = !(l.radio.checked && l.p.rotaPadrao); });
  return {
    el: grupo,
    coletar() {
      const l = linhas.find((x) => x.radio.checked);
      if (!l) return { ok: false };
      return { ok: true, parcial: { Placa: { nome: l.p.nome, ifIndex: l.p.ifIndex } } };
    },
  };
}

function rede(modelo, opcoes) {
  const r = modelo.sessao.Rede || {};
  const f = modelo.sessao.Fabrica || {};
  const mascara = campo({ rotulo: t('rede.mascara'), valor: r.mascara, mono: true, exemplo: '255.255.255.0' });
  const gateway = campo({ rotulo: t('rede.gateway'), valor: r.gateway, mono: true, exemplo: '192.0.2.1' });
  const dns = campo({ rotulo: t('rede.dns'), valor: r.dns, mono: true, exemplo: '192.0.2.1' });
  const ipPc = campo({ rotulo: t('rede.ipPc'), valor: r.ipPc, mono: true, exemplo: '192.0.2.250' });
  const ipFab = campo({ rotulo: t('rede.ipFabrica'), valor: f.ipFabrica, mono: true, exemplo: '192.168.1.108' });
  const ipPcFab = campo({ rotulo: t('rede.ipPcFabrica'), valor: f.ipPc, mono: true, exemplo: '192.168.1.220' });
  const idBroadcast = novoId('broadcast');
  const broadcast = h('input', { type: 'checkbox', id: idBroadcast, checked: !!modelo.sessao.Broadcast, 'aria-describedby': `${idBroadcast}-risco` });
  const el = h('div', { class: 'form' }, [
    h('div', { class: 'form-grade' }, [mascara.el, gateway.el, dns.el, ipPc.el]),
    h('details', { class: 'recolhido' }, [
      h('summary', null, [h('span', { class: 'recolhido-titulo' }, t('rede.fabrica')), h('span', { class: 'apoio' }, t('rede.fabrica.resumo', { ipFabrica: f.ipFabrica, ipPc: f.ipPc }))]),
      h('div', { class: 'form-grade' }, [ipFab.el, ipPcFab.el]),
    ]),
    opcoes && opcoes.comBroadcast ? h('div', { class: 'caixa' }, [
      broadcast,
      h('div', null, [
        h('label', { for: idBroadcast, class: 'caixa-rotulo' }, t('rede.broadcast')),
        h('p', { class: 'campo-ajuda', id: `${idBroadcast}-risco` }, t('rede.broadcast.risco')),
      ]),
    ]) : null,
  ]);
  return {
    el,
    coletar() {
      const todos = [mascara, gateway, dns, ipPc, ipFab, ipPcFab];
      const oks = todos.map(validarIp);
      if (oks.includes(false)) { todos[oks.indexOf(false)].entrada.focus(); return { ok: false }; }
      const parcial = {
        Rede: { mascara: mascara.valor(), gateway: gateway.valor(), dns: dns.valor(), ipPc: ipPc.valor() },
        Fabrica: { ipFabrica: ipFab.valor(), ipPc: ipPcFab.valor() },
      };
      if (opcoes && opcoes.comBroadcast) parcial.Broadcast = broadcast.checked;
      return { ok: true, parcial };
    },
  };
}

function stream(chave, valores, cat) {
  const v = valores || {};
  const opcoesBitrate = (resolucao) => {
    const rec = cat.recomendado[resolucao];
    return [
      ...cat.bitrates.map((b) => ({ valor: b, rotulo: b === rec ? t('camera.bitrate.recomendado', { v: b }) : String(b) })),
      { valor: OUTRO, rotulo: t('camera.bitrate.outro') },
    ];
  };
  const forado = v.bitrate && !cat.bitrates.includes(Number(v.bitrate));
  const resolucao = campo({ rotulo: t('camera.resolucao'), valor: v.resolucao, opcoes: cat.resolucoes.map((r) => ({ valor: r, rotulo: r })) });
  const bitrate = campo({ rotulo: t('camera.bitrate'), valor: forado ? OUTRO : v.bitrate, opcoes: opcoesBitrate(v.resolucao || cat.resolucoes[0]) });
  const outro = campo({ rotulo: t('camera.bitrate.valor'), valor: forado ? v.bitrate : '', inputmode: 'numeric', classe: 'campo-outro' });
  outro.el.hidden = !forado;
  const fps = campo({ rotulo: t('camera.fps'), valor: v.fps, opcoes: cat.fpsLista.map((n) => ({ valor: n, rotulo: String(n) })), classe: 'campo-curto' });
  const codec = campo({ rotulo: t('camera.codec'), valor: v.codec, opcoes: cat.codecs.map((c) => ({ valor: c, rotulo: c })), classe: 'campo-curto' });
  bitrate.entrada.addEventListener('change', () => { outro.el.hidden = bitrate.valor() !== OUTRO; if (!outro.el.hidden) outro.entrada.focus(); });
  resolucao.entrada.addEventListener('change', () => {
    const rec = cat.recomendado[resolucao.valor()];
    bitrate.entrada.replaceChildren(...opcoesBitrate(resolucao.valor()).map((op) => h('option', { value: String(op.valor), selected: op.valor === rec }, op.rotulo)));
    outro.el.hidden = true;
  });
  const el = h('fieldset', { class: 'stream' }, [
    h('legend', { class: 'stream-titulo' }, t(`camera.${chave}`)),
    resolucao.el, bitrate.el, outro.el, h('div', { class: 'stream-par' }, [fps.el, codec.el]),
  ]);
  return {
    el, bitrate,
    focarBitrate: () => bitrate.entrada.focus(),
    coletar() {
      let b = bitrate.valor();
      if (b === OUTRO) {
        if (!/^\d+$/.test(outro.valor())) { outro.mostrarErro(t('erro.campo.obrigatorio')); outro.entrada.focus(); return null; }
        outro.limparErro();
        b = outro.valor();
      }
      return { resolucao: resolucao.valor(), bitrate: Number(b), fps: Number(fps.valor()), codec: codec.valor() };
    },
  };
}

function camera(modelo, opcoes) {
  const c = modelo.sessao.Camera || {};
  const cat = modelo.catalogo;
  const email = campo({ rotulo: t('camera.email'), tipo: 'email', valor: c.email, ajuda: t('camera.email.ajuda'), autocomplete: 'email', exemplo: 'tecnico@exemplo.example' });
  const p = stream('principal', c.principal, { ...cat.principal, codecs: cat.codecs, fpsLista: cat.fps });
  const s = stream('secundario', c.secundario, { ...cat.secundario, codecs: cat.codecs, fpsLista: cat.fps });
  const soEncoder = opcoes && opcoes.soEncoder;
  const el = h('div', { class: 'form' }, [
    soEncoder ? null : email.el,
    h('div', { class: ['form-streams', soEncoder ? 'form-streams-coluna' : null] }, [p.el, s.el]),
    soEncoder ? null : h('details', { class: 'recolhido' }, [
      h('summary', null, h('span', { class: 'recolhido-titulo' }, t('camera.porque'))),
      h('p', { class: 'apoio' }, t('camera.porque.texto')),
    ]),
  ]);
  return {
    el,
    focarBitrate: p.focarBitrate,
    coletar() {
      if (!soEncoder && !obrigatorio(email)) { email.entrada.focus(); return { ok: false }; }
      const vp = p.coletar();
      const vs = vp && s.coletar();
      if (!vp || !vs) return { ok: false };
      return { ok: true, parcial: { Camera: { email: soEncoder ? c.email : email.valor(), principal: vp, secundario: vs } } };
    },
  };
}

function fila(modelo) {
  const f = modelo.sessao.Fila || {};
  const inicio = campo({ rotulo: t('fila.inicio'), valor: f.inicio, mono: true, exemplo: '192.0.2.10' });
  const fim = campo({ rotulo: t('fila.fim'), valor: f.fim, mono: true, exemplo: '192.0.2.12' });
  const local = campo({ rotulo: t('fila.local'), valor: f.local, exemplo: 'Obra exemplo' });
  const rack = campo({ rotulo: t('fila.rack'), valor: f.rack, classe: 'campo-curto' });
  const andar = campo({ rotulo: t('fila.andar'), valor: f.andar, classe: 'campo-curto' });
  const previa = h('p', { class: 'previa', 'aria-live': 'polite' });
  const instalados = new Set((modelo.registro || []).filter((r) => r.Status === 'Instalada').map((r) => r.Ip));
  function atualizarPrevia() {
    const a = ipParaNumero(inicio.valor());
    const b = ipParaNumero(fim.valor());
    if (a === null || b === null || b < a) { previa.replaceChildren(); return; }
    let noRegistro = 0;
    for (let n = a; n <= b; n += 1) {
      const ip = numeroParaIp(n);
      if (instalados.has(ip)) noRegistro += 1;
    }
    previa.replaceChildren(icone(noRegistro ? 'atencao' : 'informacao'), h('span', null, `${t('fila.previa', { n: b - a + 1 })} ${noRegistro ? t('fila.previa.registro', { n: noRegistro }) : t('fila.previa.livre')}`));
    previa.className = ['previa', noRegistro ? 'previa-atencao' : null].filter(Boolean).join(' ');
  }
  inicio.entrada.addEventListener('input', atualizarPrevia);
  fim.entrada.addEventListener('input', atualizarPrevia);
  atualizarPrevia();
  const el = h('div', { class: 'form' }, [
    h('div', { class: 'form-grade' }, [inicio.el, fim.el]),
    previa,
    h('div', { class: 'form-grade form-grade-local' }, [local.el, rack.el, andar.el]),
  ]);
  return {
    el,
    coletar() {
      if (!validarIp(inicio)) { inicio.entrada.focus(); return { ok: false }; }
      if (!validarIp(fim)) { fim.entrada.focus(); return { ok: false }; }
      if (ipParaNumero(fim.valor()) < ipParaNumero(inicio.valor())) { fim.mostrarErro(t('fila.erro.ordem')); fim.entrada.focus(); return { ok: false }; }
      if (!obrigatorio(local)) { local.entrada.focus(); return { ok: false }; }
      return { ok: true, parcial: { Fila: { inicio: inicio.valor(), fim: fim.valor(), local: local.valor(), rack: rack.valor(), andar: andar.valor() } } };
    },
  };
}

export const FORMULARIOS = { senha, placa, rede, camera, fila };

export function montarFormulario(secao, modelo, opcoes) {
  return FORMULARIOS[secao](modelo, opcoes || {});
}
