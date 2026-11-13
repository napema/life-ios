// La parte di src/atlas/viste/finanze/Stipendio.tsx che non disegna: identica a quella.
import { cicloDi, prossimoStipendio } from '@atlas/finanze/calcolo.js';
import { movimentiVivi, stato } from '@atlas/finanze/dati.js';
import { oggiISO, piuGiorni } from '../../../src/atlas/core/ui';

export const IMPORTO_STIPENDIO_BASE = 0; // il valore vero è nella configurazione dell'account
export const importoStipendio = () => Number(stato().config?.importoStipendio) || IMPORTO_STIPENDIO_BASE;
/** L'importo di uno stipendio preciso: quello messo per quella data, se c'è, altrimenti quello di sempre. */
export const importoDi = (data) => Number(stato().config?.importiStipendio?.[data]) || importoStipendio();

export function registrato(data) {
  const da = piuGiorni(data, -6);
  const a = piuGiorni(data, 6);
  return movimentiVivi().some((m) => m.tipo === 'in' && m.stip && m.data >= da && m.data <= a);
}

export function stipendioAtteso(oggi = oggiISO()) {
  const questo = cicloDi(oggi).da;
  const data = questo <= oggi && !registrato(questo) ? questo : prossimoStipendio(oggi);
  const fra = Math.round((Date.parse(data) - Date.parse(oggi)) / 86_400_000);
  return { data, fra, importo: importoDi(data), solito: importoStipendio(), soloQuesto: Boolean(Number(stato().config?.importiStipendio?.[data])), dovuto: fra <= 0 };
}
