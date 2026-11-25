// Transicao: sai nas frentes 3 a 5 do redesenho.
// Navegacao (Painel, Ferramentas, Sessao) e o desenho geral a cada estado
// recebido. A consulta e o ciclo moram no app.js; o formato do hash, no
// rotas.js; o passo a passo e o Conferir, no tela-inicio.js (o app.js desenha).
import { t } from './textos.js';
import { lerRota, hashDe, corrigir } from './rotas.js';
import { derivar } from './estado.js';
import {
  S, $, ORIGEM_DO_COMANDO, naTela, mostrarAviso, aplicarOcupado, anunciar, mostrarTelaFim,
} from './legado-estado.js';
import {
  anexarLog, desenharAtualizacao, desenharFila, desenharFerramenta,
} from './legado-painel.js';

// Aba do topo -> secao da marcacao (a Sessao e a secao #sessao, desenhada pelo app.js).
const VIEW_DA_TELA = Object.freeze({ painel: 'view-painel', sessao: 'sessao', ferramentas: 'view-ferramentas' });

// O passo a passo fica na tela enquanto faltar senha, sessao completa ou o
// "comecar" (iniciada): a regra mora no estado.js, a mesma que esconde o topo.
function precisaInicio() {
  return derivar({ estado: S.estado }).inicio;
}

// No passo a passo so a secao #inicio fica a vista (a rota dela e o app.js
// que corrige); fora dele, a view da aba.
export function trocarView() {
  if (!S.estado || !S.estado.fase) return;
  const inicio = precisaInicio();
  document.body.classList.toggle('no-inicio', inicio);
  // O log fica fora do passo a passo: nada roda antes do Comecar, e o rodape
  // fixo cobriria o fim dele.
  $('log-bloco').hidden = inicio;
  if (inicio) {
    for (const s of document.querySelectorAll('.view')) s.hidden = s.id !== 'inicio';
    return;
  }
  let r = lerRota();
  if (!VIEW_DA_TELA[r.tela]) r = { tela: 'painel', parte: '' };
  // Apelido antigo (#opcoes/fila) ou tela desconhecida: a URL mostra a rota de hoje.
  corrigir(hashDe(r));
  const view = VIEW_DA_TELA[r.tela];
  for (const s of document.querySelectorAll('.view')) s.hidden = s.id !== view;
  // O log so interessa no painel; nas outras abas ele empurra o conteudo.
  $('log-bloco').open = r.tela === 'painel';
}

// O modo mudou entre dois pollings ("comecar", "refazer"): a tela acompanha.
function desenharModo() {
  const modo = precisaInicio() ? 'inicio' : 'normal';
  if (modo !== S.modoAtual) {
    S.modoAtual = modo;
    trocarView();
  }
}

// ------------------------------------------------------------------ estado
// O app.js consulta (GET /api/estado) e entrega a resposta aqui.
export function receberEstado(dados) {
  S.estado = dados.estado;
  // Comando na fila do worker ainda nao virou "ocupado": trata como ocupado.
  if (S.estado && dados.comandos > 0) S.estado.ocupado = true;
  desenharAtualizacao(dados.atualizacao || {}, S.estado || {});
  anexarLog(dados.log || []);
  S.cursorLog = dados.cursor;
  desenhar();
}

// Sem resposta no meio da atualizacao: o painel esta reabrindo.
export function semResposta() {
  if (S.atualizando) mostrarTelaFim('atualizando');
}

function desenhar() {
  const e = S.estado;
  if (!e || !e.fase) return;

  for (const n of document.querySelectorAll('[data-nota-simular]')) n.hidden = !e.simular;

  desenharModo();

  desenharFila(e);
  desenharFerramenta(e.ferramenta, e);

  const falas = [];
  if (S.ultimoVisto !== null && e.ultimo && e.ultimo !== S.ultimoVisto) falas.push(e.ultimo);
  S.ultimoVisto = e.ultimo || '';
  if (S.ultimaFase && S.ultimaFase !== e.fase) {
    // Falha de camera em paralelo: quem anuncia e a tabela (tela-painel.js).
    if (e.fase === 'decisao' && e.falha && !$('bancada-decisao').hidden) {
      falas.push($('decisao-titulo').textContent + '. ' + e.falha.erro);
      S.focarTentar = true;
    }
    else if (e.fase === 'concluida') falas.push(t('anuncio.fila-concluida'));
    else if (e.fase === 'encerrada') falas.push(t('anuncio.fila-encerrada'));
  }
  if (falas.length) anunciar(falas.join(' '));
  S.ultimaFase = e.fase;

  aplicarOcupado(!!e.ocupado);
  // Senha recusada: "Tentar de novo" fica travado ate uma senha mais nova
  // (o servidor tambem recusa; repetir gastaria o lockout da camera).
  const tentar = document.querySelector('[data-decisao="tentar"]');
  if (e.fase === 'decisao' && e.falha && e.falha.loginRecusado && e.falha.geracao === e.senhaGeracao) tentar.disabled = true;
  // O foco vai para "Tentar de novo" quando o botao ja estiver ativo.
  if (e.fase !== 'decisao') S.focarTentar = false;
  if (S.focarTentar && !tentar.disabled && naTela(tentar)) { tentar.focus(); S.focarTentar = false; }

  // O slot do aviso depende de qual bloco esta na tela.
  if (e.avisoN !== S.avisoN) {
    S.avisoN = e.avisoN;
    // Fila montada pela Sessao: o resultado aparece junto do botao dela (tela-sessao.js).
    const daSessao = e.avisoOrigem === 'fila' && lerRota().tela === 'sessao';
    // Recusa de porta e canal: aparece junto dos campos da linha (tela-painel.js).
    if (e.aviso && !daSessao && e.avisoOrigem !== 'camera') mostrarAviso(e.aviso, ORIGEM_DO_COMANDO[e.avisoOrigem], { servidor: true });
    // Aviso que manda retomar: abre o bloco que ele cita.
    if (e.aviso && e.aviso.includes(t('painel.retomar.abrir'))) $('retomar').open = true;
  } else if (!e.aviso && S.avisoDoServidor) {
    mostrarAviso('');
  }
}
