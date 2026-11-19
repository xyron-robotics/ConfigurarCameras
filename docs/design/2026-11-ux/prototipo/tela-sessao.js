// Sessao, antes "Opcoes" (direcao.md, secao 3.5): menu de secoes a esquerda, uma secao por tela,
// o mesmo formulario do passo a passo e "Salvar alteracoes" com o aviso junto do botao.
import { h } from './dom.js';
import { t, traduzirServidor } from './textos.js';
import { SECOES_SESSAO, TEMAS } from './constantes.js';
import { botao, ocupar, lugarAviso, confirmar } from './componentes.js';
import { montarFormulario } from './formularios.js';
import { logo } from './marca.js';

function secaoPainel(ctx, modelo) {
  const nome = 'tema-painel';
  const opcoes = TEMAS.map((tema) => {
    const id = `tema-${tema}`;
    return h('span', { class: 'caixa' }, [
      h('input', { type: 'radio', id, name: nome, value: tema, checked: ctx.temaAtual() === tema, onchange: () => ctx.definirTema(tema) }),
      h('label', { for: id }, t(`sessao.painel.tema.${tema}`)),
    ]);
  });
  const avisoVersao = lugarAviso();
  return [
    h('fieldset', { class: 'temas' }, [h('legend', { class: 'campo-rotulo' }, t('sessao.painel.tema')), opcoes]),
    h('div', { class: 'sessao-bloco' }, [
      h('h3', null, t('sessao.painel.versao', { v: modelo.versao })),
      botao(t('sessao.painel.procurar'), () => avisoVersao.mostrar('sucesso', t('sessao.painel.semAtualizacao')), { tipo: 'secundario' }),
      avisoVersao.el,
    ]),
    h('div', { class: 'sessao-bloco' }, [
      h('h3', null, t('sessao.painel.refazer')),
      h('p', { class: 'apoio' }, t('dialogo.refazer.texto')),
      botao(t('sessao.painel.refazer'), async () => {
        const sim = await confirmar({ titulo: t('dialogo.refazer.titulo'), texto: t('dialogo.refazer.texto'), confirmar: t('dialogo.refazer.confirmar') });
        if (!sim) return;
        await ctx.api.comando('/api/sessao/refazer');
        await ctx.recarregar();
        ctx.ir('#/inicio/senha');
      }, { tipo: 'secundario' }),
    ]),
    h('div', { class: 'sessao-bloco' }, [
      h('h3', null, t('sessao.painel.sobre')),
      logo(),
      h('p', null, t('sessao.painel.sobre.texto')),
    ]),
  ];
}

export function telaSessao(ctx, parte) {
  const secao = SECOES_SESSAO.includes(parte) ? parte : SECOES_SESSAO[0];
  const modelo = ctx.modelo();
  const titulo = h('h1', null, t('sessao.titulo'));
  const menu = h('nav', { class: 'sessao-menu', 'aria-label': t('sessao.menu') }, SECOES_SESSAO.flatMap((s) => [
    s === 'painel' ? h('span', { class: 'sessao-separador', 'aria-hidden': 'true' }) : null,
    h('a', { class: 'sessao-item', href: `#/sessao/${s}`, 'aria-current': s === secao ? 'page' : null }, t('secao.nome', { secao: s })),
  ]));

  let corpo;
  if (secao === 'painel') {
    corpo = secaoPainel(ctx, modelo);
  } else {
    const form = montarFormulario(secao, modelo, { comBroadcast: true });
    const resposta = lugarAviso();
    const rotulo = secao === 'senha' ? t('senha.salvar') : t('sessao.salvar');
    const salvar = botao(rotulo, null, { tipo: 'primario', submit: true });
    const enviar = async (ev) => {
      ev.preventDefault();
      const r = form.coletar();
      if (!r.ok) return;
      if (!r.parcial && !r.senha) { resposta.mostrar('info', t('senha.simulacao')); return; }
      const restaurar = ocupar(salvar, t('sessao.salvando'));
      const res = r.senha ? await ctx.api.comando('/api/senha', { senha: r.senha }) : await ctx.api.salvarSessao(r.parcial);
      restaurar();
      if (!res.ok) { resposta.mostrar('erro', res.semResposta ? t('erro.semResposta') : traduzirServidor(res.mensagem), res.mensagem); return; }
      await ctx.recarregarSessao();
      resposta.mostrar('sucesso', r.senha ? t('senha.salva') : t('sessao.salvas'));
    };
    corpo = [
      h('form', { class: 'form', novalidate: true, onsubmit: enviar }, [
        form.el,
        h('div', { class: 'sessao-acoes' }, modelo.simular && secao === 'senha' ? null : salvar),
        resposta.el,
      ]),
    ];
  }

  const leadChave = secao === 'painel' ? 'sessao.painel.lead' : `${secao}.lead`;
  const el = h('main', { class: 'conteudo', id: 'conteudo' }, [
    h('div', { class: 'cabeca-tela' }, [titulo, h('p', { class: 'lead' }, t('sessao.lead'))]),
    h('div', { class: 'sessao-grade' }, [
      menu,
      h('section', { class: 'sessao-secao', 'aria-labelledby': 'sessao-secao-titulo' }, [
        h('div', { class: 'cabeca-tela' }, [h('h2', { id: 'sessao-secao-titulo' }, t('secao.nome', { secao })), h('p', { class: 'apoio' }, t(leadChave))]),
        corpo,
      ]),
    ]),
  ]);
  return { el, foco: titulo };
}
