// Criacao de no sem innerHTML com dado do servidor (direcao.md, secao 7.2).

// h('button', { class: 'botao', onclick: fn, dados: { acao: 'x' } }, ['texto', outroNo])
export function h(tag, atributos, filhos) {
  const el = document.createElement(tag);
  aplicar(el, atributos || {});
  anexar(el, filhos);
  return el;
}

function aplicar(el, atributos) {
  for (const [nome, valor] of Object.entries(atributos)) {
    if (valor === undefined || valor === null || valor === false) continue;
    if (nome.startsWith('on') && typeof valor === 'function') {
      el.addEventListener(nome.slice(2), valor);
    } else if (nome === 'dados') {
      for (const [k, v] of Object.entries(valor)) el.dataset[k] = v;
    } else if (nome === 'class') {
      el.className = Array.isArray(valor) ? valor.filter(Boolean).join(' ') : valor;
    } else if (nome === 'value' || nome === 'checked' || nome === 'open') {
      el[nome] = valor;
    } else if (valor === true) {
      el.setAttribute(nome, '');
    } else {
      el.setAttribute(nome, String(valor));
    }
  }
}

function anexar(el, filhos) {
  if (filhos === undefined || filhos === null || filhos === false) return el;
  const lista = Array.isArray(filhos) ? filhos : [filhos];
  for (const f of lista) {
    if (f === undefined || f === null || f === false) continue;
    if (Array.isArray(f)) { anexar(el, f); continue; }
    el.append(f instanceof Node ? f : document.createTextNode(String(f)));
  }
  return el;
}
