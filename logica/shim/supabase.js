// Il client Supabase che serve alla logica dei moduli: solo le poche chiamate che usa, via REST,
// con il token della sessione dell'app nativa (mai salvato qui).
import { CONFIG } from './config.js';

const base = () => `${CONFIG.supabaseUrl}/rest/v1`;
const headers = (extra = {}) => ({
  apikey: CONFIG.supabaseKey,
  Authorization: `Bearer ${globalThis.Nativo.token() || CONFIG.supabaseKey}`,
  'Content-Type': 'application/json',
  ...extra,
});

class Richiesta {
  constructor(tabella) {
    this.tabella = tabella;
    this.filtri = [];
    this.metodo = 'GET';
    this.corpo = null;
    this.prefer = [];
    this.h = {};
  }
  select(colonne = '*') {
    this.colonne = colonne;
    if (this.metodo !== 'GET') this.prefer.push('return=representation');
    return this;
  }
  eq(c, v) {
    this.filtri.push(`${c}=eq.${encodeURIComponent(v)}`);
    return this;
  }
  is(c, v) {
    this.filtri.push(`${c}=is.${v === null ? 'null' : v}`);
    return this;
  }
  order(c, o = {}) {
    this.ordine = `${c}.${o.ascending === false ? 'desc' : 'asc'}`;
    return this;
  }
  range(da, a) {
    this.h.Range = `${da}-${a}`;
    this.h['Range-Unit'] = 'items';
    return this;
  }
  update(riga) {
    this.metodo = 'PATCH';
    this.corpo = JSON.stringify(riga);
    return this;
  }
  upsert(righe, o = {}) {
    this.metodo = 'POST';
    this.corpo = JSON.stringify(righe);
    this.prefer.push('resolution=merge-duplicates');
    if (o.onConflict) this.conflitto = o.onConflict;
    return this;
  }
  async esegui() {
    const q = [...this.filtri];
    if (this.colonne) q.push(`select=${encodeURIComponent(this.colonne)}`);
    if (this.ordine) q.push(`order=${this.ordine}`);
    if (this.conflitto) q.push(`on_conflict=${this.conflitto}`);
    const url = `${base()}/${this.tabella}${q.length ? `?${q.join('&')}` : ''}`;
    try {
      const r = await fetch(url, {
        method: this.metodo,
        body: this.corpo,
        headers: headers({ ...this.h, ...(this.prefer.length ? { Prefer: this.prefer.join(',') } : {}) }),
      });
      const testo = await r.text();
      let dati = null;
      try {
        dati = testo ? JSON.parse(testo) : null;
      } catch {
        dati = null;
      }
      if (!r.ok) return { data: null, error: { message: dati?.message || `HTTP ${r.status}` } };
      return { data: dati, error: null };
    } catch (e) {
      return { data: null, error: { message: e?.message || String(e) } };
    }
  }
  then(ok, ko) {
    return this.esegui().then(ok, ko);
  }
}

// Il realtime non c'è: i moduli si aggiornano all'apertura, al ritorno in primo piano e ogni minuto
const canaleMuto = { on: () => canaleMuto, subscribe: () => canaleMuto };
const client = { from: (t) => new Richiesta(t), channel: () => canaleMuto };

export const supabase = () => client;

export function rememberedUser() {
  try {
    const u = globalThis.Nativo.utente();
    return u ? JSON.parse(u) : null;
  } catch {
    return null;
  }
}
export const rememberUser = () => {};
