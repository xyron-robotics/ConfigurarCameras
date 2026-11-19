// Formatacao de dado de maquina (direcao.md, secao 7.2).
import { OCTETOS_IP, OCTETO_MAX } from './constantes.js';

const LOCALE = 'pt-BR';
const numero = new Intl.NumberFormat(LOCALE);
const relogio = new Intl.DateTimeFormat(LOCALE, { hour: '2-digit', minute: '2-digit', second: '2-digit' });

export function ip(texto) {
  return String(texto || '').trim();
}

export function ipParaNumero(texto) {
  const partes = ip(texto).split('.').map(Number);
  if (partes.length !== OCTETOS_IP || partes.some((p) => !Number.isInteger(p) || p < 0 || p > OCTETO_MAX)) return null;
  return partes.reduce((acc, p) => acc * (OCTETO_MAX + 1) + p, 0);
}

export function numeroParaIp(n) {
  const partes = [];
  let resto = n;
  for (let i = 0; i < OCTETOS_IP; i += 1) {
    partes.unshift(resto % (OCTETO_MAX + 1));
    resto = Math.floor(resto / (OCTETO_MAX + 1));
  }
  return partes.join('.');
}

export function mac(texto) {
  const limpo = String(texto || '').replace(/[^0-9a-f]/gi, '').toUpperCase();
  return limpo.match(/.{1,2}/g)?.join(':') || '';
}

export function hora(data) {
  return relogio.format(data instanceof Date ? data : new Date(data));
}

export function inteiro(n) {
  return numero.format(n);
}
