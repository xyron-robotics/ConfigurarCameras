// Entrada do painel (<script type="module" src="/app.js">). Escolhe o
// adaptador da api.js (fetch, este servidor), monta a casca (topo.js, a faixa
// global, as vistas) e e o unico lugar que consulta o estado em ciclo: a
// resposta vira modelo (estado.js) para a casca, o passo a passo
// (tela-inicio.js), a Sessao (tela-sessao.js), o Painel (tela-painel.js) e as
// Ferramentas (tela-ferramentas.js). Sessao, placas e registro sao lidos aqui
// (extras do modelo): a tela so recebe o modelo e o contexto (decisao N1).
//
// Estados globais (direcao 3.6 e 5.7): Abrindo ate o 1o estado, com o topo ja
// na altura final (UI-06); uma faixa por vez sob o topo, pela prioridade
// conexao perdida (alarme) > modo de reserva (atencao) > atualizacao (info);
// Encerrado e Atualizando trocam a pagina inteira e param as consultas (UX-35).
import { criarApi, transporteFetch } from './api.js';
import { derivar } from './estado.js';
import { ABAS, lerRota, aoMudarRota, ir, corrigir, hashDe, rotaDoPasso, passoDaRota } from './rotas.js';
import { t, traduzirServidor } from './textos.js';
import { h, focar, novoId } from './dom.js';
import { botao, confirmar, faixa, lugarAviso } from './componentes.js';
import { logo } from './marca.js';
import { horaSegundos } from './formato.js';
import {
  CONSULTA_MS, CONSULTA_RAPIDA_MS, CONSULTA_APOS_ATUALIZAR_MS, ESPERA_ESTADO_PASSO_MS, AVISO_NEUTRO_MS,
  ANUNCIO_ATRASO_MS, HTTP, PASSOS, SECOES_SESSAO,
} from './constantes.js';
import { criarTopo } from './topo.js';
import { telaPasso, telaConferir } from './tela-inicio.js';
import { telaSessao, aplicarTema } from './tela-sessao.js';
import { telaPainel } from './tela-painel.js';
import { telaFerramentas } from './tela-ferramentas.js';

// Aviso do servidor que a propria tela mostra junto do controle: porta e canal
// (linha da tabela) e as ferramentas (Resultado). Os do topo do Painel (vigia,
// Configurar, decisao) ficam no Painel quando ele esta na tela.
const AVISO_DA_TELA = Object.freeze(['camera', 'sondar', 'verificar', 'descobrir', 'internet-testar']);
const AVISO_DO_PAINEL = Object.freeze(['vigia', 'conectada', 'decisao']);
const ATUALIZACAO_NA_FAIXA = Object.freeze(['disponivel', 'erro', 'baixando', 'verificando']);

const api = criarApi(transporteFetch());
let bruto = null;
// qualquerFaixa: escolha da Sessao > Rede para o proximo Ligar o vigia (sem
// escolha, vale a do servidor). vigiaDesde: quando este painel viu o vigia
// ligar. conexao: consultas seguidas sem resposta e a hora da ultima resposta.
const extras = {
  sessao: null, placas: null, registro: null, registroLeitura: null, qualquerFaixa: undefined, vigiaDesde: null,
  conexao: { falhas: 0, ultima: null },
};
let versaoExtras = 0;
let modelo = derivar(null);
let cursor = 0;
let emVoo = null;
let timerCiclo = 0;
// Encerrado ou atualizando: nenhuma consulta sai mais desta pagina.
let parado = false;
// A ultima resposta dizia "baixando" ou "verificando": o servidor sumir em
// seguida e ele fechando para instalar, nao conexao perdida.
let viuAtualizando = false;

const topo = criarTopo({ api, recarregar: consultar, encerrado: telaEncerrado });

// ------------------------------------------------------------------ casca
const raiz = document.getElementById('app');
const pular = h('a', { class: 'pular', href: '#conteudo', onclick: (ev) => { ev.preventDefault(); focar(conteudo); } }, t('topo.pular'));
const faixas = h('div', { class: 'faixas' });
const anuncio = h('div', { class: 'so-leitor', role: 'status', 'aria-live': 'polite' });
// Falha nova de camera (P3): interrompe a fala, o foco fica onde esta.
const anuncioUrgente = h('div', { class: 'so-leitor', 'aria-live': 'assertive', 'aria-atomic': 'true' });
// Aviso do servidor sem lugar na tela aberta, e o resultado do Atualizar o painel.
const avisoGeral = lugarAviso();
const avisoAtualizar = lugarAviso();
const abrindo = h('section', { class: 'fim fim-abrindo', role: 'status' }, [logo(), h('h1', null, t('app.abrindo'))]);
const vistas = {
  inicio: h('section', { class: 'view inicio', hidden: true }),
  painel: h('section', { class: 'view', hidden: true }),
  ferramentas: h('section', { class: 'view', hidden: true }),
  sessao: h('section', { class: 'view sessao', hidden: true }),
};
const conteudo = h('main', { id: 'conteudo', tabindex: '-1' }, [
  anuncio, anuncioUrgente, avisoGeral.el, avisoAtualizar.el, abrindo, ...Object.values(vistas),
]);

// urgente: a regiao assertive (falha nova de camera, P3); o resto vai na polite.
// Limpa e escreve depois, para o leitor de tela falar de novo o mesmo texto.
function anunciar(texto, urgente) {
  const a = urgente ? anuncioUrgente : anuncio;
  a.textContent = '';
  if (texto) setTimeout(() => { a.textContent = texto; }, ANUNCIO_ATRASO_MS);
}

function remodelar() {
  const v = bruto && bruto.estado && bruto.estado.vigia;
  if (!(v && v.ligado)) extras.vigiaDesde = null;
  else if (!extras.vigiaDesde) extras.vigiaDesde = new Date();
  modelo = derivar(bruto, extras);
}

// Abrindo ate o 1o estado; no passo a passo so a vista dele (a rota e o
// desenharInicio que corrige); fora dele, a vista da aba. Rota desconhecida ou
// apelido antigo (#opcoes/fila) vai para a rota de hoje.
let modoVisto = '';
function trocarView() {
  abrindo.hidden = modelo.carregado;
  let aberta = '';
  if (modelo.carregado && modelo.inicio) aberta = 'inicio';
  else if (modelo.carregado) {
    let r = lerRota();
    if (!ABAS.includes(r.tela)) r = { tela: 'painel', parte: '' };
    corrigir(hashDe(r));
    aberta = r.tela;
  }
  for (const [nome, vista] of Object.entries(vistas)) vista.hidden = nome !== aberta;
}

// O modo mudou entre duas consultas (1o estado, "Comecar", "Refazer"): a vista acompanha.
function acompanharModo() {
  const modo = !modelo.carregado ? 'abrindo' : (modelo.inicio ? 'inicio' : 'console');
  if (modo === modoVisto) return;
  modoVisto = modo;
  trocarView();
}

// Topo, faixa, aviso geral e titulo da janela seguem o modelo e a rota.
function desenharCasca() {
  const tela = lerRota().tela;
  acompanharModo();
  topo.atualizar(modelo, tela);
  desenharFaixa();
  desenharAvisoGeral();
  // Conexao perdida: nada clicavel que nao va funcionar (so a faixa fica viva).
  for (const el of [pular, topo.el, conteudo]) el.inert = modelo.conexaoPerdida;
  const nome = !modelo.inicio && ABAS.includes(tela) ? t('app.tituloTela', { tela: t('nav.' + tela) }) : t('app.titulo');
  document.title = (modelo.simular ? t('topo.prefixo-simulacao') : '') + nome;
}

// ------------------------------------------------------------------ faixa global
// Uma por vez (5.7). A chave evita redesenhar a cada consulta (o leitor de
// tela leria de novo e o foco no botao se perderia).
let chaveFaixa = '';
function desenharFaixa() {
  const a = modelo.atualizacao;
  let chave = '';
  if (modelo.conexaoPerdida) chave = 'perdida|' + (modelo.ultimaResposta ? horaSegundos(modelo.ultimaResposta) : '');
  else if (modelo.vigia.reserva) chave = 'reserva';
  else if (ATUALIZACAO_NA_FAIXA.includes(a.estado)) chave = ['atualizacao', a.estado, a.versao, a.erro, a.pagina, a.motivo].join('|');
  if (chave === chaveFaixa) return;
  chaveFaixa = chave;
  faixas.replaceChildren(...[faixaDoModelo()].filter(Boolean));
}

function faixaDoModelo() {
  if (modelo.conexaoPerdida) {
    const ultima = modelo.ultimaResposta ? t('faixa.perdida.ultima', { hora: horaSegundos(modelo.ultimaResposta) }) : '';
    return faixa('alarme', t('faixa.perdida'), [botao(t('faixa.perdida.acao'), () => location.reload(), { tipo: 'secundario' })], ultima);
  }
  if (modelo.vigia.reserva) return faixa('atencao', t('faixa.reserva'));
  const a = modelo.atualizacao;
  if (!ATUALIZACAO_NA_FAIXA.includes(a.estado)) return null;
  if (a.atualizando) {
    const texto = a.estado === 'baixando' ? t('atualizacao.baixando', { versao: a.versao }) : t('atualizacao.verificando');
    return faixa('info', texto);
  }
  // Botao travado diz o porque ao lado (aria-describedby), nunca so desabilitado.
  const motivoId = a.motivo ? novoId('faixa-motivo') : undefined;
  const opcoes = { tipo: 'secundario', desabilitado: !!a.motivo, motivoId };
  const notas = a.pagina ? h('a', { href: a.pagina, target: '_blank', rel: 'noopener' }, t('topo.atualizacao-notas')) : null;
  const motivo = a.motivo ? t('atualizacao.' + a.motivo) : '';
  if (a.estado === 'erro') {
    const texto = t('atualizacao.erro', { versao: a.versao, erro: a.erro || t('atualizacao.erro-generico') });
    return faixa('atencao', texto, [botao(t('atualizacao.tentar'), pedirAtualizacao, opcoes)], motivo, motivoId);
  }
  return faixa('info', t('faixa.atualizacao', { versao: a.versao }),
    [notas, botao(t('faixa.atualizacao.acao'), pedirAtualizacao, opcoes)].filter(Boolean), motivo, motivoId);
}

// Atualizar o painel: o dialogo diz que ele fecha e reabre. 409 (painel
// ocupado, vigia ligado) e neutro e some sozinho; o texto e o do servidor.
let timerAvisoAtualizar = 0;
async function pedirAtualizacao() {
  const a = modelo.atualizacao;
  const sim = await confirmar({
    titulo: t('dialogo.atualizar.titulo', { versao: a.versao }),
    texto: t('dialogo.atualizar.texto', { temFila: !!modelo.fila }),
    confirmar: t('dialogo.atualizar.confirmar'),
  });
  if (!sim) return;
  clearTimeout(timerAvisoAtualizar);
  avisoAtualizar.limpar();
  const r = await api.comando('/api/atualizar', {});
  if (!r.ok && r.codigo === HTTP.CONFLITO && r.mensagem) {
    avisoAtualizar.mostrar('info', r.mensagem);
    timerAvisoAtualizar = setTimeout(() => avisoAtualizar.limpar(), AVISO_NEUTRO_MS);
  } else if (!r.ok) {
    const falha = traduzirServidor(r);
    avisoAtualizar.mostrar('erro', falha.texto, falha.cru);
  }
  setTimeout(consultar, CONSULTA_APOS_ATUALIZAR_MS);
}

// ------------------------------------------------------------------ aviso do servidor
// O aviso do ultimo comando aparece junto do controle que o gerou quando a
// tela dele esta aberta; senao, aqui no alto do conteudo.
let chaveAviso = '';
function desenharAvisoGeral() {
  const a = modelo.aviso;
  const rota = lerRota();
  const daTela = AVISO_DA_TELA.includes(a.origem)
    || (a.origem === 'fila' && rota.tela === 'sessao')
    || (!modelo.inicio && rota.tela === 'painel' && AVISO_DO_PAINEL.includes(a.origem));
  const texto = a.texto && !daTela ? a.texto : '';
  const chave = texto ? a.n + '|' + texto : '';
  if (chave === chaveAviso) return;
  chaveAviso = chave;
  if (texto) avisoGeral.mostrar('atencao', texto); else avisoGeral.limpar();
}

// Fila que acabou: o leitor de tela ouve (a camera instalada e a falha, o Painel anuncia).
let faseVista = '';
function anunciarFila() {
  const fase = modelo.fase;
  if (faseVista && fase !== faseVista) {
    if (fase === 'concluida') anunciar(t('anuncio.fila-concluida'));
    else if (fase === 'encerrada') anunciar(t('anuncio.fila-encerrada'));
  }
  faseVista = fase;
}

// ------------------------------------------------------------------ telas de fim
// Encerrado e Atualizando: a pagina inteira vira a tela de fim, as consultas
// param e o foco vai para o titulo (uma vez so).
function telaFim(texto) {
  if (parado) return;
  parado = true;
  clearTimeout(timerCiclo);
  const titulo = h('h1', { tabindex: '-1' }, texto);
  raiz.replaceChildren(h('main', { class: 'fim', id: 'conteudo' }, [logo(), titulo]));
  document.title = t('app.titulo');
  focar(titulo);
}

function telaEncerrado(restaurando) {
  telaFim(t(restaurando ? 'fim.encerrado-restaurando' : 'fim.encerrado-texto'));
}

// ------------------------------------------------------------------ consulta
// Uma consulta por vez: quem pede no meio (comando, espera de uma tela) recebe a que esta em voo.
function consultar() {
  if (parado) return Promise.resolve();
  if (emVoo) return emVoo;
  emVoo = (async () => {
    const r = await api.estado(cursor);
    if (parado) return;
    if (r.ok) {
      cursor = r.dados.cursor;
      bruto = r.dados;
      extras.conexao = { falhas: 0, ultima: new Date() };
      remodelar();
      if (modelo.atualizacao.estado === 'instalando') { telaFim(t('fim.atualizando-texto')); return; }
      viuAtualizando = modelo.atualizacao.atualizando;
      anunciarFila();
      if (ferramentas) ferramentas.anexarLog(r.dados.log || []);
      // Sessao gravada de novo (secao salva, fila montada): as telas releem.
      if (!extras.sessao || geracaoLida < modelo.geracao) recarregarSessao().then(() => desenharTelas());
    } else if (r.semResposta) {
      if (viuAtualizando) { telaFim(t('fim.atualizando-texto')); return; }
      extras.conexao = { ...extras.conexao, falhas: extras.conexao.falhas + 1 };
      remodelar();
    } else {
      // Erro HTTP: o servidor respondeu, a conexao esta viva.
      extras.conexao = { falhas: 0, ultima: new Date() };
      remodelar();
    }
    desenharCasca();
    desenharTelas();
  })().finally(() => { emVoo = null; });
  return emVoo;
}

// Consulta que comeca depois de quem chama (a que esta em voo pode ter saido
// antes do comando): devolve o modelo novo.
async function consultarNova() {
  if (emVoo) await emVoo;
  await consultar();
  return modelo;
}

// Sem resposta o ciclo continua: o painel volta sozinho quando o servidor volta.
async function ciclo() {
  await consultar();
  if (parado) return;
  timerCiclo = setTimeout(ciclo, modelo.ocupado || modelo.fase === 'configurando' ? CONSULTA_RAPIDA_MS : CONSULTA_MS);
}

// Sessao > Rede, "Aceitar camera de fabrica de qualquer faixa". Com o vigia
// desligado, a escolha vai junto no proximo Ligar; ligado, vale ja (o servidor
// troca porta, canal e broadcast do vigia em curso) e, recusada, volta ao que
// o servidor usa (H2). agora: valeu ja.
async function definirQualquerFaixa(valor) {
  const antes = extras.qualquerFaixa;
  extras.qualquerFaixa = !!valor;
  remodelar();
  desenharPainel();
  const v = modelo.vigia;
  if (!v.ligado) return { ok: true, agora: false };
  const r = await api.comando('/api/vigia', { ligado: true, porta: v.porta, canal: v.canal, broadcast: !!valor });
  if (!r.ok) {
    extras.qualquerFaixa = antes;
    remodelar();
  }
  await consultarNova();
  return { ...r, agora: true };
}

// ------------------------------------------------------------------ extras das telas
// Sessao gravada e registro, juntos; um pedido por geracao da sessao.
let geracaoLida = -1;
let pedidoSessao = null;
function recarregarSessao() {
  if (pedidoSessao && pedidoSessao.g >= modelo.geracao) return pedidoSessao.p;
  const g = modelo.geracao;
  const p = (async () => {
    const [s, reg] = await Promise.all([api.sessao(), api.registro()]);
    if (s.ok) {
      extras.sessao = s.dados;
      geracaoLida = g;
    }
    if (reg.ok) guardarRegistro(reg.dados);
    versaoExtras++;
    remodelar();
  })().finally(() => { if (pedidoSessao && pedidoSessao.p === p) pedidoSessao = null; });
  pedidoSessao = { g, p };
  return p;
}

function guardarRegistro(dados) {
  extras.registro = (dados && dados.cameras) || [];
  extras.registroLeitura = { lendo: false, erro: '', simulado: !!(dados && dados.simulado) };
}

// Aba Registro do Painel: "Lendo o registro..." enquanto le; com erro, so o
// erro (nunca a lista velha).
let lendoRegistro = null;
function lerRegistro() {
  if (lendoRegistro) return lendoRegistro;
  extras.registroLeitura = { ...(extras.registroLeitura || {}), lendo: true, erro: '' };
  versaoExtras++;
  remodelar();
  desenharPainel();
  lendoRegistro = (async () => {
    const r = await api.registro();
    if (r.ok) guardarRegistro(r.dados);
    else extras.registroLeitura = { lendo: false, erro: traduzirServidor(r).texto, simulado: false };
    versaoExtras++;
    remodelar();
    desenharPainel();
  })().finally(() => { lendoRegistro = null; });
  return lendoRegistro;
}

// Placas: GET /api/placas le os adaptadores (demora); "lendo" redesenha a tela.
let lendoPlacas = null;
function lerPlacas() {
  if (lendoPlacas) return lendoPlacas;
  extras.placas = { ...(extras.placas || {}), lendo: true };
  versaoExtras++;
  remodelar();
  desenharTelas({ forcar: true });
  lendoPlacas = (async () => {
    const r = await api.placas();
    extras.placas = r.ok ? { dados: r.dados, erro: null, lendo: false } : { dados: null, erro: r.mensagem || t('erro.http', { codigo: r.codigo }), lendo: false };
    versaoExtras++;
    remodelar();
    desenharTelas({ forcar: true });
  })().finally(() => { lendoPlacas = null; });
  return lendoPlacas;
}

// Espera o modelo satisfazer a condicao (ate ms); devolve true se deu.
async function esperar(cond, ms) {
  const fim = Date.now() + ms;
  while (Date.now() < fim && !parado) {
    await consultar();
    if (cond(modelo)) return true;
    await new Promise((r) => setTimeout(r, ESPERA_ESTADO_PASSO_MS));
  }
  return false;
}

// ------------------------------------------------------------------ telas
const ctx = {
  api,
  modelo: () => modelo,
  ir,
  corrigir,
  confirmar,
  esperar,
  recarregarSessao,
  lerPlacas,
  consultarNova,
  definirQualquerFaixa,
  lerRegistro,
  anunciar,
  redesenhar: (foco) => desenharTelas({ forcar: true, focarAcao: foco === 'acao' }),
};

function desenharTelas(o) {
  if (parado) return;
  desenharInicio(o || {});
  desenharSessao(o || {});
  desenharPainel();
  if (ferramentas) ferramentas.atualizar(modelo);
}

// Ferramentas e o log do painel (tela-ferramentas.js).
let ferramentas = null;

// Painel (tela-painel.js). Com a aba Registro aberta, fila que muda de fase ou
// camera instalada agora rele o registro.
let painel = null;
let marcaRegistro = '';
function desenharPainel() {
  if (!painel || parado) return;
  painel.atualizar(modelo);
  const f = modelo.fila;
  const marca = [modelo.fase, f ? f.contagem.instalada : 0, f ? f.contagem.pulada : 0].join('|');
  if (marca !== marcaRegistro) {
    const antes = marcaRegistro;
    marcaRegistro = marca;
    if (antes && lerRota().parte === 'registro' && lerRota().tela === 'painel') lerRegistro();
  }
}
let tela = null;
let chaveTela = '';

// Desenha o passo da rota na vista do passo a passo. Nao redesenha por cima de
// campo mexido ou de tela salvando; a rota fora dos passos abertos volta ao passo certo.
function desenharInicio(o) {
  const alvo = vistas.inicio;
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
  // Foco no titulo do passo (logo depois de trocar de rota): fica no titulo novo.
  const noTitulo = focoDentro && foco === tela.foco && tela.passo === passo;
  alvo.replaceChildren(nova.el);
  tela = nova;
  chaveTela = chave;
  if (rotaMudou) { focar(nova.foco); window.scrollTo(0, 0); }
  else if (o.focarAcao) focar(nova.acao);
  else if (noTitulo) focar(nova.foco);
  else if (focoDentro && foco && foco.id) { const d = document.getElementById(foco.id); if (d) d.focus({ preventScroll: true }); }
  if (passo === 'placa' && !extras.placas) lerPlacas();
}

// Sessao (#/sessao/<secao>), fora do passo a passo. Mesmas guardas do passo:
// campo mexido ou tela salvando nao sao redesenhados por cima; o aviso da acao
// ("Alteracoes salvas") passa para a tela nova da mesma secao.
let sessaoTela = null;
let chaveSessao = '';
function desenharSessao(o) {
  const alvo = vistas.sessao;
  const rota = lerRota();
  if (!modelo.carregado || modelo.inicio || rota.tela !== 'sessao') {
    if (sessaoTela) { alvo.replaceChildren(); sessaoTela = null; chaveSessao = ''; }
    return;
  }
  let rotaMudou = !!o.rotaMudou;
  if (!SECOES_SESSAO.includes(rota.parte)) { corrigir('#/sessao/' + SECOES_SESSAO[0]); rotaMudou = true; }
  const secao = lerRota().parte;
  if (!modelo.sessaoCarregada) {
    if (!sessaoTela) alvo.replaceChildren(h('p', { class: 'apoio', role: 'status' }, t('inicio.carregando')));
    chaveSessao = '';
    return;
  }
  const a = modelo.atualizacao;
  const chave = [secao, versaoExtras, modelo.simular, modelo.senhaDefinida, modelo.geracao, modelo.versao,
    a.estado, a.versao, a.ultimaChecagem, modelo.fila ? modelo.fila.total : 0].join('|');
  // Redesenho forcado (leitura das placas) so passa por cima de campo mexido na secao Placa.
  const forcar = !!o.forcar && secao === 'placa';
  if (!forcar && !rotaMudou && chave === chaveSessao) return;
  const mesma = sessaoTela && sessaoTela.secao === secao && !rotaMudou;
  if (mesma && (sessaoTela.sujo() || sessaoTela.ocupada()) && !forcar) return;
  if (sessaoTela && sessaoTela.ocupada()) return;

  const nova = telaSessao(ctx, secao, mesma ? sessaoTela.aviso() : null);
  const foco = document.activeElement;
  const focoDentro = mesma && alvo.contains(foco);
  const noTitulo = focoDentro && foco === sessaoTela.foco;
  alvo.replaceChildren(nova.el);
  sessaoTela = nova;
  chaveSessao = chave;
  if (rotaMudou) { focar(nova.foco); window.scrollTo(0, 0); }
  else if (noTitulo) focar(nova.foco);
  else if (focoDentro && foco) {
    const d = (foco.id && document.getElementById(foco.id)) || (foco.name && alvo.querySelector('[name="' + foco.name + '"]'));
    if (d) d.focus({ preventScroll: true });
  }
  if (secao === 'placa' && !extras.placas) lerPlacas();
}

// Tela nova pela aba, pelo link ou pelo voltar do navegador: o foco vai para o
// titulo dela. A Sessao leva o foco ao titulo da secao (desenharSessao); o
// passo a passo, ao titulo do passo (desenharInicio).
function aoTrocarDeTela() {
  if (parado) return;
  if (modelo.carregado) trocarView();
  desenharCasca();
  desenharInicio({ rotaMudou: true });
  desenharSessao({ rotaMudou: true });
  const rota = lerRota();
  // Painel: a aba segue a rota (#/painel/registro) e o registro e relido ao entrar.
  if (painel && rota.tela === 'painel') {
    painel.abrirAba(rota.parte === 'registro' ? 'registro' : 'fila');
    lerRegistro();
  }
  if (rota.parte || modelo.inicio || rota.tela === 'sessao') return;
  const titulo = [...document.querySelectorAll('.view:not([hidden]) h1')].find((el) => !el.closest('[hidden]'));
  focar(titulo);
  window.scrollTo(0, 0);
}

painel = telaPainel(ctx, lerRota().parte);
vistas.painel.append(painel.topo, painel.el);
ferramentas = telaFerramentas(ctx);
vistas.ferramentas.append(ferramentas.el);
raiz.replaceChildren(pular, topo.el, faixas, conteudo);
desenharCasca();
aplicarTema(document.documentElement.dataset.tema);
aoMudarRota(aoTrocarDeTela);
ciclo();
