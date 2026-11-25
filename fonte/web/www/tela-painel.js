// Painel (direcao.md, secoes 3.2, 3.6, 5.3, 5.4, 5.5 e 5.7). Topo: cabecalho da
// fila (nome, faixa, vigia, Montar outra fila, Encerrar a fila), a fita e o
// estado vazio da vez; faixa do modo de reserva. Embaixo, a tabela das cameras:
// abas "Fila agora" e "Registro", uma linha por posicao da fila, os grupos das
// cameras sem posicao e o registro gravado. So desenha o modelo do estado.js (decisao P1); o que a
// tela guarda e o que e dela: o que o operador digitou, o envio em curso e o
// resultado junto dos campos.
//
// Porta e canal (P2): vale o valor publicado pelo servidor. A linha mostra o
// valor enviado so ate a consulta seguinte ao envio; recusado, volta ao
// publicado e o erro fica junto dos campos; reenviar o mesmo valor envia de novo.
import { h, focar } from './dom.js';
import { icone } from './icones.js';
import { t, nomeEtapa, textoDaFalha, traduzirServidor, motivoVigia } from './textos.js';
import { botao, ocupar, selo, barraEtapas, chip, lugarAviso, aviso, detalhe, lateral } from './componentes.js';
import { montarFormulario } from './formularios.js';
import { salvarParcial } from './tela-inicio.js';
import { dataHora, hora, mac as formatarMac, streamsEncoder } from './formato.js';
import {
  CONSULTA_MS, ESPERA_ESTADO_MS, ESPERA_ESTADO_PASSO_MS, NOTA_SALVO_MS, TRAVA_DECISAO_MS,
  DESTAQUE_LINHA_MS, FITA_MAX_NUMEROS, FITA_PASSO_NUMERO,
} from './constantes.js';

const COLUNAS_FILA = ['pos', 'estado', 'ip', 'modelo', 'serial', 'mac', 'porta', 'canal'];
const COLUNAS_REGISTRO = ['ip', 'mac', 'modelo', 'situacao', 'encoder', 'local', 'rackPorta', 'canal', 'data'];
const ESTADO_DO_STATUS = { Instalada: 'instalada', Falhou: 'falha', 'Em andamento': 'curso', Resetada: 'pulada' };
const COM_CAMPOS = ['instalada', 'curso', 'falha'];
const ROTA_FILA = '#/sessao/fila';
const PEDE_TITULO = 'pede-voce-titulo';
// Fita: a ordem da legenda e o rotulo de cada estado (contagem junto).
const LEGENDA = ['instalada', 'falha', 'curso', 'proxima', 'aguardando', 'pulada'];
const ROTULO_LEGENDA = {
  instalada: 'fita.instaladas', falha: 'fita.falha', curso: 'fita.curso',
  proxima: 'fita.proxima', aguardando: 'fita.aguardando', pulada: 'fita.puladas',
};
// A casa da falha e mais alta e leva a marca: forma, alem da cor (dataviz).
const MARCA_FALHA = '!';
// Motivos do vigia que o estado da tela ja diz (nao repete na frase).
const MOTIVO_JA_DITO = ['', 'pelo operador', 'fila concluida', 'fila encerrada'];

function textoEstado(p, totalEtapas) {
  if (p.estado === 'curso') return p.etapaN ? t('estado.curso', { n: p.etapaN, total: totalEtapas, etapa: p.etapa }) : t('estado.portao');
  if (p.estado === 'falha') return t('estado.falha', { etapa: p.falha.etapa });
  return t('estado.' + p.estado);
}

const pausa = (ms) => new Promise((r) => setTimeout(r, ms));

// ctx: { api, modelo(), consultarNova(), lerRegistro(), anunciar(texto), confirmar(o) }
export function telaPainel(ctx, parte) {
  const raiz = h('section', { class: 'vista', 'aria-label': t('painel.abas') });
  // Por posicao: rascunho digitado { porta, canal }, envio em curso, nota junto
  // dos campos { tipo, texto }, a decisao em curso { acao, onde }, o erro dela
  // { onde, texto, cru } e a trava dos botoes da falha.
  const linhas = new Map();
  // "Detalhe tecnico" aberto ("onde-n"): o redesenho nao fecha o que o operador abriu.
  const detalhesAbertos = new Set();
  // Por MAC: erro do "Retomar esta camera".
  const retomadas = new Map();
  let aba = parte === 'registro' ? 'registro' : 'fila';
  let assinatura = '';
  let versaoLocal = 0;
  let estadosAntes = null;
  let novas = new Set();
  let redesenhando = false;

  function linha(n) {
    if (!linhas.has(n)) linhas.set(n, { rascunho: null, enviando: false, nota: null, decidindo: null, decisao: null, trava: 0, timer: 0 });
    return linhas.get(n);
  }

  function mudouLocal() {
    versaoLocal += 1;
    atualizar(ctx.modelo());
  }

  function posicaoNoModelo(m, n) {
    return m.fila ? m.fila.posicoes.find((p) => p.posicao === n) : null;
  }

  // ------------------------------------------------------------ porta e canal
  function valoresDaLinha(n) {
    const ler = (campo) => {
      const el = raiz.querySelector(`[data-foco="${campo}-${n}"]`);
      return el ? el.value.trim() : '';
    };
    return { porta: ler('porta'), canal: ler('canal') };
  }

  function mostrarNota(n, tipo, texto) {
    const l = linha(n);
    clearTimeout(l.timer);
    l.nota = tipo ? { tipo, texto } : null;
    if (tipo === 'sucesso') l.timer = setTimeout(() => { if (l.nota && l.nota.tipo === 'sucesso') { l.nota = null; mudouLocal(); } }, NOTA_SALVO_MS);
  }

  async function salvarPortaCanal(n) {
    const l = linha(n);
    if (l.enviando) return;
    const p = posicaoNoModelo(ctx.modelo(), n);
    if (!p || !p.camera) return;
    const { porta, canal } = valoresDaLinha(n);
    const pub = p.camera;
    if (porta === pub.porta && canal === pub.canal) {
      // Igual ao publicado: nada a gravar; um erro antigo deixa de valer.
      l.rascunho = null;
      if (l.nota && l.nota.tipo === 'erro') { mostrarNota(n, null); mudouLocal(); }
      return;
    }
    const mac = pub.macBruto;
    const n0 = ctx.modelo().aviso.n;
    l.enviando = true;
    l.rascunho = { porta, canal };
    mostrarNota(n, 'info', t('painel.portaCanal.salvando'));
    mudouLocal();
    let erro = '';
    const r = await ctx.api.comando('/api/camera', { mac, porta, canal });
    if (!r.ok) {
      erro = traduzirServidor(r).texto;
    } else {
      // O comando vai para a fila do worker: espera ele publicar o valor novo ou
      // recusar. "Worker livre" nao resolve: o estado publicado pode vir antes do
      // comando ser lido e daria "nao confirmou" com o valor ja gravado.
      const fim = Date.now() + ESPERA_ESTADO_MS;
      let m = await ctx.consultarNova();
      const resolvido = (x) => {
        const c = camera(x, mac);
        return (c && c.porta === porta && c.canal === canal) || (x.aviso.n > n0 && x.aviso.origem === 'camera');
      };
      while (!resolvido(m) && Date.now() < fim) {
        await pausa(ESPERA_ESTADO_PASSO_MS);
        m = await ctx.consultarNova();
      }
      const c = camera(m, mac);
      if (c && c.porta === porta && c.canal === canal) erro = '';
      else if (m.aviso.n > n0 && m.aviso.origem === 'camera') erro = m.aviso.texto;
      else erro = t('painel.portaCanal.semConfirmacao');
    }
    // A partir daqui vale o publicado: o rascunho sai, com ou sem erro.
    l.enviando = false;
    l.rascunho = null;
    mostrarNota(n, erro ? 'erro' : 'sucesso', erro || t('painel.portaCanal.salvo'));
    mudouLocal();
  }

  function camera(m, mac) {
    const chave = formatarMac(mac);
    const p = m.fila ? m.fila.posicoes.find((x) => x.camera && x.camera.mac === chave) : null;
    return p ? p.camera : null;
  }

  // Nome do campo: cabecalho da coluna e celula Pos., os dois visiveis.
  function entrada(p, campo) {
    const n = p.posicao;
    const l = linha(n);
    const valor = l.rascunho ? l.rascunho[campo] : p.camera[campo];
    const comErro = !!(l.nota && l.nota.tipo === 'erro');
    return h('input', {
      class: ['entrada-tabela', 'mono'], type: 'text', inputmode: 'numeric', autocomplete: 'off', spellcheck: 'false',
      value: valor,
      'aria-labelledby': `painel-col-${campo} painel-pos-${n}`,
      'aria-invalid': comErro ? 'true' : null,
      'aria-describedby': l.nota ? `painel-nota-${n}` : null,
      readonly: l.enviando,
      dados: { foco: `${campo}-${n}`, campo, linha: String(n) },
      oninput: () => { l.rascunho = valoresDaLinha(n); },
      onkeydown: (ev) => { if (ev.key === 'Enter') { ev.preventDefault(); salvarPortaCanal(n); } },
      onfocusout: (ev) => {
        if (redesenhando) return;
        const para = ev.relatedTarget;
        // Indo da porta para o canal da mesma linha ainda nao grava.
        if (para && para.dataset && para.dataset.linha === String(n) && para.dataset.campo) return;
        salvarPortaCanal(n);
      },
    });
  }

  // ------------------------------------------------------------ falha
  // A decisao (Tentar de novo, Mudar o encoder, Pular) mora so na linha que
  // falhou e em Pede voce (UX-13), com o mesmo corpo. Botao travado leva
  // aria-disabled, nao disabled: o foco nao cai para o body no meio do clique e
  // o motivo da senha recusada continua lido junto do Tentar (UI-14).
  function corpoDecisao(p, acao) {
    return p.camera ? { mac: p.camera.macBruto, acao } : { acao };
  }

  // Aceito: os botoes ficam travados ate a linha mudar ou a trava vencer.
  function travar(n) {
    linha(n).trava = Date.now() + TRAVA_DECISAO_MS;
    setTimeout(mudouLocal, TRAVA_DECISAO_MS);
  }

  async function decidir(p, acao, onde) {
    const n = p.posicao;
    const l = linha(n);
    if (l.decidindo || l.trava > Date.now()) return;
    if (acao === 'pular') {
      const ok = await ctx.confirmar({
        titulo: t('painel.pular.titulo', { n }), texto: t('painel.pular.texto', { ip: p.ip }),
        confirmar: t('painel.pular.confirmar', { n }), perigo: true,
      });
      if (!ok) return;
    }
    l.decidindo = { acao, onde };
    l.decisao = null;
    mudouLocal();
    const r = await ctx.api.comando('/api/decisao', corpoDecisao(p, acao));
    l.decidindo = null;
    // Recusado: a frase do painel (ou "O painel recusou a acao.") fica onde o
    // operador clicou, com a resposta crua no Detalhe tecnico.
    if (r.ok) travar(n); else l.decisao = { onde, ...traduzirServidor(r) };
    mudouLocal();
  }

  const ROTULO_DECISAO = {
    tentar: ['painel.decisao.tentar', 'painel.decisao.tentando'],
    encoder: ['painel.decisao.encoder', 'painel.decisao.encoder'],
    pular: ['painel.decisao.pular', 'painel.decisao.pulando'],
  };

  function botaoFalha(p, onde, acao, tipo, motivoId) {
    const n = p.posicao;
    const l = linha(n);
    const ocupado = !!(l.decidindo && l.decidindo.acao === acao && l.decidindo.onde === onde);
    const travado = !!l.decidindo || l.trava > Date.now() || (acao === 'tentar' && p.falha.bloqueiaTentar);
    const executar = acao === 'encoder' ? () => abrirEncoder(p) : () => decidir(p, acao, onde);
    const b = botao(t(ROTULO_DECISAO[acao][ocupado ? 1 : 0]), (ev) => {
      if (ev.currentTarget.getAttribute('aria-disabled') !== 'true') executar();
    }, { tipo, motivoId, dados: { foco: (onde === 'pede' ? 'pede-' : '') + acao + '-' + n, posicao: String(n) } });
    if (travado) b.setAttribute('aria-disabled', 'true');
    if (ocupado) b.setAttribute('aria-busy', 'true');
    return b;
  }

  function detalheFalha(chave, cru) {
    const d = detalhe(cru);
    d.open = detalhesAbertos.has(chave);
    d.addEventListener('toggle', () => { if (d.open) detalhesAbertos.add(chave); else detalhesAbertos.delete(chave); });
    d.querySelector('summary').dataset.foco = 'detalhe-' + chave;
    return d;
  }

  // O que aconteceu e o conserto (textos.js), as decisoes, o motivo do Tentar
  // travado, o erro da ultima decisao e a resposta crua da camera recolhida.
  // onde: 'linha' | 'pede'. Valor recusado no encoder: "Mudar o encoder" e o primario.
  function corpoFalha(p, onde) {
    const n = p.posicao;
    const f = p.falha;
    const l = linha(n);
    const motivoId = `${onde}-motivo-${n}`;
    const noEncoder = f.etapa === 'encoder';
    const encoderPrimeiro = noEncoder && f.recusa && !f.bloqueiaTentar;
    return [
      h('p', { class: 'falha-conserto' }, textoDaFalha(f, p.ip)),
      h('div', { class: 'falha-acoes' }, [
        botaoFalha(p, onde, 'tentar', encoderPrimeiro ? 'secundario' : 'primario', f.bloqueiaTentar ? motivoId : undefined),
        noEncoder ? botaoFalha(p, onde, 'encoder', encoderPrimeiro ? 'primario' : 'secundario') : null,
        botaoFalha(p, onde, 'pular', 'discreto'),
      ]),
      f.bloqueiaTentar ? h('p', { class: 'falha-motivo', id: motivoId }, [icone('informacao'), h('span', null, t('painel.decisao.senha'))]) : null,
      l.decisao && l.decisao.onde === onde ? h('div', { role: 'alert' }, aviso('erro', l.decisao.texto, l.decisao.cru)) : null,
      f.erro ? detalheFalha(`${onde}-${n}`, f.erro) : null,
    ];
  }

  function linhaFalha(p, colunas) {
    return h('tr', { class: ['linha-falha', 'linha-detalhe'] }, h('td', { colspan: String(colunas) },
      h('div', { class: 'falha-linha' }, corpoFalha(p, 'linha'))));
  }

  // "Mudar o encoder" (5.8, painel lateral): o formulario da secao Camera, so
  // os streams. Salvar grava a sessao (vale para as proximas cameras tambem) e
  // so depois pede "tentar de novo" para esta.
  function abrirEncoder(p) {
    const n = p.posicao;
    const ativo = document.activeElement;
    const voltar = ativo && ativo.dataset ? ativo.dataset.foco : '';
    const form = montarFormulario('camera', ctx.modelo(), { soEncoder: true });
    const resposta = lugarAviso();
    lateral({
      titulo: t('lateral.encoder.titulo', { n }),
      texto: t('lateral.encoder.texto'),
      conteudo: (fechar) => {
        const salvar = botao(t('lateral.encoder.salvar'), null, { tipo: 'primario', submit: true });
        const enviar = async (ev) => {
          ev.preventDefault();
          if (salvar.disabled) return;
          resposta.limpar();
          const r = form.coletar();
          if (!r.ok) return;
          const restaurar = ocupar(salvar, t('lateral.encoder.salvando'));
          const ok = await salvarParcial(ctx, r.parcial, resposta, form) && await tentarDepoisDoEncoder(p, resposta);
          restaurar();
          if (ok) fechar();
        };
        return h('form', { class: 'lateral-form', novalidate: true, onsubmit: enviar }, [
          form.el,
          resposta.el,
          h('div', { class: 'lateral-acoes' }, [botao(t('dialogo.cancelar'), fechar, { tipo: 'secundario' }), salvar]),
        ]);
      },
      // O foco volta a quem abriu; se a linha ja mudou, ao que pede voce.
      aoFechar: () => {
        const el = voltar ? document.querySelector(`[data-foco="${voltar}"]`) : null;
        if (el) focar(el); else focarDeVolta(n);
      },
    });
    form.focarBitrate();
  }

  async function tentarDepoisDoEncoder(p, resposta) {
    const r = await ctx.api.comando('/api/decisao', corpoDecisao(p, 'tentar'));
    if (!r.ok) {
      const falha = traduzirServidor(r);
      resposta.mostrar('erro', falha.texto, falha.cru);
      return false;
    }
    linha(p.posicao).decisao = null;
    travar(p.posicao);
    mudouLocal();
    ctx.consultarNova();
    return true;
  }

  // Foco num botao de decisao que sumiu (a camera saiu da falha): o titulo da
  // falha em Pede voce, o titulo de Pede voce ou o nome da fila, nunca o body.
  function focarDeVolta(n) {
    const destino = topo.querySelector(`[data-pede="${n}"]`) || topo.querySelector('.pede-titulo') || topo.querySelector('.fila-titulo');
    if (destino) focar(destino);
  }

  function linhaNota(n, colunas) {
    const nota = linha(n).nota;
    if (!nota) return null;
    const nomeIcone = { erro: 'falha', sucesso: 'concluido', info: 'espera' }[nota.tipo];
    return h('tr', { class: ['linha-detalhe', 'linha-nota', nota.tipo === 'erro' ? 'linha-falha' : null] }, h('td', { colspan: String(colunas) },
      h('p', { class: ['nota', 'nota-' + nota.tipo], id: `painel-nota-${n}`, role: nota.tipo === 'erro' ? 'alert' : 'status' }, [
        icone(nomeIcone), h('span', null, nota.texto),
      ])));
  }

  // ------------------------------------------------------------ Fila agora
  function tabelaFila(m) {
    const f = m.fila;
    if (!f) return null;
    const corpo = [];
    for (const p of f.posicoes) {
      const c = p.camera;
      const n = p.posicao;
      const comCampos = c && COM_CAMPOS.includes(p.estado);
      const classes = [p.estado === 'falha' ? 'linha-falha' : null, novas.has(n) ? 'linha-nova' : null, alvo === n ? 'linha-alvo' : null];
      corpo.push(h('tr', { class: classes, dados: { linha: String(n) } }, [
        h('td', { class: 'coluna-pos', id: `painel-pos-${n}` }, String(n)),
        h('td', { class: 'coluna-estado' }, h('span', { class: 'estado-linha' }, [
          selo(p.estado, textoEstado(p, f.totalEtapas)),
          p.estado === 'curso' && p.etapaN ? barraEtapas(p.etapaN, f.totalEtapas) : null,
        ])),
        h('td', { class: 'mono', translate: 'no' }, p.ip),
        h('td', null, c ? c.modelo : ''),
        h('td', { class: 'mono', translate: 'no' }, c ? c.serial : ''),
        h('td', { class: 'mono', translate: 'no' }, c ? c.mac : ''),
        h('td', { class: 'coluna-campo' }, comCampos ? entrada(p, 'porta') : ''),
        h('td', { class: 'coluna-campo' }, comCampos ? entrada(p, 'canal') : ''),
      ]));
      if (p.estado === 'falha') corpo.push(linhaFalha(p, COLUNAS_FILA.length));
      const nota = linhaNota(n, COLUNAS_FILA.length);
      if (nota) corpo.push(nota);
    }
    return h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
      h('thead', null, h('tr', null, COLUNAS_FILA.map((k) => h('th', { scope: 'col', id: `painel-col-${k}` }, t('tabela.' + k))))),
      h('tbody', null, corpo),
    ]));
  }

  // Cameras sem posicao: na espera do portao e as ja inicializadas.
  function grupoEspera(m) {
    if (!m.espera.length) return null;
    return h('section', { class: 'grupo', 'aria-labelledby': 'painel-espera-titulo' }, [
      h('h2', { class: 'grupo-titulo', id: 'painel-espera-titulo' }, t('painel.espera.titulo', { n: m.espera.length })),
      h('p', { class: 'apoio' }, t('painel.espera.texto')),
      h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
        h('thead', null, h('tr', null, ['estado', 'modelo', 'serial', 'mac'].map((k) => h('th', { scope: 'col' }, t('tabela.' + k))))),
        h('tbody', null, m.espera.map((c) => h('tr', null, [
          h('td', { class: 'coluna-estado' }, selo('espera', t('estado.espera'))),
          h('td', null, c.modelo),
          h('td', { class: 'mono', translate: 'no' }, c.serial),
          h('td', { class: 'mono', translate: 'no' }, c.mac),
        ]))),
      ])),
    ]);
  }

  async function retomar(btn, c) {
    const restaurar = ocupar(btn, t('painel.retomando'));
    const r = await ctx.api.comando('/api/fila/conectada', { porta: '', canal: '', ip: c.ipOrigem });
    restaurar();
    if (r.ok) retomadas.delete(c.mac); else retomadas.set(c.mac, traduzirServidor(r).texto);
    mudouLocal();
  }

  function grupoIgnoradas(m) {
    if (!m.ignoradas.length) return null;
    const colunas = ['estado', 'ipAtual', 'modelo', 'serial', 'mac', 'acao'];
    const corpo = [];
    for (const c of m.ignoradas) {
      corpo.push(h('tr', null, [
        h('td', { class: 'coluna-estado' }, selo('ignorada', t('estado.ignorada'))),
        h('td', { class: 'mono', translate: 'no' }, c.ipOrigem),
        h('td', null, c.modelo),
        h('td', { class: 'mono', translate: 'no' }, c.serial),
        h('td', { class: 'mono', translate: 'no' }, c.mac),
        h('td', null, botao(t('painel.retomar'), (ev) => retomar(ev.currentTarget, c), { tipo: 'secundario', dados: { foco: `retomar-${c.mac}` } })),
      ]));
      const erro = retomadas.get(c.mac);
      if (erro) {
        corpo.push(h('tr', { class: ['linha-detalhe', 'linha-falha'] }, h('td', { colspan: String(colunas.length) },
          h('p', { class: ['nota', 'nota-erro'], role: 'alert' }, [icone('falha'), h('span', null, erro)]))));
      }
    }
    return h('section', { class: 'grupo', 'aria-labelledby': 'painel-ignoradas-titulo' }, [
      h('h2', { class: 'grupo-titulo', id: 'painel-ignoradas-titulo' }, t('painel.ignoradas.titulo', { n: m.ignoradas.length })),
      h('p', { class: 'apoio' }, t('painel.ignoradas.texto')),
      h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
        h('thead', null, h('tr', null, colunas.map((k) => h('th', { scope: 'col' }, t('tabela.' + k))))),
        h('tbody', null, corpo),
      ])),
    ]);
  }

  // ------------------------------------------------------------ Registro
  function situacao(r) {
    const estado = ESTADO_DO_STATUS[r.Status] || 'aguardando';
    const texto = ESTADO_DO_STATUS[r.Status] ? t('registro.status.' + estado) : String(r.Status || '');
    const detalheTexto = r.Status === 'Falhou' && r.Erro ? r.Erro
      : (r.Status !== 'Instalada' && r.Etapa ? t('registro.concluiu', { etapa: nomeEtapa(r.Etapa) || r.Etapa }) : '');
    return [selo(estado, texto), detalheTexto ? h('span', { class: 'situacao-detalhe' }, detalheTexto) : null];
  }

  function encoder(r) {
    const s = streamsEncoder(r.Encoder, false);
    if (!s) return '';
    return [
      s.principal ? h('span', { class: 'stream' }, t('registro.principal', { texto: s.principal })) : null,
      s.secundario ? h('span', { class: 'stream' }, t('registro.secundario', { texto: s.secundario })) : null,
    ];
  }

  function tabelaRegistro(m) {
    const reg = m.registro;
    if (reg.lendo) return h('div', { class: 'tabela-vazio', role: 'status' }, h('p', null, t('registro.lendo')));
    if (reg.erro) {
      return h('div', { class: 'tabela-vazio', role: 'alert' }, [
        h('p', null, [icone('falha'), ' ', t('registro.erro')]),
        botao(t('registro.lerDeNovo'), () => ctx.lerRegistro(), { tipo: 'secundario', dados: { foco: 'registro-ler-erro' } }),
      ]);
    }
    if (!reg.lista) return h('div', { class: 'tabela-vazio', role: 'status' }, h('p', null, t('registro.lendo')));
    if (!reg.lista.length) return h('div', { class: 'tabela-vazio' }, h('p', null, t('registro.vazio')));
    const corpo = reg.lista.map((r) => h('tr', null, [
      h('td', { class: 'mono', translate: 'no' }, r.Ip || ''),
      h('td', { class: 'mono', translate: 'no' }, formatarMac(r.Mac)),
      h('td', null, r.Modelo || ''),
      h('td', { class: 'coluna-situacao' }, situacao(r)),
      h('td', { class: 'coluna-encoder' }, encoder(r)),
      h('td', null, r.Local || ''),
      h('td', { class: 'mono' }, [r.Rack, r.Porta].filter(Boolean).join(' / ')),
      h('td', { class: 'mono' }, r.Canal || ''),
      h('td', { class: 'numeros' }, dataHora(r.Data)),
    ]));
    return h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
      h('thead', null, h('tr', null, COLUNAS_REGISTRO.map((k) => h('th', { scope: 'col' }, t('registro.col.' + k))))),
      h('tbody', null, corpo),
    ]));
  }

  function barraRegistro(m) {
    return h('div', { class: 'vista-cabeca' }, [
      h('h2', { class: 'grupo-titulo' }, m.registro.simulado || m.simular ? t('registro.titulo-simulacao') : t('registro.titulo')),
      h('div', { class: 'vista-acoes' }, [
        botao(t('registro.ler'), () => ctx.lerRegistro(), { tipo: 'secundario', desabilitado: m.registro.lendo, dados: { foco: 'registro-ler' } }),
        h('a', { class: ['botao', 'botao-secundario'], href: '/api/relatorio.csv', download: '', dados: { foco: 'registro-exportar' } },
          h('span', { class: 'botao-rotulo' }, t('registro.exportar'))),
      ]),
    ]);
  }

  // ------------------------------------------------------------ topo: cabecalho, fita e estados
  // Nos que vivem entre redesenhos: os lugares do aviso do servidor (o legado
  // mostrarAviso escreve no que estiver na tela) e o erro do pedido.
  const topo = h('section', { class: 'painel-topo', 'aria-label': t('painel.titulo') });
  const faixa = h('div', { class: ['faixa', 'faixa-atencao'], role: 'status', hidden: true },
    h('div', { class: 'faixa-conteudo' }, [icone('atencao'), h('p', { class: 'faixa-texto' }, t('faixa.reserva'))]));
  const avisoVigia = h('p', { class: 'aviso-legado', role: 'alert', hidden: true, dados: { avisoDe: 'vigia' } });
  const avisoConectada = h('p', { class: 'aviso-legado', role: 'alert', hidden: true, dados: { avisoDe: 'conectada' } });
  const erroTopo = lugarAviso();
  let assinaturaTopo = '';
  let enviando = '';
  let retomarAberto = null;
  let ipRetomar = '';
  let alvo = 0;
  let alvoTimer = 0;

  async function enviarTopo(qual, rota, corpo) {
    if (enviando) return;
    enviando = qual;
    erroTopo.limpar();
    atualizarTopo(ctx.modelo());
    const r = await ctx.api.comando(rota, corpo);
    enviando = '';
    if (!r.ok) {
      const falha = traduzirServidor(r);
      erroTopo.mostrar('erro', falha.texto, falha.cru);
    }
    await ctx.consultarNova();
    atualizarTopo(ctx.modelo());
  }

  // Botao do topo: com o pedido em curso troca o rotulo; o redesenho nao perde isso.
  function botaoTopo(qual, rotulo, rotuloOcupado, aoClicar, o) {
    const ocupado = enviando === qual;
    const b = botao(ocupado ? rotuloOcupado : rotulo, aoClicar, {
      tipo: o.tipo, desabilitado: !!enviando || !!o.desabilitado, dados: { foco: qual },
    });
    if (ocupado) b.setAttribute('aria-busy', 'true');
    return b;
  }

  async function encerrar() {
    const f = ctx.modelo().fila;
    const ok = await ctx.confirmar({
      titulo: t('dialogo.encerrarFila.titulo'), texto: t('dialogo.encerrarFila.texto', { sem: f ? f.semCamera : 0 }),
      confirmar: t('dialogo.encerrarFila.confirmar'), perigo: true,
    });
    if (ok) enviarTopo('encerrar', '/api/decisao', { acao: 'encerrar' });
  }

  function cabecalho(m) {
    const f = m.fila;
    const v = m.vigia;
    const aberta = !f.concluida && !f.encerrada;
    const acoes = [];
    if (aberta) {
      // Vigia ligado: chip em --agora, sem pulso (UI-15).
      acoes.push(v.ligado ? chip(t('painel.vigia.ligado'), 'agora', 'agora') : chip(t('painel.vigia.desligado'), 'neutro'));
      acoes.push(botaoTopo('vigia', t(v.ligado ? 'painel.vigia.desligar' : 'painel.vigia.ligar'),
        t(v.ligado ? 'painel.vigia.desligando' : 'painel.vigia.ligando'),
        () => enviarTopo('vigia', '/api/vigia', { ligado: !v.ligado, porta: '', canal: '', broadcast: v.qualquerFaixa }),
        { tipo: m.painel === 'vigiaDesligado' ? 'primario' : 'secundario' }));
    }
    acoes.push(botaoTopo('montar', t('painel.fila.montarOutra'), t('painel.fila.montarOutra'), () => ctx.ir(ROTA_FILA),
      { tipo: aberta ? 'secundario' : 'primario' }));
    if (aberta) acoes.push(botaoTopo('encerrar', t('painel.fila.encerrar'), t('painel.fila.encerrando'), encerrar, { tipo: 'discreto' }));
    // Atalho do anuncio da falha (P3): leva o foco a Pede voce, sem tirar ninguem do lugar sozinho.
    if (f.pedeVoce.length) acoes.unshift(botao(t('painel.irPedeVoce'), irParaPede, { tipo: 'discreto', icone: 'abrir', dados: { foco: 'ir-pede' } }));
    return h('div', { class: 'fila-cabeca' }, [
      h('div', { class: 'fila-nome' }, [
        h('h1', { class: 'fila-titulo' }, t('painel.fila.titulo', f)),
        h('p', { class: 'fila-faixa' }, [
          h('span', { class: 'mono', translate: 'no' }, t('painel.fila.faixa', f)),
          v.qualquerFaixa ? chip(t('painel.qualquerFaixa'), 'atencao', 'atencao') : null,
        ]),
      ]),
      h('div', { class: 'fila-acoes' }, acoes),
    ]);
  }

  // Fita (5.5): uma casa por posicao, forma alem da cor; a legenda conta cada
  // estado. Para o leitor de tela vale a frase; a tabela e o caminho do teclado.
  function fita(m) {
    const f = m.fila;
    const c = f.contagem;
    const todos = f.total <= FITA_MAX_NUMEROS;
    const casas = f.posicoes.map((p) => {
      const casa = h('span', { class: ['fita-casa', 'fita-' + p.estado], onclick: () => irParaLinha(p.posicao) },
        p.estado === 'falha' ? MARCA_FALHA : null);
      if (p.estado === 'curso') casa.style.setProperty('--fracao', String(f.totalEtapas ? p.etapaN / f.totalEtapas : 0));
      return casa;
    });
    const numeros = f.posicoes.map((p) => h('span', { class: 'fita-numero' },
      todos || p.posicao === 1 || p.posicao % FITA_PASSO_NUMERO === 0 ? String(p.posicao) : ''));
    const legenda = LEGENDA.filter((e) => c[e] > 0 || e === 'instalada').map((e) => h('span', { class: 'legenda-item', dados: { estado: e } }, [
      h('span', { class: ['legenda-amostra', 'legenda-' + e] }),
      t(ROTULO_LEGENDA[e], { n: c[e] }),
    ]));
    return h('div', { class: 'fita-bloco' }, [
      h('p', { class: 'so-leitor' }, t('fita.leitor', { total: f.total, c })),
      h('div', { class: 'fita', 'aria-hidden': 'true' }, casas),
      h('div', { class: 'fita-numeros', 'aria-hidden': 'true' }, numeros),
      h('div', { class: 'fita-legenda', 'aria-hidden': 'true' }, legenda),
    ]);
  }

  function irParaLinha(n) {
    if (aba !== 'fila') trocarAba('fila');
    alvo = n;
    clearTimeout(alvoTimer);
    alvoTimer = setTimeout(() => { alvo = 0; mudouLocal(); }, DESTAQUE_LINHA_MS);
    mudouLocal();
    const tr = raiz.querySelector(`tr[data-linha="${n}"]`);
    if (tr) tr.scrollIntoView({ block: 'center' });
  }

  function retomarBloco(m) {
    // O servidor cita "Retomar camera ja inicializada" no aviso que pede isso: o bloco abre.
    const pedido = !!(m.aviso.texto && m.aviso.texto.includes(t('painel.retomar.abrir')));
    const enviar = () => {
      if (!ipRetomar.trim()) { erroTopo.mostrar('erro', t('painel.retomar.ipInvalido')); return; }
      enviarTopo('retomar', '/api/fila/conectada', { porta: '', canal: '', ip: ipRetomar.trim() });
    };
    return h('details', {
      class: 'retomar', open: retomarAberto === null ? pedido : retomarAberto,
      ontoggle: (ev) => { retomarAberto = ev.currentTarget.open; },
    }, [
      h('summary', null, t('painel.retomar.abrir')),
      h('p', { class: 'campo-ajuda' }, t('painel.retomar.nota')),
      h('div', { class: 'retomar-linha' }, [
        h('label', { class: 'campo' }, [
          h('span', { class: 'campo-rotulo' }, t('painel.campo-ip')),
          h('input', {
            class: ['campo-entrada', 'mono'], type: 'text', inputmode: 'decimal', autocomplete: 'off', spellcheck: 'false',
            translate: 'no', value: ipRetomar, dados: { foco: 'retomar-ip' },
            oninput: (ev) => { ipRetomar = ev.currentTarget.value; },
            onkeydown: (ev) => { if (ev.key === 'Enter') { ev.preventDefault(); enviar(); } },
          }),
        ]),
        botaoTopo('retomar', t('painel.retomar.enviar'), t('painel.retomando'), enviar, { tipo: 'secundario', desabilitado: m.ocupado }),
      ]),
    ]);
  }

  function tituloBloco(texto, nomeIcone) {
    return h('h2', { class: 'bloco-titulo' }, [nomeIcone ? icone(nomeIcone, 'm') : null, h('span', null, texto)]);
  }

  // Estados do Painel (3.6), um por vez, do estado.js.
  function blocoEstado(m) {
    const f = m.fila;
    const v = m.vigia;
    const motivo = MOTIVO_JA_DITO.includes(v.motivo) ? '' : motivoVigia(v.motivo);
    const textoMotivo = motivo ? h('p', null, t('painel.vazio.motivo', { motivo })) : null;
    if (m.painel === 'semFila') {
      return h('section', { class: 'bloco' }, [
        tituloBloco(t('painel.vazio.semFila')),
        h('p', null, t('painel.vazio.semFila.texto')),
        botao(t('painel.fila.montar'), () => ctx.ir(ROTA_FILA), { tipo: 'primario', dados: { foco: 'montar-fila' } }),
      ]);
    }
    if (m.painel === 'concluida' || m.painel === 'encerrada') {
      const c = f.contagem;
      const titulo = m.painel === 'concluida' ? t('painel.concluida', { n: c.instalada })
        : t('painel.encerrada', { inst: c.instalada, sem: f.total - c.instalada - c.pulada });
      return h('section', { class: ['bloco', m.painel === 'concluida' ? 'bloco-sucesso' : null] }, [
        tituloBloco(titulo, m.painel === 'concluida' ? 'concluido' : null),
        textoMotivo,
        h('p', null, t('painel.fim.registro')),
      ]);
    }
    if (m.painel === 'vigiaDesligado') {
      const p = f.proxima;
      return h('section', { class: 'bloco' }, [
        tituloBloco(t('painel.vigia.desligado')),
        textoMotivo,
        h('p', null, t('painel.vazio.desligado')),
        h('h3', { class: 'bloco-subtitulo' }, t('painel.vazio.sequencial')),
        p ? h('p', null, t('painel.vazio.sequencial.texto', { n: p.posicao, ip: p.ip })) : null,
        p ? botaoTopo('configurar', t('painel.vazio.configurar', { n: p.posicao }), t('painel.vazio.configurando'),
          () => enviarTopo('configurar', '/api/fila/conectada', { porta: '', canal: '', ip: '' }),
          { tipo: 'secundario', desabilitado: m.ocupado }) : null,
        avisoConectada,
        retomarBloco(m),
      ]);
    }
    if (m.painel === 'esperando') {
      return h('section', { class: 'bloco' }, [
        tituloBloco(t('painel.vazio.esperando'), 'espera'),
        h('p', null, t('painel.vazio.esperando.texto', {
          ip: v.ipFabrica || t('painel.vazio.ipFabrica'), hora: v.desde ? hora(v.desde) : '', qualquer: v.qualquerFaixa,
        })),
      ]);
    }
    return null;
  }

  // Pede voce (direcao 3.2, P3): toda falha que espera decisao, a mais grave
  // primeiro (estado.js), cada uma com o mesmo corpo da linha da tabela.
  function pedeVoce(m) {
    const lista = m.fila ? m.fila.pedeVoce : [];
    if (!lista.length) return null;
    return h('section', { class: 'pede', 'aria-labelledby': PEDE_TITULO }, [
      h('h2', { class: 'pede-titulo', id: PEDE_TITULO, tabindex: '-1' }, [icone('falha', 'm'), h('span', null, t('pede.titulo', { n: lista.length }))]),
      h('ul', { class: 'pede-lista' }, lista.map((p) => h('li', { class: 'pede-item' }, [
        h('h3', { class: 'pede-item-titulo', tabindex: '-1', dados: { pede: String(p.posicao) } },
          t('pede.falhou', { n: p.posicao, ip: p.ip, etapa: p.falha.etapa })),
        ...corpoFalha(p, 'pede'),
      ]))),
    ]);
  }

  function irParaPede() {
    const destino = topo.querySelector('.pede-titulo');
    if (!destino) return;
    destino.scrollIntoView({ block: 'start' });
    focar(destino);
  }

  function desenharTopo(m) {
    const f = m.fila;
    // replaceChildren escreveria "null" como texto: so os nos que existem.
    topo.replaceChildren(...[
      f ? cabecalho(m) : h('h1', { class: 'fila-titulo' }, t('painel.titulo')),
      f ? fita(m) : null,
      pedeVoce(m),
      avisoVigia,
      erroTopo.el,
      blocoEstado(m),
    ].filter(Boolean));
    faixa.hidden = !m.vigia.reserva;
  }

  function atualizarTopo(m) {
    // versaoLocal: a trava, a decisao em curso e o erro dela vivem na tela.
    const nova = JSON.stringify([m.fila, m.vigia, m.painel, m.ocupado, m.aviso.texto, enviando, retomarAberto, versaoLocal]);
    if (nova === assinaturaTopo) return;
    assinaturaTopo = nova;
    const ativo = document.activeElement;
    const chave = ativo && topo.contains(ativo) && ativo.dataset ? ativo.dataset.foco : null;
    const posicao = chave ? ativo.dataset.posicao : '';
    const cursor = chave && ativo.tagName === 'INPUT' ? [ativo.selectionStart, ativo.selectionEnd] : null;
    desenharTopo(m);
    if (!chave) return;
    const el = topo.querySelector(`[data-foco="${chave}"]`);
    if (!el) { if (posicao) focarDeVolta(posicao); return; }
    el.focus({ preventScroll: true });
    if (cursor && el.tagName === 'INPUT') el.setSelectionRange(cursor[0], cursor[1]);
  }

  // ------------------------------------------------------------ abas e desenho
  function trocarAba(nome, focarAba) {
    if (nome !== aba) {
      aba = nome;
      history.replaceState(null, '', nome === 'registro' ? '#/painel/registro' : '#/painel');
      if (nome === 'registro') ctx.lerRegistro();
      mudouLocal();
    }
    if (focarAba) focar(raiz.querySelector(`[data-foco="aba-${nome}"]`));
  }

  function abas() {
    const nomes = ['fila', 'registro'];
    return h('div', { class: 'abas', role: 'tablist', 'aria-label': t('painel.abas') }, nomes.map((nome, i) => h('button', {
      type: 'button', role: 'tab', class: 'aba', id: `painel-aba-${nome}`,
      'aria-selected': String(aba === nome), 'aria-controls': 'painel-aba-conteudo', tabindex: aba === nome ? '0' : '-1',
      dados: { foco: `aba-${nome}` },
      onclick: () => trocarAba(nome),
      onkeydown: (ev) => {
        if (ev.key !== 'ArrowRight' && ev.key !== 'ArrowLeft') return;
        ev.preventDefault();
        const passo = ev.key === 'ArrowRight' ? 1 : -1;
        trocarAba(nomes[(i + passo + nomes.length) % nomes.length], true);
      },
    }, t('painel.aba.' + nome))));
  }

  function desenhar(m) {
    const conteudo = aba === 'fila'
      ? [tabelaFila(m), grupoEspera(m), grupoIgnoradas(m)]
      : [barraRegistro(m), tabelaRegistro(m)];
    raiz.replaceChildren(
      abas(),
      h('div', { class: 'vista-conteudo', role: 'tabpanel', id: 'painel-aba-conteudo', 'aria-labelledby': `painel-aba-${aba}` }, conteudo),
    );
  }

  // Avisa o leitor de tela da falha nova (assertive, P3: o foco fica onde esta;
  // a falha vai para Pede voce) e da camera instalada agora (polite); a linha
  // instalada agora ganha o fundo de acao por um ciclo de consulta.
  function compararEstados(m) {
    const agora = new Map(m.fila ? m.fila.posicoes.map((p) => [p.posicao, p]) : []);
    const novasAgora = new Set();
    if (estadosAntes) {
      for (const [n, p] of agora) {
        const antes = estadosAntes.get(n);
        if (antes === undefined || antes === p.estado) continue;
        // Falha nova ou saida da falha: a trava e o erro da decisao anterior nao valem mais.
        const l = linhas.get(n);
        if (l && (antes === 'falha' || p.estado === 'falha')) { l.trava = 0; l.decisao = null; }
        if (p.estado === 'falha') ctx.anunciar(t('painel.anuncio.falha', { n, etapa: p.falha.etapa }), true);
        if (p.estado === 'instalada') { ctx.anunciar(t('painel.anuncio.instalada', { n })); novasAgora.add(n); }
      }
    }
    estadosAntes = new Map([...agora].map(([n, p]) => [n, p.estado]));
    if (novasAgora.size) {
      novas = new Set([...novas, ...novasAgora]);
      setTimeout(() => { for (const n of novasAgora) novas.delete(n); mudouLocal(); }, CONSULTA_MS);
    }
  }

  function atualizar(m) {
    compararEstados(m);
    atualizarTopo(m);
    const nova = JSON.stringify([m.fila, m.espera, m.ignoradas, m.registro, m.simular, aba, versaoLocal, [...novas]]);
    if (nova === assinatura) return;
    assinatura = nova;
    // O redesenho troca os nos: o foco (e o cursor do campo) volta ao mesmo controle.
    const ativo = document.activeElement;
    const chave = ativo && raiz.contains(ativo) && ativo.dataset ? ativo.dataset.foco : null;
    const posicao = chave ? ativo.dataset.posicao : '';
    const cursor = chave && ativo.tagName === 'INPUT' ? [ativo.selectionStart, ativo.selectionEnd] : null;
    redesenhando = true;
    try {
      desenhar(m);
    } finally {
      redesenhando = false;
    }
    if (!chave) return;
    const foco = raiz.querySelector(`[data-foco="${chave}"]`);
    if (!foco) { if (posicao) focarDeVolta(posicao); return; }
    foco.focus({ preventScroll: true });
    if (cursor && foco.tagName === 'INPUT') foco.setSelectionRange(cursor[0], cursor[1]);
  }

  function abrirAba(nome) {
    trocarAba(nome === 'registro' ? 'registro' : 'fila', false);
  }

  atualizar(ctx.modelo());
  return { el: raiz, topo, faixa, atualizar, abrirAba };
}
