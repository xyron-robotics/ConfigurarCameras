// Painel (direcao.md, secoes 3.2, 3.3 e 3.6): cabecalho da fila com a fita, "Pede voce",
// tabela Fila agora / Registro e o grupo "Na espera do portao". Redesenha so quando o
// modelo muda, e devolve o foco ao mesmo controle (o operador pode estar digitando porta).
import { h, focar } from './dom.js';
import { icone } from './icones.js';
import { t, traduzirServidor, valorRecusado } from './textos.js';
import { FITA_MAX_NUMEROS, FITA_PASSO_NUMERO, TRAVA_DECISAO_MS } from './constantes.js';
import { botao, ocupar, chip, lugarAviso, detalhe, confirmar, lateral, selo, barraEtapas } from './componentes.js';
import { montarFormulario } from './formularios.js';
import { mac as formatarMac } from './formato.js';

const LEGENDA = ['instalada', 'falha', 'curso', 'proxima', 'aguardando', 'pulada'];

function textoEstado(p, totalEtapas) {
  if (p.estado === 'curso') return t('estado.curso', { n: p.etapaN, total: totalEtapas, etapa: p.etapa });
  if (p.estado === 'falha') return t('estado.falha', { etapa: p.falha.etapa });
  return t(`estado.${p.estado}`);
}

function textoLegenda(estado, c) {
  if (estado === 'instalada') return t('fita.instaladas', { n: c.instalada });
  if (estado === 'falha') return t('fita.falha', { n: c.falha });
  if (estado === 'curso') return t('fita.curso', { n: c.curso });
  if (estado === 'proxima') return t('fita.proxima');
  if (estado === 'aguardando') return t('fita.aguardando', { n: c.aguardando });
  return t('fita.puladas', { n: c.pulada });
}

export function telaPainel(ctx, parte) {
  const raiz = h('main', { class: 'conteudo', id: 'conteudo' });
  const respostaFila = lugarAviso();
  const vistos = new Map();
  let aba = parte === 'registro' ? 'registro' : 'fila';
  let assinatura = '';
  let falhasAntes = null;

  function abrirFila(modelo) {
    const form = montarFormulario('fila', modelo);
    const resposta = lugarAviso();
    lateral({
      titulo: t('lateral.fila.titulo'),
      texto: t('lateral.fila.texto'),
      conteudo: (fechar) => {
        const salvar = botao(t('fila.montar'), async () => {
          const r = form.coletar();
          if (!r.ok) return;
          const m = ctx.modelo();
          if (m.fila && m.fila.contagem.curso > 0) {
            const sim = await confirmar({ titulo: t('dialogo.trocarFila.titulo'), texto: t('dialogo.trocarFila.texto'), confirmar: t('dialogo.trocarFila.confirmar'), perigo: true });
            if (!sim) return;
          }
          const restaurar = ocupar(salvar, t('sessao.salvando'));
          const res = await ctx.api.comando('/api/fila', r.parcial.Fila);
          restaurar();
          if (!res.ok) { resposta.mostrar('erro', traduzirServidor(res.mensagem), res.mensagem); return; }
          fechar();
          const f = r.parcial.Fila;
          await ctx.recarregarSessao();
          await ctx.recarregar();
          const n = ctx.modelo().fila ? ctx.modelo().fila.total : 0;
          respostaFila.mostrar('sucesso', t('fila.montada', { n, inicio: f.inicio, fim: f.fim }));
        }, { tipo: 'primario' });
        return [form.el, resposta.el, h('div', { class: 'lateral-acoes' }, [botao(t('lateral.cancelar'), () => fechar(), { tipo: 'secundario' }), salvar])];
      },
    });
  }

  function abrirEncoder(modelo, item, mac) {
    const form = montarFormulario('camera', modelo, { soEncoder: true });
    const resposta = lugarAviso();
    lateral({
      titulo: t('lateral.encoder.titulo', { n: item.posicao }),
      texto: t('lateral.encoder.texto'),
      conteudo: (fechar) => {
        const salvar = botao(t('lateral.encoder.salvar'), async () => {
          const r = form.coletar();
          if (!r.ok) return;
          const restaurar = ocupar(salvar, t('sessao.salvando'));
          const s = await ctx.api.salvarSessao(r.parcial);
          const d = s.ok ? await ctx.api.comando('/api/decisao', { mac, acao: 'tentar' }) : s;
          restaurar();
          if (!d.ok) { resposta.mostrar('erro', d.semResposta ? t('erro.semResposta') : traduzirServidor(d.mensagem), d.mensagem); return; }
          fechar();
          await ctx.recarregarSessao();
          await ctx.recarregar();
        }, { tipo: 'primario' });
        return [form.el, resposta.el, h('div', { class: 'lateral-acoes' }, [botao(t('lateral.cancelar'), () => fechar(), { tipo: 'secundario' }), salvar])];
      },
    });
    form.focarBitrate();
  }

  async function decidir(btn, mac, acao, resposta) {
    const restaurar = ocupar(btn, acao === 'tentar' ? t('pede.tentando') : btn.textContent);
    const r = await ctx.api.comando('/api/decisao', { mac, acao });
    restaurar();
    if (!r.ok) { resposta.mostrar('erro', r.semResposta ? t('erro.semResposta') : traduzirServidor(r.mensagem), r.mensagem); return; }
    ctx.recarregar();
  }

  function cabecalho(m) {
    const f = m.fila;
    const fechada = f.concluida || f.encerrada;
    const vigia = m.vigia.ligado ? chip(t('painel.vigia.ligado'), 'agora', 'agora') : chip(t('painel.vigia.desligado'), 'neutro');
    const alternar = botao(m.vigia.ligado ? t('painel.vigia.desligar') : t('painel.vigia.ligar'), async () => {
      const r = await ctx.api.comando('/api/vigia', { ligado: !m.vigia.ligado, broadcast: m.vigia.broadcast });
      if (!r.ok) respostaFila.mostrar('erro', traduzirServidor(r.mensagem), r.mensagem); else respostaFila.limpar();
      ctx.recarregar();
    }, { tipo: m.vigia.ligado ? 'secundario' : 'primario', dados: { foco: 'vigia' } });
    const encerrar = botao(t('painel.fila.encerrar'), async () => {
      const sim = await confirmar({ titulo: t('dialogo.encerrarFila.titulo'), texto: t('dialogo.encerrarFila.texto', { sem: f.semCamera }), confirmar: t('dialogo.encerrarFila.confirmar'), perigo: true });
      if (!sim) return;
      const r = await ctx.api.comando('/api/decisao', { acao: 'encerrar' });
      if (!r.ok) respostaFila.mostrar('erro', traduzirServidor(r.mensagem), r.mensagem);
      ctx.recarregar();
    }, { tipo: 'discreto', dados: { foco: 'encerrar-fila' } });
    return h('div', { class: 'fila-cabeca' }, [
      h('div', { class: 'fila-nome' }, [
        h('h1', null, t('painel.fila.titulo', f)),
        h('div', { class: 'fila-faixa' }, [
          h('span', { class: 'mono apoio' }, t('painel.fila.faixa', f)),
          m.vigia.broadcast ? chip(t('painel.qualquerFaixa'), 'atencao', 'atencao') : null,
        ]),
      ]),
      h('div', { class: 'fila-acoes' }, [
        fechada ? null : vigia,
        fechada ? null : alternar,
        botao(t('fila.montarOutra'), () => abrirFila(ctx.modelo()), { tipo: fechada ? 'primario' : 'secundario', dados: { foco: 'montar' } }),
        fechada ? null : encerrar,
      ]),
    ]);
  }

  function irParaLinha(posicao) {
    if (aba !== 'fila') { aba = 'fila'; assinatura = ''; atualizar(ctx.modelo()); }
    const linha = raiz.querySelector(`[data-linha="${posicao}"]`);
    if (!linha) return;
    for (const l of raiz.querySelectorAll('.linha-alvo')) l.classList.remove('linha-alvo');
    linha.classList.add('linha-alvo');
    linha.scrollIntoView({ block: 'nearest' });
  }

  function fita(m) {
    const f = m.fila;
    const comNumeros = f.total <= FITA_MAX_NUMEROS;
    const casas = f.posicoes.map((p) => {
      const casa = h('span', { class: ['fita-casa', `fita-${p.estado}`], onclick: () => irParaLinha(p.posicao) }, p.estado === 'falha' ? '!' : null);
      if (p.estado === 'curso') casa.style.setProperty('--fracao', String((p.etapaN - 1) / f.totalEtapas));
      return casa;
    });
    const numeros = f.posicoes.map((p) => h('span', { class: 'fita-numero' }, comNumeros || p.posicao === 1 || p.posicao % FITA_PASSO_NUMERO === 0 ? String(p.posicao) : ''));
    const legenda = LEGENDA.filter((e) => f.contagem[e] > 0 || e === 'instalada').map((e) => h('span', { class: 'legenda-item' }, [
      h('span', { class: ['legenda-amostra', `legenda-${e}`] }), h('span', null, textoLegenda(e, f.contagem)),
    ]));
    return h('div', { class: 'fita-bloco' }, [
      h('p', { class: 'visualmente-oculto' }, t('fita.resumo', { c: f.contagem })),
      h('div', { class: 'fita', 'aria-hidden': 'true' }, casas),
      h('div', { class: 'fita-numeros', 'aria-hidden': 'true' }, numeros),
      h('div', { class: 'fita-legenda', 'aria-hidden': 'true' }, legenda),
    ]);
  }

  function estadoDaFila(m) {
    const f = m.fila;
    if (f.concluida) {
      return h('section', { class: ['bloco', 'bloco-sucesso'] }, [
        h('h2', { class: 'bloco-titulo' }, [icone('concluido', 'm'), h('span', null, t('painel.concluida', { n: f.contagem.instalada }))]),
        h('p', { class: 'apoio' }, t('painel.concluida.texto')),
      ]);
    }
    if (f.encerrada) {
      return h('section', { class: 'bloco' }, [
        h('h2', { class: 'bloco-titulo' }, t('painel.encerrada', { inst: f.contagem.instalada, sem: f.semCamera })),
        h('p', { class: 'apoio' }, t('painel.encerrada.texto')),
      ]);
    }
    const parada = f.contagem.curso === 0 && f.contagem.falha === 0;
    if (!m.vigia.ligado && parada) {
      return h('section', { class: 'bloco' }, [
        h('h2', { class: 'bloco-titulo' }, t('painel.vigia.desligado')),
        h('p', null, t('painel.vazio.desligado')),
        h('p', { class: 'apoio' }, t('painel.vazio.sequencial')),
      ]);
    }
    if (m.vigia.ligado && parada && f.contagem.instalada === 0) {
      return h('section', { class: 'bloco' }, [
        h('h2', { class: 'bloco-titulo' }, [icone('espera', 'm'), h('span', null, t('painel.vazio.esperando'))]),
        h('p', { class: 'apoio' }, t('painel.vazio.esperando.texto')),
      ]);
    }
    return null;
  }

  function pedeVoce(m) {
    if (!m.pedeVoce.length) return null;
    const agora = Date.now();
    const itens = m.pedeVoce.map((item) => {
      const pos = m.fila.posicoes.find((p) => p.posicao === item.posicao);
      const mac = pos.camera.macBruto;
      if (!vistos.has(mac)) vistos.set(mac, agora);
      const travado = agora - vistos.get(mac) < TRAVA_DECISAO_MS;
      const resposta = lugarAviso();
      const explica = item.tipo === 'recusa' ? t('pede.recusa', { valor: valorRecusado(item.erroCru) }) : item.tipo === 'senha' ? t('pede.senha') : t('pede.outro');
      const motivoId = `motivo-${item.posicao}`;
      const tentar = botao(t('pede.tentar'), (ev) => decidir(ev.currentTarget, mac, 'tentar', resposta), {
        tipo: item.etapa === 'encoder' ? 'secundario' : 'primario', desabilitado: item.bloqueiaTentar || travado,
        motivoId: item.bloqueiaTentar ? motivoId : undefined, dados: { foco: `tentar-${mac}`, trava: item.bloqueiaTentar ? '' : 'sim' },
      });
      const encoder = item.etapa === 'encoder'
        ? botao(t('pede.mudarEncoder'), () => abrirEncoder(ctx.modelo(), item, mac), { tipo: 'primario', desabilitado: travado, dados: { foco: `encoder-${mac}`, trava: 'sim' } })
        : null;
      const pular = botao(t('pede.pular'), async (ev) => {
        const btn = ev.currentTarget;
        const sim = await confirmar({ titulo: t('pede.pular.titulo', { n: item.posicao }), texto: t('pede.pular.texto', { ip: item.ip }), confirmar: t('pede.pular.confirmar', { n: item.posicao }), perigo: true });
        if (sim) decidir(btn, mac, 'pular', resposta);
      }, { tipo: 'discreto', desabilitado: travado, dados: { foco: `pular-${mac}`, trava: 'sim' } });
      return h('div', { class: 'pede-item' }, [
        h('h3', { class: 'pede-titulo' }, [icone('falha', 'm'), h('span', null, t('pede.falhou', { n: item.posicao, ip: item.ip, etapa: item.etapa }))]),
        h('p', null, explica),
        h('div', { class: 'pede-acoes' }, [encoder, tentar, pular, item.erroCru ? detalhe(item.erroCru) : null]),
        item.bloqueiaTentar ? h('p', { class: 'motivo', id: motivoId }, [icone('informacao'), h('span', null, t('pede.senha.motivo'))]) : null,
        resposta.el,
      ]);
    });
    const espera = Math.max(0, ...[...vistos.values()].map((v) => v + TRAVA_DECISAO_MS - agora));
    if (espera > 0) {
      setTimeout(() => { for (const b of raiz.querySelectorAll('[data-trava="sim"]')) b.disabled = false; }, espera);
    }
    return h('section', { class: 'pede', id: 'pede-voce', 'aria-labelledby': 'pede-titulo' }, [
      h('h2', { id: 'pede-titulo' }, t('pede.titulo', { n: m.pedeVoce.length })),
      itens,
    ]);
  }

  // Nome do campo vem do cabecalho da coluna e da celula Pos., os dois visiveis.
  function entradaTabela(p, campoNome) {
    const cam = p.camera;
    const entrada = h('input', {
      class: 'entrada-tabela', type: 'text', inputmode: 'numeric', value: cam[campoNome] || '',
      'aria-labelledby': `col-${campoNome} pos-${p.posicao}`, dados: { foco: `${campoNome}-${p.posicao}` },
      onchange: async () => {
        const linha = entrada.closest('tr');
        const porta = linha.querySelector('[data-campo="porta"]').value.trim();
        const canal = linha.querySelector('[data-campo="canal"]').value.trim();
        const r = await ctx.api.comando('/api/camera', { mac: cam.macBruto, porta, canal });
        if (!r.ok) respostaFila.mostrar('erro', traduzirServidor(r.mensagem), r.mensagem);
        ctx.recarregar();
      },
    });
    entrada.dataset.campo = campoNome;
    return entrada;
  }

  function tabelaFila(m) {
    const f = m.fila;
    const cab = ['pos', 'estado', 'ip', 'modelo', 'serial', 'mac', 'porta', 'canal'];
    const linhas = f.posicoes.map((p) => {
      const c = p.camera;
      const comCampos = c && (p.estado === 'instalada' || p.estado === 'curso' || p.estado === 'falha');
      return h('tr', { class: p.estado === 'falha' ? 'linha-falha' : null, dados: { linha: p.posicao } }, [
        h('td', { class: 'coluna-pos', id: `pos-${p.posicao}` }, String(p.posicao)),
        h('td', { class: 'coluna-estado' }, h('span', { class: 'selo-linha' }, [selo(p.estado, textoEstado(p, f.totalEtapas)), p.estado === 'curso' ? [' ', barraEtapas(p.etapaN, f.totalEtapas)] : null])),
        h('td', { class: 'mono' }, p.ip),
        h('td', null, c ? c.modelo : ''),
        h('td', { class: 'mono' }, c ? c.serial : ''),
        h('td', { class: 'mono' }, c ? c.mac : ''),
        h('td', null, comCampos ? entradaTabela(p, 'porta') : ''),
        h('td', null, comCampos ? entradaTabela(p, 'canal') : ''),
      ]);
    });
    return h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
      h('thead', null, h('tr', null, cab.map((k) => h('th', { scope: 'col', id: `col-${k}` }, t(`tabela.${k}`))))),
      h('tbody', null, linhas),
    ]));
  }

  function tabelaRegistro(m) {
    if (m.registroErro) {
      return h('div', { class: 'tabela-vazio' }, [h('p', null, t('registro.erro')), botao(t('registro.lerDeNovo'), () => ctx.recarregarRegistro(), { tipo: 'secundario' })]);
    }
    if (!m.registro) return h('div', { class: 'tabela-vazio' }, h('p', null, t('registro.lendo')));
    if (!m.registro.length) return h('div', { class: 'tabela-vazio' }, h('p', null, t('registro.vazio')));
    const cab = ['data', 'ip', 'modelo', 'serial', 'mac', 'status', 'local', 'porta', 'canal'];
    const estadoStatus = { Instalada: 'instalada', Falhou: 'falha', 'Em andamento': 'curso', Resetada: 'pulada' };
    const linhas = m.registro.map((r) => h('tr', null, [
      h('td', { class: 'numeros' }, r.Data),
      h('td', { class: 'mono' }, r.Ip),
      h('td', null, r.Modelo),
      h('td', { class: 'mono' }, r.Serial),
      h('td', { class: 'mono' }, formatarMac(r.Mac)),
      h('td', null, selo(estadoStatus[r.Status] || 'aguardando', t(`registro.status.${r.Status}`))),
      h('td', null, r.Local),
      h('td', { class: 'numeros' }, r.Porta),
      h('td', { class: 'numeros' }, r.Canal),
    ]));
    return h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
      h('thead', null, h('tr', null, cab.map((k) => h('th', { scope: 'col' }, t(`tabela.${k}`))))),
      h('tbody', null, linhas),
    ]));
  }

  function vista(m) {
    const ids = { fila: 'aba-fila', registro: 'aba-registro' };
    const botoes = ['fila', 'registro'].map((nome) => h('button', {
      type: 'button', role: 'tab', class: 'aba', id: ids[nome], 'aria-selected': String(aba === nome), 'aria-controls': 'painel-vista',
      tabindex: aba === nome ? '0' : '-1', dados: { foco: `aba-${nome}` },
      onclick: () => trocarAba(nome),
      onkeydown: (ev) => {
        if (ev.key === 'ArrowRight' || ev.key === 'ArrowLeft') { ev.preventDefault(); trocarAba(nome === 'fila' ? 'registro' : 'fila', true); }
      },
    }, t(`painel.aba.${nome}`)));
    return h('section', { class: 'vista' }, [
      h('div', { class: 'abas', role: 'tablist', 'aria-label': t('painel.abas') }, botoes),
      h('div', { role: 'tabpanel', id: 'painel-vista', 'aria-labelledby': ids[aba] }, aba === 'fila' ? tabelaFila(m) : tabelaRegistro(m)),
    ]);
  }

  function trocarAba(nome, focarAba) {
    aba = nome;
    history.replaceState(null, '', nome === 'registro' ? '#/painel/registro' : '#/painel');
    if (nome === 'registro') ctx.recarregarRegistro();
    assinatura = '';
    atualizar(ctx.modelo());
    if (focarAba) focar(raiz.querySelector(`[data-foco="aba-${nome}"]`));
  }

  function espera(m) {
    if (!m.espera.length) return null;
    return h('section', { class: 'espera', 'aria-labelledby': 'espera-titulo' }, [
      h('h2', { id: 'espera-titulo' }, t('tabela.espera', { n: m.espera.length })),
      h('p', { class: 'apoio' }, t('tabela.espera.explica')),
      h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
        h('thead', null, h('tr', null, ['estado', 'modelo', 'serial', 'mac'].map((k) => h('th', { scope: 'col' }, t(`tabela.${k}`))))),
        h('tbody', null, m.espera.map((c) => h('tr', null, [
          h('td', { class: 'coluna-estado' }, selo('espera', t('estado.espera'))),
          h('td', null, c.modelo), h('td', { class: 'mono' }, c.serial), h('td', { class: 'mono' }, c.mac),
        ]))),
      ])),
    ]);
  }

  function semFila() {
    return [
      h('h1', null, t('painel.titulo')),
      h('section', { class: 'bloco' }, [
        h('h2', { class: 'bloco-titulo' }, t('painel.vazio.semFila')),
        h('p', null, t('painel.vazio.semFila.texto')),
        botao(t('fila.montar'), () => abrirFila(ctx.modelo()), { tipo: 'primario', dados: { foco: 'montar' } }),
      ]),
    ];
  }

  function desenhar(m) {
    if (!m.fila) { raiz.replaceChildren(...semFila(), respostaFila.el); return; }
    const atalho = m.pedeVoce.length
      ? h('a', { class: 'botao botao-discreto', href: '#/painel', dados: { foco: 'atalho' }, onclick: (ev) => { ev.preventDefault(); focar(raiz.querySelector('.pede h2')); } }, t('nav.irPedeVoce'))
      : null;
    raiz.replaceChildren(
      h('section', { class: 'painel-topo', 'aria-label': t('painel.titulo') }, [cabecalho(m), fita(m), atalho, respostaFila.el]),
      estadoDaFila(m) || '',
      pedeVoce(m) || '',
      vista(m),
      espera(m) || '',
    );
  }

  function anunciarFalhas(m) {
    const agora = new Set(m.pedeVoce.map((p) => p.posicao));
    if (falhasAntes) for (const n of agora) if (!falhasAntes.has(n)) ctx.anunciar(t('app.anuncio.falha', { n }));
    falhasAntes = agora;
  }

  function atualizar(m) {
    anunciarFalhas(m);
    const nova = JSON.stringify([m.fila, m.pedeVoce, m.espera, m.vigia, m.registro, m.registroErro, aba]);
    if (nova === assinatura) return;
    assinatura = nova;
    const ativo = document.activeElement;
    const chave = ativo && raiz.contains(ativo) ? ativo.dataset.foco : null;
    const valor = chave && ativo.tagName === 'INPUT' ? ativo.value : null;
    desenhar(m);
    if (chave) {
      const alvo = raiz.querySelector(`[data-foco="${chave}"]`);
      if (alvo) { if (valor !== null) alvo.value = valor; alvo.focus({ preventScroll: true }); }
    }
  }

  atualizar(ctx.modelo());
  return { el: raiz, foco: () => raiz.querySelector('h1'), atualizar };
}
