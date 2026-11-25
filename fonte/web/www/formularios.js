// Formularios das secoes da sessao (direcao.md, secoes 2.2 e 5.2): uma
// definicao por secao (senha, placa, rede, camera, fila), usada pelo passo a
// passo, pela Sessao e depois pelo painel lateral. Monta a partir do modelo,
// confere no envio e devolve o pedaco da sessao com os nomes do servidor; quem
// salva e a tela. Rotulo sempre visivel, exemplo nunca no lugar do rotulo, erro
// com o conserto junto do campo e o foco no primeiro campo errado.
import { h, focar, novoId } from './dom.js';
import { botao, campo, chip, aviso } from './componentes.js';
import { icone } from './icones.js';
import { t } from './textos.js';
import { resolucao, ipParaNumero } from './formato.js';
import { conflitoDaFaixa } from './estado.js';
import {
  RE_IP, RE_EMAIL, BITRATE_MIN, BITRATE_MAX, FILA_MAX_ENDERECOS, OCTETO_PC_FABRICA, NBSP, ETAPA_DO_PASSO,
} from './constantes.js';

const MONTADORES = { senha: formSenha, placa: formPlaca, rede: formRede, camera: formCamera, fila: formFila };

// secao: 'senha' | 'placa' | 'rede' | 'camera' | 'fila'; opcoes: { lerPlacas }.
// Devolve { el, campos: { NomeDoServidor: campo }, coletar() -> { ok, parcial, senha } }.
export function montarFormulario(secao, modelo, opcoes) {
  return MONTADORES[secao](modelo, opcoes || {});
}

// Erros por campo que o servidor devolveu (400): cada um no seu campo, o foco no
// primeiro. Devolve as mensagens sem campo nesta secao, para o aviso da tela.
export function mostrarErrosServidor(form, lista) {
  const resto = [];
  let primeiro = null;
  for (const e of lista || []) {
    const c = form.campos[e.campo];
    if (c) {
      c.mostrarErro(e.msg);
      if (!primeiro) primeiro = c;
    } else {
      resto.push(e.msg);
    }
  }
  if (primeiro) levarAoCampo(primeiro);
  return resto;
}

// Campo dentro de um <details> fechado abre antes de receber o foco.
function levarAoCampo(c) {
  const recolhido = c.entrada.closest('details');
  if (recolhido) recolhido.open = true;
  focar(c.entrada);
}

// regras: [[campo, mensagem ou '']]. Mostra todos os erros e leva o foco ao primeiro.
function conferir(regras) {
  let primeiro = null;
  for (const [c, msg] of regras) {
    if (msg) {
      c.mostrarErro(msg);
      if (!primeiro) primeiro = c;
    } else {
      c.limparErro();
    }
  }
  if (primeiro) levarAoCampo(primeiro);
  return !primeiro;
}

function erroIp(c, obrigatorio) {
  const v = c.valor();
  if (!v) return obrigatorio ? t('erro.obrigatorio') : '';
  return RE_IP.test(v) ? '' : t('campo.ip-invalido');
}

function nota(nomeIcone, texto, classe) {
  return h('p', { class: classe || 'nota-neutra' }, [icone(nomeIcone), h('span', null, texto)]);
}

// ------------------------------------------------------------------ senha
function formSenha(modelo) {
  if (modelo.simular) {
    return { el: nota('simulacao', t('senha.simulacao')), campos: {}, coletar: () => ({ ok: true, parcial: null, senha: null }) };
  }
  const opcional = modelo.senhaDefinida;
  const senha = campo({ rotulo: t('senha.campo'), tipo: 'password', autocomplete: 'new-password', ajuda: t('senha.ajuda') });
  const repetir = campo({ rotulo: t('senha.repetir'), tipo: 'password', autocomplete: 'new-password' });
  const el = h('div', { class: 'form' }, [
    opcional ? nota('concluido', t('senha.salvaTrocar')) : null,
    h('div', { class: 'form-grade' }, [senha.el, repetir.el]),
  ]);
  return {
    el,
    campos: { senha, senha2: repetir },
    coletar() {
      const a = senha.entrada.value;
      const b = repetir.entrada.value;
      if (opcional && !a && !b) {
        conferir([[senha, ''], [repetir, '']]);
        return { ok: true, parcial: null, senha: null };
      }
      const ok = conferir([[senha, a ? '' : t('senha.digite')], [repetir, a && a !== b ? t('senha.erro.diferente') : '']]);
      return { ok, parcial: null, senha: ok ? a : null };
    },
  };
}

// ------------------------------------------------------------------ placa
function formPlaca(modelo, opcoes) {
  const p = modelo.placas;
  const ler = botao(t('placa.ler'), opcoes.lerPlacas, { tipo: 'secundario', classe: 'placa-ler' });
  const erroId = novoId('placa-erro');
  const erro = h('p', { class: 'campo-erro', id: erroId, hidden: true });
  const linhas = [];
  let corpo;
  if (p.erro) corpo = aviso('erro', t('placa.erroLeitura'), p.erro);
  else if (p.lendo || !p.carregadas) corpo = nota('espera', t('placa.lendo'));
  else if (!p.lista.length) corpo = aviso('atencao', t('placa.nenhuma'));
  else corpo = listaDePlacas(modelo, linhas, erroId);
  const soWifi = p.lista.length > 0 && p.lista.every((x) => x.tipo === 'wifi');
  const el = h('div', { class: 'form' }, [corpo, erro, soWifi ? aviso('info', t('placas.so-wifi')) : null, h('div', null, ler)]);
  const escolhida = () => linhas.find((l) => l.radio.checked);
  const grupo = {
    entrada: linhas.length ? linhas[0].radio : ler,
    mostrarErro(texto) {
      erro.replaceChildren(icone('falha'), h('span', null, texto));
      erro.hidden = false;
    },
    limparErro() { erro.hidden = true; },
  };
  return {
    el,
    campos: { Placa: grupo },
    coletar() {
      const l = escolhida();
      if (!conferir([[grupo, l ? '' : t('placas.escolha')]])) return { ok: false };
      const x = l.placa;
      return { ok: true, parcial: { Placa: { Nome: x.nome, IfIndex: Number(x.ifIndex), Mac: x.mac || '', Tipo: x.tipo } } };
    },
  };
}

function listaDePlacas(modelo, linhas, erroId) {
  const p = modelo.placas;
  const atual = modelo.sessao.Placa;
  const nome = novoId('placa');
  const marcada = (atual && p.lista.find((x) => Number(x.ifIndex) === Number(atual.IfIndex)))
    || p.lista.find((x) => x.sugerida || x.ifIndex === p.sugerida) || null;
  // A nota da internet so aparece na placa marcada (sem confirm(), UX-17).
  const atualizar = () => { for (const l of linhas) if (l.nota) l.nota.hidden = !l.radio.checked; };
  const itens = p.lista.map((x) => {
    const radio = h('input', { type: 'radio', name: nome, class: 'placa-radio', value: String(x.ifIndex), checked: x === marcada, onchange: atualizar });
    const notaInternet = x.rotaPadrao
      ? h('span', { class: 'placa-nota', hidden: x !== marcada }, [icone('internet'), h('span', null, t('placa.notaInternet'))])
      : null;
    linhas.push({ radio, placa: x, nota: notaInternet });
    return h('label', { class: 'placa-linha' }, [radio, h('span', { class: 'placa-texto' }, [
      h('span', { class: 'placa-cabeca' }, [
        h('span', { class: 'placa-rotulo' }, x.nome),
        x.sugerida || x.ifIndex === p.sugerida ? chip(t('placas.selo-sugerida'), 'neutro') : null,
        x.cabo ? null : chip(x.tipo === 'wifi' ? t('placas.desconectada') : t('placas.sem-cabo'), 'atencao', 'atencao'),
      ]),
      h('span', { class: 'placa-desc' }, descricaoPlaca(x)),
      notaInternet,
    ])]);
  });
  return h('fieldset', { class: 'placa-lista', 'aria-describedby': erroId }, [
    h('legend', { class: 'so-leitor' }, t('placa.lista')),
    itens,
  ]);
}

function descricaoPlaca(x) {
  const sep = t('geral.separador');
  const ips = x.ips && x.ips.length ? h('span', { class: 'mono' }, x.ips.join(', ')) : t('placas.sem-ip');
  return [x.tipo === 'wifi' ? t('placas.wifi') : t('placas.ethernet'), sep, ips, sep, x.dhcp ? t('placas.dhcp') : t('placas.ip-fixo')];
}

// ------------------------------------------------------------------ rede
function formRede(modelo) {
  const s = modelo.sessao;
  const ip = (nome, rotulo, extra) => campo({ rotulo, nome, valor: s[nome] || '', mono: true, inputmode: 'decimal', ...(extra || {}) });
  const c = {
    Mascara: ip('Mascara', t('rede.mascara'), { exemplo: '255.255.255.0' }),
    Gateway: ip('Gateway', t('rede.gateway'), { exemplo: '192.0.2.1' }),
    Dns1: ip('Dns1', t('rede.dns1'), { exemplo: '8.8.8.8' }),
    Dns2: ip('Dns2', t('rede.dns2'), { exemplo: '8.8.4.4' }),
    IpPcCameras: ip('IpPcCameras', t('rede.ipPc'), { ajuda: t('rede.ipPc.ajuda') }),
    IpFabrica: ip('IpFabrica', t('rede.ipFabrica'), { exemplo: '192.168.1.108' }),
    IpPcFabrica: ip('IpPcFabrica', t('rede.ipPcFabrica'), { ajuda: t('rede.ipPcFabrica.ajuda') }),
  };
  const resumo = h('span', { class: 'recolhido-resumo' });
  const desenharResumo = () => {
    const fabrica = c.IpFabrica.valor();
    const pc = c.IpPcFabrica.valor() || pcNaFabrica(fabrica);
    resumo.replaceChildren(
      t('rede.fabrica.ip') + ' ', h('span', { class: 'mono' }, fabrica || NBSP),
      t('conferir.virgula') + t('rede.fabrica.pc') + ' ', h('span', { class: 'mono' }, pc || NBSP),
    );
  };
  c.IpFabrica.entrada.addEventListener('input', desenharResumo);
  c.IpPcFabrica.entrada.addEventListener('input', desenharResumo);
  desenharResumo();
  const fabrica = h('details', { class: 'recolhido' }, [
    h('summary', null, [
      h('span', { class: 'recolhido-titulo' }, t('rede.fabrica')),
      resumo,
      h('span', { class: 'recolhido-acao' }, t('rede.alterar')),
    ]),
    h('div', { class: 'form-grade recolhido-corpo' }, [c.IpFabrica.el, c.IpPcFabrica.el]),
  ]);
  const el = h('div', { class: 'form' }, [
    h('div', { class: 'form-grade' }, [c.Mascara.el, c.Gateway.el, c.Dns1.el, c.Dns2.el, c.IpPcCameras.el]),
    fabrica,
  ]);
  return {
    el,
    campos: c,
    coletar() {
      const obrigatorios = ['Mascara', 'Gateway', 'IpFabrica'];
      const ok = conferir(Object.keys(c).map((n) => [c[n], erroIp(c[n], obrigatorios.includes(n))]));
      if (!ok) return { ok };
      const parcial = {};
      for (const n of Object.keys(c)) parcial[n] = c[n].valor();
      return { ok, parcial };
    },
  };
}

// IP do PC na faixa de fabrica quando o campo fica vazio: o mesmo do servidor (.220).
export function pcNaFabrica(ipFabrica) {
  if (!RE_IP.test(ipFabrica || '')) return '';
  const partes = ipFabrica.split('.');
  partes[partes.length - 1] = String(OCTETO_PC_FABRICA);
  return partes.join('.');
}

// ------------------------------------------------------------------ camera
const OUTRO = 'outro';
const NOMES_STREAM = {
  principal: { res: 'Resolucao', fps: 'FpsPrincipal', br: 'BitRate', codec: 'CodecPrincipal', lista: 'resolucoes' },
  secundario: { res: 'ResolucaoSecundario', fps: 'FpsSecundario', br: 'BitRateSecundario', codec: 'CodecSecundario', lista: 'resolucoesSecundario' },
};

// opcoes.soEncoder: so os dois streams, sem e-mail nem o "porque" (painel
// lateral "Mudar o encoder" da tela Painel); o parcial leva so o Encoder.
function formCamera(modelo, opcoes) {
  const s = modelo.sessao;
  const cat = modelo.catalogo || {};
  // Antes de a secao ser salva, o bitrate recomendado vem marcado; depois, o salvo.
  const recomendado = modelo.etapa < ETAPA_DO_PASSO.camera;
  const principal = montarStream('principal', s.Encoder.Principal, cat, recomendado);
  const secundario = montarStream('secundario', s.Encoder.Secundario, cat, recomendado);
  const streams = h('div', { class: 'form-streams' }, [principal.el, secundario.el]);
  const encoder = () => ({ Principal: principal.valor(), Secundario: secundario.valor() });
  const camposStream = { ...principal.campos, ...secundario.campos };
  if (opcoes && opcoes.soEncoder) {
    return {
      el: h('div', { class: 'form' }, [streams]),
      campos: camposStream,
      focarBitrate: () => focar(principal.campos[NOMES_STREAM.principal.br].entrada),
      coletar() {
        const ok = conferir([...principal.regras(), ...secundario.regras()]);
        return ok ? { ok, parcial: { Encoder: encoder() } } : { ok };
      },
    };
  }
  const email = campo({
    rotulo: t('camera.email'), tipo: 'email', autocomplete: 'email', valor: s.EmailRecuperacao || '',
    ajuda: t('camera.email.ajuda'), exemplo: 'cameras@empresa.example',
  });
  const porque = h('details', { class: 'recolhido' }, [
    h('summary', null, h('span', { class: 'recolhido-titulo' }, t('camera.porque'))),
    h('p', { class: 'recolhido-corpo apoio' }, t('camera.porque.texto')),
  ]);
  const el = h('div', { class: 'form' }, [email.el, streams, porque]);
  return {
    el,
    campos: { EmailRecuperacao: email, ...camposStream },
    coletar() {
      const v = email.valor();
      const erroEmail = v ? (RE_EMAIL.test(v) ? '' : t('erro.email')) : t('erro.obrigatorio');
      const ok = conferir([[email, erroEmail], ...principal.regras(), ...secundario.regras()]);
      if (!ok) return { ok };
      return { ok, parcial: { EmailRecuperacao: v, Encoder: encoder() } };
    },
  };
}

function marca(cat, stream, tipo, v) {
  if (!cat.testado) return '';
  if (cat.recusado && cat.recusado[stream] && (cat.recusado[stream][tipo] || []).includes(v)) return t('encoder.recusado-na', { modelo: cat.modelo });
  return ((cat.testado[stream] || {})[tipo] || []).includes(v) ? t('encoder.testado') : t('encoder.nao-testado');
}

// A lista do catalogo com o valor salvo, se ele nao estiver nela.
function comAtual(lista, atual) {
  const l = [...(lista || [])];
  if (atual !== undefined && atual !== null && atual !== '' && !l.some((v) => String(v) === String(atual))) l.push(atual);
  return l;
}

function montarStream(stream, v, cat, recomendado) {
  const n = NOMES_STREAM[stream];
  const res = campo({
    rotulo: t('camera.resolucao'), nome: n.res, valor: v.Resolucao,
    opcoes: comAtual(cat[n.lista], v.Resolucao).map((r) => ({ valor: r, rotulo: resolucao(r) + marca(cat, stream, 'resolucoes', r) })),
  });
  const codec = campo({
    rotulo: t('camera.codec'), nome: n.codec, valor: v.Codec,
    opcoes: comAtual(cat.codecs, v.Codec).map((c) => ({ valor: c, rotulo: c + marca(cat, stream, 'codecs', c) })),
  });
  const fps = campo({
    rotulo: t('camera.fps'), nome: n.fps, valor: v.Fps,
    opcoes: comAtual(cat.fps, v.Fps).sort((a, b) => a - b).map((f) => ({ valor: f, rotulo: f + NBSP + t('unidade.fps') })),
  });
  const bitrate = campo({ rotulo: t('camera.bitrate'), nome: n.br, opcoes: [] });
  const outro = campo({ rotulo: t('camera.bitrate.valor'), mono: true, inputmode: 'numeric', ajuda: t('camera.bitrate.limites', { min: BITRATE_MIN, max: BITRATE_MAX }) });
  const escolherOutro = () => {
    const aberto = bitrate.entrada.value === OUTRO;
    outro.el.hidden = !aberto;
    return aberto;
  };
  // Degraus do catalogo dentro da faixa usual da resolucao e do codec, com o
  // recomendado marcado e escolhido; um valor fora deles abre "Outro valor".
  const desenharBitrates = (preferido) => {
    const fx = cat.faixas && cat.faixas[res.valor()];
    const rec = fx ? fx[codec.valor()] : undefined;
    const todos = cat.bitrates || [];
    const valores = fx ? todos.filter((b) => b >= fx.min && b <= fx.max) : todos;
    bitrate.entrada.replaceChildren(
      ...valores.map((b) => h('option', { value: String(b) }, b === rec ? t('encoder.recomendado', { v: b }) : String(b) + NBSP + t('unidade.kbps'))),
      h('option', { value: OUTRO }, t('encoder.outro-valor')),
    );
    const alvo = preferido !== undefined ? Number(preferido) : (rec !== undefined ? rec : valores[0]);
    if (valores.includes(alvo)) {
      bitrate.entrada.value = String(alvo);
    } else {
      bitrate.entrada.value = OUTRO;
      outro.entrada.value = alvo ? String(alvo) : '';
    }
    escolherOutro();
  };
  desenharBitrates(recomendado ? undefined : v.BitRate);
  res.entrada.addEventListener('change', () => desenharBitrates());
  codec.entrada.addEventListener('change', () => desenharBitrates());
  bitrate.entrada.addEventListener('change', () => { if (escolherOutro()) focar(outro.entrada); });
  const valorBitrate = () => (bitrate.entrada.value === OUTRO ? outro.valor() : bitrate.entrada.value);
  // Erro do servidor no bitrate vai para o campo que esta a vista.
  const campoBitrate = {
    get entrada() { return bitrate.entrada.value === OUTRO ? outro.entrada : bitrate.entrada; },
    mostrarErro: (texto) => (bitrate.entrada.value === OUTRO ? outro : bitrate).mostrarErro(texto),
    limparErro: () => { outro.limparErro(); bitrate.limparErro(); },
  };
  const el = h('fieldset', { class: 'stream' }, [
    h('legend', { class: 'stream-titulo' }, t('camera.' + stream)),
    h('div', { class: 'form-grade' }, [res.el, codec.el, fps.el, bitrate.el, outro.el]),
  ]);
  return {
    el,
    campos: { [n.res]: res, [n.fps]: fps, [n.br]: campoBitrate, [n.codec]: codec },
    regras() {
      if (bitrate.entrada.value !== OUTRO) return [[outro, '']];
      const b = Number(outro.valor());
      const ok = outro.valor() !== '' && Number.isInteger(b) && b >= BITRATE_MIN && b <= BITRATE_MAX;
      return [[outro, ok ? '' : t('erro.bitrate', { min: BITRATE_MIN, max: BITRATE_MAX })]];
    },
    valor: () => ({ Resolucao: res.valor(), Fps: Number(fps.valor()), BitRate: Number(valorBitrate()), Codec: codec.valor() }),
  };
}

// ------------------------------------------------------------------ fila
function formFila(modelo) {
  const f = modelo.sessao.Fila || {};
  const inicio = campo({ rotulo: t('fila.inicio'), nome: 'FilaInicio', valor: f.Inicio || '', mono: true, inputmode: 'decimal', exemplo: '192.0.2.10' });
  const fim = campo({ rotulo: t('fila.fim'), nome: 'FilaFim', valor: f.Fim || '', mono: true, inputmode: 'decimal', exemplo: '192.0.2.40' });
  const local = campo({ rotulo: t('fila.local'), nome: 'FilaLocal', valor: f.Local || '', exemplo: t('fila.local.exemplo') });
  const rack = campo({ rotulo: t('fila.rack'), nome: 'FilaRack', valor: f.Rack || '' });
  const andar = campo({ rotulo: t('fila.andar'), nome: 'FilaAndar', valor: f.Andar || '' });
  const previa = h('p', { class: 'previa', 'aria-live': 'polite' });
  // Quantas posicoes a faixa tem e quantas ja estao no registro (ficam de fora).
  const desenharPrevia = () => {
    const a = inicio.valor();
    const b = fim.valor();
    // Sem faixa valida a linha sai do fluxo (nao deixa um vao entre as grades).
    previa.hidden = !RE_IP.test(a) || !RE_IP.test(b);
    if (previa.hidden) { previa.replaceChildren(); return; }
    const total = ipParaNumero(b) - ipParaNumero(a) + 1;
    previa.classList.toggle('previa-atencao', total < 1 || total > FILA_MAX_ENDERECOS);
    if (total < 1) { previa.replaceChildren(icone('atencao'), h('span', null, t('fila.previa-invertida'))); return; }
    if (total > FILA_MAX_ENDERECOS) { previa.replaceChildren(icone('atencao'), h('span', null, t('fila.previa-acima', { n: total }))); return; }
    const c = conflitoDaFaixa(a, b, modelo.instaladas);
    const registro = !modelo.registroCarregado ? '' : (c.instaladas ? t('fila.noRegistro', { n: c.instaladas, total }) : t('fila.livre'));
    previa.replaceChildren(icone('informacao'), h('span', null, [t('fila.posicoes', { n: total }), registro ? ' ' + registro : '']));
  };
  inicio.entrada.addEventListener('input', desenharPrevia);
  fim.entrada.addEventListener('input', desenharPrevia);
  desenharPrevia();
  const el = h('div', { class: 'form' }, [
    h('div', { class: 'form-grade' }, [inicio.el, fim.el]),
    previa,
    h('div', { class: ['form-grade', 'form-grade-local'] }, [local.el, rack.el, andar.el]),
  ]);
  return {
    el,
    campos: { FilaInicio: inicio, FilaFim: fim },
    coletar() {
      const erroInicio = erroIp(inicio, true);
      let erroFim = erroIp(fim, true);
      if (!erroInicio && !erroFim) {
        const total = ipParaNumero(fim.valor()) - ipParaNumero(inicio.valor()) + 1;
        if (total < 1) erroFim = t('fila.erro.ordem');
        else if (total > FILA_MAX_ENDERECOS) erroFim = t('fila.previa-acima', { n: total });
      }
      const ok = conferir([[inicio, erroInicio], [fim, erroFim]]);
      if (!ok) return { ok };
      return { ok, parcial: { Fila: { Inicio: inicio.valor(), Fim: fim.valor(), Local: local.valor(), Rack: rack.valor(), Andar: andar.valor() } } };
    },
  };
}
