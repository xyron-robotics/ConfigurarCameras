// Icones (direcao.md, secao 4.5). Caminhos do Lucide, https://lucide.dev
// Lucide: ISC License. Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022
// as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022.
//
// Um conjunto so, traco de 1,5 px (--traco-icone) a 16 px ('p', --icone-p) ou
// 20 px ('m', --icone-m). Sem glifo de texto como icone (UI-16). Os caminhos sao
// constantes deste arquivo, nunca dado do servidor.

const NS = 'http://www.w3.org/2000/svg';

const CAMINHOS = Object.freeze({
  concluido: '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
  falha: '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>',
  atencao: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  informacao: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
  espera: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  agora: '<circle cx="12" cy="12" r="5" class="icone-cheio"/>',
  placa: '<path d="m15 20 3-3h2a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h2l3 3z"/><path d="M6 8v1"/><path d="M10 8v1"/><path d="M14 8v1"/><path d="M18 8v1"/>',
  internet: '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
  simulacao: '<path d="M14 2v6a2 2 0 0 0 .245.96l5.51 10.08A2 2 0 0 1 18 22H6a2 2 0 0 1-1.755-2.96l5.51-10.08A2 2 0 0 0 10 8V2"/><path d="M6.453 15h11.094"/><path d="M8.5 2h7"/>',
  fechar: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
  abrir: '<path d="m6 9 6 6 6-6"/>',
  pulada: '<path d="M5 12h14"/>',
  mais: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
});

// icone('falha')                 decorativo (aria-hidden): a palavra ao lado diz o estado.
// icone('falha', 'p', t('...'))  com nome acessivel, quando nao ha palavra ao lado.
export function icone(nome, tamanho, rotulo) {
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('focusable', 'false');
  svg.setAttribute('class', `icone icone-${tamanho || 'p'} icone-${nome}`);
  if (rotulo) {
    svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', rotulo);
  } else {
    svg.setAttribute('aria-hidden', 'true');
  }
  svg.innerHTML = CAMINHOS[nome] || '';
  return svg;
}
