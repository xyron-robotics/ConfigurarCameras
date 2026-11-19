// Entrada do painel (direcao.md, secao 7.2): liga api, ciclo de consulta, rotas, telas e tema.
// No prototipo o transporte e o falso (api-falsa.js), escolhido por ?cenario=; na fase B troca
// por transporteFetch() e a barra do prototipo sai.
import { h, focar } from './dom.js';
import { t } from './textos.js';
import { CONSULTA_MS } from './constantes.js';
import { hora } from './formato.js';
import { criarApi } from './api.js';
import { derivar } from './estado.js';
import { lerRota, ir, aoMudarRota } from './rotas.js';
import { botao, faixa } from './componentes.js';
import { logo } from './marca.js';
import { criarTopo } from './topo.js';
import { telaPasso, telaConferir } from './tela-inicio.js';
import { telaPainel } from './tela-painel.js';
import { telaSessao } from './tela-sessao.js';
import { telaFerramentas } from './tela-ferramentas.js';
import { CENARIOS, criarTransporteFalso } from './api-falsa.js';
import { montarBarra, lerParametros } from './prototipo-barra.js';

const TELAS_CONSOLE = { painel: telaPainel, sessao: telaSessao, ferramentas: telaFerramentas };

function iniciar() {
  const raiz = document.querySelector('[data-raiz]');
  const anuncio = h('p', { class: 'visualmente-oculto', 'aria-live': 'assertive' });
  const params = lerParametros();
  const transporte = criarTransporteFalso(params.cenario);
  const api = criarApi(transporte);

  let tema = params.tema;
  let bruto = null;
  let extras = { registro: null, registroErro: false, sessao: null, placas: null, conexao: { falhas: 0, ultima: null } };
  let modelo = derivar(null, extras);
  let tela = null;
  let nomeTela = '';
  let topo = null;
  let faixas = null;
  let relogio = null;
  let primeiraRota = true;
  let instaladasAntes = -1;

  function aplicarTema(valor) {
    if (valor === 'sistema') document.documentElement.removeAttribute('data-tema');
    else document.documentElement.setAttribute('data-tema', valor);
  }

  const ctx = {
    api,
    ir,
    modelo: () => modelo,
    temaAtual: () => tema,
    async recarregar() { await consultar(); },
    async recarregarSessao() {
      const r = await api.sessao();
      if (r.ok) extras = { ...extras, sessao: r.dados };
      rederivar();
    },
    async recarregarRegistro() {
      const r = await api.registro();
      extras = { ...extras, registro: r.ok ? r.dados.cameras : extras.registro, registroErro: !r.ok };
      rederivar();
    },
    anunciar(texto) {
      anuncio.textContent = '';
      setTimeout(() => { anuncio.textContent = texto; }, 0);
    },
    definirTema(valor) {
      tema = valor;
      aplicarTema(valor);
      api.tema(valor);
      barra.sincronizarTema(valor);
      const p = new URLSearchParams(location.search);
      p.set('tema', valor);
      history.replaceState(null, '', `?${p.toString()}${location.hash}`);
    },
    encerrar() {
      clearInterval(relogio);
      raiz.replaceChildren(h('main', { class: 'fim', id: 'conteudo' }, [
        logo(),
        h('h1', null, t('app.encerrado.titulo')),
        h('p', { class: 'apoio' }, t('app.encerrado.texto')),
      ]));
      nomeTela = 'encerrado';
      tela = null;
    },
  };

  const barra = montarBarra({
    temaAtual: () => tema,
    aoTema: (valor) => ctx.definirTema(valor),
    aoAvancar: async () => { transporte.avancar(); await consultar(); },
  });

  function desenharFaixas() {
    if (!faixas) return;
    let nova = null;
    if (modelo.conexaoPerdida) {
      nova = faixa('alarme', t('faixa.perdida'), botao(t('faixa.perdida.acao'), () => location.reload(), { tipo: 'secundario' }),
        modelo.ultimaResposta ? t('faixa.perdida.ultima', { hora: hora(modelo.ultimaResposta) }) : null);
    } else if (modelo.vigia.reserva) {
      nova = faixa('atencao', t('faixa.reserva'));
    } else if (modelo.atualizacao.estado === 'disponivel') {
      nova = faixa('info', t('faixa.atualizacao', { versao: modelo.atualizacao.versao }), botao(t('faixa.atualizacao.acao'), null, { tipo: 'secundario' }));
    }
    const chave = nova ? nova.className + nova.textContent : '';
    if (faixas.dataset.chave === chave) return;
    faixas.dataset.chave = chave;
    faixas.replaceChildren(nova || '');
    const inerte = modelo.conexaoPerdida;
    for (const el of raiz.querySelectorAll('[data-inerte]')) el.inert = inerte;
  }

  function rederivar() {
    modelo = derivar(bruto, extras);
    if (topo) topo.atualizar(modelo, nomeTela);
    desenharFaixas();
    if (tela && tela.atualizar) tela.atualizar(modelo);
  }

  async function consultar() {
    const r = await api.estado();
    if (r.ok) {
      bruto = r.dados;
      extras = { ...extras, conexao: { falhas: 0, ultima: new Date() } };
    } else {
      extras = { ...extras, conexao: { ...extras.conexao, falhas: extras.conexao.falhas + 1 } };
    }
    const instaladas = bruto && bruto.estado.fila ? bruto.estado.fila.itens.filter((i) => i.Estado === 'feita').length : 0;
    if (r.ok && instaladas !== instaladasAntes) {
      instaladasAntes = instaladas;
      const reg = await api.registro();
      extras = { ...extras, registro: reg.ok ? reg.dados.cameras : extras.registro, registroErro: !reg.ok };
    }
    rederivar();
  }

  function desenhar(rota) {
    const fabrica = TELAS_CONSOLE[rota.tela];
    if (rota.tela === 'inicio' || rota.tela === 'conferir') {
      topo = null;
      faixas = null;
      tela = rota.tela === 'inicio' ? telaPasso(ctx, rota.parte) : telaConferir(ctx);
      nomeTela = rota.tela;
      raiz.replaceChildren(tela.el);
    } else if (fabrica) {
      topo = criarTopo(ctx);
      faixas = h('div', { class: 'faixas' });
      nomeTela = rota.tela;
      tela = fabrica(ctx, rota.parte);
      topo.el.dataset.inerte = '';
      tela.el.dataset.inerte = '';
      const pular = h('a', { class: 'pular', href: '#/painel', onclick: (ev) => { ev.preventDefault(); focar(tela.el); } }, t('app.pular'));
      raiz.replaceChildren(pular, topo.el, faixas, tela.el);
      topo.atualizar(modelo, nomeTela);
      desenharFaixas();
    } else {
      const destino = CENARIOS.find((c) => c.id === params.cenario);
      ir(destino.rota);
      return;
    }
    document.title = fabrica ? `${t(`nav.${rota.tela}`)} - ${t('app.titulo')}` : t('app.titulo');
    if (!primeiraRota) {
      const alvo = typeof tela.foco === 'function' ? tela.foco() : tela.foco;
      focar(alvo);
    }
    primeiraRota = false;
  }

  aplicarTema(tema);
  document.body.append(anuncio, barra.el);
  raiz.replaceChildren(h('main', { class: 'fim', id: 'conteudo' }, [logo(), h('h1', null, t('app.abrindo'))]));

  (async () => {
    const [s, p] = await Promise.all([api.sessao(), api.placas()]);
    extras = { ...extras, sessao: s.ok ? s.dados : null, placas: p.ok ? p.dados.placas : null };
    await consultar();
    aoMudarRota(desenhar);
    desenhar(lerRota());
    relogio = setInterval(consultar, CONSULTA_MS);
  })();
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar);
else iniciar();
