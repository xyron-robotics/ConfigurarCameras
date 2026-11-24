// Transicao: sai nas frentes 3 a 5 do redesenho.
// Ligacoes dos eventos da marcacao (painel, ferramentas, opcoes) e a troca
// de tema. O passo a passo liga os proprios eventos (tela-inicio.js).
import { t } from './textos.js';
import { SECOES_ORDEM, HTTP, CONSULTA_APOS_ATUALIZAR_MS } from './constantes.js';
import {
  S, ganchos, $, exigir, comando, mostrarAviso, mostrarTelaFim, conferirCampoIp,
} from './legado-estado.js';
import {
  atualizarPlaceholdersPc, escolherListaValor, desenharAvisosCamera, desenharEncoder, desenharPrevia,
  salvarSecao, carregarPlacas, mostrarSenha, enviarSenha, notaSenhaInstaladas, textoTrocarFila,
} from './legado-formularios.js';
import { carregarRegistro } from './legado-painel.js';

// Fechar ou recarregar a aba com secao editada e nao salva pede confirmacao.
// Nas telas de fim o servidor ja saiu: nao ha o que salvar.
function sairComSujo(ev) {
  if (!Object.values(S.sujo).some(Boolean)) return;
  if (!$('encerrado').hidden || !$('atualizando').hidden) return;
  ev.preventDefault();
  ev.returnValue = '';
}

function temFila() {
  return !!(S.estado && S.estado.fila && S.estado.fila.itens && S.estado.fila.itens.length);
}

export function ligar() {
  window.addEventListener('beforeunload', sairComSujo);

  // Formularios de Opcoes (a Sessao de hoje).
  for (const secao of SECOES_ORDEM) {
    const form = $('form-' + secao);
    form.addEventListener('submit', (ev) => {
      ev.preventDefault();
      if (secao === 'senha') { enviarSenha(form).then((ok) => { if (ok) notaSenhaInstaladas(); }); return; }
      if (secao === 'fila') {
        const f = form.elements;
        const troca = textoTrocarFila();
        if (troca && !confirm(troca)) return;
        comando('/api/fila', { inicio: f.inicio.value, fim: f.fim.value, local: f.local.value, rack: f.rack.value, andar: f.andar.value });
        S.sujo.fila = false;
        return;
      }
      salvarSecao(secao);
    });
    form.addEventListener('input', (ev) => {
      S.sujo[secao] = true;
      const ok = form.querySelector('[data-ok]'); if (ok) ok.hidden = true;
      if (secao === 'rede' || secao === 'fabrica') atualizarPlaceholdersPc();
      // Lista de bitrates so muda com resolucao ou codec.
      if (secao === 'camera') {
        if (ev.target.matches('select.lista-valor')) { escolherListaValor(ev.target); desenharAvisosCamera(); }
        else if (ev.target.tagName === 'SELECT') desenharEncoder();
        else desenharAvisosCamera();
      }
      if (secao === 'fila') desenharPrevia();
      if (secao === 'senha') $('senha-erro').hidden = true;
    });
  }
  for (const c of document.querySelectorAll('input[data-ip]')) c.addEventListener('input', () => conferirCampoIp(c));
  $('btn-placas-atualizar').addEventListener('click', () => carregarPlacas(true));
  $('btn-senha-mostrar').addEventListener('click', () => {
    mostrarSenha($('btn-senha-mostrar').getAttribute('aria-pressed') !== 'true');
  });

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

  // Sessao > Painel.
  $('btn-restaurar').addEventListener('click', () => {
    if (confirm(t('confirmar.restaurar'))) comando('/api/rede/restaurar');
  });
  $('btn-refazer').addEventListener('click', () => {
    if (!confirm(t('confirmar.refazer', { temFila: temFila() }))) return;
    comando('/api/sessao/refazer');
  });

  $('btn-atualizar').addEventListener('click', async () => {
    if (!confirm(t('confirmar.atualizar', { temFila: temFila() }))) return;
    try { await exigir(S.api.comando('/api/atualizar', {})); mostrarAviso(''); } catch (e) { mostrarAviso(e.message, null, { neutro: e.status === HTTP.CONFLITO }); }
    setTimeout(ganchos.buscarEstado, CONSULTA_APOS_ATUALIZAR_MS);
  });

  $('btn-encerrar').addEventListener('click', async () => {
    const e = S.estado;
    let texto = t('confirmar.encerrar');
    if (e && e.fase === 'configurando') texto = t('confirmar.encerrar-configurando');
    else if (e && e.ocupado) texto = t('confirmar.encerrar-ocupado');
    if (e && e.rede && e.rede.preparada) texto += t('confirmar.encerrar-dhcp');
    if (!confirm(texto)) return;
    let r = {};
    try { r = await exigir(S.api.comando('/api/encerrar', {})); } catch (_) { /* o servidor fecha junto */ }
    telaEncerrado(!!r.restaurando);
  });
}

// Tela de fim do "Encerrar o painel" (topo e Sessao > Painel).
export function telaEncerrado(restaurando) {
  if (restaurando) $('encerrado-texto').textContent = t('fim.encerrado-restaurando');
  mostrarTelaFim('encerrado');
}

// ------------------------------------------------------------------ tema
// O servidor ja entrega o <html> com data-tema (sem flash). Aqui so a troca
// em Opcoes: atributo + metas theme-color na hora, e PUT /api/tema para a
// proxima abertura (a porta muda; localStorage nao serve).
const MEDIA_TEMA = { claro: '(prefers-color-scheme: light)', escuro: '(prefers-color-scheme: dark)' };
function aplicarTema(v) {
  const tema = MEDIA_TEMA[v] ? v : 'sistema';
  document.documentElement.dataset.tema = tema;
  for (const m of document.querySelectorAll('meta[data-tema-cor]')) {
    const dela = m.dataset.temaCor;
    m.media = tema === 'sistema' ? MEDIA_TEMA[dela] : (dela === tema ? 'all' : 'not all');
  }
  for (const r of document.querySelectorAll('input[name="tema"]')) r.checked = r.value === tema;
  return tema;
}

export function ligarTema() {
  aplicarTema(document.documentElement.dataset.tema);
  $('tema').addEventListener('change', async (ev) => {
    const anterior = document.documentElement.dataset.tema;
    const novo = aplicarTema(ev.target.value);
    try { await exigir(S.api.tema(novo)); } catch (e) {
      aplicarTema(anterior);
      mostrarAviso(t('opcoes.tema-erro', { erro: e.message }), 'painel');
    }
  });
}
