// Transicao: sai nas frentes 3 a 5 do redesenho.
// Painel: faixa de atualizacao e bancada da retomada manual (etapas). A tabela,
// a fita, o cabecalho da fila, o vigia e os estados vazios moram em tela-painel.js;
// o log e o resultado das ferramentas, em tela-ferramentas.js.
import { t } from './textos.js';
import { ETAPAS } from './constantes.js';
import { S, $, mostrarTelaFim } from './legado-estado.js';

// Faixa de atualizacao: aparece com versao nova conhecida; o botao so ativa
// com o painel parado (o servidor tambem recusa com 409 e diz o motivo).
export function desenharAtualizacao(a, e) {
  const faixa = $('atualizacao');
  const txt = $('atualizacao-texto');
  const btn = $('btn-atualizar');
  const notas = $('atualizacao-notas');
  const estadoA = a.estado || 'nenhuma';
  S.atualizando = ['baixando', 'verificando', 'instalando'].includes(estadoA);
  if (estadoA === 'instalando') { mostrarTelaFim('atualizando'); }
  if (!['disponivel', 'baixando', 'verificando', 'instalando', 'erro'].includes(estadoA)) { faixa.hidden = true; return; }
  faixa.hidden = false;
  faixa.classList.toggle('falha', estadoA === 'erro');
  notas.hidden = !a.pagina;
  if (a.pagina) notas.href = a.pagina;
  let motivo = '';
  if (e.ocupado) motivo = t('atualizacao.motivo-ocupado');
  // Camera em curso no paralelo, ou a retomada manual pelo IP (fase legada).
  else if ((e.paralelo && e.paralelo.emCurso > 0) || ['configurando', 'decisao'].includes(e.fase)) {
    motivo = t('atualizacao.motivo-em-curso');
  }
  else if (e.vigia && e.vigia.ligado) motivo = t('atualizacao.motivo-vigia');
  else if (e.admin === false) motivo = t('atualizacao.motivo-admin');
  if (estadoA === 'disponivel') {
    txt.textContent = t('atualizacao.disponivel', { versao: a.versao, atual: a.versaoAtual });
    btn.textContent = t('topo.btn-atualizar');
  } else if (estadoA === 'erro') {
    txt.textContent = t('atualizacao.erro', { versao: a.versao, erro: a.erro || t('atualizacao.erro-generico') });
    btn.textContent = t('atualizacao.tentar');
  } else {
    txt.textContent = {
      baixando: t('atualizacao.baixando', { versao: a.versao }),
      verificando: t('atualizacao.verificando'),
      instalando: t('atualizacao.instalando', { versao: a.versao }),
    }[estadoA];
    motivo = t('atualizacao.em-andamento');
  }
  btn.disabled = !!motivo;
  btn.title = motivo;
}

// ------------------------------------------------------------------ painel (fila)
// So a retomada manual pelo IP (C7): etapas em curso. A decisao dela e o resto
// do Painel (cabecalho, fita, vigia, estados vazios, Pede voce, tabela) e de tela-painel.js.
export function desenharFila(e) {
  const fila = e.fila;
  const temFila = !!(fila && fila.itens && fila.itens.length);
  const ult = $('ultimo');
  // Na falha, a "ultima instalada" so distrai da decisao.
  ult.hidden = !temFila || !e.ultimo || e.fase === 'decisao';
  ult.textContent = e.ultimo || '';
  const blocos = { trabalho: false };
  if (!temFila) { mostrarBlocos(blocos); return; }
  const cams = listaCameras(e);
  const itens = fila.itens;
  // Posicoes que contam para "N de M": as puladas na montagem (gateway, fora
  // da rede, com camera instalada) nao sao lugar para camera nenhuma.
  const usavel = (i) => i.Estado !== 'pulada' || /operador|responde/.test(i.Motivo || '');
  const usaveis = itens.filter(usavel);
  const livres = usaveis.length;
  const posAtual = e.atual >= 0 ? itens[e.atual] : null;
  const ordinal = (item) => t('bancada.ordinal', { n: usaveis.indexOf(item) + 1, total: livres });
  // Bloco de camera unica (C7): so a retomada manual pelo IP, isto e, fase
  // legada que cameras[] nao explica (com camera em curso, a fase legada vem
  // dela e quem mostra e a linha da tabela).
  const temFase = (fases) => cams.some((c) => fases.includes(c.fase));
  const manualConfigurando = e.fase === 'configurando' && !temFase(['portao', 'conferindo']);

  if (manualConfigurando || (e.ocupado && e.trabalho && e.fase === 'fila')) {
    blocos.trabalho = true;
    $('trabalho-titulo').textContent = posAtual ? t('bancada.trabalho-titulo', { ordinal: ordinal(posAtual), ip: posAtual.Ip }) : (e.trabalho || t('geral.trabalhando'));
    $('trabalho-texto').textContent = e.trabalho || '';
    const barra = $('trabalho-progresso');
    barra.hidden = !e.progresso;
    if (e.progresso) {
      barra.max = e.progresso.total;
      barra.value = e.progresso.atual;
      barra.setAttribute('aria-label', e.trabalho || t('geral.progresso'));
    }
    const i = ETAPAS.indexOf(e.etapa);
    for (const li of $('etapas').children) {
      const j = ETAPAS.indexOf(li.dataset.etapa);
      li.className = e.fase !== 'configurando' ? '' : (j < i ? 'feita' : (j === i ? 'agora' : ''));
    }
  }
  mostrarBlocos(blocos);
}

// A bancada so aparece com a retomada manual em curso.
function mostrarBlocos(blocos) {
  $('bancada-trabalho').hidden = !blocos.trabalho;
  $('bancada').hidden = !blocos.trabalho;
}

function listaCameras(e) {
  const c = e && e.cameras;
  return Array.isArray(c) ? c.filter(Boolean) : (c ? [c] : []);
}
