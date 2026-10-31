// Controlla che ogni funzione della logica chiamata dalle schermate Swift esista davvero nel bundle.
//   node ios/logica/controlla.mjs
import { readdirSync, readFileSync, statSync } from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const qui = path.dirname(fileURLToPath(import.meta.url));
const memoria = new Map();
const Nativo = {
  leggi: (k) => memoria.get(k),
  scrivi: (k, v) => memoria.set(k, v),
  togli: (k) => memoria.delete(k),
  chiavi: () => JSON.stringify([...memoria.keys()]),
  log: () => {},
  avviso: () => {},
  copia: () => {},
  uuid: () => crypto.randomUUID(),
  token: () => null,
  utente: () => null,
  configurazione: () => 'https://esempio.invalid',
  datiCambiati: () => {},
  tabella: () => '[]',
  scriviRighe: () => {},
  timer: () => 0,
  fermaTimer: () => {},
  fetch: (_u, _m, _h, _c, fatto) => fatto(200, '[]', null),
  base64: () => '',
};
const ambiente = { Nativo, Intl, Date, Math, JSON, Promise, Uint8Array, DataView, Int32Array };
ambiente.globalThis = ambiente;
vm.createContext(ambiente);
vm.runInContext(readFileSync(path.join(qui, '../Life/Risorse/logica.js'), 'utf8'), ambiente);

function file(dir) {
  return readdirSync(dir).flatMap((n) => {
    const p = path.join(dir, n);
    return statSync(p).isDirectory() ? file(p) : p.endsWith('.swift') ? [p] : [];
  });
}

const PREFISSI = { fin: 'finanze', abi: 'abitudini', tra: 'allenamenti', mob: 'mobilita', pas: 'pasti' };
const percorsi = new Map();
for (const f of file(path.join(qui, '../Life'))) {
  const testo = readFileSync(f, 'utf8');
  const nome = path.basename(f);
  for (const m of testo.matchAll(/\b(fin|abi|tra|mob|pas)\("([A-Za-z0-9_.]+)"/g)) percorsi.set(`${PREFISSI[m[1]]}.${m[2]}`, nome);
  for (const m of testo.matchAll(/\.(?:chiama|chiamaAsync)\("([A-Za-z0-9_.]+)"/g)) percorsi.set(m[1], nome);
  for (const m of testo.matchAll(/fin\(previsto \? "([^"]+)" : "([^"]+)"/g)) {
    percorsi.set(`finanze.${m[1]}`, nome);
    percorsi.set(`finanze.${m[2]}`, nome);
  }
}

let mancanti = 0;
for (const [p, nome] of [...percorsi].sort()) {
  let qui2 = ambiente.Logica;
  for (const k of p.split('.')) qui2 = qui2?.[k];
  if (qui2 === undefined) {
    mancanti++;
    console.log(`MANCA ${p}  (${nome})`);
  }
}
console.log(`${percorsi.size} chiamate controllate, ${mancanti} mancanti`);
process.exit(mancanti ? 1 : 0);
