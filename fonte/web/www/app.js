// Entrada do painel (<script type="module" src="/app.js">). Escolhe o
// adaptador da api.js (fetch, este servidor), monta a casca nova (topo.js) com
// a marcacao de transicao dos legado-*.js e e o unico lugar que consulta o
// estado em ciclo: a resposta vira modelo (estado.js) para a casca e segue
// crua para os legado-*.js, que as frentes 3 a 5 substituem.
import { criarApi, transporteFetch } from './api.js';
import { derivar } from './estado.js';
import { ABAS, lerRota, aoMudarRota } from './rotas.js';
import { t } from './textos.js';
import { focar } from './dom.js';
import { CONSULTA_MS, CONSULTA_RAPIDA_MS } from './constantes.js';
import { criarTopo } from './topo.js';
import { montarMarcacao } from './legado-marcacao.js';
import { usarApi, ganchos } from './legado-estado.js';
import { carregarSessao } from './legado-formularios.js';
import { iniciar, receberEstado, semResposta, trocarView } from './legado-navegacao.js';
import { ligar, ligarTema, telaEncerrado } from './legado-ligacoes.js';

const api = criarApi(transporteFetch());
let modelo = derivar(null);
let cursor = 0;
let emVoo = null;

const topo = criarTopo({ api, recarregar: consultar, encerrado: telaEncerrado });

// Topo e titulo da janela seguem o modelo e a rota.
function desenharCasca() {
  const tela = lerRota().tela;
  topo.atualizar(modelo, tela);
  const nome = !modelo.inicio && ABAS.includes(tela) ? t('app.tituloTela', { tela: t('nav.' + tela) }) : t('app.titulo');
  document.title = (modelo.simular ? t('topo.prefixo-simulacao') : '') + nome;
}

// Uma consulta por vez: quem pede no meio (comando, espera do legado) recebe a que esta em voo.
function consultar() {
  if (emVoo) return emVoo;
  emVoo = (async () => {
    const r = await api.estado(cursor);
    if (r.ok) {
      cursor = r.dados.cursor;
      modelo = derivar(r.dados);
      receberEstado(r.dados);
    } else {
      semResposta();
    }
    desenharCasca();
  })().finally(() => { emVoo = null; });
  return emVoo;
}

async function ciclo() {
  await consultar();
  setTimeout(ciclo, modelo.ocupado || modelo.fase === 'configurando' ? CONSULTA_RAPIDA_MS : CONSULTA_MS);
}

// Tela nova pela aba, pelo link ou pelo voltar do navegador: o foco vai para o
// titulo dela. Rota com secao (#/sessao/fila) leva o foco a secao (legado), e o
// passo a passo leva ao primeiro campo do passo (montarPasso).
function aoTrocarDeTela() {
  trocarView();
  desenharCasca();
  const rota = lerRota();
  if (rota.parte || modelo.inicio) return;
  const titulo = [...document.querySelectorAll('.view:not([hidden]) h1')].find((el) => !el.closest('[hidden]'));
  focar(titulo);
  window.scrollTo(0, 0);
}

usarApi(api);
ganchos.buscarEstado = consultar;
document.getElementById('app').replaceChildren(...montarMarcacao(topo.el));
iniciar();
ligar();
ligarTema();
carregarSessao();
aoMudarRota(aoTrocarDeTela);
ciclo();
