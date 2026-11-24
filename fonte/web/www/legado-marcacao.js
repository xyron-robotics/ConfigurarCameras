// Transicao: sai nas frentes 3 a 5 do redesenho.
// Marcacao do painel de hoje (era o <body> do index.html), montada com h()
// e sem innerHTML. Os textos estao em textos.js, com as mesmas letras.
import { h, focar } from './dom.js';
import { t } from './textos.js';
import { logo } from './marca.js';
import { BITRATE_MAX, BITRATE_MIN, FPS_MAX, FPS_MIN, PROGRESSO_MAX } from './constantes.js';

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
        h('section', { id: 'inicio', class: 'view inicio', hidden: true, 'aria-labelledby': 'inicio-titulo' }, [
          h('p', { id: 'inicio-titulo', class: 'so-leitor' }, t('inicio.inicio-titulo')),
          logo(),
          h('ol', { id: 'passos', class: 'passos', 'aria-label': t('inicio.passos.rotulo-leitor') }, [
            h('li', { 'data-passo': '1' }, [
              h('button', { type: 'button', class: 'passo-botao' }, t('inicio.passo1.botao')),
            ]),
            h('li', { 'data-passo': '2' }, [
              h('button', { type: 'button', class: 'passo-botao' }, t('inicio.passo2.botao')),
            ]),
            h('li', { 'data-passo': '3' }, [
              h('button', { type: 'button', class: 'passo-botao' }, t('inicio.passo3.botao')),
            ]),
            h('li', { 'data-passo': '4' }, [
              h('button', { type: 'button', class: 'passo-botao' }, t('inicio.passo4.botao')),
            ]),
            h('li', { 'data-passo': '5' }, [
              h('button', { type: 'button', class: 'passo-botao' }, t('inicio.passo5.botao')),
            ]),
            h('li', { 'data-passo': '6' }, [
              h('button', { type: 'button', class: 'passo-botao' }, t('inicio.passo6.botao')),
            ]),
            h('li', { 'data-passo': '7' }, [
              h('button', { type: 'button', class: 'passo-botao' }, t('inicio.passo7.botao')),
            ]),
          ]),
          h('div', { class: 'passo', 'data-passo': '1', hidden: true }, [
            h('h1', null, t('inicio.passo1.titulo')),
            h('p', { class: 'explica' }, [
              t('inicio.passo1.explica'),
              ' ',
              h('span', { class: 'mono', translate: 'no' }, t('inicio.passo1.termo')),
              ' ',
              t('inicio.passo1.explica.2'),
            ]),
            h('div', { id: 'passo-escolha', class: 'passo-escolha', hidden: true }, [
              h('p', { id: 'escolha-texto' }),
              h('div', { class: 'acoes' }, [
                h('button', { type: 'button', class: 'btn acento', id: 'btn-usar-sessao' }, t('inicio.btn-usar-sessao')),
                ' ',
                h('button', { type: 'button', class: 'btn', id: 'btn-revisar-sessao' }, t('inicio.btn-revisar-sessao')),
              ]),
            ]),
            h('p', { id: 'senha-definida', class: 'senha-definida', hidden: true }, [
              t('inicio.senha-definida'),
              ' ',
              h('button', { type: 'button', class: 'btn discreto', id: 'btn-trocar-senha' }, t('inicio.btn-trocar-senha')),
            ]),
            h('div', { class: 'slot' }),
          ]),
          h('div', { class: 'passo', 'data-passo': '2', hidden: true }, [
            h('h1', null, t('inicio.passo2.titulo')),
            h('p', { class: 'explica' }, t('inicio.passo2.explica')),
            h('div', { class: 'slot' }),
          ]),
          h('div', { class: 'passo', 'data-passo': '3', hidden: true }, [
            h('h1', null, t('inicio.passo3.titulo')),
            h('p', { class: 'explica' }, t('inicio.passo3.explica')),
            h('div', { class: 'slot' }),
          ]),
          h('div', { class: 'passo', 'data-passo': '4', hidden: true }, [
            h('h1', null, t('inicio.passo4.titulo')),
            h('p', { class: 'explica' }, t('inicio.passo4.explica')),
            h('div', { class: 'slot' }),
          ]),
          h('div', { class: 'passo', 'data-passo': '5', hidden: true }, [
            h('h1', null, t('inicio.passo5.titulo')),
            h('p', { class: 'explica' }, [
              t('inicio.passo5.explica'),
              ' ',
              h('span', { translate: 'no' }, t('inicio.passo5.termo')),
              t('inicio.passo5.explica.2'),
              ' ',
              h('span', { translate: 'no' }, t('inicio.passo5.termo.2')),
              ' ',
              t('inicio.passo5.explica.3'),
              ' ',
              h('span', { translate: 'no' }, t('inicio.passo5.termo.3')),
              ' ',
              t('inicio.passo5.explica.4'),
              ' ',
              h('span', { translate: 'no' }, t('inicio.passo5.termo.4')),
              t('inicio.passo5.explica.5'),
            ]),
            h('div', { class: 'slot' }),
          ]),
          h('div', { class: 'passo', 'data-passo': '6', hidden: true }, [
            h('h1', null, t('inicio.passo6.titulo')),
            h('p', { class: 'explica' }, t('inicio.passo6.explica')),
            h('div', { class: 'slot' }),
          ]),
          h('div', { class: 'passo', 'data-passo': '7', hidden: true }, [
            h('h1', null, t('inicio.passo7.titulo')),
            h('p', { class: 'explica' }, t('inicio.passo7.explica')),
            h('div', { id: 'resumo', class: 'resumo' }),
            ' ',
            h('label', { class: 'check', id: 'resumo-montar-rotulo', hidden: true }, [
              h('input', { type: 'checkbox', id: 'resumo-montar', checked: true }),
              ' ',
              t('inicio.resumo-montar'),
            ]),
            ' ',
            h('p', { class: 'aviso-legado', 'data-aviso-de': 'concluir', role: 'alert', hidden: true }),
          ]),
          h('div', { class: 'passo-acoes' }, [
            h('button', { type: 'button', class: 'btn discreto', id: 'btn-voltar' }, t('inicio.btn-voltar')),
            ' ',
            h('span', { id: 'passo-n', class: 'apoio', 'aria-live': 'polite' }),
            ' ',
            h('span', { class: 'espaco' }),
            ' ',
            h('button', { type: 'button', class: 'btn discreto', id: 'btn-montar-depois', hidden: true }, t('inicio.btn-montar-depois')),
            ' ',
            h('button', { type: 'button', class: 'btn acento', id: 'btn-avancar' }, t('inicio.btn-avancar')),
            ' ',
            h('button', { type: 'button', class: 'btn acento', id: 'btn-comecar', hidden: true }, t('inicio.btn-comecar')),
          ]),
        ]),
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
            h('ol', { id: 'cartoes', class: 'cartoes', 'aria-label': t('painel.cartoes.rotulo-leitor'), hidden: true }),
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
          h('div', { id: 'registro-bloco', class: 'registro-bloco' }, [
            h('div', { class: 'fita-cabeca' }, [
              h('h2', { id: 'registro-titulo' }, t('painel.registro-titulo')),
              h('div', { class: 'acoes' }, [
                h('button', { type: 'button', class: 'btn discreto', id: 'btn-registro-atualizar' }, t('painel.btn-registro-atualizar')),
                ' ',
                h('a', { class: 'btn', id: 'btn-exportar', href: '/api/relatorio.csv' }, t('painel.btn-exportar')),
              ]),
            ]),
            h('div', { class: 'tabela-rolagem' }, [
              h('table', { class: 'tabela' }, [
                h('thead', null, [
                  h('tr', null, [
                    h('th', { scope: 'col' }, t('painel.registro-bloco.coluna')),
                    h('th', { scope: 'col' }, t('painel.registro-bloco.coluna.2')),
                    h('th', { scope: 'col' }, t('painel.registro-bloco.coluna.3')),
                    h('th', { scope: 'col' }, t('painel.registro-bloco.coluna.4')),
                    h('th', { scope: 'col' }, t('painel.registro-bloco.coluna.5')),
                    h('th', { scope: 'col' }, t('painel.registro-bloco.coluna.6')),
                    h('th', { scope: 'col' }, t('painel.registro-bloco.coluna.7')),
                    h('th', { scope: 'col' }, t('painel.registro-bloco.coluna.8')),
                  ]),
                ]),
                h('tbody', { id: 'registro-corpo' }),
              ]),
            ]),
            h('p', { id: 'registro-vazio', class: 'apoio', hidden: true }, t('painel.registro-vazio')),
          ]),
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
        h('section', { id: 'view-opcoes', class: 'view opcoes', hidden: true }, [
          h('h1', null, t('opcoes.titulo')),
          h('p', { class: 'apoio' }, t('opcoes.apoio')),
          h('div', { class: 'secao', 'data-secao': 'senha' }, [
            h('h2', null, t('opcoes.secao-senha.titulo')),
            h('p', { class: 'apoio' }, t('opcoes.secao-senha.apoio')),
            h('p', { id: 'senha-instaladas', class: 'nota', hidden: true }),
            h('div', { class: 'slot' }, [
              h('form', { id: 'form-senha', class: 'secao-form' }, [
                h('div', { class: 'campos' }, [
                  h('label', null, [
                    t('opcoes.campo-senha'),
                    h('input', { name: 'senha', type: 'password', autocomplete: 'new-password' }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-senha2'),
                    h('input', { name: 'senha2', type: 'password', autocomplete: 'new-password' }),
                  ]),
                  ' ',
                  h('button', { class: 'btn discreto', type: 'button', id: 'btn-senha-mostrar', 'aria-pressed': 'false' }, t('opcoes.btn-senha-mostrar')),
                ]),
                h('p', { id: 'senha-erro', class: 'aviso-legado', role: 'alert', hidden: true }, t('opcoes.senha-erro')),
                h('ul', { class: 'erros', role: 'alert', hidden: true }),
                h('div', { class: 'acoes so-opcoes' }, [
                  h('button', { class: 'btn', type: 'submit' }, t('opcoes.form-senha.botao')),
                  ' ',
                  h('span', { class: 'apoio', 'data-ok': true, role: 'status', hidden: true }),
                ]),
              ]),
            ]),
          ]),
          h('div', { class: 'secao', 'data-secao': 'placa' }, [
            h('h2', null, t('opcoes.secao-placa.titulo')),
            h('p', { class: 'apoio' }, t('opcoes.secao-placa.apoio')),
            h('div', { class: 'slot' }, [
              h('form', { id: 'form-placa', class: 'secao-form' }, [
                h('ul', { id: 'placas', class: 'placas', 'aria-label': t('opcoes.placas.rotulo-leitor') }),
                h('p', { class: 'nota', id: 'placas-nota', hidden: true }),
                h('ul', { class: 'erros', role: 'alert', hidden: true }),
                h('div', { class: 'acoes' }, [
                  h('button', { type: 'button', class: 'btn discreto', id: 'btn-placas-atualizar' }, t('opcoes.btn-placas-atualizar')),
                  ' ',
                  h('button', { class: 'btn so-opcoes', type: 'submit' }, t('opcoes.form-placa.botao')),
                  ' ',
                  h('span', { class: 'apoio', 'data-ok': true, role: 'status', hidden: true }),
                ]),
              ]),
            ]),
          ]),
          h('div', { class: 'secao', 'data-secao': 'rede' }, [
            h('h2', null, t('opcoes.secao-rede.titulo')),
            h('p', { class: 'apoio' }, t('opcoes.secao-rede.apoio')),
            h('div', { class: 'slot' }, [
              h('form', { id: 'form-rede', class: 'secao-form' }, [
                h('div', { class: 'campos' }, [
                  h('label', null, [
                    t('opcoes.campo-Mascara'),
                    h('input', { name: 'Mascara', autocomplete: 'off', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', required: true }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-Gateway'),
                    h('input', { name: 'Gateway', autocomplete: 'off', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', required: true }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-Dns1'),
                    h('input', { name: 'Dns1', autocomplete: 'off', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', required: true }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-Dns2'),
                    h('input', { name: 'Dns2', autocomplete: 'off', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', required: true }),
                  ]),
                  ' ',
                  h('label', { class: 'duplo' }, [
                    t('opcoes.campo-IpPcCameras'),
                    h('input', { name: 'IpPcCameras', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', autocomplete: 'off', placeholder: t('opcoes.campo-IpPcCameras.exemplo') }),
                  ]),
                ]),
                h('ul', { class: 'erros', role: 'alert', hidden: true }),
                h('div', { class: 'acoes so-opcoes' }, [
                  h('button', { class: 'btn', type: 'submit' }, t('opcoes.form-rede.botao')),
                  ' ',
                  h('span', { class: 'apoio', 'data-ok': true, role: 'status', hidden: true }),
                ]),
              ]),
            ]),
          ]),
          h('div', { class: 'secao', 'data-secao': 'fabrica' }, [
            h('h2', null, t('opcoes.secao-fabrica.titulo')),
            h('p', { class: 'apoio' }, t('opcoes.secao-fabrica.apoio')),
            h('div', { class: 'slot' }, [
              h('form', { id: 'form-fabrica', class: 'secao-form' }, [
                h('div', { class: 'campos' }, [
                  h('label', null, [
                    t('opcoes.campo-IpFabrica'),
                    h('input', { name: 'IpFabrica', autocomplete: 'off', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', required: true }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-IpPcFabrica'),
                    h('input', { name: 'IpPcFabrica', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', autocomplete: 'off', placeholder: t('opcoes.campo-IpPcFabrica.exemplo') }),
                  ]),
                ]),
                h('ul', { class: 'erros', role: 'alert', hidden: true }),
                h('div', { class: 'acoes so-opcoes' }, [
                  h('button', { class: 'btn', type: 'submit' }, t('opcoes.form-fabrica.botao')),
                  ' ',
                  h('span', { class: 'apoio', 'data-ok': true, role: 'status', hidden: true }),
                ]),
              ]),
            ]),
          ]),
          h('div', { class: 'secao', 'data-secao': 'camera' }, [
            h('h2', null, t('opcoes.secao-camera.titulo')),
            h('p', { class: 'apoio' }, t('opcoes.secao-camera.apoio')),
            h('div', { class: 'slot' }, [
              h('form', { id: 'form-camera', class: 'secao-form' }, [
                h('div', { class: 'campos' }, [
                  h('label', { class: 'largo' }, [
                    t('opcoes.campo-EmailRecuperacao'),
                    h('input', { name: 'EmailRecuperacao', autocomplete: 'off', type: 'email', spellcheck: 'false', required: true }),
                  ]),
                ]),
                h('fieldset', null, [
                  h('legend', null, t('opcoes.form-camera.legenda')),
                  h('div', { class: 'campos' }, [
                    h('label', null, [
                      t('opcoes.campo-Resolucao'),
                      h('select', { name: 'Resolucao' }),
                    ]),
                    ' ',
                    h('label', null, [
                      t('opcoes.campo-FpsPrincipal'),
                      h('select', { class: 'lista-valor', 'data-para': 'FpsPrincipal' }),
                      h('input', { name: 'FpsPrincipal', autocomplete: 'off', type: 'number', min: FPS_MIN, max: FPS_MAX, 'aria-label': t('opcoes.campo-FpsPrincipal.rotulo-leitor'), required: true, hidden: true }),
                    ]),
                    ' ',
                    h('label', null, [
                      t('opcoes.campo-BitRate'),
                      h('select', { class: 'lista-valor', 'data-para': 'BitRate', 'aria-describedby': 'faixa-principal' }),
                      h('input', { name: 'BitRate', autocomplete: 'off', type: 'number', min: BITRATE_MIN, max: BITRATE_MAX, 'aria-label': t('opcoes.campo-BitRate.rotulo-leitor'), 'aria-describedby': 'faixa-principal', required: true, hidden: true }),
                    ]),
                    ' ',
                    h('label', null, [
                      t('opcoes.campo-CodecPrincipal'),
                      h('select', { name: 'CodecPrincipal' }),
                    ]),
                  ]),
                  h('p', { class: 'faixa-encoder', id: 'faixa-principal' }),
                ]),
                h('fieldset', null, [
                  h('legend', null, t('opcoes.form-camera.legenda.2')),
                  h('div', { class: 'campos' }, [
                    h('label', null, [
                      t('opcoes.campo-ResolucaoSecundario'),
                      h('select', { name: 'ResolucaoSecundario' }),
                    ]),
                    ' ',
                    h('label', null, [
                      t('opcoes.campo-FpsSecundario'),
                      h('select', { class: 'lista-valor', 'data-para': 'FpsSecundario' }),
                      h('input', { name: 'FpsSecundario', autocomplete: 'off', type: 'number', min: FPS_MIN, max: FPS_MAX, 'aria-label': t('opcoes.campo-FpsSecundario.rotulo-leitor'), required: true, hidden: true }),
                    ]),
                    ' ',
                    h('label', null, [
                      t('opcoes.campo-BitRateSecundario'),
                      h('select', { class: 'lista-valor', 'data-para': 'BitRateSecundario', 'aria-describedby': 'faixa-secundario' }),
                      h('input', { name: 'BitRateSecundario', autocomplete: 'off', type: 'number', min: BITRATE_MIN, max: BITRATE_MAX, 'aria-label': t('opcoes.campo-BitRateSecundario.rotulo-leitor'), 'aria-describedby': 'faixa-secundario', required: true, hidden: true }),
                    ]),
                    ' ',
                    h('label', null, [
                      t('opcoes.campo-CodecSecundario'),
                      h('select', { name: 'CodecSecundario' }),
                    ]),
                  ]),
                  h('p', { class: 'faixa-encoder', id: 'faixa-secundario' }),
                ]),
                h('p', { class: 'nota' }, t('opcoes.form-camera.nota')),
                h('ul', { class: 'avisos-leves', id: 'camera-avisos', 'aria-live': 'polite', hidden: true }),
                h('ul', { class: 'erros', role: 'alert', hidden: true }),
                h('div', { class: 'acoes so-opcoes' }, [
                  h('button', { class: 'btn', type: 'submit' }, t('opcoes.form-camera.botao')),
                  ' ',
                  h('span', { class: 'apoio', 'data-ok': true, role: 'status', hidden: true }),
                ]),
              ]),
            ]),
          ]),
          h('div', { class: 'secao', 'data-secao': 'fila' }, [
            h('h2', null, t('opcoes.secao-fila.titulo')),
            h('p', { class: 'apoio' }, t('opcoes.secao-fila.apoio')),
            h('div', { class: 'slot' }, [
              h('form', { id: 'form-fila', class: 'secao-form' }, [
                h('div', { class: 'campos' }, [
                  h('label', null, [
                    t('opcoes.campo-inicio'),
                    h('input', { name: 'inicio', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', placeholder: t('opcoes.campo-inicio.exemplo'), autocomplete: 'off' }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-fim'),
                    h('input', { name: 'fim', class: 'mono', translate: 'no', 'data-ip': true, spellcheck: 'false', placeholder: t('opcoes.campo-fim.exemplo'), autocomplete: 'off' }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-local'),
                    h('input', { name: 'local', autocomplete: 'off', placeholder: t('opcoes.campo-local.exemplo') }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-rack'),
                    h('input', { name: 'rack', autocomplete: 'off', placeholder: t('opcoes.campo-rack.exemplo') }),
                  ]),
                  ' ',
                  h('label', null, [
                    t('opcoes.campo-andar'),
                    h('input', { name: 'andar', autocomplete: 'off', placeholder: t('opcoes.campo-andar.exemplo') }),
                  ]),
                ]),
                h('p', { class: 'nota', id: 'fila-previa', 'aria-live': 'polite', hidden: true }),
                h('p', { class: 'nota', id: 'fila-ultima', hidden: true }),
                h('ul', { class: 'erros', role: 'alert', hidden: true }),
                h('div', { class: 'acoes so-opcoes' }, [
                  h('button', { class: 'btn', type: 'submit' }, t('opcoes.form-fila.botao')),
                  ' ',
                  h('span', { class: 'apoio', 'data-ok': true, role: 'status', hidden: true }),
                ]),
                h('p', { class: 'aviso-legado', 'data-aviso-de': 'fila', role: 'alert', hidden: true }),
              ]),
            ]),
          ]),
          h('div', { class: 'secao', 'data-secao': 'painel' }, [
            h('h2', null, t('opcoes.secao-painel.titulo')),
            h('p', { class: 'apoio' }, t('opcoes.secao-painel.apoio')),
            h('div', { class: 'acoes' }, [
              h('button', { type: 'button', class: 'btn', id: 'btn-restaurar' }, t('opcoes.btn-restaurar')),
              ' ',
              h('button', { type: 'button', class: 'btn', id: 'btn-refazer' }, t('opcoes.btn-refazer')),
              ' ',
              h('button', { type: 'button', class: 'btn discreto', id: 'btn-encerrar' }, t('opcoes.btn-encerrar')),
              ' ',
              h('span', { class: 'apoio', id: 'versao-painel' }),
            ]),
            h('fieldset', { class: 'tema', id: 'tema' }, [
              h('legend', null, t('opcoes.tema.legenda')),
              h('div', { class: 'segmentos' }, [
                h('label', null, [
                  h('input', { type: 'radio', name: 'tema', value: 'sistema', checked: true }),
                  t('opcoes.tema-sistema'),
                ]),
                ' ',
                h('label', null, [
                  h('input', { type: 'radio', name: 'tema', value: 'claro' }),
                  t('opcoes.tema-claro'),
                ]),
                ' ',
                h('label', null, [
                  h('input', { type: 'radio', name: 'tema', value: 'escuro' }),
                  t('opcoes.tema-escuro'),
                ]),
              ]),
            ]),
            h('p', { class: 'aviso-legado', 'data-aviso-de': 'painel', role: 'alert', hidden: true }),
          ]),
        ]),
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
