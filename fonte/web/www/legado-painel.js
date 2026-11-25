// Transicao: sai nas frentes 3 a 5 do redesenho.
// Painel: log, faixa de atualizacao, bancada da retomada manual (etapas e
// decisao) e resultado das ferramentas. A tabela, a fita, o cabecalho da fila,
// o vigia e os estados vazios moram em tela-painel.js.
import { h } from './dom.js';
import { icone } from './icones.js';
import { t } from './textos.js';
import { streamsEncoder } from './formato.js';
import {
  ETAPAS, LOG_FOLGA_FIM, LOG_MAX_LINHAS, LOG_INICIO_HORA, PORTA_HTTP,
  COLUNAS_MONO_DESCOBRIR, COLUNAS_MONO_VERIFICAR,
} from './constantes.js';
import { S, $, mostrarTelaFim, barraProgresso } from './legado-estado.js';

// ------------------------------------------------------------------ significado
// A classe diz o significado, nunca a cor (direcao 4.2): vermelho so falha que
// pede voce, ambar so atencao, verde concluido, azul-500 o que esta em curso,
// cinza o resto, inclusive simulacao. Sem classe = cinza.
// O log traz a cor do console (Write-Log); a linha leva a classe do significado.
const SIGNIFICADO_DO_CONSOLE = Object.freeze({
  Red: 'falha', Green: 'sucesso', Yellow: 'atencao', DarkYellow: 'atencao',
  DarkGray: 'neutro', Cyan: 'destaque',
});
// Icone da linha do log por significado (direcao 4.5): estado nunca so pela cor
// da barra. Com nome acessivel, porque a mensagem nem sempre traz a palavra.
// neutro e destaque nao levam icone (nao sao estado).
const ICONE_DO_SIGNIFICADO = Object.freeze({
  falha: { nome: 'falha', rotulo: 'log.falha' },
  sucesso: { nome: 'concluido', rotulo: 'log.sucesso' },
  atencao: { nome: 'atencao', rotulo: 'log.atencao' },
});

// ------------------------------------------------------------------ log
export function anexarLog(entrada) {
  // Duas buscas em voo podem trazer a mesma linha: so entra o que e mais novo que o cursor.
  const linhas = entrada.filter((l) => !(l.n <= S.cursorLog));
  if (!linhas.length) return;
  const caixa = $('log');
  const noFim = caixa.scrollHeight - caixa.scrollTop - caixa.clientHeight < LOG_FOLGA_FIM;
  for (const l of linhas) {
    const significado = SIGNIFICADO_DO_CONSOLE[l.cor] || null;
    const ic = ICONE_DO_SIGNIFICADO[significado];
    // A casa do icone existe em toda linha, para a hora e a mensagem ficarem alinhadas.
    caixa.append(h('div', { class: significado }, [
      h('span', { class: 'log-sinal' }, ic ? icone(ic.nome, 'p', t(ic.rotulo)) : null),
      h('span', { class: 'ts' }, String(l.ts).slice(LOG_INICIO_HORA)),
      l.msg,
    ]));
  }
  while (caixa.childElementCount > LOG_MAX_LINHAS) caixa.firstElementChild.remove();
  if (noFim) caixa.scrollTop = caixa.scrollHeight;
}

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

// IP, MAC, modelo e serial (sempre em .mono) nao passam por tradutor.
const MONO = { class: 'mono', translate: 'no' };

// ------------------------------------------------------------------ ferramentas
function tabela(cabecalho, linhas, colunasMono) {
  return h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
    h('thead', null, h('tr', null, cabecalho.map((c) => h('th', null, c)))),
    h('tbody', null, linhas.map((l) => h('tr', null, l.map((c, n) => h('td',
      colunasMono.includes(n) ? MONO : null, String(c ?? '')))))),
  ]));
}

export function desenharFerramenta(f, e) {
  const caixa = $('resultado-ferramenta');
  if (!f) { caixa.hidden = true; S.ferramentaChave = ''; return; }
  // So redesenha quando muda: o polling nao pode apagar o que esta na tela.
  const chave = JSON.stringify(f) + (f.emCurso ? '|' + (e.trabalho || '') + '|' + JSON.stringify(e.progresso || null) : '');
  if (chave === S.ferramentaChave) return;
  S.ferramentaChave = chave;
  caixa.hidden = false;
  if (f.emCurso) {
    const titulo = { sondar: () => t('ferramenta.sondando', { ip: f.ip }), descobrir: () => t('ferramenta.procurando'),
      verificar: () => t('ferramenta.verificando') }[f.tipo];
    caixa.replaceChildren(h('h3', null, titulo ? titulo() : t('geral.trabalhando')), h('p', { class: 'apoio' }, e.trabalho || ''),
      e.progresso ? barraProgresso(e.progresso, e.trabalho) : '');
    return;
  }
  const titulo = { sondar: () => t('ferramenta.sondagem', { ip: f.ip }), descobrir: () => t('ferramenta.encontradas'),
    verificar: () => t('ferramenta.verificacao') }[f.tipo];
  const partes = [h('h3', null, t('ferramenta.titulo-as', { titulo: titulo ? titulo() : f.tipo, quando: f.quando }))];

  if (f.tipo === 'sondar') {
    const enc = streamsEncoder(f.encoder, true);
    const campos = [
      [t('sondar.ping'), f.ping ? t('sondar.responde') : t('sondar.nao-responde')],
      [t('sondar.estado'), f.fabrica ? t('sondar.de-fabrica') : (f.init === -1 ? t('sondar.nao-respondeu') : t('sondar.inicializada'))],
      [t('sondar.modelo'), f.modelo], [t('sondar.serial'), f.serial], [t('sondar.firmware'), f.firmware], [t('sondar.mac'), f.mac],
      [t('sondar.rede'), f.rede],
      [t('sondar.stream-principal'), enc && enc.principal], [t('sondar.stream-secundario'), enc && enc.secundario],
      [t('sondar.erro'), f.erro],
    ].filter(([, v]) => v !== undefined && v !== null && v !== '');
    partes.push(h('dl', null, campos.flatMap(([k, v]) => [h('dt', null, k), h('dd', null, String(v))])));
  } else if (f.tipo === 'descobrir') {
    const itens = f.itens || [];
    if (!itens.length) {
      partes.push(h('p', { class: 'apoio' }, t('descobrir.nada')));
    } else {
      partes.push(h('p', { class: 'apoio' }, t('descobrir.resumo', { broadcast: f.broadcast, varredura: f.varredura || 0 })));
      const estadoDe = (i) => {
        let s = i.fabrica ? t('descobrir.de-fabrica') : (i.init === -1 ? t('descobrir.desconhecido') : t('descobrir.inicializada'));
        if (i.classe && i.classe !== 'IPC') s += ' (' + i.classe + ')';
        if (!i.alcancavel) s += t('descobrir.fora-das-faixas');
        else if (i.fabrica && !i.confirmado) s += t('descobrir.nao-confirmado');
        return s;
      };
      const linhas = itens.map((i) => [i.ip + (i.httpPort && i.httpPort !== PORTA_HTTP ? ':' + i.httpPort : ''), i.mascara || '',
        i.mac || t('descobrir.nao-lido'), i.modelo || '', i.serial || '', i.firmware || '', estadoDe(i)]);
      partes.push(tabela(t('descobrir.colunas'), linhas, COLUNAS_MONO_DESCOBRIR));
    }
  } else if (f.tipo === 'verificar') {
    const itens = f.itens || [];
    if (!itens.length) partes.push(h('p', { class: 'apoio' }, t('verificar.nenhuma')));
    else {
      const resultado = (i) => (i.ok ? t('verificar.ok') : (i.ping ? (i.login ? t('verificar.divergente') : t('verificar.login-falhou')) : t('verificar.sem-ping')));
      const linhas = itens.map((i) => [i.ip, i.mac, resultado(i), i.detalhe]);
      partes.push(tabela(t('verificar.colunas'), linhas, COLUNAS_MONO_VERIFICAR));
    }
  }
  caixa.replaceChildren(...partes);
}
