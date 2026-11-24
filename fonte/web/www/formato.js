// Formatacao de dado de maquina (direcao.md, secao 7.2), no formato do pt-BR (Intl).
import { OCTETOS_IP, OCTETO_MAX, MAC_DIGITOS, RE_DATA_SERVIDOR, RE_NAO_HEX } from './constantes.js';
import { t } from './textos.js';

const LOCALE = 'pt-BR';
const FMT_DIA_HORA = new Intl.DateTimeFormat(LOCALE, { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
const FMT_DATA_HORA = new Intl.DateTimeFormat(LOCALE, { dateStyle: 'short', timeStyle: 'short' });
const FMT_HORA = new Intl.DateTimeFormat(LOCALE, { hour: '2-digit', minute: '2-digit' });
const FMT_NUMERO = new Intl.NumberFormat(LOCALE);

// Data do servidor (hora local da maquina) vira Date; fora do formato, null.
function dataDoServidor(q) {
  const m = RE_DATA_SERVIDOR.exec(String(q || ''));
  if (!m) return null;
  const [, ano, mes, dia, hh, mm, ss] = m;
  const d = new Date(+ano, +mes - 1, +dia, +hh, +mm, +(ss || 0));
  return isNaN(d) ? null : d;
}

function formatarData(q, fmt) {
  const d = dataDoServidor(q);
  return d ? fmt.format(d) : String(q || '');
}

export function dataCurta(q) {
  return formatarData(q, FMT_DIA_HORA);
}

export function dataHora(q) {
  return formatarData(q, FMT_DATA_HORA);
}

export function hora(data) {
  return FMT_HORA.format(data);
}

export function numero(v) {
  const n = Number(v);
  return v !== '' && v !== null && Number.isFinite(n) ? FMT_NUMERO.format(n) : String(v);
}

export function mac(m) {
  const n = String(m || '').toLowerCase().replace(RE_NAO_HEX, '');
  return n.length === MAC_DIGITOS ? n.match(/../g).join(':') : n;
}

// Para ordenar e contar IPs; fora de quatro partes, 0.
export function ipParaNumero(ip) {
  const p = String(ip || '').split('.').map(Number);
  return p.length === OCTETOS_IP ? p.reduce((acc, x) => acc * (OCTETO_MAX + 1) + x, 0) : 0;
}

// "1920x1080" vira "1920 × 1080".
export function resolucao(r) {
  return String(r).replace('x', t('formato.vezes'));
}
