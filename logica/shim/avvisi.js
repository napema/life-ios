// La conferma breve dei moduli: la disegna l'app nativa.
export function avviso(testo, o = {}) {
  globalThis.Nativo.avviso(String(testo), o.tipo === 'errore' || o.tono === 'male' ? 'errore' : 'info');
}
export function celebra(testo = '') {
  globalThis.Nativo.avviso(String(testo || 'Fatto'), 'festa');
}
export const chiudiAvviso = () => {};
