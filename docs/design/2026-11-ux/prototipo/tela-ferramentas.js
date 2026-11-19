// Ferramentas (direcao.md, secao 3.4): uma linha por ferramenta, um Resultado so e o log
// recolhido. Ferramenta indisponivel fica desabilitada com o motivo escrito ao lado.
import { h, novoId } from './dom.js';
import { t, traduzirServidor } from './textos.js';
import { botao, ocupar, campo, aviso, lugarAviso } from './componentes.js';
import { ipParaNumero } from './formato.js';

const COR_LOG = { Yellow: 'log-aviso', Red: 'log-erro', Green: 'log-sucesso' };

export function telaFerramentas(ctx) {
  const titulo = h('h1', null, t('ferr.titulo'));
  const resultado = h('div', { class: 'resultado-corpo', 'aria-live': 'polite' });
  const erroAcao = lugarAviso();
  const log = h('div', { class: 'log' });
  let ultima = null;
  let assinatura = '';
  let soAvisos = false;

  async function rodar(btn, rota, corpo, tipo) {
    const restaurar = ocupar(btn, btn.textContent);
    const r = await ctx.api.comando(rota, corpo);
    restaurar();
    if (!r.ok) {
      erroAcao.mostrar('erro', r.semResposta ? t('erro.semResposta') : traduzirServidor(r.mensagem), r.mensagem);
      return;
    }
    erroAcao.limpar();
    ultima = tipo;
    await ctx.recarregar();
    assinatura = '';
    atualizar(ctx.modelo());
  }

  const ip = campo({ rotulo: t('ferr.sondar.campo'), valor: '192.0.2.10', mono: true, exemplo: '192.0.2.10' });
  const sondar = botao(t('ferr.sondar.acao'), (ev) => {
    if (ipParaNumero(ip.valor()) === null) { ip.mostrarErro(t('fila.erro.ip')); ip.entrada.focus(); return; }
    ip.limparErro();
    rodar(ev.currentTarget, '/api/sondar', { ip: ip.valor() }, 'sondar');
  }, { tipo: 'secundario' });
  const verificar = botao(t('ferr.verificar'), (ev) => rodar(ev.currentTarget, '/api/verificar', {}, 'verificar'), { tipo: 'secundario' });
  const motivoId = novoId('motivo-procurar');
  const modelo = ctx.modelo();
  const procurar = botao(t('ferr.procurar'), (ev) => rodar(ev.currentTarget, '/api/descobrir', {}, 'procurar'), { tipo: 'secundario', desabilitado: modelo.simular, motivoId: modelo.simular ? motivoId : undefined });
  const internet = botao(t('ferr.internet'), (ev) => rodar(ev.currentTarget, '/api/internet/testar', {}, 'internet'), { tipo: 'secundario' });

  const linha = (nome, texto, acao, extra) => h('div', { class: 'ferramenta' }, [
    h('h2', null, nome),
    h('div', { class: 'ferramenta-corpo' }, [texto ? h('p', { class: 'apoio' }, texto) : null, extra || null]),
    acao,
  ]);

  const filtro = h('input', { type: 'checkbox', id: 'filtro-log', onchange: (ev) => { soAvisos = ev.currentTarget.checked; desenharLog(ctx.modelo()); } });

  const el = h('main', { class: 'conteudo', id: 'conteudo' }, [
    h('div', { class: 'cabeca-tela' }, [titulo, h('p', { class: 'lead' }, t('ferr.lead'))]),
    h('div', { class: 'ferramentas' }, [
      linha(t('ferr.sondar'), t('ferr.sondar.texto'), h('div', { class: 'ferramenta-sondar' }, [ip.el, sondar])),
      linha(t('ferr.verificar'), t('ferr.verificar.texto'), verificar),
      linha(t('ferr.procurar'), t('ferr.procurar.texto'), procurar, modelo.simular ? h('p', { class: 'motivo', id: motivoId }, t('ferr.procurar.motivo')) : null),
      linha(t('ferr.internet'), t('ferr.internet.texto'), internet),
    ]),
    erroAcao.el,
    h('section', { class: 'resultado', 'aria-labelledby': 'ferr-resultado' }, [h('h2', { id: 'ferr-resultado' }, t('ferr.resultado')), resultado]),
    h('details', { class: 'recolhido' }, [
      h('summary', null, h('span', { class: 'recolhido-titulo' }, t('ferr.log'))),
      h('div', { class: 'resultado' }, [
        h('span', { class: 'caixa' }, [filtro, h('label', { for: 'filtro-log' }, t('ferr.log.filtro'))]),
        log,
      ]),
    ]),
  ]);

  function desenharResultado(m) {
    const f = m.ferramenta;
    if (ultima === 'internet') {
      resultado.replaceChildren(aviso('sucesso', t('ferr.internet.ok', { quando: m.internet.quando })));
    } else if (f && f.tipo === 'sondar') {
      resultado.replaceChildren(aviso('sucesso', t('ferr.sondar.ok', f)));
    } else if (f && f.tipo === 'verificar') {
      resultado.replaceChildren(aviso('sucesso', t('ferr.verificar.ok', { n: f.itens.length, quando: f.quando })));
    } else {
      resultado.replaceChildren(h('p', { class: 'apoio' }, t('ferr.resultado.vazio')));
    }
  }

  function desenharLog(m) {
    const linhas = m.log.filter((l) => !soAvisos || l.cor === 'Yellow' || l.cor === 'Red');
    log.replaceChildren(...linhas.map((l) => h('p', { class: ['log-linha', 'mono', COR_LOG[l.cor]] }, [h('span', { class: 'apoio' }, l.ts), h('span', null, l.msg)])));
  }

  function atualizar(m) {
    const nova = JSON.stringify([m.ferramenta, m.internet, m.log.length, ultima]);
    if (nova === assinatura) return;
    assinatura = nova;
    desenharResultado(m);
    desenharLog(m);
  }

  atualizar(modelo);
  return { el, foco: titulo, atualizar };
}
