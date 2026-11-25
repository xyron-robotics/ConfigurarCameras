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
      h('main', { id: 'conteudo', tabindex: '-1' }, [
        h('div', { id: 'aviso', class: 'aviso-legado', role: 'alert', hidden: true }),
        h('div', { id: 'anuncio', class: 'so-leitor', role: 'status', 'aria-live': 'polite' }),
        // Passo a passo e Conferir: o app.js desenha aqui a tela de tela-inicio.js.
        h('section', { id: 'inicio', class: 'view inicio', hidden: true }),
        h('section', { id: 'view-painel', class: 'view', hidden: true }, [
          h('div', { id: 'painel-sem-fila', class: 'painel-sem-fila', hidden: true }, [
            h('h1', null, t('painel.painel-sem-fila.titulo')),
            h('p', { class: 'apoio' }, [
              t('painel.painel-sem-fila.apoio'),
              ' ',
              h('a', { href: '#/sessao/fila' }, t('painel.painel-sem-fila.link')),
            ]),
          ]),
          h('div', { id: 'fita-bloco', hidden: true }, [
            h('div', { class: 'fita-cabeca' }, [
              h('h1', { id: 'fita-titulo' }, t('painel.fita-titulo')),
              h('div', { class: 'fita-cabeca-fim' }, [
                h('span', { id: 'fita-resumo', class: 'apoio' }),
                ' ',
                h('button', { type: 'button', class: 'btn discreto', id: 'btn-encerrar-fila', hidden: true }, t('painel.btn-encerrar-fila')),
              ]),
            ]),
            h('ol', { id: 'fita', class: 'fita', translate: 'no', 'aria-label': t('painel.fita.rotulo-leitor') }),
          ]),
          h('div', { id: 'bancada', class: 'bancada', hidden: true }, [
            h('div', { id: 'vigia', class: 'vigia', hidden: true }, [
              h('div', { class: 'vigia-cabeca' }, [
                h('span', { class: 'luz', id: 'vigia-luz' }),
                ' ',
                h('h2', null, t('painel.vigia.titulo')),
                ' ',
                h('span', { class: 'apoio', id: 'vigia-estado', role: 'status', 'aria-live': 'polite' }, t('painel.vigia-estado')),
              ]),
              h('p', { class: 'apoio', id: 'vigia-texto', 'aria-live': 'polite' }),
              h('p', { class: 'apoio', id: 'vigia-dhip', hidden: true }, t('painel.vigia-dhip')),
              h('form', { id: 'form-vigia', class: 'linha-campos' }, [
                h('label', { class: 'check largo', title: t('painel.campo-broadcast.dica') }, [
                  h('input', { type: 'checkbox', name: 'broadcast' }),
                  ' ',
                  t('painel.campo-broadcast'),
                ]),
                ' ',
                h('button', { class: 'btn', type: 'submit', id: 'btn-vigia' }, t('painel.btn-vigia')),
              ]),
              h('p', { class: 'aviso-legado', 'data-aviso-de': 'vigia', role: 'alert', hidden: true }),
            ]),
            h('div', { id: 'bancada-pronta' }, [
              h('p', { class: 'bancada-pos', id: 'bancada-pos' }),
              h('p', { class: 'bancada-destino' }, [
                t('painel.bancada-destino.rotulo'),
                ' ',
                h('span', { class: 'mono', translate: 'no', id: 'bancada-destino' }),
              ]),
              h('p', { class: 'apoio', id: 'bancada-apoio' }, t('painel.bancada-apoio')),
              h('form', { id: 'form-conectada' }, [
                h('div', { class: 'linha-campos' }, [
                  h('label', null, [
                    t('painel.campo-porta'),
                    h('input', { name: 'porta', autocomplete: 'off' }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('painel.campo-canal'),
                    h('input', { name: 'canal', autocomplete: 'off' }),
                  ]),
                  ' ',
                  h('button', { class: 'btn acento', type: 'submit', id: 'btn-conectada' }, t('painel.btn-conectada')),
                ]),
                h('details', { id: 'retomar', class: 'retomar' }, [
                  h('summary', null, t('painel.retomar.abrir')),
                  h('p', { class: 'nota' }, t('painel.retomar.nota')),
                  ' ',
                  h('label', null, [
                    t('painel.campo-ip'),
                    h('input', { name: 'ip', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', autocomplete: 'off' }),
                  ]),
                ]),
              ]),
            ]),
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
            h('div', { id: 'bancada-decisao', hidden: true }, [
              h('p', { class: 'bancada-pos falha-titulo', id: 'decisao-titulo' }),
              h('p', { id: 'decisao-erro', class: 'decisao-erro' }),
              h('p', { class: 'apoio', id: 'decisao-apoio' }, t('painel.decisao-apoio')),
              h('div', { class: 'acoes' }, [
                h('button', { type: 'button', class: 'btn acento', 'data-decisao': 'tentar' }, t('painel.decisao-tentar')),
                ' ',
                h('button', { type: 'button', class: 'btn', 'data-decisao': 'pular' }, t('painel.decisao-pular')),
              ]),
            ]),
            h('div', { id: 'bancada-fim', class: 'bancada-fim', hidden: true }, [
              h('p', { class: 'bancada-pos', id: 'fim-titulo' }),
              h('p', { class: 'apoio', id: 'fim-texto' }),
              ' ',
              h('a', { class: 'btn', href: '#/sessao/fila' }, t('painel.bancada-fim.link')),
            ]),
            h('p', { class: 'aviso-legado', 'data-aviso-de': 'conectada', role: 'alert', hidden: true }),
          ]),
          h('p', { id: 'ultimo', class: 'ultimo', hidden: true }),
          // Tabela Fila agora / Registro e linhas de cada camera: o app.js monta aqui a tela-painel.js.
          h('div', { id: 'painel-tabela' }),
        ]),
        h('section', { id: 'view-ferramentas', class: 'view', hidden: true }, [
          h('h1', null, t('ferramentas.titulo')),
          h('p', { class: 'apoio' }, t('ferramentas.apoio')),
          h('div', { class: 'ferramentas' }, [
            h('form', { id: 'form-sondar', class: 'ferramenta' }, [
              h('h2', null, t('ferramentas.form-sondar.titulo')),
              h('p', { class: 'apoio' }, t('ferramentas.form-sondar.apoio')),
              h('div', { class: 'linha-campos' }, [
                h('label', null, [
                  t('ferramentas.campo-ip'),
                  h('input', { name: 'ip', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', required: true, autocomplete: 'off' }),
                ]),
                ' ',
                h('button', { class: 'btn', type: 'submit', 'data-so-real': true }, t('ferramentas.form-sondar.botao')),
              ]),
              h('p', { class: 'nota', 'data-nota-simular': true, hidden: true }, t('ferramentas.form-sondar.nota')),
              h('p', { class: 'aviso-legado', 'data-aviso-de': 'sondar', role: 'alert', hidden: true }),
            ]),
            h('div', { class: 'ferramenta' }, [
              h('h2', null, t('ferramentas.descobrir.titulo')),
              h('p', { class: 'apoio' }, [
                t('ferramentas.descobrir.apoio'),
                ' ',
                h('span', { translate: 'no' }, t('ferramentas.descobrir.termo')),
                ' ',
                t('ferramentas.descobrir.apoio.2'),
              ]),
              ' ',
              h('button', { type: 'button', class: 'btn', id: 'btn-descobrir', 'data-so-real': true }, t('ferramentas.btn-descobrir')),
              ' ',
              h('p', { class: 'nota', 'data-nota-simular': true, hidden: true }, t('ferramentas.descobrir.nota')),
              h('p', { class: 'aviso-legado', 'data-aviso-de': 'descobrir', role: 'alert', hidden: true }),
            ]),
            h('div', { class: 'ferramenta' }, [
              h('h2', null, t('ferramentas.verificar.titulo')),
              h('p', { class: 'apoio' }, t('ferramentas.verificar.apoio')),
              ' ',
              h('button', { type: 'button', class: 'btn', id: 'btn-verificar' }, t('ferramentas.btn-verificar')),
              ' ',
              h('p', { class: 'aviso-legado', 'data-aviso-de': 'verificar', role: 'alert', hidden: true }),
            ]),
          ]),
          h('div', { id: 'resultado-ferramenta', class: 'resultado', 'aria-live': 'polite', hidden: true }),
        ]),
        // Sessao: o app.js desenha aqui a tela de tela-sessao.js.
        h('section', { id: 'sessao', class: 'view sessao', hidden: true }),
        h('details', { class: 'log', id: 'log-bloco', open: true }, [
          h('summary', null, t('log.abrir')),
          h('div', { id: 'log', class: 'log-linhas mono', translate: 'no', 'aria-live': 'off' }),
        ]),
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
