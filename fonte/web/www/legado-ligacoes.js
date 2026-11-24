// Transicao: sai nas frentes 4 e 5 do redesenho.
// Ligacoes dos eventos da marcacao (painel e ferramentas). O passo a passo e a
// Sessao ligam os proprios eventos (tela-inicio.js, tela-sessao.js).
import { t } from './textos.js';
import { HTTP, CONSULTA_APOS_ATUALIZAR_MS } from './constantes.js';
import {
  S, ganchos, $, exigir, comando, mostrarAviso, mostrarTelaFim,
} from './legado-estado.js';
import { carregarRegistro } from './legado-painel.js';

function temFila() {
  return !!(S.estado && S.estado.fila && S.estado.fila.itens && S.estado.fila.itens.length);
}

export function ligar() {
  // Painel.
  $('form-conectada').addEventListener('submit', (ev) => {
    ev.preventDefault();
    const f = ev.target.elements;
    comando('/api/fila/conectada', { porta: f.porta.value, canal: f.canal.value, ip: f.ip.value });
    f.porta.value = ''; f.canal.value = ''; f.ip.value = '';
    $('retomar').open = false;
  });
  $('form-vigia').addEventListener('submit', (ev) => {
    ev.preventDefault();
    const f = ev.target.elements;
    const ligado = !(S.estado && S.estado.vigia && S.estado.vigia.ligado);
    comando('/api/vigia', { ligado, broadcast: f.broadcast.checked });
  });
  // Bloco legado (retomada manual pelo IP, C7): decisao sem MAC, como antes.
  for (const b of document.querySelectorAll('[data-decisao]')) {
    b.addEventListener('click', () => {
      const acao = b.dataset.decisao;
      if (acao === 'pular' && !confirm(t('decisao.confirmar-pular'))) return;
      comando('/api/decisao', { acao });
    });
  }
  // Encerrar a fila (botao da fila): sem MAC; quem esta em curso termina.
  $('btn-encerrar-fila').addEventListener('click', () => {
    const itens = (S.estado && S.estado.fila && S.estado.fila.itens) || [];
    const pend = itens.filter((i) => i.Estado === 'pendente').length;
    if (!confirm(t('confirmar.encerrar-fila', { pend }))) return;
    comando('/api/decisao', { acao: 'encerrar' });
  });
  $('btn-registro-atualizar').addEventListener('click', carregarRegistro);

  // Ferramentas.
  $('form-sondar').addEventListener('submit', (ev) => { ev.preventDefault(); comando('/api/sondar', { ip: ev.target.elements.ip.value }); });
  $('btn-descobrir').addEventListener('click', () => comando('/api/descobrir'));
  $('btn-verificar').addEventListener('click', () => comando('/api/verificar'));

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
