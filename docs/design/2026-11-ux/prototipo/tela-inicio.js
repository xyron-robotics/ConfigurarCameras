// Passo a passo e Conferir (direcao.md, secoes 2.2 e 3.1). Coluna de 720 px sob a logo,
// trilha com numero, palavra e icone, rodape fixo com Voltar e Avancar ou Comecar.
import { h } from './dom.js';
import { icone } from './icones.js';
import { t, traduzirServidor } from './textos.js';
import { PASSOS } from './constantes.js';
import { botao, ocupar, lugarAviso, chip, aviso, campo } from './componentes.js';
import { montarFormulario } from './formularios.js';
import { logo } from './marca.js';

function trilha(atual) {
  const iAtual = PASSOS.indexOf(atual);
  const itens = PASSOS.map((passo, i) => {
    const feito = i < iAtual;
    const corrente = i === iAtual;
    const conteudo = [
      h('span', { class: 'trilha-numero' }, feito ? icone('concluido') : String(i + 1)),
      h('span', null, t('secao.nome', { secao: passo })),
      feito ? h('span', { class: 'visualmente-oculto' }, `, ${t('inicio.feito')}`) : null,
      corrente ? h('span', { class: 'visualmente-oculto' }, `, ${t('inicio.atual')}`) : null,
    ];
    return h('li', { class: ['trilha-passo', feito ? 'trilha-feito' : null, corrente ? 'trilha-atual' : null], 'aria-current': corrente ? 'step' : null },
      feito ? h('a', { class: 'trilha-link', href: rotaDoPasso(passo) }, conteudo) : conteudo);
  });
  return h('nav', { class: 'inicio-trilha', 'aria-label': t('inicio.trilha') }, h('ol', { class: 'trilha-lista' }, itens));
}

function rotaDoPasso(passo) {
  return passo === 'conferir' ? '#/conferir' : `#/inicio/${passo}`;
}

function cabeca(modelo) {
  return h('header', { class: 'inicio-cabeca' }, [
    logo(),
    modelo.simular ? chip(t('chip.simulacao'), 'neutro', 'simulacao') : null,
  ]);
}

// Rodape fixo; estreito alinha os botoes com a coluna do formulario (passo a passo).
function rodape(esquerda, direita, estreito) {
  return h('footer', { class: 'rodape' }, h('div', { class: 'rodape-conteudo' }, h('div', { class: ['rodape-linha', estreito ? 'rodape-estreito' : null] }, [esquerda, h('div', { class: 'rodape-fim' }, direita)])));
}

export function telaPasso(ctx, passoPedido) {
  const passo = PASSOS.includes(passoPedido) && passoPedido !== 'conferir' ? passoPedido : PASSOS[0];
  const modelo = ctx.modelo();
  const i = PASSOS.indexOf(passo);
  const form = montarFormulario(passo, modelo, { comBroadcast: false });
  const resposta = lugarAviso();
  const titulo = h('h2', { class: 'inicio-secao-titulo' }, t(`${passo}.titulo`));

  async function avancar(ev) {
    ev.preventDefault();
    const r = form.coletar();
    if (!r.ok) return;
    const restaurar = ocupar(btnAvancar, t('sessao.salvando'));
    let res = { ok: true };
    if (passo === 'senha' && r.senha) res = await ctx.api.comando('/api/senha', { senha: r.senha });
    else if (r.parcial) res = await ctx.api.salvarSessao(r.parcial);
    restaurar();
    if (!res.ok) {
      resposta.mostrar('erro', res.semResposta ? t('erro.semResposta') : traduzirServidor(res.mensagem), res.mensagem);
      return;
    }
    await ctx.recarregarSessao();
    ctx.ir(rotaDoPasso(PASSOS[i + 1]));
  }

  const btnAvancar = botao(t('inicio.avancar'), null, { tipo: 'primario', submit: true });
  btnAvancar.setAttribute('form', 'form-passo');
  const voltar = i > 0 ? botao(t('inicio.voltar'), () => ctx.ir(rotaDoPasso(PASSOS[i - 1])), { tipo: 'secundario' }) : h('span');

  const el = h('div', { class: 'inicio' }, [
    cabeca(modelo),
    h('main', { class: 'inicio-corpo', id: 'conteudo' }, [
      h('h1', { class: 'inicio-titulo' }, t('inicio.titulo')),
      trilha(passo),
      h('div', { class: 'inicio-secao' }, [titulo, h('p', { class: 'lead' }, t(`${passo}.lead`))]),
      h('form', { id: 'form-passo', class: 'form', novalidate: true, onsubmit: avancar }, form.el),
      resposta.el,
    ]),
    rodape(voltar, btnAvancar, true),
  ]);
  return { el, foco: titulo };
}

function valorConferir(secao, modelo) {
  const s = modelo.sessao;
  if (secao === 'placa') return s.Placa && s.Placa.nome ? t('conferir.placa', { nome: s.Placa.nome }) : '';
  if (secao === 'rede') return s.Rede && s.Rede.gateway ? t('conferir.rede', s.Rede) : '';
  if (secao === 'camera') {
    const c = s.Camera;
    if (!c || !c.principal) return '';
    return t('conferir.camera', { codec: c.principal.codec, p: t('conferir.stream', c.principal), s: t('conferir.stream', c.secundario), email: c.email });
  }
  if (secao === 'fila') return s.Fila && s.Fila.inicio ? t('conferir.fila', s.Fila) : '';
  return '';
}

export function telaConferir(ctx) {
  const modelo = ctx.modelo();
  const resposta = lugarAviso();
  const titulo = h('h1', { class: 'inicio-titulo' }, t('conferir.titulo'));

  function linhaSenha() {
    if (modelo.simular) return [h('span', { class: 'apoio' }, t('senha.simulacao')), h('span')];
    if (modelo.senhaDefinida) return [h('span', null, t('senha.definida')), h('a', { class: 'botao botao-discreto', href: '#/inicio/senha' }, t('secao.alterar', { secao: 'senha' }))];
    const c = campo({ rotulo: t('senha.campo'), tipo: 'password', autocomplete: 'new-password', ajuda: t('senha.ajuda') });
    const salvar = botao(t('senha.salvar'), async () => {
      const r = await ctx.api.comando('/api/senha', { senha: c.valor() });
      if (r.ok) ctx.recarregar(); else c.mostrarErro(traduzirServidor(r.mensagem));
    }, { tipo: 'secundario' });
    return [h('div', { class: 'ferramenta-sondar' }, [c.el, salvar]), h('span')];
  }

  function linhaFila() {
    const valor = valorConferir('fila', modelo);
    const partes = [valor ? h('span', null, valor) : falta()];
    const cf = modelo.conflito;
    if (cf && cf.instaladas) {
      const f = modelo.sessao.Fila;
      partes.push(aviso('atencao', cf.todas ? t('fila.conflito.todas', { n: cf.total, inicio: f.inicio, fim: f.fim }) : t('fila.conflito.parte', { n: cf.instaladas, total: cf.total })));
      if (cf.todas && cf.seguinte) {
        partes.push(botao(t('fila.usarSeguinte', cf.seguinte), async () => {
          const r = await ctx.api.salvarSessao({ Fila: { ...f, inicio: cf.seguinte.inicio, fim: cf.seguinte.fim } });
          if (!r.ok) { resposta.mostrar('erro', traduzirServidor(r.mensagem), r.mensagem); return; }
          await ctx.recarregarSessao();
          ctx.ir('#/conferir');
        }, { tipo: 'secundario' }));
      }
    }
    return partes;
  }

  const falta = () => h('span', { class: 'conferir-falta' }, [icone('atencao'), h('span', null, t('conferir.vazio'))]);
  const alterar = (secao) => h('a', { class: 'botao botao-discreto', href: `#/inicio/${secao}` }, t('secao.alterar', { secao }));

  const [senhaValor, senhaAcao] = linhaSenha();
  const linhas = [
    h('div', { class: 'conferir-linha' }, [h('div', { class: 'conferir-rotulo' }, t('secao.nome', { secao: 'senha' })), h('div', { class: 'conferir-valor' }, senhaValor), h('div', { class: 'conferir-acao' }, senhaAcao)]),
    ...['placa', 'rede', 'camera'].map((secao) => {
      const v = valorConferir(secao, modelo);
      return h('div', { class: 'conferir-linha' }, [
        h('div', { class: 'conferir-rotulo' }, t('secao.nome', { secao })),
        h('div', { class: 'conferir-valor' }, v ? h('span', null, v) : falta()),
        h('div', { class: 'conferir-acao' }, alterar(secao)),
      ]);
    }),
    h('div', { class: 'conferir-linha' }, [h('div', { class: 'conferir-rotulo' }, t('secao.nome', { secao: 'fila' })), h('div', { class: 'conferir-valor' }, linhaFila()), h('div', { class: 'conferir-acao' }, alterar('fila'))]),
  ];

  const comecar = botao(t('inicio.comecar'), async () => {
    const restaurar = ocupar(comecar, t('inicio.comecar'));
    const r = await ctx.api.comando('/api/sessao/concluir', { montarFila: true });
    restaurar();
    if (!r.ok) { resposta.mostrar('erro', r.semResposta ? t('erro.semResposta') : traduzirServidor(r.mensagem), r.mensagem); return; }
    await ctx.recarregar();
    ctx.ir('#/painel');
  }, { tipo: 'primario' });
  const nota = h('span', { class: 'apoio' }, t('inicio.comecar.nota'));
  const voltar = modelo.sessaoCompleta ? h('span') : botao(t('inicio.voltar'), () => ctx.ir('#/inicio/fila'), { tipo: 'secundario' });

  const el = h('div', { class: 'inicio' }, [
    cabeca(modelo),
    h('main', { class: ['inicio-corpo', 'inicio-conferir'], id: 'conteudo' }, [
      h('div', { class: 'inicio-secao' }, [titulo, h('p', { class: 'lead' }, t('conferir.lead'))]),
      h('div', { class: 'conferir-lista' }, linhas),
      resposta.el,
    ]),
    rodape(voltar, [nota, comecar]),
  ]);
  return { el, foco: titulo };
}
