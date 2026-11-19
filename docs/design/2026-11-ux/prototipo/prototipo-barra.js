// PROTOTIPO. Barra discreta de cenario e tema (skill prototype, ramo UI): fixa embaixo, troca
// o cenario por ?cenario= e o tema por ?tema=. Setas esquerda e direita trocam o cenario
// quando o foco nao esta num campo. A fase B nao leva este arquivo; os textos daqui sao do
// prototipo e por isso nao moram em textos.js.
import { h } from './dom.js';
import { CENARIOS } from './api-falsa.js';
import { TEMAS } from './constantes.js';

const NOMES = {
  primeira: 'Primeira configuração',
  'sessao-salva': 'Sessão salva: Conferir',
  vazio: 'Fila montada, vigia desligado',
  painel: 'Painel com 3 câmeras',
  falha: 'Falha com decisão',
  concluida: 'Fila concluída',
  dezesseis: 'Fila de 16 posições',
  reserva: 'Modo de reserva',
  perdida: 'Conexão perdida',
};
const NOMES_TEMA = { sistema: 'Sistema', claro: 'Claro', escuro: 'Escuro' };

export function lerParametros() {
  const p = new URLSearchParams(location.search);
  const cenario = CENARIOS.some((c) => c.id === p.get('cenario')) ? p.get('cenario') : CENARIOS[0].id;
  const tema = TEMAS.includes(p.get('tema')) ? p.get('tema') : 'sistema';
  return { cenario, tema };
}

function irPara(cenario, tema) {
  const destino = CENARIOS.find((c) => c.id === cenario);
  location.href = `?cenario=${encodeURIComponent(cenario)}&tema=${encodeURIComponent(tema)}${destino.rota}`;
}

export function montarBarra(o) {
  const { cenario, tema } = lerParametros();
  const seletor = h('select', { id: 'prototipo-cenario', onchange: (ev) => irPara(ev.currentTarget.value, o.temaAtual()) },
    CENARIOS.map((c) => h('option', { value: c.id, selected: c.id === cenario }, NOMES[c.id])));
  const temas = h('select', { id: 'prototipo-tema', onchange: (ev) => o.aoTema(ev.currentTarget.value) },
    TEMAS.map((t) => h('option', { value: t, selected: t === tema }, NOMES_TEMA[t])));
  const barra = h('aside', { class: 'prototipo', 'aria-label': 'Controles do protótipo' }, [
    h('span', { class: 'prototipo-marca' }, 'Protótipo'),
    h('span', { class: 'prototipo-campo' }, [h('label', { for: 'prototipo-cenario' }, 'Cenário'), seletor]),
    h('span', { class: 'prototipo-campo' }, [h('label', { for: 'prototipo-tema' }, 'Tema'), temas]),
    h('button', { type: 'button', onclick: o.aoAvancar }, 'Avançar o tempo'),
    h('span', { class: 'prototipo-dica' }, 'Setas ← → trocam o cenário'),
  ]);

  document.addEventListener('keydown', (ev) => {
    if (ev.key !== 'ArrowLeft' && ev.key !== 'ArrowRight') return;
    if (ev.target.closest && ev.target.closest('input, select, textarea, [role="tab"], dialog')) return;
    if (document.querySelector('dialog[open]')) return;
    const i = CENARIOS.findIndex((c) => c.id === cenario);
    const passo = ev.key === 'ArrowRight' ? 1 : -1;
    const proximo = CENARIOS[(i + passo + CENARIOS.length) % CENARIOS.length];
    irPara(proximo.id, o.temaAtual());
  });

  return { el: barra, sincronizarTema: (t) => { temas.value = t; } };
}
