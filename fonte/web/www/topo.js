// Topo fixo do console (direcao.md, secoes 2.1 e 5.9): simbolo, nome, as tres
// abas, os chips de estado com popover e "Encerrar o painel". Le so o modelo
// (estado.js); fala com o servidor so pelo ctx.api.
// ctx: { api, recarregar(), encerrado(restaurando) }
import { h } from './dom.js';
import { t, nomeEtapa, traduzirServidor } from './textos.js';
import { ABAS } from './rotas.js';
import { botao, chip, popover, detalhe, lugarAviso, ocupar, confirmar } from './componentes.js';
import { simbolo } from './marca.js';

// motivo da placa (estado.js) -> [rotulo do chip, icone, frase do popover]
const CHIP_PLACA = Object.freeze({
  simulacao: ['chip.placa', 'placa', 'popover.placa.simulacao'],
  'sem-sessao': ['chip.placa', 'placa', 'popover.placa.semSessao'],
  'com-faixas': ['chip.placa', 'placa', 'popover.placa.comFaixas'],
  pronta: ['chip.placaPronta', 'concluido', 'popover.placa.pronta'],
  'sem-cabo': ['chip.placaSemCabo', 'falha', 'popover.placa.semCabo'],
  ausente: ['chip.placaAusente', 'falha', 'popover.placa.ausente'],
  'nao-preparada': ['chip.placaNaoPreparada', 'falha', 'popover.placa.naoPreparada'],
});

const FRASE_INTERNET = Object.freeze({
  ok: 'popover.internet.ok',
  caiu: 'popover.internet.caiu',
  'ja-sem': 'popover.internet.jaSem',
  sem: 'popover.internet.sem',
  'nao-testado': 'popover.internet.naoTestado',
});

export function criarTopo(ctx) {
  const links = ABAS.map((aba) => h('a', { class: 'topo-aba', href: '#/' + aba, dados: { aba } }, t('nav.' + aba)));

  const placa = criarChipPlaca(ctx);
  const internet = criarChipInternet(ctx);
  const simulacao = criarChipSimulacao();

  const encerrar = botao(t('nav.encerrar'), async () => {
    const m = modelo;
    if (!m) return;
    const sim = await confirmar({
      titulo: t('dialogo.encerrarPainel.titulo'),
      texto: t('dialogo.encerrarPainel.texto', {
        situacao: m.fase === 'configurando' ? 'configurando' : (m.ocupado ? 'ocupado' : ''),
        dhcp: m.placa.preparada,
      }),
      confirmar: t('dialogo.encerrarPainel.confirmar'),
      perigo: true,
    });
    if (!sim) return;
    // O servidor fecha logo depois de responder: sem resposta tambem e encerrado.
    const r = await ctx.api.comando('/api/encerrar', {});
    ctx.encerrado(!!(r.ok && r.dados && r.dados.restaurando));
  }, { tipo: 'secundario' });

  const el = h('header', { class: 'topo', hidden: true }, h('div', { class: 'topo-conteudo' }, [
    h('a', { class: 'topo-marca', href: '#/painel' }, [simbolo(), h('span', { class: 'topo-nome' }, t('app.titulo'))]),
    h('nav', { class: 'topo-nav', 'aria-label': t('nav.rotulo') }, links),
    h('span'),
    h('div', { class: 'topo-chips' }, [placa.el, internet.el, simulacao.el]),
    encerrar,
  ]));

  let modelo = null;

  return {
    el,
    atualizar(m, tela) {
      modelo = m;
      el.hidden = !m.carregado || m.inicio;
      for (const a of links) {
        if (a.dataset.aba === tela) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
      }
      placa.atualizar(m);
      internet.atualizar(m);
      simulacao.atualizar(m);
    },
  };
}

// Botao do chip (abre o popover) + o popover. O botao e o popover nascem uma
// vez; o polling so troca o conteudo, e o popover aberto continua aberto.
function chipComPopover(id, titulo, corpo) {
  const btn = h('button', { type: 'button', class: 'chip-botao', popovertarget: id });
  const pop = popover(id, titulo, corpo);
  let assinatura = '';
  return {
    el: h('span', { class: 'topo-chip' }, [btn, pop]),
    btn,
    pop,
    // Redesenha o chip so quando rotulo, nivel ou icone mudam.
    chip(rotulo, nivel, nomeIcone) {
      const nova = rotulo + '|' + nivel + '|' + nomeIcone;
      if (nova === assinatura) return;
      assinatura = nova;
      btn.setAttribute('aria-label', t('chip.detalhe', { nome: rotulo }));
      btn.replaceChildren(chip(rotulo, nivel, nomeIcone));
    },
  };
}

// Acao de rede de dentro do popover: ocupa o botao, mostra o erro no proprio
// popover e pede o estado novo ao terminar.
async function acaoRede(ctx, btn, rotuloOcupado, rota, aviso) {
  const restaurar = ocupar(btn, rotuloOcupado);
  aviso.limpar();
  const r = await ctx.api.comando(rota, {});
  restaurar();
  if (!r.ok) {
    const falha = traduzirServidor(r);
    aviso.mostrar('erro', falha.texto, falha.cru);
  }
  await ctx.recarregar();
}

function criarChipPlaca(ctx) {
  const frase = h('p');
  const listas = h('div', { class: 'popover-listas' });
  const nota = h('p', { class: 'popover-nota' });
  const aviso = lugarAviso();
  const preparar = botao(t('popover.placa.preparar'), () => acaoRede(ctx, preparar, t('popover.placa.preparando'), '/api/rede/preparar', aviso), { tipo: 'primario' });
  const restaurar = botao(t('popover.placa.restaurar'), async () => {
    const sim = await confirmar({
      titulo: t('dialogo.restaurar.titulo'),
      texto: t('dialogo.restaurar.texto'),
      confirmar: t('dialogo.restaurar.confirmar'),
      perigo: true,
    });
    if (sim) await acaoRede(ctx, restaurar, t('popover.placa.restaurando'), '/api/rede/restaurar', aviso);
  }, { tipo: 'secundario' });
  const acoes = h('div', { class: 'popover-acoes' }, [preparar, restaurar]);
  const tecnico = h('div');
  const c = chipComPopover('popover-placa', t('popover.placa.titulo'), h('div', { class: 'popover-corpo' }, [frase, listas, nota, acoes, aviso.el, tecnico]));
  let assinatura = '';

  function lista(rotulo, itens) {
    if (!itens.length) return null;
    return h('div', { class: 'popover-lista' }, [
      h('span', { class: 'popover-rotulo' }, rotulo),
      itens.map((x) => h('span', { class: 'mono' }, x)),
    ]);
  }

  return {
    el: c.el,
    atualizar(m) {
      const p = m.placa;
      const [rotulo, nomeIcone, chaveFrase] = CHIP_PLACA[p.motivo];
      c.chip(t(rotulo), p.nivel, nomeIcone);
      // Botoes: fora da simulacao; travados enquanto o painel trabalha.
      preparar.hidden = !p.podePreparar;
      restaurar.hidden = !p.podeRestaurar;
      acoes.hidden = preparar.hidden && restaurar.hidden;
      if (!preparar.hasAttribute('aria-busy')) preparar.disabled = m.ocupado;
      if (!restaurar.hasAttribute('aria-busy')) restaurar.disabled = m.ocupado;
      const nova = JSON.stringify([p, m.pastaAlternativa]);
      if (nova === assinatura) return;
      assinatura = nova;
      frase.textContent = t(chaveFrase, { nome: p.nome || t('popover.placa.semNome') });
      listas.replaceChildren(...[
        lista(t('popover.placa.ips'), p.ips),
        lista(t('popover.placa.faltando'), p.faltando),
        lista(t('popover.placa.temporarios'), p.temporarios.map((x) => (x.camera ? t('popover.placa.temporario', x) : x.ip))),
        lista(t('popover.placa.rotas'), p.rotas),
      ].filter(Boolean));
      const notas = [p.preparada ? t('popover.placa.voltaDhcp') : '', m.pastaAlternativa ? t('popover.placa.pasta', { pasta: m.pastaAlternativa }) : ''];
      nota.textContent = notas.filter(Boolean).join(' ');
      nota.hidden = !nota.textContent;
      tecnico.replaceChildren(p.ifIndex ? detalhe(t('detalhe.ifIndex', { n: p.ifIndex })) : '');
    },
  };
}

function criarChipInternet(ctx) {
  const frase = h('p');
  const aviso = lugarAviso();
  const testar = botao(t('popover.internet.testar'), () => acaoRede(ctx, testar, t('popover.internet.testando'), '/api/internet/testar', aviso), { tipo: 'secundario' });
  const c = chipComPopover('popover-internet', t('popover.internet.titulo'), h('div', { class: 'popover-corpo' }, [
    frase,
    h('div', { class: 'popover-acoes' }, testar),
    aviso.el,
  ]));
  return {
    el: c.el,
    atualizar(m) {
      const i = m.internet;
      c.chip(i.semResposta ? t('chip.semInternet') : t('chip.internet'), i.nivel, i.semResposta ? 'falha' : 'internet');
      frase.textContent = t(FRASE_INTERNET[i.motivo], { quando: i.quando });
      if (!testar.hasAttribute('aria-busy')) testar.disabled = m.ocupado;
    },
  };
}

// Simulacao e chip neutro (UI-08); a falha forcada aparece no popover dele (UX-08).
function criarChipSimulacao() {
  const falha = h('p', { class: 'popover-nota' });
  const c = chipComPopover('popover-simulacao', t('popover.simulacao.titulo'), h('div', { class: 'popover-corpo' }, [
    h('p', null, t('popover.simulacao.texto')),
    falha,
  ]));
  c.chip(t('chip.simulacao'), 'neutro', 'simulacao');
  return {
    el: c.el,
    atualizar(m) {
      c.el.hidden = !m.simular;
      if (!m.simular && c.pop.matches(':popover-open')) c.pop.hidePopover();
      falha.textContent = m.falhaForcada ? t('popover.simulacao.falha', { etapa: nomeEtapa(m.falhaForcada) || m.falhaForcada }) : '';
      falha.hidden = !m.falhaForcada;
    },
  };
}
