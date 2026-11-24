// Marca Grupo SmartSeg (direcao.md, secao 4.6). Logo inteira no passo a passo e na
// tela de encerrado; simbolo no topo, ao lado de "Configurar cameras". No escuro a
// logo oficial vai sobre a placa clara (--logo-placa), em definitivo (decisao do
// usuario, Task 6). Os PNG sao os do prototipo, sem redesenho.
import { h } from './dom.js';
import { t } from './textos.js';

export function logo() {
  return h('img', { class: 'logo', src: 'logo.png', alt: t('marca.alt'), width: '336', height: '172' });
}

// Decorativo: o texto ao lado ja diz o nome do painel.
export function simbolo() {
  return h('img', { class: 'simbolo', src: 'simbolo.png', alt: '', width: '64', height: '64' });
}
