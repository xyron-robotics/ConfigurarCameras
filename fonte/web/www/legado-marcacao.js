// Transicao: sai nas frentes 3 a 5 do redesenho.
// Marcacao do painel de hoje (era o <body> do index.html), montada com h()
// e sem innerHTML. Os textos estao em textos.js, com as mesmas letras.
import { h, focar } from './dom.js';
import { t } from './textos.js';
import { logo } from './marca.js';
import { PROGRESSO_MAX } from './constantes.js';

// "Pular para o conteudo" sem mexer no hash (o hash e a rota, rotas.js).
function pularParaConteudo(ev) {
  ev.preventDefault();
  focar(document.getElementById('conteudo'));
}

// Os nos do ponto de montagem, na ordem do <body> de antes. O topo (topo.js)
// entra no lugar do cabecalho e do menu antigos.
export function montarMarcacao(topo) {
  return [
    h('a', { class: 'pular', href: '#conteudo', onclick: pularParaConteudo }, t('topo.pular')),
    ' ',
    h('div', { id: 'atualizacao', class: 'atualizacao', role: 'status', 'aria-live': 'polite', hidden: true }, [
      h('span', { id: 'atualizacao-texto' }),
      ' ',
      h('a', { id: 'atualizacao-notas', href: '#', target: '_blank', rel: 'noopener', hidden: true }, t('topo.atualizacao-notas')),
      ' ',
      h('button', { type: 'button', class: 'btn', id: 'btn-atualizar' }, t('topo.btn-atualizar')),
    ]),
    topo,
    // Faixa do modo de reserva do vigia (direcao 3.6 e 5.7): o app.js monta aqui a de tela-painel.js.
    h('div', { id: 'faixa-painel' }),
      h('main', { id: 'conteudo', tabindex: '-1' }, [
        h('div', { id: 'aviso', class: 'aviso-legado', role: 'alert', hidden: true }),
        h('div', { id: 'anuncio', class: 'so-leitor', role: 'status', 'aria-live': 'polite' }),
        // Falha nova de camera (P3): interrompe a fala, o foco fica onde esta.
        h('div', { id: 'anuncio-urgente', class: 'so-leitor', 'aria-live': 'assertive', 'aria-atomic': 'true' }),
        // Passo a passo e Conferir: o app.js desenha aqui a tela de tela-inicio.js.
        h('section', { id: 'inicio', class: 'view inicio', hidden: true }),
        h('section', { id: 'view-painel', class: 'view', hidden: true }, [
          // Cabecalho da fila, fita e estados vazios: o app.js monta aqui o topo de tela-painel.js.
          h('div', { id: 'painel-topo' }),
          h('div', { id: 'bancada', class: 'bancada', hidden: true }, [
            h('div', { id: 'bancada-trabalho', hidden: true }, [
              h('p', { class: 'bancada-pos', id: 'trabalho-titulo' }),
              h('ol', { class: 'etapas', id: 'etapas' }, [
                h('li', { 'data-etapa': 'inicializada' }, t('painel.etapa-inicializada')),
                h('li', { 'data-etapa': 'encoder' }, t('painel.etapa-encoder')),
                h('li', { 'data-etapa': 'rede' }, t('painel.etapa-rede')),
                h('li', { 'data-etapa': 'conferida' }, t('painel.etapa-conferida')),
              ]),
              h('p', { class: 'apoio', id: 'trabalho-texto', 'aria-live': 'polite' }),
              ' ',
              h('progress', { id: 'trabalho-progresso', max: PROGRESSO_MAX, value: '0', hidden: true }),
            ]),
            // A decisao da retomada manual pelo IP mora em Pede voce (tela-painel.js).
            h('p', { class: 'aviso-legado', 'data-aviso-de': 'conectada', role: 'alert', hidden: true }),
          ]),
          h('p', { id: 'ultimo', class: 'ultimo', hidden: true }),
          // Tabela Fila agora / Registro e linhas de cada camera: o app.js monta aqui a tela-painel.js.
          h('div', { id: 'painel-tabela' }),
        ]),
        // Ferramentas: o app.js monta aqui a tela de tela-ferramentas.js (com o log do painel).
        h('section', { id: 'ferramentas', class: 'view', hidden: true }),
        // Sessao: o app.js desenha aqui a tela de tela-sessao.js.
        h('section', { id: 'sessao', class: 'view sessao', hidden: true }),
      ]),
    h('div', { id: 'encerrado', class: 'encerrado', tabindex: '-1', hidden: true }, [
      h('div', { class: 'fim-marca' }, [
        logo(),
        h('p', { id: 'encerrado-texto' }, t('fim.encerrado-texto')),
      ]),
    ]),
    h('div', { id: 'atualizando', class: 'encerrado', tabindex: '-1', hidden: true }, [
      h('p', { id: 'atualizando-texto' }, t('fim.atualizando-texto')),
    ]),
  ];
}
