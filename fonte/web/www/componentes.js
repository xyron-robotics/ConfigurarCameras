// Componentes da direcao.md, secao 5: botao (5.1), campo (5.2), aviso (5.6),
// dialogo de confirmacao (5.8), chip e popover (5.9), selo e mini barra das
// etapas da linha da tabela (5.3). Aqui so estrutura, estado
// e acessibilidade; a cara de cada um esta em componentes.css, so com tokens.
import { h, novoId, focar } from './dom.js';
import { icone } from './icones.js';
import { t } from './textos.js';

// tipo: 'primario' (um por area) | 'secundario' | 'discreto' | 'perigo'
export function botao(rotulo, aoClicar, opcoes) {
  const o = opcoes || {};
  return h('button', {
    type: o.submit ? 'submit' : 'button',
    class: ['botao', 'botao-' + (o.tipo || 'secundario'), o.classe],
    onclick: aoClicar || undefined,
    disabled: !!o.desabilitado,
    'aria-describedby': o.motivoId,
    dados: o.dados,
  }, [o.icone ? icone(o.icone) : null, h('span', { class: 'botao-rotulo' }, rotulo)]);
}

// Ocupado: o mesmo verbo no gerundio e aria-busy. Devolve a funcao que restaura.
export function ocupar(btn, rotuloOcupado) {
  const rotulo = btn.querySelector('.botao-rotulo');
  const antes = rotulo.textContent;
  btn.setAttribute('aria-busy', 'true');
  btn.disabled = true;
  rotulo.textContent = rotuloOcupado;
  return () => { btn.removeAttribute('aria-busy'); btn.disabled = false; rotulo.textContent = antes; };
}

// nivel: 'neutro' | 'pronta' | 'alarme' | 'atencao' | 'agora'. Sempre icone e palavra.
export function chip(rotulo, nivel, nomeIcone) {
  return h('span', { class: ['chip', 'chip-' + (nivel || 'neutro')] }, [
    nomeIcone ? icone(nomeIcone) : null,
    h('span', null, rotulo),
  ]);
}

// Estado de uma linha da tabela (5.3): icone e palavra, nunca so a cor.
// estado: 'instalada' | 'curso' | 'falha' | 'proxima' | 'aguardando' | 'pulada' | 'espera' | 'ignorada'
const ICONE_DO_ESTADO = {
  instalada: 'concluido', curso: 'agora', falha: 'falha', proxima: 'abrir',
  aguardando: null, pulada: 'pulada', espera: 'espera', ignorada: 'informacao',
};
export function selo(estado, texto) {
  const nomeIcone = ICONE_DO_ESTADO[estado];
  return h('span', { class: ['selo', 'selo-' + estado] }, [nomeIcone ? icone(nomeIcone) : null, h('span', null, texto)]);
}

// Mini barra das etapas (UX-04): as feitas cheias, a atual so contornada. O
// texto do selo ja diz "n de total"; a barra e so desenho.
export function barraEtapas(n, total) {
  const el = h('span', { class: 'barra-etapas', 'aria-hidden': 'true' });
  for (let i = 1; i <= total; i += 1) {
    el.append(h('span', { class: ['barra-etapa', i < n ? 'barra-etapa-feita' : null, i === n ? 'barra-etapa-atual' : null] }));
  }
  return el;
}

// Popover do chip (5.9): Popover API nativa, fecha com Esc e clique fora.
// corpo e o no que a tela atualiza no lugar (o popover aberto continua aberto).
export function popover(id, titulo, corpo) {
  const tituloId = novoId('popover-titulo');
  return h('div', { id, popover: 'auto', class: 'popover', role: 'dialog', 'aria-labelledby': tituloId }, [
    h('h2', { id: tituloId, class: 'popover-titulo' }, titulo),
    corpo,
  ]);
}

// Aviso junto do controle que o gerou. tipo: 'sucesso' | 'erro' | 'atencao' | 'info'
export function aviso(tipo, texto, detalheCru) {
  const nomeIcone = { sucesso: 'concluido', erro: 'falha', atencao: 'atencao', info: 'informacao' }[tipo];
  return h('div', { class: ['aviso', 'aviso-' + tipo] }, [
    icone(nomeIcone),
    h('div', { class: 'aviso-corpo' }, [
      h('p', null, texto),
      detalheCru ? detalhe(detalheCru) : null,
    ]),
  ]);
}

// O que e tecnico (ifIndex, resposta crua do servidor) fica recolhido.
export function detalhe(cru) {
  return h('details', { class: 'detalhe' }, [
    h('summary', null, t('detalhe.tecnico')),
    h('pre', { class: 'mono detalhe-cru' }, cru),
  ]);
}

// Lugar fixo do aviso de uma acao, ja em aria-live: troca o conteudo e nunca some sozinho.
export function lugarAviso() {
  const el = h('div', { class: 'lugar-aviso', role: 'status', 'aria-live': 'polite' });
  return {
    el,
    mostrar(tipo, texto, cru) { el.replaceChildren(aviso(tipo, texto, cru)); },
    limpar() { el.replaceChildren(); },
  };
}

// Campo com rotulo visivel acima, ajuda embaixo e erro com o conserto (5.2).
// o: { rotulo, id?, nome?, tipo?, valor?, ajuda?, exemplo?, mono?, curto?, inputmode?, autocomplete?, opcoes?, classe? }
export function campo(o) {
  const id = o.id || novoId('campo');
  const ajudaId = id + '-ajuda';
  const erroId = id + '-erro';
  const atributos = {
    id,
    name: o.nome || id,
    class: ['campo-entrada', o.mono ? 'mono' : null],
    autocomplete: o.autocomplete || 'off',
    'aria-describedby': o.ajuda ? ajudaId : undefined,
  };
  const entrada = o.opcoes
    ? h('select', atributos, o.opcoes.map((op) => h('option', { value: String(op.valor), selected: String(op.valor) === String(o.valor) }, op.rotulo)))
    : h('input', {
      ...atributos,
      type: o.tipo || 'text',
      value: o.valor === undefined ? '' : String(o.valor),
      inputmode: o.inputmode,
      placeholder: o.exemplo ? t('campo.exemplo', { v: o.exemplo }) : undefined,
      spellcheck: o.mono ? 'false' : undefined,
    });
  const erro = h('p', { class: 'campo-erro', id: erroId, hidden: true });
  const el = h('div', { class: ['campo', o.curto ? 'campo-curto' : null, o.classe] }, [
    h('label', { class: 'campo-rotulo', for: id }, o.rotulo),
    entrada,
    o.ajuda ? h('p', { class: 'campo-ajuda', id: ajudaId }, o.ajuda) : null,
    erro,
  ]);
  return {
    el,
    entrada,
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

// Confirmacao (5.8): <dialog> nativo com showModal(), titulo em pergunta com o
// verbo do botao ("Encerrar o painel?" / "Encerrar o painel"). Esc e Cancelar
// resolvem false. Acao de perigo comeca com o foco em Cancelar.
// o: { titulo, texto, confirmar, perigo? } -> Promise<boolean>
let dialogoAtual = null;
export function confirmar(o) {
  return new Promise((resolver) => {
    if (dialogoAtual) dialogoAtual.fechar(false);
    const tituloId = novoId('dialogo-titulo');
    const textoId = novoId('dialogo-texto');
    const cancelar = botao(t('dialogo.cancelar'), () => fechar(false), { tipo: 'secundario' });
    const ok = botao(o.confirmar, () => fechar(true), { tipo: o.perigo ? 'perigo' : 'primario' });
    const d = h('dialog', { class: 'dialogo', 'aria-labelledby': tituloId, 'aria-describedby': textoId }, [
      h('h2', { id: tituloId, class: 'dialogo-titulo' }, o.titulo),
      h('p', { id: textoId, class: 'dialogo-texto' }, o.texto),
      h('div', { class: 'dialogo-acoes' }, [cancelar, ok]),
    ]);
    const devolverFoco = document.activeElement;
    function fechar(v) {
      if (!d.isConnected) return;
      d.close();
      d.remove();
      dialogoAtual = null;
      if (devolverFoco && devolverFoco.isConnected) focar(devolverFoco);
      resolver(v);
    }
    d.addEventListener('cancel', (ev) => { ev.preventDefault(); fechar(false); });
    document.body.append(d);
    dialogoAtual = { fechar };
    d.showModal();
    focar(o.perigo ? cancelar : ok);
  });
}

// Painel lateral (5.8, variante): <dialog> modal encostado a direita, para uma
// correcao que precisa de formulario sem sair da tela. O resto da pagina fica
// inert enquanto ele esta aberto; Esc e Fechar fecham. Quem abre decide para
// onde o foco volta (aoFechar), porque o botao que abriu pode ter sumido.
// o: { titulo, texto?, conteudo(fechar) -> Node, aoFechar? } -> { el, fechar }
export function lateral(o) {
  const tituloId = novoId('lateral-titulo');
  const textoId = o.texto ? novoId('lateral-texto') : undefined;
  let fechado = false;
  const d = h('dialog', { class: 'lateral', 'aria-labelledby': tituloId, 'aria-describedby': textoId });
  const inertes = [];
  function fechar() {
    if (fechado) return;
    fechado = true;
    d.close();
    d.remove();
    inertes.forEach((el) => el.removeAttribute('inert'));
    if (o.aoFechar) o.aoFechar();
  }
  const botaoFechar = h('button', { type: 'button', class: ['botao', 'botao-discreto', 'botao-icone'], 'aria-label': t('lateral.fechar'), onclick: fechar }, icone('fechar'));
  d.append(
    h('div', { class: 'lateral-cabeca' }, [h('h2', { id: tituloId, class: 'lateral-titulo' }, o.titulo), botaoFechar]),
    o.texto ? h('p', { id: textoId, class: 'lateral-texto' }, o.texto) : null,
    h('div', { class: 'lateral-corpo' }, o.conteudo(fechar)),
  );
  d.addEventListener('cancel', (ev) => { ev.preventDefault(); fechar(); });
  Array.from(document.body.children).forEach((el) => {
    if (!el.hasAttribute('inert')) { el.setAttribute('inert', ''); inertes.push(el); }
  });
  document.body.append(d);
  d.showModal();
  return { el: d, fechar };
}
