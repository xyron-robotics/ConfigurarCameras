// Transicao: sai nas frentes 3 a 5 do redesenho.
// Painel: log, faixa de atualizacao, fita da fila, bancada da retomada
// manual, vigia e resultado das ferramentas (a tabela mora em tela-painel.js).
import { h } from './dom.js';
import { icone } from './icones.js';
import { t, nomeEtapa, motivoVigia, textoDaFalha } from './textos.js';
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

function classeLuz(significado) { return significado ? 'luz ' + significado : 'luz'; }

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
const ESTADO_NA_FITA = { feita: t('fita.instalada'), falhou: t('fita.falhou'), pulada: t('fita.pulada') };

export function desenharFila(e) {
  const fila = e.fila;
  const temFila = !!(fila && fila.itens && fila.itens.length);
  $('painel-sem-fila').hidden = temFila;
  $('fita-bloco').hidden = !temFila;
  $('bancada').hidden = !temFila;
  const ult = $('ultimo');
  // Na falha, a "ultima instalada" so distrai da decisao.
  ult.hidden = !e.ultimo || e.fase === 'decisao';
  ult.textContent = e.ultimo || '';
  const cams = temFila ? listaCameras(e) : [];
  // Encerrar a fila: botao da fila enquanto ela esta aberta (admitindo).
  $('btn-encerrar-fila').hidden = !temFila || ['concluida', 'encerrada'].includes(e.fase) ||
    !!(e.paralelo && e.paralelo.admitindo === false);
  if (!temFila) { desenharVigia(e, false); return; }

  const itens = fila.itens;
  const pendentes = itens.filter((i) => i.Estado === 'pendente');
  const feitas = itens.filter((i) => i.Estado === 'feita').length;
  // Posicao com camera (cameras[].indice e base 0 em fila.itens).
  const comCamera = new Set(cams.filter((c) => c.indice >= 0).map((c) => c.indice));
  const aberta = !['concluida', 'encerrada'].includes(e.fase) && !(e.paralelo && e.paralelo.admitindo === false);
  // Proxima: a primeira pendente sem camera.
  const proxima = aberta ? itens.find((i, idx) => i.Estado === 'pendente' && !comCamera.has(idx)) || null : null;
  // "agora" em toda posicao com camera no portao, conferindo ou em decisao
  // (varias ao mesmo tempo); sem nenhuma, a retomada manual pela fase legada (C7).
  const agora = new Set(cams.filter((c) => c.indice >= 0 && ['portao', 'conferindo', 'decisao'].includes(c.fase)).map((c) => c.indice));
  if (!agora.size && e.atual >= 0 && ['configurando', 'decisao'].includes(e.fase)) agora.add(e.atual);
  // Posicoes que contam para "N de M": as puladas na montagem (gateway, fora
  // da rede, com camera instalada) nao sao lugar para camera nenhuma.
  const usavel = (i) => i.Estado !== 'pulada' || /operador|responde/.test(i.Motivo || '');
  const usaveis = itens.filter(usavel);
  const livres = usaveis.length;

  $('fita-titulo').textContent = t('fita.titulo', { inicio: itens[0].Ip, fim: itens[itens.length - 1].Ip });
  $('fita-resumo').textContent = t('fita.resumo', { feitas, pendentes: pendentes.length }) +
    [fila.local, fila.rack, fila.andar].filter(Boolean).map((x) => ', ' + x).join('');

  const fita = $('fita');
  fita.replaceChildren(...itens.map((i, idx) => {
    const cls = [i.Estado];
    // Estado em palavra, nao so na cor.
    let palavra = ESTADO_NA_FITA[i.Estado] || '';
    if (agora.has(idx)) { cls.push('atual'); if (i.Estado !== 'falhou') palavra = t('fita.agora'); }
    else if (i === proxima) { cls.push('proxima'); palavra = t('fita.proxima'); }
    // Mesma numeracao da bancada: so as posicoes usaveis contam.
    const n = usaveis.indexOf(i);
    const rotulo = n >= 0 ? t('fita.camera', { n: n + 1 }) : '';
    return h('li', { class: cls.join(' '), title: i.Motivo || null }, [
      h('span', { class: 'pos' }, [rotulo, palavra ? h('span', { class: 'estado' }, (rotulo ? ' ' : '') + palavra) : null]),
      h('span', null, i.Ip),
      i.Motivo ? h('span', { class: 'motivo' }, i.Motivo) : null]);
  }));

  const blocos = { pronta: false, trabalho: false, decisao: false, fim: false };
  const posAtual = e.atual >= 0 ? itens[e.atual] : null;
  const ordinal = (item) => t('bancada.ordinal', { n: usaveis.indexOf(item) + 1, total: livres });
  // Bloco de camera unica (C7): so a retomada manual pelo IP, isto e, fase
  // legada que cameras[] nao explica (com camera em curso ou em decisao, a
  // fase legada vem dela e quem mostra e a linha da tabela).
  const temFase = (fases) => cams.some((c) => fases.includes(c.fase));
  const manualConfigurando = e.fase === 'configurando' && !temFase(['portao', 'conferindo']);
  const manualDecisao = e.fase === 'decisao' && !!e.falha && !temFase(['decisao']);
  const emAndamento = temFase(['espera', 'portao', 'conferindo', 'decisao']);

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
  } else if (manualDecisao) {
    blocos.decisao = true;
    $('decisao-titulo').textContent = t('bancada.decisao-titulo', { etapa: nomeEtapa(e.falha.etapa) || e.falha.etapa, ip: posAtual ? posAtual.Ip : '' });
    $('decisao-erro').textContent = e.falha.erro;
    $('decisao-apoio').textContent = textoDaFalha(e.falha, posAtual ? posAtual.Ip : '');
  } else if (e.fase === 'concluida' || e.fase === 'encerrada' || (!proxima && !emAndamento)) {
    blocos.fim = true;
    $('fim-titulo').textContent = e.fase === 'encerrada' ? t('bancada.fila-encerrada') : t('bancada.fila-concluida');
    const motivo = e.vigia && !e.vigia.ligado && e.vigia.motivo;
    $('fim-texto').textContent = t('bancada.fim-texto') + (motivo ? t('bancada.fim-vigia', { motivo: motivoVigia(motivo) }) : '');
  } else if (proxima) {
    const vigiando = !!(e.vigia && e.vigia.ligado);
    blocos.pronta = true;
    $('bancada-pos').textContent = t('bancada.conecte', { n: usaveis.indexOf(proxima) + 1, total: livres });
    $('bancada-destino').textContent = proxima.Ip;
    $('bancada-apoio').textContent = vigiando ? t('bancada.apoio-vigia') : t('bancada.apoio-cabo');
    // Uma acao principal por vez (C5): com o vigia ligado o destaque e dele;
    // com camera em decisao, do "Tentar de novo" da linha dela.
    $('btn-conectada').className = vigiando || temFase(['decisao']) ? 'btn' : 'btn acento';
  }
  for (const [k, v] of Object.entries(blocos)) $('bancada-' + k).hidden = !v;
  desenharVigia(e, !blocos.fim);
}

function listaCameras(e) {
  const c = e && e.cameras;
  return Array.isArray(c) ? c.filter(Boolean) : (c ? [c] : []);
}

// IP, MAC, modelo e serial (sempre em .mono) nao passam por tradutor.
const MONO = { class: 'mono', translate: 'no' };

// ------------------------------------------------------------------ vigia
// Vigia do modo paralelo (C1, C4): porta e canal nao moram aqui, cada
// linha da tabela tem os seus. Sem DHIP, o coordenador cai para uma camera por vez.
export function desenharVigia(e, visivel) {
  $('vigia').hidden = !visivel;
  if (!visivel) return;
  const v = e.vigia || {};
  const f = $('form-vigia').elements;
  const ip = S.ipFabrica || t('vigia.ip-generico');
  $('vigia-luz').className = classeLuz(v.ligado ? 'agora' : '');
  $('vigia-estado').textContent = v.ligado ? t('vigia.ligado') : t('vigia.desligado');
  $('btn-vigia').textContent = v.ligado ? t('vigia.desligar') : t('vigia.ligar');
  f.broadcast.disabled = !!v.ligado;
  if (v.ligado) f.broadcast.checked = !!v.broadcast;
  const texto = v.ligado
    ? t('vigia.texto-ligado', { ip })
    : (v.motivo ? t('vigia.motivo', { motivo: motivoVigia(v.motivo) }) : '') + t('vigia.texto-desligado', { ip });
  $('vigia-texto').textContent = texto;
  $('vigia-dhip').hidden = !(v.ligado && e.paralelo && e.paralelo.dhip === 'sem-resposta');
}

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
