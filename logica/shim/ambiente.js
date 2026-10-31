// L'ambiente che la logica di Life si aspetta da un browser, sopra JavaScriptCore.
// Il lato nativo (Logica.swift, o prova.mjs in Node) mette `Nativo` prima di caricare il bundle:
//   Nativo.leggi(chiave) / scrivi(chiave, valore) / togli(chiave) / chiavi()   la memoria locale
//   Nativo.fetch(url, metodo, headersJson, corpo, fatto)                       la rete
//   Nativo.timer(ms, ripeti, fn) -> id / Nativo.fermaTimer(id)                 i timer
//   Nativo.avviso(testo, tipo) / Nativo.log(testo)
//   Nativo.tabella(nome) / Nativo.scriviRighe(nome, json)                      calendari ed eventi
const g = globalThis;
const N = g.Nativo;

g.console = {
  log: (...a) => N.log(a.map(String).join(' ')),
  info: (...a) => N.log(a.map(String).join(' ')),
  warn: (...a) => N.log('[warn] ' + a.map(String).join(' ')),
  error: (...a) => N.log('[errore] ' + a.map((x) => (x && x.stack) || String(x)).join(' ')),
  debug: () => {},
};

g.localStorage = {
  getItem: (k) => {
    const v = N.leggi(String(k));
    return v === undefined || v === null ? null : String(v);
  },
  setItem: (k, v) => N.scrivi(String(k), String(v)),
  removeItem: (k) => N.togli(String(k)),
  key: (i) => JSON.parse(N.chiavi())[i] ?? null,
  get length() {
    return JSON.parse(N.chiavi()).length;
  },
};

g.setTimeout = (fn, ms = 0, ...a) => N.timer(Number(ms) || 0, false, () => fn(...a));
g.setInterval = (fn, ms = 0, ...a) => N.timer(Number(ms) || 0, true, () => fn(...a));
g.clearTimeout = g.clearInterval = (id) => {
  if (id !== undefined && id !== null) N.fermaTimer(id);
};
if (!g.queueMicrotask) g.queueMicrotask = (fn) => void Promise.resolve().then(fn);
if (!g.structuredClone) g.structuredClone = (v) => (v === undefined ? v : JSON.parse(JSON.stringify(v)));

const ascoltatori = {};
g.document = {
  hidden: false,
  visibilityState: 'visible',
  activeElement: null,
  body: { append() {}, appendChild() {} },
  addEventListener: (e, f) => void (ascoltatori[e] ||= []).push(f),
  removeEventListener: (e, f) => void (ascoltatori[e] = (ascoltatori[e] || []).filter((x) => x !== f)),
  dispatchEvent: (ev) => {
    for (const f of ascoltatori[ev.type] || []) {
      try {
        f(ev);
      } catch (e) {
        console.error(e);
      }
    }
    return true;
  },
  getElementById: () => null,
  createElement: () => ({ style: {}, click() {}, remove() {}, append() {}, appendChild() {} }),
  querySelector: () => null,
};
g.CustomEvent = class {
  constructor(type, o = {}) {
    this.type = type;
    this.detail = o.detail;
  }
};
g.window = g;
g.addEventListener = (e, f) => g.document.addEventListener(e, f);
g.removeEventListener = (e, f) => g.document.removeEventListener(e, f);
g.navigator = { onLine: true, userAgent: 'Life iOS', platform: 'iPhone', clipboard: { writeText: async (t) => N.copia(String(t)) } };

// Il telefono torna in primo piano (o va in background): lo dice il lato nativo
g.__visibile = (si) => {
  g.document.hidden = !si;
  g.document.visibilityState = si ? 'visible' : 'hidden';
  g.document.dispatchEvent(new g.CustomEvent('visibilitychange'));
};

// fetch essenziale: basta a ciò che serve (JSON verso Supabase)
g.fetch = (url, o = {}) =>
  new Promise((risolvi, rifiuta) => {
    N.fetch(String(url), o.method || 'GET', JSON.stringify(o.headers || {}), o.body ?? null, (stato, testo, errore) => {
      if (errore) return rifiuta(new Error(errore));
      risolvi({
        ok: stato >= 200 && stato < 300,
        status: stato,
        text: async () => testo,
        json: async () => JSON.parse(testo),
      });
    });
  });

// SHA-1 per l'id stabile degli eventi del ponte Training ↔ Calendario (stesso risultato di WebCrypto)
function sha1(b) {
  const r = (x, n) => (x << n) | (x >>> (32 - n));
  const l = b.length;
  const m = new Uint8Array(((l + 9 + 63) >> 6) << 6);
  m.set(b);
  m[l] = 0x80;
  new DataView(m.buffer).setUint32(m.length - 4, l * 8);
  const d = new DataView(m.buffer);
  let h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;
  const w = new Int32Array(80);
  for (let o = 0; o < m.length; o += 64) {
    for (let i = 0; i < 16; i++) w[i] = d.getInt32(o + i * 4);
    for (let i = 16; i < 80; i++) w[i] = r(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    let a = h0, b_ = h1, c = h2, e = h3, f = h4;
    for (let i = 0; i < 80; i++) {
      const [ff, k] = i < 20 ? [(b_ & c) | (~b_ & e), 0x5a827999] : i < 40 ? [b_ ^ c ^ e, 0x6ed9eba1] : i < 60 ? [(b_ & c) | (b_ & e) | (c & e), 0x8f1bbcdc] : [b_ ^ c ^ e, 0xca62c1d6];
      const t = (r(a, 5) + ff + f + k + w[i]) | 0;
      f = e;
      e = c;
      c = r(b_, 30);
      b_ = a;
      a = t;
    }
    h0 = (h0 + a) | 0;
    h1 = (h1 + b_) | 0;
    h2 = (h2 + c) | 0;
    h3 = (h3 + e) | 0;
    h4 = (h4 + f) | 0;
  }
  const out = new Uint8Array(20);
  const v = new DataView(out.buffer);
  [h0, h1, h2, h3, h4].forEach((x, i) => v.setInt32(i * 4, x));
  return out;
}
if (!g.TextEncoder) {
  g.TextEncoder = class {
    encode(s) {
      const u = unescape(encodeURIComponent(String(s)));
      return Uint8Array.from(u, (c) => c.charCodeAt(0));
    }
  };
}
g.crypto = g.crypto || {
  subtle: { digest: async (_alg, dati) => sha1(new Uint8Array(dati)).buffer },
  randomUUID: () => N.uuid(),
  getRandomValues: (a) => {
    for (let i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 256);
    return a;
  },
};
