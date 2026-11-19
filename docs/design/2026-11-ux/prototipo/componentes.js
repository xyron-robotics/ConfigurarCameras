// Componentes da direcao.md, secao 5. So tokens semanticos no CSS; aqui so estrutura e estado.
import { h, novoId, focar } from './dom.js';
import { icone } from './icones.js';
import { t } from './textos.js';

// tipo: 'primario' | 'secundario' | 'discreto' | 'perigo'
export function botao(rotulo, aoClicar, opcoes) {
  const o = opcoes || {};
  return h('button', {
    type: o.submit ? 'submit' : 'button',
    class: ['botao', `botao-${o.tipo || 'secundario'}`, o.classe],
    onclick: aoClicar || undefined,
    disabled: !!o.desabilitado,
    'aria-describedby': o.motivoId,
    dados: o.dados,
    popovertarget: o.popover,
  }, [o.icone ? icone(o.icone) : null, h('span', { class: 'botao-rotulo' }, rotulo)]);
}

// Ocupado: mesmo verbo, aria-busy. Devolve a funcao que restaura.
export function ocupar(btn, rotuloOcupado) {
  const rotulo = btn.querySelector('.botao-rotulo');
  const antes = rotulo.textContent;
  btn.setAttribute('aria-busy', 'true');
  btn.disabled = true;
  rotulo.textContent = rotuloOcupado;
  return () => { btn.removeAttribute('aria-busy'); btn.disabled = false; rotulo.textContent = antes; };
}

// nivel: 'neutro' | 'pronta' | 'alarme' | 'atencao' | 'agora'
export function chip(rotulo, nivel, nomeIcone) {
  return h('span', { class: ['chip', `chip-${nivel || 'neutro'}`] }, [nomeIcone ? icone(nomeIcone) : null, h('span', null, rotulo)]);
}

// Aviso junto do controle que o gerou. tipo: 'sucesso' | 'erro' | 'atencao' | 'info'
export function aviso(tipo, texto, detalheCru) {
  const nomeIcone = { sucesso: 'concluido', erro: 'falha', atencao: 'atencao', info: 'informacao' }[tipo];
  return h('div', { class: ['aviso', `aviso-${tipo}`], role: tipo === 'erro' ? 'alert' : 'status' }, [
    icone(nomeIcone),
    h('div', { class: 'aviso-corpo' }, [
      h('p', null, texto),
      detalheCru ? detalhe(detalheCru) : null,
    ]),
  ]);
}

export function detalhe(cru) {
  return h('details', { class: 'detalhe' }, [
    h('summary', null, t('detalhe.tecnico')),
    h('pre', { class: 'mono detalhe-cru' }, cru),
  ]);
}

// Lugar fixo para o aviso de uma acao: troca o conteudo, nunca some sozinho.
export function lugarAviso() {
  const el = h('div', { class: 'lugar-aviso', 'aria-live': 'polite' });
  return {
    el,
    mostrar(tipo, texto, cru) { el.replaceChildren(aviso(tipo, texto, cru)); },
    limpar() { el.replaceChildren(); },
  };
}

// Campo com rotulo visivel acima, ajuda embaixo e erro com o conserto (secao 5.2).
export function campo(o) {
  const id = o.id || novoId('campo');
  const ajudaId = `${id}-ajuda`;
  const erroId = `${id}-erro`;
  const atributos = {
    id, name: o.nome || id, type: o.tipo || 'text', value: o.valor === undefined ? '' : String(o.valor),
    class: ['campo-entrada', o.mono ? 'mono' : null, o.curto ? 'campo-curto' : null],
    autocomplete: o.autocomplete || 'off', inputmode: o.inputmode, placeholder: o.exemplo ? t('rede.exemplo', { v: o.exemplo }) : undefined,
    'aria-describedby': o.ajuda ? ajudaId : undefined, spellcheck: o.mono ? 'false' : undefined,
  };
  const entrada = o.opcoes ? selecao(atributos, o.opcoes, o.valor) : h('input', atributos);
  const erro = h('p', { class: 'campo-erro', id: erroId, hidden: true });
  const el = h('div', { class: ['campo', o.classe] }, [
    h('label', { class: 'campo-rotulo', for: id }, o.rotulo),
    entrada,
    o.ajuda ? h('p', { class: 'campo-ajuda', id: ajudaId }, o.ajuda) : null,
    erro,
  ]);
  return {
    el, entrada,
    valor: () => entrada.value.trim(),
    mostrarErro(texto) {
      erro.replaceChildren(icone('falha'), h('span', null, texto));
      erro.hidden = false;
      entrada.setAttribute('aria-invalid', 'true');
      entrada.setAttribute('aria-describedby', [o.ajuda ? ajudaId : null, erroId].filter(Boolean).join(' '));
    },
    limparErro() {
      erro.hidden = true;
      entrada.removeAttribute('aria-invalid');
      if (o.ajuda) entrada.setAttribute('aria-describedby', ajudaId); else entrada.removeAttribute('aria-describedby');
    },
  };
}

function selecao(atributos, opcoes, valor) {
  const { type, value, placeholder, inputmode, spellcheck, autocomplete, ...resto } = atributos;
  return h('select', resto, opcoes.map((op) => h('option', { value: String(op.valor), selected: String(op.valor) === String(valor) }, op.rotulo)));
}

// Dialogo de confirmacao (secao 5.8): <dialog> nativo, titulo com o verbo do botao, foco em Cancelar.
let dialogoAtual = null;
export function confirmar(o) {
  return new Promise((resolver) => {
    if (dialogoAtual) dialogoAtual.remove();
    const tituloId = novoId('dialogo-titulo');
    const cancelar = botao(t('dialogo.cancelar'), () => fechar(false), { tipo: 'secundario' });
    const ok = botao(o.confirmar, () => fechar(true), { tipo: o.perigo ? 'perigo' : 'primario' });
    const d = h('dialog', { class: 'dialogo', 'aria-labelledby': tituloId }, [
      h('h2', { id: tituloId, class: 'dialogo-titulo' }, o.titulo),
      h('p', { class: 'dialogo-texto' }, o.texto),
      h('div', { class: 'dialogo-acoes' }, [cancelar, ok]),
    ]);
    function fechar(v) { d.close(); d.remove(); dialogoAtual = null; resolver(v); }
    d.addEventListener('cancel', (ev) => { ev.preventDefault(); fechar(false); });
    document.body.append(d);
    dialogoAtual = d;
    d.showModal();
    focar(o.perigo ? cancelar : ok);
  });
}

// Painel lateral (secao 3.3): <dialog> modal a direita, conteudo atras inerte. Esc fecha.
export function lateral(o) {
  const tituloId = novoId('lateral-titulo');
  const d = h('dialog', { class: 'lateral', 'aria-labelledby': tituloId });
  const fecharBtn = h('button', { type: 'button', class: 'botao botao-icone', 'aria-label': t('lateral.fechar'), onclick: () => fechar() }, icone('fechar', 'm'));
  function fechar() { d.close(); d.remove(); if (o.aoFechar) o.aoFechar(); }
  d.append(
    h('div', { class: 'lateral-cabeca' }, [h('h2', { id: tituloId }, o.titulo), fecharBtn]),
    o.texto ? h('p', { class: 'lateral-texto' }, o.texto) : null,
    h('div', { class: 'lateral-corpo' }, o.conteudo(fechar)),
  );
  d.addEventListener('cancel', (ev) => { ev.preventDefault(); fechar(); });
  document.body.append(d);
  d.showModal();
  return { fechar };
}

// Faixa do painel inteiro (secao 5.7). tipo: 'alarme' | 'atencao' | 'info'
export function faixa(tipo, texto, acao, extra) {
  const nomeIcone = { alarme: 'falha', atencao: 'atencao', info: 'informacao' }[tipo];
  return h('div', { class: ['faixa', `faixa-${tipo}`], role: tipo === 'alarme' ? 'alert' : 'status' }, [
    h('div', { class: 'faixa-conteudo' }, [
      icone(nomeIcone, 'm'),
      h('p', { class: 'faixa-texto' }, texto),
      acao || null,
      extra ? h('span', { class: 'faixa-extra apoio' }, extra) : null,
    ]),
  ]);
}

// Estado da posicao: sempre icone mais palavra (secao 5.3).
export function selo(estado, texto) {
  const nomeIcone = { instalada: 'concluido', curso: 'agora', falha: 'falha', proxima: 'abrir', aguardando: null, pulada: 'pulada', espera: 'espera' }[estado];
  return h('span', { class: ['selo', `selo-${estado}`] }, [nomeIcone ? icone(nomeIcone) : null, h('span', null, texto)]);
}

export function barraEtapas(n, total) {
  const el = h('span', { class: 'barra-etapas', 'aria-hidden': 'true' });
  for (let i = 1; i <= total; i += 1) el.append(h('span', { class: ['barra-etapa', i < n ? 'barra-etapa-feita' : null, i === n ? 'barra-etapa-atual' : null] }));
  return el;
}
