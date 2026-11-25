// Transicao: sai nas frentes 4 e 5 do redesenho.
// Ligacoes dos eventos da marcacao (o Atualizar do topo). O passo a passo, a
// Sessao e as Ferramentas ligam os proprios eventos (tela-*.js).
import { t } from './textos.js';
import { HTTP, CONSULTA_APOS_ATUALIZAR_MS } from './constantes.js';
import {
  S, ganchos, $, exigir, mostrarAviso, mostrarTelaFim,
} from './legado-estado.js';

function temFila() {
  return !!(S.estado && S.estado.fila && S.estado.fila.itens && S.estado.fila.itens.length);
}

export function ligar() {
  // Painel: o vigia, o Configurar sem vigia, a retomada pelo IP, o Encerrar a
  // fila e a decisao de toda falha (Pede voce) sao de tela-painel.js.

  // Ferramentas: tela-ferramentas.js liga os proprios eventos.

  $('btn-atualizar').addEventListener('click', async () => {
    if (!confirm(t('confirmar.atualizar', { temFila: temFila() }))) return;
    try { await exigir(S.api.comando('/api/atualizar', {})); mostrarAviso(''); } catch (e) { mostrarAviso(e.message, null, { neutro: e.status === HTTP.CONFLITO }); }
    setTimeout(ganchos.buscarEstado, CONSULTA_APOS_ATUALIZAR_MS);
  });
}

// Tela de fim do "Encerrar o painel" (topo).
export function telaEncerrado(restaurando) {
  if (restaurando) $('encerrado-texto').textContent = t('fim.encerrado-restaurando');
  mostrarTelaFim('encerrado');
}
