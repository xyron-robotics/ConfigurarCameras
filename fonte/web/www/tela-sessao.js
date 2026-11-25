// Sessao (direcao.md, secao 3.5): menu das secoes a esquerda (Senha, Placa,
// Rede, Camera, Fila e, separada, Painel) e a escolhida a direita, na rota
// #/sessao/<secao>. Os formularios sao os do passo a passo (formularios.js);
// "Salvar alteracoes" confirma com "Alteracoes salvas" junto do botao, no
// aria-live. A tela recebe o modelo e o contexto do app.js (decisao N1).
import { h, novoId } from './dom.js';
import { t, traduzirServidor } from './textos.js';
import { logo } from './marca.js';
import { botao, ocupar, lugarAviso } from './componentes.js';
import { montarFormulario } from './formularios.js';
import { mostrarFalha, salvarSenha, salvarParcial } from './tela-inicio.js';
import { rotaDoPasso } from './rotas.js';
import { dataHora } from './formato.js';
import { SECOES_SESSAO, TEMAS, ESPERA_ESTADO_MS, ESPERA_SESSAO_MS } from './constantes.js';

// ctx (do app.js): o mesmo do passo a passo (tela-inicio.js). A tela devolve
// { el, foco, secao, sujo(), ocupada(), aviso() }: o app.js nao redesenha por
// cima de campo mexido ou de tela salvando, e o aviso da acao passa para a
// tela redesenhada (o "Alteracoes salvas" fica depois da recarga da sessao).

// ------------------------------------------------------------------ tema
// O servidor ja entrega o <html> com data-tema (sem flash). Trocar o tema muda
// o atributo e as metas theme-color na hora; PUT /api/tema guarda para a
// proxima abertura (a porta muda; localStorage nao serve).
const MEDIA_TEMA = { claro: '(prefers-color-scheme: light)', escuro: '(prefers-color-scheme: dark)' };
const NOME_TEMA = 'tema-painel';

export function aplicarTema(v) {
  const tema = TEMAS.includes(v) ? v : TEMAS[0];
  document.documentElement.dataset.tema = tema;
  for (const m of document.querySelectorAll('meta[data-tema-cor]')) {
    const dela = m.dataset.temaCor;
    m.media = tema === 'sistema' ? MEDIA_TEMA[dela] : (dela === tema ? 'all' : 'not all');
  }
  for (const r of document.querySelectorAll('input[name="' + NOME_TEMA + '"]')) r.checked = r.value === tema;
  return tema;
}

// ------------------------------------------------------------------ pecas
// Lugar do aviso que lembra o ultimo mostrado (a tela redesenhada o recebe).
function avisoLembrado(inicial) {
  const lugar = lugarAviso();
  let atual = null;
  const r = {
    el: lugar.el,
    mostrar(tipo, texto, cru) { atual = { tipo, texto, cru }; lugar.mostrar(tipo, texto, cru); },
    limpar() { atual = null; lugar.limpar(); },
    atual: () => atual,
  };
  if (inicial) r.mostrar(inicial.tipo, inicial.texto, inicial.cru);
  return r;
}

function menu(secao) {
  return h('nav', { class: 'sessao-menu', 'aria-label': t('sessao.menu') }, SECOES_SESSAO.map((s) => [
    s === 'painel' ? h('span', { class: 'sessao-separador', 'aria-hidden': 'true' }) : null,
    h('a', { class: 'sessao-item', href: '#/sessao/' + s, 'aria-current': s === secao ? 'page' : null }, t('secao.nome', { secao: s })),
  ]));
}

// O botao ocupado fica desabilitado e o navegador tira o foco dele: ao
// liberar, o foco volta ao botao (se nao foi para um campo com erro), para o
// redesenho seguinte o manter no lugar.
function liberar(restaurar, btn) {
  restaurar();
  const ativo = document.activeElement;
  if (!ativo || ativo === document.body) btn.focus({ preventScroll: true });
}

// ------------------------------------------------------------------ fila
// POST /api/fila monta a fila no worker. Deu certo quando a sessao e gravada
// (a geracao sobe); nao deu quando chega aviso sem gravacao.
async function montarFila(ctx, f, resposta, form) {
  const antes = ctx.modelo();
  const g = antes.geracao;
  const n = antes.aviso.n;
  const res = await ctx.api.comando('/api/fila', { inicio: f.Inicio, fim: f.Fim, local: f.Local, rack: f.Rack, andar: f.Andar });
  if (!res.ok) { mostrarFalha(res, resposta, form); return false; }
  const veio = await ctx.esperar((m) => !m.ocupado && (m.geracao > g || m.aviso.n > n), ESPERA_SESSAO_MS);
  const m = ctx.modelo();
  if (!veio) { resposta.mostrar('atencao', t('inicio.demorou')); return false; }
  if (m.geracao <= g) { resposta.mostrar('erro', m.aviso.texto || t('inicio.demorou')); return false; }
  await ctx.recarregarSessao();
  const texto = m.fila ? t('sessao.fila.montada', { n: m.fila.total, inicio: m.fila.inicio, fim: m.fila.fim }) : t('sessao.salvas');
  // Montou com ressalva (sem Administrador: uma camera por vez).
  if (m.aviso.n > n && m.aviso.texto) resposta.mostrar('atencao', texto + ' ' + m.aviso.texto);
  else resposta.mostrar('sucesso', texto);
  return true;
}

// ------------------------------------------------------------------ secao com formulario
// Nota junto do botao. Placa e Rede: salvar a placa ou as faixas devolve a
// placa e a prepara de novo (decisao N3: o servidor segue igual, a tela diz).
// Fila: Salvar so guarda a faixa; Montar a fila troca a fila agora.
const NOTA_SALVAR = { placa: 'sessao.placa.nota', rede: 'sessao.rede.nota', fila: 'sessao.fila.nota' };

function secaoFormulario(ctx, modelo, secao, est, resposta) {
  const form = montarFormulario(secao, modelo, { lerPlacas: () => { est.sujo = false; ctx.lerPlacas(); } });
  const notaId = NOTA_SALVAR[secao] ? novoId('sessao-nota') : undefined;
  // Na simulacao a senha nao e usada: a secao so mostra a nota.
  const salvar = secao === 'senha' && modelo.simular ? null : botao(t('sessao.salvar'), null, { tipo: 'primario', submit: true, motivoId: notaId });
  if (salvar) salvar.id = 'sessao-salvar';
  let montar = null;

  async function aoSalvar(ev) {
    ev.preventDefault();
    if (est.ocupada || !salvar) return;
    resposta.limpar();
    const r = form.coletar();
    if (!r.ok) return;
    if (secao === 'senha' && !r.senha) { est.sujo = false; resposta.mostrar('info', t('sessao.senhaContinua')); return; }
    est.ocupada = true;
    const restaurar = ocupar(salvar, t('sessao.salvando'));
    let ok = false;
    try {
      ok = secao === 'senha' ? await salvarSenha(ctx, r.senha, resposta, form) : await salvarParcial(ctx, r.parcial, resposta, form);
    } finally { est.ocupada = false; liberar(restaurar, salvar); }
    if (!ok) return;
    est.sujo = false;
    resposta.mostrar('sucesso', t('sessao.salvas'));
  }

  // Ate o painel lateral da frente 4, a fila nova se monta aqui (decisao do usuario).
  async function aoMontar() {
    if (est.ocupada) return;
    resposta.limpar();
    const r = form.coletar();
    if (!r.ok) return;
    const atual = ctx.modelo().fila;
    if (atual) {
      const sim = await ctx.confirmar({
        titulo: t('sessao.fila.trocar.titulo'),
        texto: t('sessao.fila.trocar.texto', { inicio: atual.inicio, fim: atual.fim, total: atual.total, pend: atual.pendentes }),
        confirmar: t('sessao.fila.trocar.botao'),
      });
      if (!sim) return;
    }
    est.ocupada = true;
    const restaurar = ocupar(montar, t('sessao.fila.montando'));
    let ok = false;
    try { ok = await montarFila(ctx, r.parcial.Fila, resposta, form); } finally { est.ocupada = false; liberar(restaurar, montar); }
    if (ok) est.sujo = false;
  }

  if (secao === 'fila') {
    montar = botao(t('sessao.fila.montar'), aoMontar, { tipo: 'secundario' });
    montar.id = 'sessao-montar';
  }
  const marcarSujo = () => { est.sujo = true; };
  return h('form', { class: 'form sessao-form', novalidate: true, onsubmit: aoSalvar, oninput: marcarSujo, onchange: marcarSujo }, [
    form.el,
    notaId && salvar ? h('p', { class: 'sessao-nota', id: notaId }, t(NOTA_SALVAR[secao])) : null,
    salvar ? h('div', { class: 'sessao-acoes' }, [salvar, montar]) : null,
    resposta.el,
  ]);
}

// ------------------------------------------------------------------ secao Rede: qualquer faixa
// Escolha do vigia, fora do formulario (nao passa pelo Salvar alteracoes): vale
// na hora com o vigia ligado e no proximo Ligar com ele desligado. O risco fica
// escrito embaixo, sem title (UX-10, UI-11).
function blocoQualquerFaixa(ctx, modelo, est) {
  const resultado = lugarAviso();
  const riscoId = novoId('qualquer-faixa-risco');
  async function trocar(ev) {
    const caixa = ev.target;
    resultado.limpar();
    est.ocupada = true;
    caixa.disabled = true;
    let r;
    try { r = await ctx.definirQualquerFaixa(caixa.checked); } finally { est.ocupada = false; caixa.disabled = false; }
    if (!r.ok) {
      const falha = traduzirServidor(r);
      resultado.mostrar('erro', t('sessao.rede.qualquerFaixa.erro', { motivo: falha.texto }), falha.cru);
      return;
    }
    const chave = caixa.checked ? 'ligada' : 'desligada';
    resultado.mostrar('sucesso', t('sessao.rede.qualquerFaixa.' + chave, { agora: !!r.agora }));
  }
  return h('div', { class: 'sessao-bloco' }, [
    h('label', { class: 'check' }, [
      h('input', { type: 'checkbox', name: 'qualquerFaixa', checked: modelo.vigia.qualquerFaixa, 'aria-describedby': riscoId, onchange: trocar }),
      t('sessao.rede.qualquerFaixa'),
    ]),
    h('p', { class: 'campo-ajuda', id: riscoId }, t('sessao.rede.qualquerFaixa.risco')),
    resultado.el,
  ]);
}

// ------------------------------------------------------------------ secao Painel
function blocoTema(ctx) {
  const avisoTema = lugarAviso();
  const atual = document.documentElement.dataset.tema || TEMAS[0];
  async function trocar(ev) {
    const anterior = document.documentElement.dataset.tema;
    const novo = aplicarTema(ev.target.value);
    avisoTema.limpar();
    const res = await ctx.api.tema(novo);
    if (res.ok) return;
    aplicarTema(anterior);
    const falha = traduzirServidor(res);
    avisoTema.mostrar('erro', t('sessao.painel.temaErro', { motivo: falha.texto }), falha.cru);
  }
  const opcoes = TEMAS.map((tema) => h('label', null, [
    h('input', { type: 'radio', id: 'tema-' + tema, name: NOME_TEMA, value: tema, checked: tema === atual }),
    t('sessao.painel.tema.' + tema),
  ]));
  return h('div', { class: 'sessao-bloco' }, [
    h('fieldset', { class: 'tema', onchange: trocar }, [
      h('legend', null, t('sessao.painel.tema')),
      h('div', { class: 'segmentos' }, opcoes),
    ]),
    avisoTema.el,
  ]);
}

// Versao e o resultado da ultima procura automatica (o servidor procura uma vez
// por dia). Procurar sob demanda fica para a frente 5 (decisao do usuario).
function textoProcura(a) {
  const quando = a.ultimaChecagem ? dataHora(a.ultimaChecagem) : '';
  if (a.estado === 'desligada') return t('sessao.painel.procura.desligada');
  if (a.estado === 'disponivel') return t('sessao.painel.procura.disponivel', { versao: a.versao, quando });
  if (a.estado === 'erro') return t('sessao.painel.procura.erro', { versao: a.versao });
  if (['baixando', 'verificando', 'instalando'].includes(a.estado)) return t('sessao.painel.procura.andamento', { versao: a.versao });
  return quando ? t('sessao.painel.procura.nenhuma', { quando }) : t('sessao.painel.procura.nunca');
}

function blocoVersao(modelo) {
  return h('div', { class: 'sessao-bloco' }, [
    h('h3', null, t('sessao.painel.versao', { v: modelo.versao })),
    h('p', { class: 'sessao-nota' }, textoProcura(modelo.atualizacao)),
  ]);
}

function blocoRefazer(ctx, est) {
  const resposta = lugarAviso();
  const refazer = botao(t('sessao.painel.refazer'), aoRefazer, { tipo: 'secundario' });
  refazer.id = 'sessao-refazer';
  async function aoRefazer() {
    if (est.ocupada) return;
    resposta.limpar();
    const sim = await ctx.confirmar({
      titulo: t('sessao.refazer.titulo'),
      texto: t('sessao.refazer.texto', { temFila: !!ctx.modelo().fila }),
      confirmar: t('sessao.painel.refazer'),
    });
    if (!sim) return;
    est.ocupada = true;
    const restaurar = ocupar(refazer, t('sessao.painel.refazendo'));
    let ok = false;
    try {
      const res = await ctx.api.comando('/api/sessao/refazer');
      if (!res.ok) mostrarFalha(res, resposta, null);
      else if (await ctx.esperar((m) => m.inicio, ESPERA_ESTADO_MS)) ok = true;
      else resposta.mostrar('atencao', t('inicio.demorou'));
    } finally { est.ocupada = false; liberar(restaurar, refazer); }
    if (ok) ctx.ir(rotaDoPasso(ctx.modelo().passoSugerido));
  }
  return h('div', { class: 'sessao-bloco' }, [
    h('h3', null, t('sessao.painel.passo')),
    h('p', { class: 'sessao-nota' }, t('sessao.painel.passo.apoio')),
    refazer,
    resposta.el,
  ]);
}

function blocoSobre() {
  return h('div', { class: 'sessao-bloco' }, [
    h('h3', null, t('sessao.painel.sobre')),
    logo(),
    h('p', { class: 'sessao-nota' }, t('sessao.painel.sobre.texto')),
  ]);
}

// ------------------------------------------------------------------ tela
// parte: a secao da rota, ja conferida pelo app.js. avisoAntes: o aviso da
// tela anterior da mesma secao (redesenho depois de salvar).
export function telaSessao(ctx, parte, avisoAntes) {
  const modelo = ctx.modelo();
  const secao = SECOES_SESSAO.includes(parte) ? parte : SECOES_SESSAO[0];
  const est = { sujo: false, ocupada: false };
  const resposta = avisoLembrado(avisoAntes);
  const tituloId = novoId('sessao-secao');
  const tituloSecao = h('h2', { id: tituloId, class: 'sessao-secao-titulo' }, t('secao.nome', { secao }));
  const lead = secao === 'painel' ? t('sessao.painel.lead') : t(secao + '.lead');
  const corpo = secao === 'painel'
    ? [blocoTema(ctx), blocoVersao(modelo), blocoRefazer(ctx, est), blocoSobre()]
    : [secaoFormulario(ctx, modelo, secao, est, resposta), secao === 'rede' ? blocoQualquerFaixa(ctx, modelo, est) : null];
  const el = h('div', { class: 'sessao-tela' }, [
    h('div', { class: 'sessao-cabeca' }, [h('h1', null, t('sessao.titulo')), h('p', { class: 'lead' }, t('sessao.lead'))]),
    h('div', { class: 'sessao-grade' }, [
      menu(secao),
      h('section', { class: 'sessao-secao', 'aria-labelledby': tituloId }, [
        h('div', { class: 'sessao-secao-cabeca' }, [tituloSecao, h('p', { class: 'lead' }, lead)]),
        corpo,
      ]),
    ]),
  ]);
  return {
    el,
    foco: tituloSecao,
    secao,
    sujo: () => est.sujo,
    ocupada: () => est.ocupada,
    aviso: () => resposta.atual(),
  };
}
