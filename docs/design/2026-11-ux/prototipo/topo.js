// Topo fixo do console (direcao.md, secoes 2.1 e 5.9): simbolo, nome, tres abas, chips com
// popover e "Encerrar o painel". Os chips so se redesenham quando o estado deles muda.
import { h } from './dom.js';
import { t, traduzirServidor } from './textos.js';
import { botao, chip, confirmar, detalhe } from './componentes.js';
import { simbolo } from './marca.js';

const ABAS = ['painel', 'sessao', 'ferramentas'];

const CHIP_PLACA = {
  normal: ['chip.placa', 'neutro', 'placa', 'popover.placa.normal'],
  pronta: ['chip.placaPronta', 'pronta', 'concluido', 'popover.placa.pronta'],
  'sem-cabo': ['chip.placaSemCabo', 'alarme', 'falha', 'popover.placa.semCabo'],
  ausente: ['chip.placaAusente', 'alarme', 'falha', 'popover.placa.ausente'],
  'nao-preparada': ['chip.placaNaoPreparada', 'alarme', 'falha', 'popover.placa.naoPreparada'],
};

export function criarTopo(ctx) {
  const links = ABAS.map((aba) => h('a', { class: 'topo-aba', href: `#/${aba}`, dados: { aba } }, t(`nav.${aba}`)));
  const chips = h('div', { class: 'topo-chips' });
  const encerrar = botao(t('nav.encerrar'), async () => {
    const sim = await confirmar({ titulo: t('dialogo.encerrarPainel.titulo'), texto: t('dialogo.encerrarPainel.texto'), confirmar: t('dialogo.encerrarPainel.confirmar'), perigo: true });
    if (!sim) return;
    const r = await ctx.api.comando('/api/encerrar');
    if (r.ok || r.semResposta) ctx.encerrar();
  }, { tipo: 'secundario' });
  const el = h('header', { class: 'topo' }, h('div', { class: 'topo-conteudo' }, [
    h('a', { class: 'topo-marca', href: '#/painel' }, [simbolo(), h('span', { class: 'topo-nome' }, t('app.titulo'))]),
    h('nav', { class: 'topo-nav', 'aria-label': t('nav.rotulo') }, links),
    h('span'),
    chips,
    encerrar,
  ]));

  let assinatura = '';

  function popover(id, titulo, corpo) {
    return h('div', { id, popover: 'auto', class: 'popover' }, [h('h2', { class: 'popover-titulo' }, titulo), corpo]);
  }

  function chipBotao(id, rotulo, nivel, nomeIcone) {
    return h('button', { type: 'button', class: 'chip-botao', popovertarget: id, 'aria-label': t('chip.detalhe', { nome: rotulo }) }, chip(rotulo, nivel, nomeIcone));
  }

  function acaoRede(rota, rotulo, pergunta) {
    return botao(rotulo, async () => {
      if (pergunta && !(await confirmar(pergunta))) return;
      const r = await ctx.api.comando(rota);
      if (!r.ok) ctx.anunciar(traduzirServidor(r.mensagem));
      ctx.recarregar();
    }, { tipo: 'secundario' });
  }

  function desenharChips(m) {
    const [rotulo, nivel, nomeIcone, frase] = CHIP_PLACA[m.placa.motivo] || CHIP_PLACA.normal;
    const nomePlaca = m.placa.nome || (m.sessao.Placa && m.sessao.Placa.nome) || '';
    const popPlaca = popover('popover-placa', t('popover.placa.titulo'), [
      h('p', null, t(frase, { nome: nomePlaca })),
      m.placa.ips.length ? h('div', { class: 'popover-lista' }, [
        h('span', { class: 'campo-rotulo' }, t('popover.placa.ips')),
        m.placa.ips.map((ip) => h('span', { class: 'mono' }, ip)),
      ]) : null,
      m.simular ? null : h('div', { class: 'popover-acoes' }, [
        acaoRede('/api/rede/preparar', t('popover.placa.preparar')),
        acaoRede('/api/rede/restaurar', t('popover.placa.restaurar'), { titulo: t('dialogo.restaurar.titulo'), texto: t('dialogo.restaurar.texto'), confirmar: t('dialogo.restaurar.confirmar'), perigo: true }),
      ]),
      m.placa.ifIndex ? detalhe(t('detalhe.ifIndex', { n: m.placa.ifIndex })) : null,
    ]);
    const i = m.internet;
    const fraseInternet = i.agora === 'ok' ? t('popover.internet.ok', { quando: i.quando }) : i.agora === 'sem' ? t('popover.internet.sem') : t('popover.internet.naoTestado');
    const popInternet = popover('popover-internet', t('popover.internet.titulo'), [
      h('p', null, fraseInternet),
      h('div', { class: 'popover-acoes' }, acaoRede('/api/internet/testar', t('popover.internet.testar'))),
    ]);
    const lista = [
      chipBotao('popover-placa', t(rotulo), nivel, nomeIcone), popPlaca,
      chipBotao('popover-internet', i.nivel === 'alarme' ? t('chip.semInternet') : t('chip.internet'), i.nivel, i.nivel === 'alarme' ? 'falha' : 'internet'), popInternet,
    ];
    if (m.simular) {
      lista.push(
        chipBotao('popover-simulacao', t('chip.simulacao'), 'neutro', 'simulacao'),
        popover('popover-simulacao', t('popover.simulacao.titulo'), h('p', null, t('popover.simulacao.texto'))),
      );
    }
    chips.replaceChildren(...lista);
  }

  return {
    el,
    atualizar(m, tela) {
      for (const a of links) {
        if (a.dataset.aba === tela) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
      }
      const nova = JSON.stringify([m.placa, m.internet, m.simular]);
      if (nova === assinatura) return;
      assinatura = nova;
      desenharChips(m);
    },
  };
}
