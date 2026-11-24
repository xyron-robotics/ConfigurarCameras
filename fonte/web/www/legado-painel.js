// Transicao: sai nas frentes 3 a 5 do redesenho.
// Painel: log, faixa de atualizacao, fita da fila, cartoes
// das cameras, vigia, resultado das ferramentas e registro.
import { h } from './dom.js';
import { icone } from './icones.js';
import { t, nomeEtapa, motivoVigia } from './textos.js';
import { dataHora, ipParaNumero, mac as formatarMac } from './formato.js';
import {
  ETAPAS, LOG_FOLGA_FIM, LOG_MAX_LINHAS, LOG_INICIO_HORA, TRAVA_DECISAO_MS, PORTA_HTTP,
  COLUNAS_MONO_DESCOBRIR, COLUNAS_MONO_VERIFICAR,
} from './constantes.js';
import {
  S, $, exigir, comando, naTela, mostrarAviso, mostrarTelaFim, barraProgresso, streamsEncoder,
} from './legado-estado.js';

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
// Situacao gravada no registro (coluna Status do CSV).
const SIGNIFICADO_DA_SITUACAO = Object.freeze({ Instalada: 'sucesso', Falhou: 'falha', Resetada: 'neutro' });

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
  if (!temFila) { desenharCartoes([], [], [], e); desenharVigia(e, false); return; }

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

  desenharCartoes(cams, itens, usaveis, e);

  const blocos = { pronta: false, trabalho: false, decisao: false, fim: false };
  const posAtual = e.atual >= 0 ? itens[e.atual] : null;
  const ordinal = (item) => t('bancada.ordinal', { n: usaveis.indexOf(item) + 1, total: livres });
  // Bloco de camera unica (C7): so a retomada manual pelo IP, isto e, fase
  // legada que cameras[] nao explica (com camera em curso ou em decisao, a
  // fase legada vem dela e quem mostra e o cartao).
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
    $('decisao-apoio').textContent = textoDaFalha(e.falha, posAtual);
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
    // com cartao em decisao, do "Tentar de novo" do primeiro.
    $('btn-conectada').className = vigiando || temFase(['decisao']) ? 'btn' : 'btn acento';
  }
  for (const [k, v] of Object.entries(blocos)) $('bancada-' + k).hidden = !v;
  desenharVigia(e, !blocos.fim);
}

// ------------------------------------------------------------------ cartoes
// Um cartao por camera de cameras[] (modo paralelo). Chave no MAC: o no e
// criado uma vez e atualizado campo a campo (C3). Campo com foco ou com texto
// nao salvo nunca e sobrescrito pelo polling. A linha de estado (aria-live)
// so muda quando a fase muda; o progresso nao e anunciado.
const PALAVRA_FASE = {
  espera: t('cartao.fase-espera'), portao: t('cartao.fase-portao'), conferindo: t('cartao.fase-conferindo'),
  decisao: t('cartao.fase-decisao'), feita: t('cartao.fase-feita'), pulada: t('cartao.fase-pulada'),
  ignorada: t('cartao.fase-ignorada'),
};

function listaCameras(e) {
  const c = e && e.cameras;
  return Array.isArray(c) ? c.filter(Boolean) : (c ? [c] : []);
}

function poeTexto(el, texto) {
  const v = texto === null || texto === undefined ? '' : String(texto);
  if (el.textContent !== v) el.textContent = v;
}

function poeOculto(el, oculto) {
  if (el.hidden !== !!oculto) el.hidden = !!oculto;
}

// IP, MAC, modelo e serial (sempre em .mono) nao passam por tradutor.
const MONO = { class: 'mono', translate: 'no' };

function novoCartao(mac) {
  // travaAte: botoes de decisao travados ate esse instante (ms) ou ate a fase
  // mudar. querFoco/focou: o foco vai ao "Tentar de novo" so na primeira
  // entrada em decisao deste cartao. numero: posicao mostrada no titulo (0 = sem).
  const k = { mac, fase: null, publicado: { porta: '', canal: '' }, enviado: null,
              travaAte: 0, querFoco: false, focou: false, senhaVelha: false, numero: 0 };
  k.titulo = h('span');
  k.destino = h('span', { class: 'mono cartao-destino', translate: 'no' });
  k.quem = h('span', { class: 'so-leitor' });
  k.selo = h('span', { class: 'selo' });
  k.modelo = h('span', MONO);
  k.serial = h('span', MONO);
  k.macTxt = h('span', MONO);
  k.parteModelo = h('span', null, k.modelo);
  k.parteSerial = h('span', null, [t('cartao.serial'), k.serial]);
  k.parteMac = h('span', null, [t('cartao.mac'), k.macTxt]);
  k.etapa = h('p', { class: 'cartao-etapa' });
  k.barra = h('progress', { max: 1, value: 0, hidden: true });
  k.trabalho = h('p', { class: 'apoio cartao-trabalho' });
  k.curso = h('div', { class: 'cartao-curso' }, [k.etapa, k.barra, k.trabalho]);
  // Decisao do cartao: etapa e erro da falha, "Tentar de novo" e "Pular".
  k.falhaTitulo = h('p', { class: 'cartao-falha falha-titulo' });
  k.falhaErro = h('p', { class: 'decisao-erro' });
  k.falhaApoio = h('p', { class: 'apoio cartao-falha-apoio' });
  k.tentar = h('button', { type: 'button', class: 'btn', onclick: () => decidirCartao(k, 'tentar') }, t('cartao.tentar'));
  k.pular = h('button', { type: 'button', class: 'btn', onclick: () => decidirCartao(k, 'pular') }, t('cartao.pular'));
  k.decisao = h('div', { class: 'cartao-decisao', hidden: true },
    [k.falhaTitulo, k.falhaErro, k.falhaApoio, h('div', { class: 'acoes' }, [k.tentar, k.pular])]);
  k.aviso = h('p', { class: 'cartao-aviso' });
  k.porta = h('input', { name: 'porta', autocomplete: 'off', spellcheck: 'false' });
  k.canal = h('input', { name: 'canal', autocomplete: 'off', spellcheck: 'false' });
  k.salvo = h('span', { class: 'cartao-salvo', role: 'status' });
  k.campos = h('div', { class: 'linha-campos cartao-campos' },
    [h('label', null, [t('cartao.porta'), k.porta]), h('label', null, [t('cartao.canal'), k.canal]), k.salvo]);
  k.el = h('li', { class: 'cartao', 'data-mac': mac }, [
    h('div', { class: 'cartao-cabeca' }, [
      h('h3', { class: 'cartao-titulo' }, [k.titulo, k.destino]),
      h('p', { class: 'cartao-estado', 'aria-live': 'polite' }, [k.quem, k.selo])]),
    h('p', { class: 'cartao-id' }, [k.parteModelo, k.parteSerial, k.parteMac]),
    k.curso, k.decisao, k.aviso, k.campos]);
  for (const campo of [k.porta, k.canal]) {
    campo.addEventListener('input', () => { campo.dataset.sujo = '1'; poeTexto(k.salvo, ''); });
    campo.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') { ev.preventDefault(); salvarCartao(k); } });
    // change: ao sair do campo, se o valor mudou desde o foco.
    campo.addEventListener('change', () => salvarCartao(k));
  }
  return k;
}

// Envia porta e canal do cartao se diferem do publicado (ou do ultimo envio
// ainda nao refletido). A recusa chega pelo aviso global.
function salvarCartao(k) {
  const porta = k.porta.value.trim();
  const canal = k.canal.value.trim();
  if (k.enviado && k.enviado.porta === porta && k.enviado.canal === canal) return;
  if (!k.enviado && k.publicado.porta === porta && k.publicado.canal === canal) return;
  k.enviado = { porta, canal };
  comando('/api/camera', { mac: k.mac, porta, canal });
}

function botoesDecisao(k) {
  const travado = k.travaAte > Date.now();
  // Senha recusada: "Tentar de novo" fica travado ate uma senha mais nova
  // (o servidor tambem recusa; repetir gastaria o lockout da camera).
  k.tentar.disabled = travado || k.senhaVelha;
  k.pular.disabled = travado;
}

// Decisao sobre a camera do cartao (POST /api/decisao {mac, acao}). Trava so
// os botoes deste cartao: os outros cartoes seguem livres.
async function decidirCartao(k, acao) {
  if (acao === 'pular') {
    const pergunta = t('cartao.confirmar-pular', { numero: k.numero, serial: k.serial.textContent, mac: k.macTxt.textContent });
    if (!confirm(pergunta)) return;
  }
  k.travaAte = Date.now() + TRAVA_DECISAO_MS;
  botoesDecisao(k);
  const ok = await comando('/api/decisao', { mac: k.mac, acao }, { semTrava: true });
  if (!ok) { k.travaAte = 0; botoesDecisao(k); }
}

// Valor publicado entra no campo so sem foco e sem texto pendente; o texto
// pendente deixa de ser pendente quando o publicado o alcanca.
function sincronizarCampo(campo, valor) {
  if (campo.dataset.sujo && campo.value.trim() === valor) delete campo.dataset.sujo;
  if (document.activeElement === campo || campo.dataset.sujo) return;
  if (campo.value !== valor) campo.value = valor;
}

function atualizarCartao(k, c, itens, usaveis, senhaGeracao) {
  const fase = String(c.fase || '');
  const item = c.indice >= 0 ? itens[c.indice] : null;
  const n = item ? usaveis.indexOf(item) : -1;
  // Mesma numeracao da fita: so as posicoes usaveis contam.
  k.numero = n >= 0 ? n + 1 : (c.posicao > 0 ? c.posicao : 0);
  const titulo = k.numero ? t('cartao.titulo', { n: k.numero }) : t('cartao.sem-posicao');
  poeTexto(k.titulo, titulo);
  poeTexto(k.destino, c.destino || '');
  poeOculto(k.destino, !c.destino);
  if (k.fase !== fase) {
    k.fase = fase;
    // Fase nova: o comando do cartao andou; a trava sai.
    k.travaAte = 0;
    k.querFoco = fase === 'decisao' && !k.focou;
    k.el.dataset.fase = fase;
    k.el.classList.toggle('compacto', ['feita', 'pulada', 'ignorada'].includes(fase));
    poeTexto(k.quem, titulo + ': ');
    poeTexto(k.selo, PALAVRA_FASE[fase] || fase);
  }

  poeTexto(k.modelo, c.modelo || '');
  poeOculto(k.parteModelo, !c.modelo);
  poeTexto(k.serial, c.serial || '');
  poeOculto(k.parteSerial, !c.serial);
  poeTexto(k.macTxt, formatarMac(c.mac));
  poeOculto(k.parteMac, !c.mac);

  const curso = fase === 'portao' || fase === 'conferindo';
  poeOculto(k.curso, !curso);
  if (curso) {
    const i = ETAPAS.indexOf(c.etapa);
    poeTexto(k.etapa, i >= 0 ? t('cartao.etapa', { i: i + 1, total: ETAPAS.length, nome: nomeEtapa(c.etapa) }) : '');
    poeOculto(k.etapa, i < 0);
    const p = c.progresso;
    poeOculto(k.barra, !p);
    if (p) {
      if (k.barra.max !== p.total) k.barra.max = p.total;
      if (k.barra.value !== p.atual) k.barra.value = p.atual;
      k.barra.setAttribute('aria-label', c.trabalho || t('geral.progresso'));
    }
    poeTexto(k.trabalho, c.trabalho || '');
    poeOculto(k.trabalho, !c.trabalho);
  }
  const f = fase === 'decisao' ? c.falha : null;
  poeOculto(k.decisao, !f);
  if (f) {
    poeTexto(k.falhaTitulo, t('cartao.falhou-etapa', { etapa: nomeEtapa(f.etapa) || f.etapa || t('cartao.etapa-desconhecida') }));
    poeTexto(k.falhaErro, f.erro || '');
    poeOculto(k.falhaErro, !f.erro);
    poeTexto(k.falhaApoio, textoDaFalha(f, item));
    k.senhaVelha = !!f.loginRecusado && f.geracao === senhaGeracao;
    botoesDecisao(k);
  } else {
    k.querFoco = false;
  }
  poeTexto(k.aviso, c.aviso || '');
  poeOculto(k.aviso, !c.aviso);

  // Porta e canal ate a fila fechar (C2), menos pulada e ignorada.
  poeOculto(k.campos, fase === 'pulada' || fase === 'ignorada');
  k.publicado = { porta: String(c.porta || '').trim(), canal: String(c.canal || '').trim() };
  sincronizarCampo(k.porta, k.publicado.porta);
  sincronizarCampo(k.canal, k.publicado.canal);
  if (k.enviado && k.enviado.porta === k.publicado.porta && k.enviado.canal === k.publicado.canal) {
    k.enviado = null;
    poeTexto(k.salvo, t('cartao.salvo'));
  }
}

// Ordem (C6): pela posicao; sem posicao no fim, na ordem de cameras[].
function desenharCartoes(cams, itens, usaveis, e) {
  const caixa = $('cartoes');
  const senhaGeracao = e ? e.senhaGeracao : undefined;
  const chave = (c) => (c.posicao > 0 ? c.posicao : Infinity);
  const ordem = cams.map((c, i) => ({ c, i }))
    .sort((a, b) => (chave(a.c) - chave(b.c)) || (a.i - b.i))
    .map((x) => x.c);
  const vistos = new Set();
  const nos = [];
  for (const c of ordem) {
    const mac = String(c.mac || '');
    if (vistos.has(mac)) continue;
    vistos.add(mac);
    let k = S.cartoes.get(mac);
    if (!k) { k = novoCartao(mac); S.cartoes.set(mac, k); }
    atualizarCartao(k, c, itens, usaveis, senhaGeracao);
    nos.push(k.el);
  }
  for (const [mac, k] of S.cartoes) {
    if (!vistos.has(mac)) { k.el.remove(); S.cartoes.delete(mac); }
  }
  // Mover o no com foco tira o foco: com foco num cartao, so entram os novos
  // (no fim); a ordem se acerta no polling seguinte sem foco.
  const atual = [...caixa.children];
  if (nos.length !== atual.length || nos.some((el, i) => el !== atual[i])) {
    if (caixa.contains(document.activeElement)) caixa.append(...nos.filter((el) => !el.isConnected));
    else caixa.append(...nos);
  }
  poeOculto(caixa, !nos.length);
  focarDecisao(nos.map((el) => S.cartoes.get(el.dataset.mac)).filter(Boolean));
}

// Um acento por vista (C5): so o "Tentar de novo" do primeiro cartao em
// decisao. O foco vai a ele na primeira entrada em decisao do cartao, com o
// botao ativo e na tela; quem esta digitando num campo nao perde o foco (a
// linha de estado do cartao ja anuncia a falha).
function focarDecisao(ks) {
  const emDecisao = ks.filter((k) => !k.decisao.hidden);
  for (const k of ks) {
    const cls = k === emDecisao[0] ? 'btn acento' : 'btn';
    if (k.tentar.className !== cls) k.tentar.className = cls;
  }
  const ativo = document.activeElement;
  const digitando = !!ativo && ativo.matches && ativo.matches('input, select, textarea');
  const alvo = emDecisao.find((k) => k.querFoco && !k.tentar.disabled && naTela(k.tentar));
  if (!alvo) return;
  if (!digitando) { alvo.tentar.focus(); alvo.focou = true; }
  // Uma entrada em decisao, um foco (no maximo): as outras do mesmo ciclo nao roubam.
  for (const k of emDecisao) if (k.querFoco && !k.tentar.disabled && naTela(k.tentar)) { k.querFoco = false; k.focou = true; }
}

// O que a camera ja recebeu e o que "Tentar de novo" faz, por etapa. Espelha
// Get-PlanoRetomada: a nova tentativa olha onde a camera esta antes de agir.
export function textoDaFalha(f, pos) {
  if (f.loginRecusado) return f.bloqueada ? t('falha.bloqueada') : t('falha.senha-recusada');
  if (f.recusa) return t('falha.recusa');
  const destino = pos ? pos.Ip : t('falha.o-destino');
  const porEtapa = {
    inicializada: () => t('falha.inicializada'),
    encoder: () => t('falha.encoder'),
    rede: () => t('falha.rede', { destino }),
    conferida: () => t('falha.conferida', { destino }),
  }[f.etapa];
  return porEtapa ? porEtapa() : t('falha.outra');
}

// ------------------------------------------------------------------ vigia
// Vigia do modo paralelo (C1, C4): porta e canal nao moram aqui, cada
// cartao tem os seus. Sem DHIP, o coordenador cai para uma camera por vez.
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

// ------------------------------------------------------------------ registro
export async function carregarRegistro() {
  try {
    const d = await exigir(S.api.registro());
    const cams = (d.cameras || []).slice().sort((a, b) => ipParaNumero(a.Ip) - ipParaNumero(b.Ip));
    $('registro-titulo').textContent = d.simulado ? t('registro.titulo-simulacao') : t('painel.registro-titulo');
    $('registro-vazio').hidden = cams.length > 0;
    $('registro-corpo').replaceChildren(...cams.map((c) => {
      const enc = streamsEncoder(c.Encoder, false);
      const detalhe = c.Status === 'Instalada' ? '' : (c.Erro || (c.Etapa ? t('registro.concluiu', { etapa: nomeEtapa(c.Etapa) }) : ''));
      return h('tr', null, [
        h('td', MONO, c.Ip),
        h('td', MONO, formatarMac(c.Mac)),
        h('td', { translate: 'no' }, c.Modelo || ''),
        h('td', null, [h('span', { class: ['sit', SIGNIFICADO_DA_SITUACAO[c.Status]] }, c.Status), detalhe ? h('span', { class: 'sit-detalhe' }, detalhe) : null]),
        h('td', MONO, enc ? [h('div', null, t('registro.principal', { texto: enc.principal })),
          h('div', { class: 'enc-sec' }, t('registro.secundario', { texto: enc.secundario }))] : null),
        h('td', null, c.Local || ''),
        h('td', null, [c.Rack, c.Porta].filter(Boolean).join(' / ')),
        h('td', MONO, dataHora(c.Data))]);
    }));
  } catch (e) { mostrarAviso(e.message); }
}
