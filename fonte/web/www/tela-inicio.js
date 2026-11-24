// Passo a passo e Conferir (direcao.md, secoes 2.2 e 3.1): seis passos numa
// coluna de leitura sob a logo, trilha com numero, palavra e icone, e rodape
// fixo com Voltar e Avancar ou Comecar. A tela recebe o modelo (estado.js) e o
// contexto do app.js (decisao N1): nao busca nem guarda estado. Os formularios
// vem do formularios.js; aqui so o salvar, a navegacao e o Conferir.
import { h } from './dom.js';
import { icone } from './icones.js';
import { t } from './textos.js';
import { logo } from './marca.js';
import { botao, ocupar, lugarAviso, chip, aviso } from './componentes.js';
import { montarFormulario, mostrarErrosServidor, pcNaFabrica } from './formularios.js';
import { rotaDoPasso, ROTA_INICIAL } from './rotas.js';
import { numero, resolucao, mac } from './formato.js';
import {
  PASSOS, ETAPA_DO_PASSO, HTTP, NBSP, ESPERA_ESTADO_MS, ESPERA_SESSAO_MS, ESPERA_COMECAR_MS,
} from './constantes.js';

// ctx (do app.js): { api, modelo(), ir(hash), corrigir(hash), confirmar(o),
// esperar(cond, ms), recarregarSessao(), lerPlacas(), redesenhar(foco) }.
// As duas telas devolvem { el, foco, acao, sujo(), ocupada() }: o app.js nao
// redesenha por cima de uma tela com campo mexido ou salvando.

// ------------------------------------------------------------------ pecas comuns
function cabeca(modelo) {
  return h('header', { class: 'inicio-cabeca' }, [
    logo(),
    modelo.simular ? chip(t('chip.simulacao'), 'neutro', 'simulacao') : null,
  ]);
}

// Trilha (UI-10): numero, palavra e, nos feitos, o icone. Abre ate o passo mais
// adiante que o modelo deixa; os de depois sao so texto.
function trilha(modelo, atual) {
  const iAtual = PASSOS.indexOf(atual);
  const iMax = PASSOS.indexOf(modelo.passoMax);
  const itens = PASSOS.map((passo, i) => {
    const corrente = i === iAtual;
    const feito = !corrente && i < iMax;
    const conteudo = [
      h('span', { class: 'trilha-numero' }, feito ? icone('concluido') : String(i + 1)),
      h('span', null, t('secao.nome', { secao: passo })),
      feito ? h('span', { class: 'so-leitor' }, t('inicio.feito')) : null,
    ];
    const aberto = !corrente && i <= iMax;
    return h('li', {
      class: ['trilha-passo', feito ? 'trilha-feito' : null, corrente ? 'trilha-atual' : null],
      'aria-current': corrente ? 'step' : null,
    }, aberto ? h('a', { class: 'trilha-link', href: rotaDoPasso(passo) }, conteudo) : conteudo);
  });
  return h('nav', { class: 'inicio-trilha', 'aria-label': t('inicio.trilha') }, h('ol', { class: 'trilha-lista' }, itens));
}

// Rodape fixo (UX-20); estreito alinha os botoes com a coluna do formulario.
function rodape(esquerda, direita, estreito) {
  return h('footer', { class: 'rodape' }, h('div', { class: 'rodape-conteudo' },
    h('div', { class: ['rodape-linha', estreito ? 'rodape-estreito' : null] }, [esquerda || h('span'), h('div', { class: 'rodape-fim' }, direita)])));
}

function corpo(modelo, atual, classe, filhos) {
  return h('div', { class: 'inicio-tela' }, [
    cabeca(modelo),
    h('div', { class: ['inicio-corpo', classe] }, [
      h('h1', { class: 'inicio-titulo' }, t('inicio.titulo')),
      trilha(modelo, atual),
      filhos,
    ]),
  ]);
}

// Falha de salvar: erro por campo no campo (400), "aguarde" em atencao (409),
// sem resposta com o conserto. Devolve nada; quem chama so para.
function mostrarFalha(res, resposta, form) {
  if (res.semResposta) { resposta.mostrar('erro', t('erro.semResposta')); return; }
  const d = res.detalhe || {};
  if (res.codigo === HTTP.REQUISICAO_INVALIDA && form && Array.isArray(d.campos) && d.campos.length) {
    const resto = mostrarErrosServidor(form, d.campos);
    const marcados = d.campos.length - resto.length;
    const texto = resto.length ? resto.join(' ') : t('form.nada-salvo', { marcados });
    resposta.mostrar('erro', texto);
    return;
  }
  const texto = res.mensagem || (Array.isArray(d.erros) ? d.erros.join(' ') : '') || t('erro.http', { codigo: res.codigo });
  resposta.mostrar(res.codigo === HTTP.CONFLITO ? 'atencao' : 'erro', texto);
}

// Senha nova: comando e espera o estado dizer que ela chegou ao worker.
async function salvarSenha(ctx, senha, resposta, form) {
  const res = await ctx.api.comando('/api/senha', { senha });
  if (!res.ok) { mostrarFalha(res, resposta, form); return false; }
  if (await ctx.esperar((m) => m.senhaDefinida, ESPERA_ESTADO_MS)) return true;
  resposta.mostrar('atencao', t('inicio.demorou'));
  return false;
}

// PUT /api/sessao e a espera da gravacao (a geracao sobe). Rede trocada com fila
// na memoria volta 409 pedindo confirmacao: o dialogo pergunta e reenvia.
async function salvarParcial(ctx, parcial, resposta, form) {
  const g = ctx.modelo().geracao;
  let res = await ctx.api.salvarSessao(parcial);
  if (!res.ok && res.codigo === HTTP.CONFLITO && res.detalhe && res.detalhe.precisaConfirmar) {
    const sim = await ctx.confirmar({ titulo: t('rede.confirmar.titulo'), texto: res.mensagem, confirmar: t('rede.confirmar.botao') });
    if (!sim) return false;
    res = await ctx.api.salvarSessao({ ...parcial, confirmar: true });
  }
  if (!res.ok) { mostrarFalha(res, resposta, form); return false; }
  if (!await ctx.esperar((m) => m.geracao > g, ESPERA_SESSAO_MS)) {
    resposta.mostrar('atencao', t('inicio.demorou'));
    return false;
  }
  await ctx.recarregarSessao();
  return true;
}

// ------------------------------------------------------------------ passo
export function telaPasso(ctx, passo) {
  const modelo = ctx.modelo();
  const i = PASSOS.indexOf(passo);
  let sujo = false;
  let ocupada = false;
  const lerPlacas = () => { sujo = false; ctx.lerPlacas(); };
  const form = montarFormulario(passo, modelo, { lerPlacas });
  const resposta = lugarAviso();
  const titulo = h('h2', { class: 'inicio-secao-titulo' }, t(passo + '.titulo'));
  const formId = 'form-passo-' + passo;

  let rotulo = t('inicio.avancar');
  let rotuloOcupado = t('inicio.salvando');
  if (passo === 'senha' && !modelo.simular && !modelo.senhaDefinida) { rotulo = t('senha.salvar'); rotuloOcupado = t('senha.salvando'); }
  const avancar = botao(rotulo, null, { tipo: 'primario', submit: true });
  avancar.setAttribute('form', formId);

  async function salvar(r) {
    if (passo === 'senha') return r.senha ? salvarSenha(ctx, r.senha, resposta, form) : true;
    return salvarParcial(ctx, { ...r.parcial, etapa: ETAPA_DO_PASSO[passo] }, resposta, form);
  }

  async function aoEnviar(ev) {
    ev.preventDefault();
    if (ocupada) return;
    resposta.limpar();
    const r = form.coletar();
    if (!r.ok) return;
    ocupada = true;
    const restaurar = ocupar(avancar, rotuloOcupado);
    let ok = false;
    try { ok = await salvar(r); } finally { ocupada = false; restaurar(); }
    if (!ok) return;
    sujo = false;
    ctx.ir(rotaDoPasso(ctx.modelo().sessaoCompleta ? 'conferir' : PASSOS[i + 1]));
  }

  const voltar = i > 0 ? botao(t('inicio.voltar'), () => ctx.ir(rotaDoPasso(PASSOS[i - 1])), { tipo: 'secundario' }) : null;
  const marcarSujo = () => { sujo = true; };
  const el = h('div', { class: 'inicio-passo' }, [
    corpo(modelo, passo, null, [
      h('div', { class: 'inicio-secao' }, [titulo, h('p', { class: 'lead' }, t(passo + '.lead'))]),
      h('form', { id: formId, class: 'form', novalidate: true, onsubmit: aoEnviar, oninput: marcarSujo, onchange: marcarSujo }, form.el),
      resposta.el,
    ]),
    rodape(voltar, avancar, true),
  ]);
  return { el, foco: titulo, acao: avancar, sujo: () => sujo, ocupada: () => ocupada };
}

// ------------------------------------------------------------------ conferir
const mono = (texto) => h('span', { class: 'mono' }, texto);

// "Rotulo valor, rotulo valor": rotulo em texto, IP em mono.
function pares(lista) {
  const partes = [];
  for (const [rotulo, ip] of lista) {
    if (partes.length) partes.push(t('conferir.virgula'));
    partes.push(rotulo + ' ', ip ? mono(ip) : t('conferir.automatico'));
  }
  return h('span', null, partes);
}

function textoStream(v) {
  const fps = numero(v.Fps) + NBSP + t('unidade.fps');
  const kbps = numero(v.BitRate) + NBSP + t('unidade.kbps');
  return [resolucao(v.Resolucao), fps, kbps, v.Codec].join(t('conferir.virgula'));
}

// Valor de cada secao, ou null se ela ainda nao foi salva.
function valorSecao(secao, modelo) {
  const s = modelo.sessao;
  if (modelo.etapa < ETAPA_DO_PASSO[secao]) return null;
  if (secao === 'placa') {
    const p = s.Placa;
    if (!p || !p.Nome) return null;
    const tipo = p.Tipo === 'wifi' ? t('placas.wifi') : t('placas.ethernet');
    return h('span', null, [p.Nome, t('geral.separador'), tipo, p.Mac ? [t('geral.separador'), mono(mac(p.Mac))] : null]);
  }
  if (secao === 'rede') {
    if (!s.Gateway) return null;
    const dns = [s.Dns1, s.Dns2].filter(Boolean);
    // Duas linhas: a rede das cameras e a faixa de fabrica (cabe sem rolar a 768).
    return [
      h('span', null, [
        pares([[t('rede.gateway'), s.Gateway], [t('conferir.mascara'), s.Mascara]]),
        dns.length ? [t('conferir.virgula') + t('conferir.dns') + ' ', dns.map((d, n) => [n ? t('conferir.e') : '', mono(d)])] : null,
        t('conferir.virgula'),
        pares([[t('conferir.ipPc'), s.IpPcCameras]]),
      ]),
      pares([[t('rede.fabrica.ip'), s.IpFabrica], [t('rede.fabrica.pc'), s.IpPcFabrica || pcNaFabrica(s.IpFabrica)]]),
    ];
  }
  if (secao === 'camera') {
    if (!s.EmailRecuperacao) return null;
    return [
      h('span', null, s.EmailRecuperacao),
      h('span', null, t('conferir.streams', { principal: textoStream(s.Encoder.Principal), secundario: textoStream(s.Encoder.Secundario) })),
    ];
  }
  if (secao === 'fila') {
    const f = s.Fila;
    if (!f || !f.Inicio) return null;
    const lugar = [f.Local, f.Rack && t('conferir.rack', { v: f.Rack }), f.Andar && t('conferir.andar', { v: f.Andar })].filter(Boolean);
    return [
      h('span', null, [mono(f.Inicio), t('conferir.ate'), mono(f.Fim)]),
      lugar.length ? h('span', null, lugar.join(t('conferir.virgula'))) : null,
    ];
  }
  return null;
}

function falta() {
  return h('span', { class: 'conferir-falta' }, [icone('atencao'), h('span', null, t('conferir.falta'))]);
}

function alterar(secao) {
  return h('a', { class: 'botao botao-discreto', href: rotaDoPasso(secao) }, t('secao.alterar', { secao }));
}

function linha(secao, valor, acao) {
  return h('div', { class: 'conferir-linha' }, [
    h('div', { class: 'conferir-rotulo' }, t('secao.nome', { secao })),
    h('div', { class: 'conferir-valor' }, valor),
    h('div', { class: 'conferir-acao' }, acao),
  ]);
}

export function telaConferir(ctx) {
  const modelo = ctx.modelo();
  let ocupada = false;
  let sujo = false;
  const resposta = lugarAviso();
  const titulo = h('h2', { class: 'inicio-secao-titulo' }, t('conferir.titulo'));

  // Senha: a linha de cima. Sem senha nesta abertura (sessao guardada), o campo
  // fica aqui mesmo e o Comecar salva junto (UX-16).
  let formSenha = null;
  let senhaValor;
  let senhaAcao = null;
  if (modelo.simular) {
    senhaValor = h('span', { class: 'apoio' }, t('senha.simulacao'));
  } else if (modelo.senhaDefinida) {
    senhaValor = h('span', null, t('senha.salva'));
    senhaAcao = alterar('senha');
  } else {
    formSenha = montarFormulario('senha', modelo);
    senhaValor = h('div', { class: 'conferir-senha', oninput: () => { sujo = true; } }, [
      h('p', { class: 'conferir-pede' }, t('conferir.senhaPede')),
      formSenha.el,
    ]);
  }

  const linhas = [linha('senha', senhaValor, senhaAcao)];
  for (const secao of ['placa', 'rede', 'camera']) {
    linhas.push(linha(secao, valorSecao(secao, modelo) || falta(), alterar(secao)));
  }

  // Fila: o conflito com o registro aparece na linha dela, com a saida pronta (UX-27).
  const fila = [valorSecao('fila', modelo) || falta()];
  const cf = modelo.conflito;
  let usarSeguinte = null;
  if (cf && cf.instaladas && modelo.registroCarregado) {
    // A faixa ja esta na linha de cima: o aviso so diz o que houve, e a saida
    // fica ao lado dele (cabe sem rolar a 768).
    const conflito = [aviso('atencao', cf.todas
      ? t('fila.conflito.todas', { n: cf.total })
      : t('fila.conflito.parte', { n: cf.instaladas, total: cf.total }))];
    if (cf.todas && cf.seguinte) {
      usarSeguinte = botao(t('fila.usarSeguinte', cf.seguinte), trocarFaixa, { tipo: 'secundario' });
      conflito.push(usarSeguinte);
    }
    fila.push(h('div', { class: 'conferir-conflito' }, conflito));
  }
  linhas.push(linha('fila', fila, alterar('fila')));

  async function trocarFaixa() {
    if (ocupada) return;
    resposta.limpar();
    ocupada = true;
    const restaurar = ocupar(usarSeguinte, t('fila.trocandoFaixa'));
    let ok = false;
    try {
      ok = await salvarParcial(ctx, { Fila: { ...modelo.sessao.Fila, Inicio: cf.seguinte.inicio, Fim: cf.seguinte.fim } }, resposta, null);
    } finally { ocupada = false; restaurar(); }
    if (ok) ctx.redesenhar('acao');
  }

  const comecar = botao(t('inicio.comecar'), aoComecar, { tipo: 'primario' });
  async function aoComecar() {
    if (ocupada) return;
    resposta.limpar();
    let senha = null;
    if (formSenha) {
      const r = formSenha.coletar();
      if (!r.ok) return;
      senha = r.senha;
    }
    ocupada = true;
    const restaurar = ocupar(comecar, t('inicio.comecando'));
    let ok = false;
    try {
      ok = !senha || await salvarSenha(ctx, senha, resposta, formSenha);
      if (ok) {
        const m = ctx.modelo();
        const res = await ctx.api.comando('/api/sessao/concluir', { montarFila: !!m.sessao.Fila });
        if (!res.ok) { mostrarFalha(res, resposta, null); ok = false; }
      }
      if (ok && !await ctx.esperar((m) => m.sessaoIniciada && !m.ocupado, ESPERA_COMECAR_MS)) {
        resposta.mostrar('atencao', t('inicio.comecar.demorou'));
        ok = false;
      }
    } finally { ocupada = false; restaurar(); }
    if (!ok) return;
    sujo = false;
    ctx.corrigir(ROTA_INICIAL);
    ctx.ir(ROTA_INICIAL);
  }

  const voltar = modelo.sessaoCompleta ? null : botao(t('inicio.voltar'), () => ctx.ir(rotaDoPasso('fila')), { tipo: 'secundario' });
  const nota = h('span', { class: 'rodape-nota' }, t('inicio.comecar.nota', { simular: modelo.simular }));
  const el = h('div', { class: 'inicio-passo' }, [
    corpo(modelo, 'conferir', 'inicio-conferir', [
      h('div', { class: 'inicio-secao' }, [titulo, h('p', { class: 'lead' }, t('conferir.lead'))]),
      h('div', { class: 'conferir-lista' }, linhas),
      resposta.el,
    ]),
    rodape(voltar, [nota, comecar]),
  ]);
  return { el, foco: titulo, acao: comecar, sujo: () => sujo, ocupada: () => ocupada };
}
