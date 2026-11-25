// Ferramentas (direcao.md, secao 3.4): uma linha por ferramenta (nome, texto,
// acao), um Resultado so e o log do painel recolhido. Nenhuma ferramenta altera
// camera. A tela recebe o modelo (estado.js) e o contexto do app.js; o que ela
// guarda e dela: a ultima ferramenta pedida aqui, o envio em curso e o filtro
// do log. O log chega aos pedacos (cursor do GET /api/estado) por anexarLog.
import { h } from './dom.js';
import { icone } from './icones.js';
import { t, traduzirServidor, traduzirAvisoFerramenta } from './textos.js';
import { botao, ocupar, campo, aviso } from './componentes.js';
import { streamsEncoder } from './formato.js';
import {
  RE_IP, LOG_FOLGA_FIM, LOG_MAX_LINHAS, LOG_INICIO_HORA, PORTA_HTTP,
  COLUNAS_MONO_DESCOBRIR, COLUNAS_MONO_VERIFICAR,
} from './constantes.js';

// Ferramenta -> rota. A chave e o tipo do comando no servidor, que tambem e a
// origem do aviso que ele publica (avisoOrigem).
const ROTA = Object.freeze({
  sondar: '/api/sondar', verificar: '/api/verificar', descobrir: '/api/descobrir',
  'internet-testar': '/api/internet/testar',
});

// Frase do teste da internet por motivo (estado.js): o mesmo texto do popover do chip (topo.js).
const FRASE_INTERNET = Object.freeze({
  ok: 'popover.internet.ok', caiu: 'popover.internet.caiu', 'ja-sem': 'popover.internet.jaSem',
  sem: 'popover.internet.sem', 'nao-testado': 'popover.internet.naoTestado',
});

// Linha do log: a classe diz o significado, nunca a cor (direcao 4.2). O log
// traz a cor do console (Write-Log). Sem classe: sem barra.
const SIGNIFICADO_DO_CONSOLE = Object.freeze({
  Red: 'falha', Green: 'sucesso', Yellow: 'atencao', DarkYellow: 'atencao',
  DarkGray: 'neutro', Cyan: 'destaque',
});
// Icone por significado (direcao 4.5), com nome acessivel: estado nunca so pela barra.
const ICONE_DO_SIGNIFICADO = Object.freeze({
  falha: { nome: 'falha', rotulo: 'log.falha' },
  sucesso: { nome: 'concluido', rotulo: 'log.sucesso' },
  atencao: { nome: 'atencao', rotulo: 'log.atencao' },
});

// So IP, MAC, serial e log em mono (direcao 4.3), fora do tradutor do navegador.
const MONO = { class: 'mono', translate: 'no' };

export function telaFerramentas(ctx) {
  const titulo = h('h1', null, t('ferr.titulo'));
  const caixa = h('div', { class: 'resultado' });
  // pedido: { tipo, ip, avisoN, quando, antes } da ultima ferramenta pedida aqui.
  // falha: recusa do POST ({ texto, cru }). esperando: entre o 202 e a consulta seguinte.
  let pedido = null;
  let falha = null;
  let esperando = false;
  let liberar = null;
  let chave = '';
  let fala = '';
  let ultimoN = 0;

  async function rodar(tipo, btn, rotuloOcupado, corpo) {
    if (liberar) return;
    const antes = ctx.modelo();
    const restaurar = ocupar(btn, rotuloOcupado);
    // Se o foco caiu no body no meio do pedido, volta para o botao ao liberar.
    liberar = () => {
      restaurar();
      if (!document.activeElement || document.activeElement === document.body) btn.focus();
    };
    pedido = {
      tipo, ip: corpo && corpo.ip, avisoN: antes.aviso.n, quando: antes.internet.quando,
      antes: JSON.stringify(antes.ferramenta),
    };
    falha = null;
    esperando = true;
    desenhar(antes);
    const r = await ctx.api.comando(ROTA[tipo], corpo || {});
    if (!r.ok) {
      falha = traduzirServidor(r);
      esperando = false;
      soltar();
      desenhar(ctx.modelo());
      return;
    }
    const m = await ctx.consultarNova();
    esperando = false;
    atualizar(m);
  }

  function soltar() {
    if (!liberar) return;
    const restaurar = liberar;
    liberar = null;
    restaurar();
  }

  // ---------------------------------------------------------------- as quatro linhas
  // Sondar: o nome da linha e o rotulo que se ve; o do campo (o mesmo texto) e do leitor de tela.
  const ip = campo({ rotulo: t('ferr.sondar'), mono: true, exemplo: '192.0.2.10', classe: 'ferramenta-campo' });
  ip.entrada.setAttribute('translate', 'no');
  // O erro some quando o IP fica valido; enquanto digita, nao aparece erro novo.
  ip.entrada.addEventListener('input', () => { if (RE_IP.test(ip.valor())) ip.limparErro(); });
  const sondar = botao(t('ferr.sondar.acao'), null, { submit: true });
  const formSondar = h('form', {
    class: 'ferramenta',
    novalidate: true,
    onsubmit: (ev) => {
      ev.preventDefault();
      if (!RE_IP.test(ip.valor())) {
        ip.mostrarErro(ip.valor() ? t('campo.ip-invalido') : t('erro.obrigatorio'));
        ip.entrada.focus();
        return;
      }
      ip.limparErro();
      rodar('sondar', sondar, t('ferr.sondar.ocupado'), { ip: ip.valor() });
    },
  }, [h('h2', { class: 'ferramenta-nome' }, t('ferr.sondar')), ip.el, sondar]);

  const verificar = botao(t('ferr.verificar'), (ev) => rodar('verificar', ev.currentTarget, t('ferr.verificar.ocupado')));
  const procurar = botao(t('ferr.procurar'), (ev) => rodar('descobrir', ev.currentTarget, t('ferr.procurar.ocupado')));
  const internet = botao(t('ferr.internet'), (ev) => rodar('internet-testar', ev.currentTarget, t('ferr.internet.ocupado')));
  const textoProcurar = h('p', { class: 'ferramenta-texto', id: 'ferramenta-procurar-texto' });

  const linha = (nome, texto, acao) => h('div', { class: 'ferramenta' }, [
    h('h2', { class: 'ferramenta-nome' }, nome),
    texto instanceof Node ? texto : h('p', { class: 'ferramenta-texto' }, texto),
    acao,
  ]);

  // ---------------------------------------------------------------- log do painel
  const linhasLog = h('div', {
    class: 'log-linhas mono', translate: 'no', 'aria-live': 'off', tabindex: '0', role: 'log', 'aria-label': t('ferr.log'),
  });
  const filtro = h('input', {
    type: 'checkbox',
    onchange: (ev) => linhasLog.classList.toggle('log-so-avisos', ev.currentTarget.checked),
  });
  // Recolhido como os outros da casa (formularios.js): titulo, resumo e a acao escrita.
  const acaoLog = h('span', { class: 'recolhido-acao' }, t('ferr.log.mostrar'));
  const log = h('details', { class: 'recolhido log-painel' }, [
    h('summary', null, [
      h('span', { class: 'recolhido-titulo' }, t('ferr.log')),
      h('span', { class: 'recolhido-resumo' }, t('ferr.log.resumo')),
      acaoLog,
    ]),
    h('div', { class: 'log-corpo' }, [h('label', { class: 'check' }, [filtro, t('ferr.log.filtro')]), linhasLog]),
  ]);
  // Aberto agora: mostra o fim, onde esta o que acabou de acontecer.
  log.addEventListener('toggle', () => {
    acaoLog.textContent = log.open ? t('ferr.log.esconder') : t('ferr.log.mostrar');
    if (log.open) linhasLog.scrollTop = linhasLog.scrollHeight;
  });

  // Duas consultas em voo podem trazer a mesma linha: so entra o que e mais novo.
  function anexarLog(entrada) {
    const novas = (entrada || []).filter((l) => l.n > ultimoN);
    if (!novas.length) return;
    const noFim = linhasLog.scrollHeight - linhasLog.scrollTop - linhasLog.clientHeight < LOG_FOLGA_FIM;
    for (const l of novas) {
      const significado = SIGNIFICADO_DO_CONSOLE[l.cor] || null;
      const ic = ICONE_DO_SIGNIFICADO[significado];
      // A casa do icone existe em toda linha, para a hora e a mensagem alinharem.
      linhasLog.append(h('div', { class: significado }, [
        h('span', { class: 'log-sinal' }, ic ? icone(ic.nome, 'p', t(ic.rotulo)) : null),
        h('span', { class: 'ts' }, String(l.ts).slice(LOG_INICIO_HORA)),
        l.msg,
      ]));
      ultimoN = l.n;
    }
    while (linhasLog.childElementCount > LOG_MAX_LINHAS) linhasLog.firstElementChild.remove();
    if (noFim) linhasLog.scrollTop = linhasLog.scrollHeight;
  }

  const el = h('div', { class: 'ferramentas-tela' }, [
    h('div', { class: 'ferramentas-cabeca' }, [titulo, h('p', { class: 'lead' }, t('ferr.lead'))]),
    h('div', { class: 'ferramentas-lista' }, [
      formSondar,
      linha(t('ferr.verificar'), t('ferr.verificar.texto'), verificar),
      linha(t('ferr.procurar'), textoProcurar, procurar),
      linha(t('ferr.internet'), t('ferr.internet.texto'), internet),
    ]),
    h('section', { class: 'ferramentas-resultado', 'aria-labelledby': 'ferramentas-resultado-titulo' }, [
      h('h2', { id: 'ferramentas-resultado-titulo' }, t('ferr.resultado')),
      caixa,
    ]),
    log,
  ]);

  // ---------------------------------------------------------------- resultado
  function tabela(cabecalho, linhas, colunasMono) {
    return h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
      h('thead', null, h('tr', null, cabecalho.map((c) => h('th', { scope: 'col' }, c)))),
      h('tbody', null, linhas.map((l) => h('tr', null, l.map((c, n) => h('td',
        colunasMono.includes(n) ? MONO : null, String(c ?? '')))))),
    ]));
  }

  const tituloDe = (texto) => h('h3', { class: 'resultado-titulo' }, texto);

  function emCurso(tipo, m, f) {
    const texto = {
      sondar: () => t('ferramenta.sondando', { ip: (f && f.ip) || (pedido && pedido.ip) || '' }),
      descobrir: () => t('ferramenta.procurando'),
      verificar: () => t('ferramenta.verificando'),
      'internet-testar': () => t('popover.internet.testando'),
    }[tipo];
    return [
      tituloDe(texto ? texto() : t('geral.trabalhando')),
      m.trabalho ? h('p', { class: 'resultado-texto' }, m.trabalho) : null,
      m.progresso ? h('progress', { value: m.progresso.atual, max: m.progresso.total, 'aria-label': m.trabalho || t('geral.progresso') }) : null,
    ];
  }

  function sondagem(f) {
    const enc = streamsEncoder(f.encoder, true);
    const estado = f.fabrica ? t('sondar.de-fabrica') : (f.init === -1 ? t('sondar.nao-respondeu') : t('sondar.inicializada'));
    // [rotulo, valor, mono]
    const campos = [
      [t('sondar.ip'), f.ip, true],
      [t('sondar.ping'), f.ping ? t('sondar.responde') : t('sondar.nao-responde')],
      [t('sondar.estado'), estado],
      [t('sondar.modelo'), f.modelo], [t('sondar.serial'), f.serial, true], [t('sondar.firmware'), f.firmware],
      [t('sondar.mac'), f.mac, true], [t('sondar.rede'), f.rede, true],
      [t('sondar.stream-principal'), enc && enc.principal], [t('sondar.stream-secundario'), enc && enc.secundario],
      [t('sondar.erro'), f.erro],
    ].filter(([, v]) => v !== undefined && v !== null && v !== '');
    return h('dl', null, campos.flatMap(([k, v, mono]) => [h('dt', null, k), h('dd', mono ? MONO : null, String(v))]));
  }

  function descoberta(f) {
    const itens = f.itens || [];
    if (!itens.length) return [h('p', { class: 'resultado-texto' }, t('descobrir.nada'))];
    const estadoDe = (i) => {
      let s = i.fabrica ? t('descobrir.de-fabrica') : (i.init === -1 ? t('descobrir.desconhecido') : t('descobrir.inicializada'));
      if (i.classe && i.classe !== 'IPC') s += ' (' + i.classe + ')';
      if (!i.alcancavel) s += t('descobrir.fora-das-faixas');
      else if (i.fabrica && !i.confirmado) s += t('descobrir.nao-confirmado');
      return s;
    };
    const linhas = itens.map((i) => [i.ip + (i.httpPort && i.httpPort !== PORTA_HTTP ? ':' + i.httpPort : ''), i.mascara || '',
      i.mac || t('descobrir.nao-lido'), i.modelo || '', i.serial || '', i.firmware || '', estadoDe(i)]);
    return [
      h('p', { class: 'resultado-texto' }, t('descobrir.resumo', { broadcast: f.broadcast, varredura: f.varredura || 0 })),
      tabela(t('descobrir.colunas'), linhas, COLUNAS_MONO_DESCOBRIR),
    ];
  }

  function verificacao(f) {
    const itens = f.itens || [];
    if (!itens.length) return [h('p', { class: 'resultado-texto' }, t('verificar.nenhuma'))];
    const resultado = (i) => (i.ok ? t('verificar.ok')
      : (i.ping ? (i.login ? t('verificar.divergente') : t('verificar.login-falhou')) : t('verificar.sem-ping')));
    return [tabela(t('verificar.colunas'), itens.map((i) => [i.ip, i.mac, resultado(i), i.detalhe]), COLUNAS_MONO_VERIFICAR)];
  }

  function feita(f) {
    const nome = { sondar: 'ferr.sondar.resultado', descobrir: 'ferramenta.encontradas', verificar: 'ferramenta.verificacao' }[f.tipo];
    const partes = [tituloDe(t('ferramenta.titulo-as', { titulo: nome ? t(nome) : f.tipo, quando: f.quando }))];
    if (f.tipo === 'sondar') partes.push(sondagem(f));
    else if (f.tipo === 'descobrir') partes.push(...descoberta(f));
    else if (f.tipo === 'verificar') partes.push(...verificacao(f));
    return partes;
  }

  function testeInternet(m) {
    const i = m.internet;
    const tipo = i.motivo === 'ok' ? 'sucesso' : (i.nivel === 'alarme' ? 'atencao' : 'info');
    return [tituloDe(t('ferr.internet.resultado')), aviso(tipo, t(FRASE_INTERNET[i.motivo], { quando: i.quando }))];
  }

  // O que vai na caixa: o erro com o conserto primeiro, depois o resultado da vez.
  function conteudo(m) {
    if (falha) return [aviso('erro', falha.texto, falha.cru)];
    const p = pedido;
    const partes = [];
    const a = m.aviso;
    const temAviso = !!(p && a.texto && a.n > p.avisoN && a.origem === p.tipo);
    if (temAviso) {
      const tr = traduzirAvisoFerramenta(a.texto);
      partes.push(aviso(tr.tipo, tr.texto));
    }
    const ocupado = esperando || m.ocupado;
    if (p && p.tipo === 'internet-testar') {
      if (ocupado && m.internet.quando === p.quando) partes.push(...emCurso(p.tipo, m));
      else partes.push(...testeInternet(m));
      return partes;
    }
    const f = m.ferramenta;
    // Resultado de antes do pedido (a simulacao recusa o Sondar sem trocar a ferramenta) nao entra.
    const daVez = !!f && (!p || (f.tipo === p.tipo && (JSON.stringify(f) !== p.antes || (!ocupado && !temAviso))));
    if (daVez && f.emCurso) partes.push(...emCurso(f.tipo, m, f));
    else if (daVez) partes.push(...feita(f));
    else if (p && ocupado && !temAviso) partes.push(...emCurso(p.tipo, m));
    if (!partes.length) partes.push(h('p', { class: 'resultado-vazio' }, t('ferr.resultado.vazio')));
    return partes;
  }

  function desenhar(m) {
    const nova = JSON.stringify([pedido, falha, esperando, m.ferramenta, m.trabalho, m.progresso, m.aviso, m.internet, m.ocupado]);
    if (nova === chave) return;
    chave = nova;
    const partes = conteudo(m).filter(Boolean);
    caixa.replaceChildren(...partes);
    // Uma frase curta por mudanca para o leitor de tela (o aviso ou o titulo),
    // so depois de um pedido daqui: abrir a tela nao fala nada.
    const primeiro = partes[0];
    const frase = primeiro ? (primeiro.querySelector('p') || primeiro).textContent : '';
    if (pedido && frase !== fala) ctx.anunciar(frase);
    fala = frase;
  }

  function atualizar(m) {
    // A ferramenta terminou no servidor: o botao volta.
    if (liberar && !esperando && !m.ocupado && !(m.ferramenta && m.ferramenta.emCurso)) soltar();
    // Procurar: desligado em simulacao, com o motivo escrito ao lado (aria-describedby).
    const simular = !!m.simular;
    textoProcurar.textContent = simular ? t('ferr.procurar.motivo') : t('ferr.procurar.texto');
    if (!liberar) {
      procurar.disabled = simular;
      if (simular) procurar.setAttribute('aria-describedby', textoProcurar.id);
      else procurar.removeAttribute('aria-describedby');
    }
    desenhar(m);
  }

  return { el, foco: titulo, atualizar, anexarLog };
}
