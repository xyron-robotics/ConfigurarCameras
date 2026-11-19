// Marca Grupo SmartSeg (direcao.md, secao 4.6). Logo inteira nas telas de abertura, passo a passo,
// Conferir, Encerrado e Sessao > Painel > Sobre; simbolo no topo. No escuro a logo oficial vai
// sobre a placa clara (--logo-placa), em definitivo (decisao do usuario, Task 6).
import { h } from './dom.js';
import { t } from './textos.js';

export function logo() {
  return h('img', { class: 'logo', src: 'logo.png', alt: t('marca.alt'), width: '336', height: '172' });
}

export function simbolo() {
  return h('img', { class: 'simbolo', src: 'simbolo.png', alt: '', width: '64', height: '64' });
}
