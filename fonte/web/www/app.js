// Entrada do painel (<script type="module" src="/app.js">). Escolhe o
// adaptador da api.js (fetch, este servidor), monta a casca nova (topo.js) com
// a marcacao de transicao dos legado-*.js e e o unico lugar que consulta o
// estado em ciclo: a resposta vira modelo (estado.js) para a casca e o passo a
// passo (tela-inicio.js) e segue crua para os legado-*.js, que as frentes 3 a 5
// substituem. Sessao, placas e registro do passo a passo sao lidos aqui
// (extras do modelo): a tela so recebe o modelo e o contexto (decisao N1).
import { criarApi, transporteFetch } from './api.js';
import { derivar } from './estado.js';
import { ABAS, lerRota, aoMudarRota, ir, corrigir, rotaDoPasso, passoDaRota } from './rotas.js';
import { t } from './textos.js';
import { h, focar } from './dom.js';
import { confirmar } from './componentes.js';
import { CONSULTA_MS, CONSULTA_RAPIDA_MS, ESPERA_ESTADO_PASSO_MS, PASSOS } from './constantes.js';
import { criarTopo } from './topo.js';
import { telaPasso, telaConferir } from './tela-inicio.js';
import { montarMarcacao } from './legado-marcacao.js';
import { usarApi, ganchos } from './legado-estado.js';
import { carregarSessao } from './legado-formularios.js';
import { receberEstado, semResposta, trocarView } from './legado-navegacao.js';
import { ligar, ligarTema, telaEncerrado } from './legado-ligacoes.js';

const api = criarApi(transporteFetch());
let bruto = null;
const extras = { sessao: null, placas: null, registro: null };
let versaoExtras = 0;
let modelo = derivar(null);
let cursor = 0;
let emVoo = null;

const topo = criarTopo({ api, recarregar: consultar, encerrado: telaEncerrado });

function remodelar() {
  modelo = derivar(bruto, extras);
}

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
      bruto = r.dados;
      remodelar();
      receberEstado(r.dados);
      if (modelo.inicio && (!extras.sessao || geracaoLida < modelo.geracao)) recarregarSessao().then(() => desenharInicio({}));
    } else {
      semResposta();
    }
    desenharCasca();
    desenharInicio({});
  })().finally(() => { emVoo = null; });
  return emVoo;
}

async function ciclo() {
  await consultar();
  setTimeout(ciclo, modelo.ocupado || modelo.fase === 'configurando' ? CONSULTA_RAPIDA_MS : CONSULTA_MS);
}

// ------------------------------------------------------------------ extras do passo a passo
// Sessao gravada e registro, juntos; um pedido por geracao da sessao.
let geracaoLida = -1;
let pedidoSessao = null;
function recarregarSessao() {
  if (pedidoSessao && pedidoSessao.g >= modelo.geracao) return pedidoSessao.p;
  const g = modelo.geracao;
  const p = (async () => {
    const [s, reg] = await Promise.all([api.sessao(), api.registro()]);
    if (s.ok) { extras.sessao = s.dados; geracaoLida = g; }
    if (reg.ok) extras.registro = (reg.dados && reg.dados.cameras) || [];
    versaoExtras++;
    remodelar();
  })().finally(() => { if (pedidoSessao && pedidoSessao.p === p) pedidoSessao = null; });
  pedidoSessao = { g, p };
  return p;
}

// Placas: GET /api/placas le os adaptadores (demora); "lendo" redesenha o passo.
let lendoPlacas = null;
function lerPlacas() {
  if (lendoPlacas) return lendoPlacas;
  extras.placas = { ...(extras.placas || {}), lendo: true };
  versaoExtras++;
  remodelar();
  desenharInicio({ forcar: true });
  lendoPlacas = (async () => {
    const r = await api.placas();
    extras.placas = r.ok ? { dados: r.dados, erro: null, lendo: false } : { dados: null, erro: r.mensagem || t('erro.http', { codigo: r.codigo }), lendo: false };
    versaoExtras++;
    remodelar();
    desenharInicio({ forcar: true });
  })().finally(() => { lendoPlacas = null; });
  return lendoPlacas;
}

// Espera o modelo satisfazer a condicao (ate ms); devolve true se deu.
async function esperar(cond, ms) {
  const fim = Date.now() + ms;
  while (Date.now() < fim) {
    await consultar();
    if (cond(modelo)) return true;
    await new Promise((r) => setTimeout(r, ESPERA_ESTADO_PASSO_MS));
  }
  return false;
}

// ------------------------------------------------------------------ passo a passo
const ctx = {
  api,
  modelo: () => modelo,
  ir,
  corrigir,
  confirmar,
  esperar,
  recarregarSessao,
  lerPlacas,
  redesenhar: (foco) => desenharInicio({ forcar: true, focarAcao: foco === 'acao' }),
};
let tela = null;
let chaveTela = '';

// Desenha o passo da rota em #inicio. Nao redesenha por cima de campo mexido
// ou de tela salvando; a rota fora dos passos abertos volta ao passo certo.
function desenharInicio(o) {
  const alvo = document.getElementById('inicio');
  if (!alvo) return;
  if (!modelo.carregado || !modelo.inicio) {
    if (tela) { alvo.replaceChildren(); tela = null; chaveTela = ''; }
    return;
  }
  let rotaMudou = !!o.rotaMudou;
  let passo = passoDaRota(lerRota());
  const iMax = PASSOS.indexOf(modelo.passoMax);
  if (!PASSOS.includes(passo)) passo = modelo.passoSugerido;
  else if (PASSOS.indexOf(passo) > iMax) passo = modelo.passoMax;
  if (location.hash !== rotaDoPasso(passo)) { corrigir(rotaDoPasso(passo)); rotaMudou = true; }

  if (!modelo.sessaoCarregada) {
    if (!tela) alvo.replaceChildren(h('p', { class: 'apoio', role: 'status' }, t('inicio.carregando')));
    chaveTela = '';
    return;
  }
  const chave = [passo, modelo.passoMax, modelo.simular, modelo.senhaDefinida, modelo.sessaoCompleta, versaoExtras].join('|');
  if (!o.forcar && !rotaMudou && chave === chaveTela) return;
  if (tela && tela.passo === passo && (tela.sujo() || tela.ocupada()) && !o.forcar) return;
  if (tela && tela.ocupada()) return;

  const nova = passo === 'conferir' ? telaConferir(ctx) : telaPasso(ctx, passo);
  nova.passo = passo;
  const foco = document.activeElement;
  const focoDentro = tela && alvo.contains(foco) && !rotaMudou;
  alvo.replaceChildren(nova.el);
  tela = nova;
  chaveTela = chave;
  if (rotaMudou) { focar(nova.foco); window.scrollTo(0, 0); }
  else if (o.focarAcao) focar(nova.acao);
  else if (focoDentro && foco && foco.id) { const d = document.getElementById(foco.id); if (d) d.focus({ preventScroll: true }); }
  if (passo === 'placa' && !extras.placas) lerPlacas();
}

// Tela nova pela aba, pelo link ou pelo voltar do navegador: o foco vai para o
// titulo dela. Rota com secao (#/sessao/fila) leva o foco a secao (legado); o
// passo a passo leva ao titulo do passo (desenharInicio).
function aoTrocarDeTela() {
  trocarView();
  desenharCasca();
  desenharInicio({ rotaMudou: true });
  const rota = lerRota();
  if (rota.parte || modelo.inicio) return;
  const titulo = [...document.querySelectorAll('.view:not([hidden]) h1')].find((el) => !el.closest('[hidden]'));
  focar(titulo);
  window.scrollTo(0, 0);
}

usarApi(api);
ganchos.buscarEstado = consultar;
document.getElementById('app').replaceChildren(...montarMarcacao(topo.el));
ligar();
ligarTema();
carregarSessao();
aoMudarRota(aoTrocarDeTela);
ciclo();
