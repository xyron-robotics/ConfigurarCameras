// Passo a passo e Conferir (direcao.md, secoes 2.2 e 3.1): seis passos numa
// coluna de leitura sob a logo, trilha com numero, palavra e icone, e rodape
// fixo com Voltar e Avancar ou Comecar. A tela recebe o modelo (estado.js) e o
// contexto do app.js (decisao N1): nao busca nem guarda estado. Os formularios
// e o salvar vem do formularios.js; aqui so a navegacao e o Conferir.
import { h } from './dom.js';
import { icone } from './icones.js';
import { t, traduzirServidor } from './textos.js';
import { logo } from './marca.js';
import { botao, ocupar, lugarAviso, chip, aviso } from './componentes.js';
import { montarFormulario, pcNaFabrica, mostrarFalha, salvarSenha, salvarParcial } from './formularios.js';
import { rotaDoPasso, ROTA_INICIAL } from './rotas.js';
import { numero, resolucao, mac } from './formato.js';
import {
  PASSOS, ETAPA_DO_PASSO, NBSP, ESPERA_COMECAR_MS, RE_DATA_SERVIDOR, REVOGAR_BLOB_MS,
} from './constantes.js';

// ctx (do app.js): { api, modelo(), ir(hash), corrigir(hash), confirmar(o),
// esperar(cond, ms), recarregarSessao(), lerPlacas(), redesenhar(foco) }.
// As duas telas devolvem { el, foco, acao, sujo(), ocupada() }: o app.js nao
// redesenha por cima de uma tela com campo mexido ou salvando.

// ------------------------------------------------------------------ pecas comuns
function cabeca(modelo) {
  return h('header', { class: 'inicio-cabeca' }, [
    logo(),
    modelo.simular ? chip(t('chip.simulacao'), 'neutro', 'simulacao') : null,
  ]);
}

// Trilha (UI-10): numero, palavra e, nos feitos, o icone. Abre ate o passo mais
// adiante que o modelo deixa; os de depois sao so texto.
function trilha(modelo, atual) {
  const iAtual = PASSOS.indexOf(atual);
  const iMax = PASSOS.indexOf(modelo.passoMax);
  const itens = PASSOS.map((passo, i) => {
    const corrente = i === iAtual;
    const feito = !corrente && i < iMax;
    const conteudo = [
      h('span', { class: 'trilha-numero' }, feito ? icone('concluido') : String(i + 1)),
      h('span', null, t('secao.nome', { secao: passo })),
      feito ? h('span', { class: 'so-leitor' }, t('inicio.feito')) : null,
    ];
    const aberto = !corrente && i <= iMax;
    return h('li', {
      class: ['trilha-passo', feito ? 'trilha-feito' : null, corrente ? 'trilha-atual' : null],
      'aria-current': corrente ? 'step' : null,
    }, aberto ? h('a', { class: 'trilha-link', href: rotaDoPasso(passo) }, conteudo) : conteudo);
  });
  return h('nav', { class: 'inicio-trilha', 'aria-label': t('inicio.trilha') }, h('ol', { class: 'trilha-lista' }, itens));
}

// Rodape fixo (UX-20); estreito alinha os botoes com a coluna do formulario.
function rodape(esquerda, direita, estreito) {
  return h('footer', { class: 'rodape' }, h('div', { class: 'rodape-conteudo' },
    h('div', { class: ['rodape-linha', estreito ? 'rodape-estreito' : null] }, [esquerda || h('span'), h('div', { class: 'rodape-fim' }, direita)])));
}

function corpo(modelo, atual, classe, filhos) {
  return h('div', { class: 'inicio-tela' }, [
    cabeca(modelo),
    h('div', { class: ['inicio-corpo', classe] }, [
      h('h1', { class: 'inicio-titulo' }, t('inicio.titulo')),
      trilha(modelo, atual),
      filhos,
    ]),
  ]);
}

// ------------------------------------------------------------------ registro de antes (G1)
// Passo a passo novo com registro nao vazio: o passo da placa (onde o passo a
// passo abre, inclusive pelo "Refazer") mostra quantas cameras ha e a data da
// ultima, com Manter, Exportar e zerar e Zerar. Nada sai sozinho: Avancar sem
// escolher mantem tudo. A escolha e o resultado dela valem ate o Comecar desta
// abertura (a tela e refeita a cada redesenho; a escolha nao).
const PASSO_DO_REGISTRO = 'placa';
const ROTA_RELATORIO = '/api/relatorio.csv';
const ROTA_EXCLUIR = '/api/registro/excluir';
// O POST do relatorio nomeia o arquivo como selecao; aqui ele e o registro inteiro.
const SUFIXO_SELECAO = '-selecao';
const ID_ESCOLHA = 'registro-escolha';
const escolhaRegistro = { feita: false, aviso: null };

// "dd/mm/aaaa" da camera mais recente; '' sem data legivel.
function ultimaData(lista) {
  const datas = lista.map((r) => RE_DATA_SERVIDOR.exec(String(r.Data || ''))).filter(Boolean);
  if (!datas.length) return '';
  const [, ano, mes, dia] = datas.reduce((a, b) => (b[0] > a[0] ? b : a));
  return [dia, mes, ano].join('/');
}

function baixarArquivo(blob, nome) {
  const url = URL.createObjectURL(blob);
  const a = h('a', { href: url, download: nome || '', hidden: true });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), REVOGAR_BLOB_MS);
}

// o: { marcarOcupada(bool): a tela do passo nao e redesenhada no meio da acao;
// depois(feita, id): redesenha so o bloco (o formulario do passo nao perde o
// que o operador mexeu) e leva o foco ao Avancar ou de volta ao botao. }
function blocoRegistro(ctx, modelo, o) {
  const lista = (modelo.registro && !modelo.registro.erro && modelo.registro.lista) || [];
  const aviso0 = escolhaRegistro.aviso ? aviso(escolhaRegistro.aviso.tipo, escolhaRegistro.aviso.texto, escolhaRegistro.aviso.cru) : null;
  if (escolhaRegistro.feita || !lista.length) return aviso0;
  const n = lista.length;
  const macs = lista.map((r) => r.Mac).filter(Boolean);
  const tituloId = ID_ESCOLHA + '-titulo';

  function concluir(tipo, texto, cru, feita) {
    escolhaRegistro.feita = feita;
    escolhaRegistro.aviso = tipo ? { tipo, texto, cru: cru || '' } : null;
    ctx.anunciar(texto);
  }

  function manter() {
    concluir(null, t('inicio.registro.mantido'), '', true);
    o.depois(true, '');
  }

  async function zerar(exportar, btn) {
    const sim = await ctx.confirmar({
      titulo: t('dialogo.zerar.titulo', { exportar }),
      texto: t('dialogo.zerar.texto', { n, exportar }),
      confirmar: t('dialogo.zerar.confirmar', { exportar }),
      perigo: true,
    });
    if (!sim) return;
    o.marcarOcupada(true);
    const restaurar = ocupar(btn, exportar ? t('inicio.registro.exportando') : t('inicio.registro.zerando'));
    let feita = false;
    try {
      // So zera depois do download iniciado: sem o arquivo, nada sai do registro.
      if (exportar) {
        const r = await ctx.api.baixar(ROTA_RELATORIO, { macs });
        if (!r.ok) {
          const e = traduzirServidor(r);
          concluir('erro', t('inicio.registro.exportarFalhou') + ' ' + e.texto, e.cru, false);
          return;
        }
        baixarArquivo(r.blob, r.nome.replace(SUFIXO_SELECAO, ''));
        btn.querySelector('.botao-rotulo').textContent = t('inicio.registro.zerando');
      }
      const res = await ctx.api.comando(ROTA_EXCLUIR, { macs });
      if (!res.ok) {
        const e = traduzirServidor(res);
        concluir('erro', t('inicio.registro.zerarFalhou', { exportado: exportar }) + ' ' + e.texto, e.cru, false);
        return;
      }
      const saiu = Number(res.dados && res.dados.removidas) || 0;
      concluir('sucesso', t('inicio.registro.zerado', { n: saiu, exportado: exportar }), '', true);
      feita = true;
      await ctx.lerRegistro();
    } finally {
      restaurar();
      o.marcarOcupada(false);
      // Zerado: o bloco sai e o foco vai ao Avancar. Falha: o bloco fica, e o
      // foco volta ao botao que falhou (mesmo id).
      o.depois(feita, btn.id);
    }
  }

  const exportarZerar = botao(t('inicio.registro.exportarZerar'), () => zerar(true, exportarZerar), { tipo: 'secundario' });
  exportarZerar.id = ID_ESCOLHA + '-exportar';
  const zerarSo = botao(t('inicio.registro.zerar'), () => zerar(false, zerarSo), { tipo: 'secundario' });
  zerarSo.id = ID_ESCOLHA + '-zerar';
  const manterBtn = botao(t('inicio.registro.manter'), manter, { tipo: 'secundario' });
  manterBtn.id = ID_ESCOLHA + '-manter';
  return h('section', { class: ['bloco', 'registro-escolha'], 'aria-labelledby': tituloId }, [
    h('h3', { class: 'bloco-titulo', id: tituloId }, t('inicio.registro.titulo', { n, ultima: ultimaData(lista) })),
    h('p', null, t('inicio.registro.texto')),
    h('div', { class: 'registro-escolha-acoes' }, [manterBtn, exportarZerar, zerarSo]),
    aviso0,
  ]);
}

// ------------------------------------------------------------------ passo
export function telaPasso(ctx, passo) {
  const modelo = ctx.modelo();
  const i = PASSOS.indexOf(passo);
  let sujo = false;
  let ocupada = false;
  const lerPlacas = () => { sujo = false; ctx.lerPlacas(); };
  const form = montarFormulario(passo, modelo, { lerPlacas });
  const resposta = lugarAviso();
  const titulo = h('h2', { class: 'inicio-secao-titulo' }, t(passo + '.titulo'));
  const formId = 'form-passo-' + passo;

  let rotulo = t('inicio.avancar');
  let rotuloOcupado = t('inicio.salvando');
  if (passo === 'senha' && !modelo.simular && !modelo.senhaDefinida) { rotulo = t('senha.salvar'); rotuloOcupado = t('senha.salvando'); }
  const avancar = botao(rotulo, null, { tipo: 'primario', submit: true });
  avancar.setAttribute('form', formId);
  // Com id, o foco no Avancar fica depois do redesenho (o registro relido no G1 refaz a tela).
  avancar.id = 'inicio-avancar';

  async function salvar(r) {
    if (passo === 'senha') return r.senha ? salvarSenha(ctx, r.senha, resposta, form) : true;
    return salvarParcial(ctx, { ...r.parcial, etapa: ETAPA_DO_PASSO[passo] }, resposta, form);
  }

  async function aoEnviar(ev) {
    ev.preventDefault();
    if (ocupada) return;
    resposta.limpar();
    const r = form.coletar();
    if (!r.ok) return;
    ocupada = true;
    const restaurar = ocupar(avancar, rotuloOcupado);
    let ok = false;
    try { ok = await salvar(r); } finally { ocupada = false; restaurar(); }
    if (!ok) return;
    sujo = false;
    ctx.ir(rotaDoPasso(ctx.modelo().sessaoCompleta ? 'conferir' : PASSOS[i + 1]));
  }

  // G1: o registro de antes, so no passo da placa.
  const lugarRegistro = passo === PASSO_DO_REGISTRO ? h('div', { class: 'registro-escolha-lugar' }) : null;
  function desenharRegistro() {
    const bloco = blocoRegistro(ctx, ctx.modelo(), {
      marcarOcupada: (v) => { ocupada = v; },
      depois: (feita, id) => {
        desenharRegistro();
        const alvo = !feita && id ? document.getElementById(id) : null;
        (alvo || avancar).focus();
      },
    });
    lugarRegistro.replaceChildren(...(bloco ? [bloco] : []));
  }
  if (lugarRegistro) desenharRegistro();

  const voltar = i > 0 ? botao(t('inicio.voltar'), () => ctx.ir(rotaDoPasso(PASSOS[i - 1])), { tipo: 'secundario' }) : null;
  const marcarSujo = () => { sujo = true; };
  const el = h('div', { class: 'inicio-passo' }, [
    corpo(modelo, passo, null, [
      h('div', { class: 'inicio-secao' }, [titulo, h('p', { class: 'lead' }, t(passo + '.lead'))]),
      lugarRegistro,
      h('form', { id: formId, class: 'form', novalidate: true, onsubmit: aoEnviar, oninput: marcarSujo, onchange: marcarSujo }, form.el),
      resposta.el,
    ]),
    rodape(voltar, avancar, true),
  ]);
  return { el, foco: titulo, acao: avancar, sujo: () => sujo, ocupada: () => ocupada };
}

// ------------------------------------------------------------------ conferir
const mono = (texto) => h('span', { class: 'mono' }, texto);

// "Rotulo valor, rotulo valor": rotulo em texto, IP em mono.
function pares(lista) {
  const partes = [];
  for (const [rotulo, ip] of lista) {
    if (partes.length) partes.push(t('conferir.virgula'));
    partes.push(rotulo + ' ', ip ? mono(ip) : t('conferir.automatico'));
  }
  return h('span', null, partes);
}

function textoStream(v) {
  const fps = numero(v.Fps) + NBSP + t('unidade.fps');
  const kbps = numero(v.BitRate) + NBSP + t('unidade.kbps');
  return [resolucao(v.Resolucao), fps, kbps, v.Codec].join(t('conferir.virgula'));
}

// Valor de cada secao, ou null se ela ainda nao foi salva.
function valorSecao(secao, modelo) {
  const s = modelo.sessao;
  if (modelo.etapa < ETAPA_DO_PASSO[secao]) return null;
  if (secao === 'placa') {
    const p = s.Placa;
    if (!p || !p.Nome) return null;
    const tipo = p.Tipo === 'wifi' ? t('placas.wifi') : t('placas.ethernet');
    return h('span', null, [p.Nome, t('geral.separador'), tipo, p.Mac ? [t('geral.separador'), mono(mac(p.Mac))] : null]);
  }
  if (secao === 'rede') {
    if (!s.Gateway) return null;
    const dns = [s.Dns1, s.Dns2].filter(Boolean);
    // Duas linhas: a rede das cameras e a faixa de fabrica (cabe sem rolar a 768).
    return [
      h('span', null, [
        pares([[t('rede.gateway'), s.Gateway], [t('conferir.mascara'), s.Mascara]]),
        dns.length ? [t('conferir.virgula') + t('conferir.dns') + ' ', dns.map((d, n) => [n ? t('conferir.e') : '', mono(d)])] : null,
        t('conferir.virgula'),
        pares([[t('conferir.ipPc'), s.IpPcCameras]]),
      ]),
      pares([[t('rede.fabrica.ip'), s.IpFabrica], [t('rede.fabrica.pc'), s.IpPcFabrica || pcNaFabrica(s.IpFabrica)]]),
    ];
  }
  if (secao === 'camera') {
    if (!s.EmailRecuperacao) return null;
    return [
      h('span', null, s.EmailRecuperacao),
      h('span', null, t('conferir.streams', { principal: textoStream(s.Encoder.Principal), secundario: textoStream(s.Encoder.Secundario) })),
    ];
  }
  if (secao === 'fila') {
    const f = s.Fila;
    if (!f || !f.Inicio) return null;
    const lugar = [f.Local, f.Rack && t('conferir.rack', { v: f.Rack }), f.Andar && t('conferir.andar', { v: f.Andar })].filter(Boolean);
    return [
      h('span', null, [mono(f.Inicio), t('conferir.ate'), mono(f.Fim)]),
      lugar.length ? h('span', null, lugar.join(t('conferir.virgula'))) : null,
    ];
  }
  return null;
}

function falta() {
  return h('span', { class: 'conferir-falta' }, [icone('atencao'), h('span', null, t('conferir.falta'))]);
}

function alterar(secao) {
  return h('a', { class: 'botao botao-discreto', href: rotaDoPasso(secao) }, t('secao.alterar', { secao }));
}

function linha(secao, valor, acao) {
  return h('div', { class: 'conferir-linha' }, [
    h('div', { class: 'conferir-rotulo' }, t('secao.nome', { secao })),
    h('div', { class: 'conferir-valor' }, valor),
    h('div', { class: 'conferir-acao' }, acao),
  ]);
}

export function telaConferir(ctx) {
  const modelo = ctx.modelo();
  let ocupada = false;
  let sujo = false;
  const resposta = lugarAviso();
  const titulo = h('h2', { class: 'inicio-secao-titulo' }, t('conferir.titulo'));

  // Senha: a linha de cima. Sem senha nesta abertura (sessao guardada), o campo
  // fica aqui mesmo e o Comecar salva junto (UX-16).
  let formSenha = null;
  let senhaValor;
  let senhaAcao = null;
  if (modelo.simular) {
    senhaValor = h('span', { class: 'apoio' }, t('senha.simulacao'));
  } else if (modelo.senhaDefinida) {
    senhaValor = h('span', null, t('senha.salva'));
    senhaAcao = alterar('senha');
  } else {
    formSenha = montarFormulario('senha', modelo);
    senhaValor = h('div', { class: 'conferir-senha', oninput: () => { sujo = true; } }, [
      h('p', { class: 'conferir-pede' }, t('conferir.senhaPede')),
      formSenha.el,
    ]);
  }

  const linhas = [linha('senha', senhaValor, senhaAcao)];
  for (const secao of ['placa', 'rede', 'camera']) {
    linhas.push(linha(secao, valorSecao(secao, modelo) || falta(), alterar(secao)));
  }

  // Fila: o conflito com o registro aparece na linha dela, com a saida pronta (UX-27).
  const fila = [valorSecao('fila', modelo) || falta()];
  const cf = modelo.conflito;
  let usarSeguinte = null;
  if (cf && cf.instaladas && modelo.registroCarregado) {
    // A faixa ja esta na linha de cima: o aviso so diz o que houve, e a saida
    // fica ao lado dele (cabe sem rolar a 768).
    const conflito = [aviso('atencao', cf.todas
      ? t('fila.conflito.todas', { n: cf.total })
      : t('fila.conflito.parte', { n: cf.instaladas, total: cf.total }))];
    if (cf.todas && cf.seguinte) {
      usarSeguinte = botao(t('fila.usarSeguinte', cf.seguinte), trocarFaixa, { tipo: 'secundario' });
      conflito.push(usarSeguinte);
    }
    fila.push(h('div', { class: 'conferir-conflito' }, conflito));
  }
  linhas.push(linha('fila', fila, alterar('fila')));

  async function trocarFaixa() {
    if (ocupada) return;
    resposta.limpar();
    ocupada = true;
    const restaurar = ocupar(usarSeguinte, t('fila.trocandoFaixa'));
    let ok = false;
    try {
      ok = await salvarParcial(ctx, { Fila: { ...modelo.sessao.Fila, Inicio: cf.seguinte.inicio, Fim: cf.seguinte.fim } }, resposta, null);
    } finally { ocupada = false; restaurar(); }
    if (ok) ctx.redesenhar('acao');
  }

  const comecar = botao(t('inicio.comecar'), aoComecar, { tipo: 'primario' });
  async function aoComecar() {
    if (ocupada) return;
    resposta.limpar();
    let senha = null;
    if (formSenha) {
      const r = formSenha.coletar();
      if (!r.ok) return;
      senha = r.senha;
    }
    ocupada = true;
    const restaurar = ocupar(comecar, t('inicio.comecando'));
    let ok = false;
    try {
      ok = !senha || await salvarSenha(ctx, senha, resposta, formSenha);
      if (ok) {
        const m = ctx.modelo();
        const res = await ctx.api.comando('/api/sessao/concluir', { montarFila: !!m.sessao.Fila });
        if (!res.ok) { mostrarFalha(res, resposta, null); ok = false; }
      }
      if (ok && !await ctx.esperar((m) => m.sessaoIniciada && !m.ocupado, ESPERA_COMECAR_MS)) {
        resposta.mostrar('atencao', t('inicio.comecar.demorou'));
        ok = false;
      }
    } finally { ocupada = false; restaurar(); }
    if (!ok) return;
    sujo = false;
    // O proximo passo a passo (Refazer) pergunta de novo pelo registro (G1).
    escolhaRegistro.feita = false;
    escolhaRegistro.aviso = null;
    ctx.corrigir(ROTA_INICIAL);
    ctx.ir(ROTA_INICIAL);
  }

  const voltar = modelo.sessaoCompleta ? null : botao(t('inicio.voltar'), () => ctx.ir(rotaDoPasso('fila')), { tipo: 'secundario' });
  const nota = h('span', { class: 'rodape-nota' }, t('inicio.comecar.nota', { simular: modelo.simular }));
  const el = h('div', { class: 'inicio-passo' }, [
    corpo(modelo, 'conferir', 'inicio-conferir', [
      h('div', { class: 'inicio-secao' }, [titulo, h('p', { class: 'lead' }, t('conferir.lead'))]),
      h('div', { class: 'conferir-lista' }, linhas),
      resposta.el,
    ]),
    rodape(voltar, [nota, comecar]),
  ]);
  return { el, foco: titulo, acao: comecar, sujo: () => sujo, ocupada: () => ocupada };
}
