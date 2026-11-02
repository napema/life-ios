// Prova il bundle fuori dall'iPhone: stesso `Nativo` di Logica.swift, in memoria.
//   node ios/logica/prova.mjs
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const qui = path.dirname(fileURLToPath(import.meta.url));
const memoria = new Map();
const timer = new Map();
let prossimo = 1;
const log = [];

const Nativo = {
  leggi: (k) => memoria.get(k),
  scrivi: (k, v) => memoria.set(k, v),
  togli: (k) => memoria.delete(k),
  chiavi: () => JSON.stringify([...memoria.keys()]),
  log: (t) => log.push(t),
  avviso: (t, tipo) => log.push(`avviso ${tipo}: ${t}`),
  copia: () => {},
  uuid: () => crypto.randomUUID(),
  token: () => null,
  utente: () => null, // senza utente: i canali restano spenti, i dati sono solo locali
  configurazione: (k) => (k === 'url' ? 'https://esempio.invalid' : 'chiave'),
  datiCambiati: () => log.push('dati cambiati'),
  tabella: () => '[]',
  scriviRighe: () => {},
  timer: (ms, ripeti, fn) => {
    const id = prossimo++;
    timer.set(id, (ripeti ? setInterval : setTimeout)(fn, ms));
    return id;
  },
  fermaTimer: (id) => {
    clearTimeout(timer.get(id));
    timer.delete(id);
  },
  fetch: (_u, _m, _h, _c, fatto) => fatto(200, '[]', null),
};

const ambiente = { Nativo, Intl, Date, Math, JSON, Promise, Uint8Array, DataView, Int32Array };
ambiente.globalThis = ambiente;
const ctx = vm.createContext(ambiente);
vm.runInContext(readFileSync(path.join(qui, '../Life/Risorse/logica.js'), 'utf8'), ctx);

const chiama = (p, ...a) => {
  const r = JSON.parse(ambiente.__chiama(p, JSON.stringify(a)));
  if (r.errore) throw new Error(`${p}: ${r.errore}`);
  return r.ok;
};

let errori = 0;
const prova = (nome, f) => {
  try {
    const r = f();
    console.log(`ok  ${nome}: ${JSON.stringify(r)?.slice(0, 110)}`);
  } catch (e) {
    errori++;
    console.log(`NO  ${nome}: ${e.message}`);
  }
};

ambiente.__avvia();
prova('parser', () => chiama('parser.parseTask', 'chiamare Luca domani alle 15 !2', {}));
prova('ricorrenze', () => chiama('ricorrenze.describeRrule', 'FREQ=WEEKLY;BYDAY=MO'));
prova('home.oggi', () => Object.keys(chiama('home.oggi')));
prova('home.quadro', () => chiama('home.quadro').verdetto);
prova('finanze: pocket', () => chiama('finanze.calcolo.pocketConSaldi').length);
prova('finanze: ricarica', () => chiama('finanze.calcolo.finoAllaRicarica').giorni);
prova('finanze: stipendio', () => chiama('finanze.stipendio.stipendioAtteso').importo);
prova('finanze: nuovo movimento', () => {
  chiama('finanze.dati.salvaMovimento', { id: 'm_prova', data: chiama('ui.oggiISO'), tipo: 'out', imp: 1250, nota: 'Prova', cat: null, sub: null, rif: null, ecc: false, pocket: 'principale', pocketTo: null });
  return chiama('finanze.dati.movimentiVivi').length;
});
prova('abitudini: giornata', () => chiama('abitudini.calcolo.giornataOggi'));
prova('allenamenti: test', () => [chiama('allenamenti.dati.dataTest'), chiama('allenamenti.calcolo.giorniRimasti')]);
prova('allenamenti: analisi', () => chiama('allenamenti.analisi.limitiZone'));
prova('mobilita: sessione', () => chiama('mobilita.sessione.oggiISO'));
prova('pasti: bersagli', () => chiama('pasti.calcolo.bersagli'));
prova('persistenza', () => [...memoria.keys()].filter((k) => k.startsWith('atlas.')));
console.log(log.filter((l) => l.includes('errore')).slice(0, 10).join('\n'));
// Sezione: organico, un'assenza dalle 11:55 alle 13:30, il messaggio delle 07:15
prova('sezione: aggiungi', () => {
  chiama('sezione.dati.aggiungiPax', [{ grado: 'S.Ten.', cognome: 'ROSSI', nome: 'Mario' }, { grado: 'S.Ten.', cognome: "D'ESEMPIO", nome: 'Luca' }]);
  return chiama('sezione.dati.organico').length;
});
prova('sezione: fascia oraria', () => {
  const [p] = chiama('sezione.dati.organico');
  const g = chiama('ui.oggiISO');
  chiama('sezione.dati.impostaStato', p.id, g, 'A', { motivo: 'Altra attività', frase: 'impegnato in altra attività', oraDal: '11:55', oraAl: '13:30', al: g });
  const alle12 = chiama('sezione.dati.forza', g, 12 * 60).assenti.length;
  const alle10 = chiama('sezione.dati.forza', g, 10 * 60).assenti.length;
  if (alle12 !== 1 || alle10 !== 0) throw new Error(`assenti alle 12 ${alle12}, alle 10 ${alle10}`);
  return { alle12, alle10 };
});
prova('sezione: messaggio', () => {
  const m = chiama('sezione.dati.messaggio', chiama('ui.oggiISO'));
  if (!m.includes('Forza presente della sezione: 1 Ufficiale Frequentatore') || !m.includes('ROSSI Mario impegnato in altra attività dalle 11:55 alle 13:30')) throw new Error(m);
  return m.split(String.fromCharCode(10)).slice(9, 11);
});

console.log(errori ? `${errori} prove fallite` : 'tutte le prove passate');
process.exit(errori ? 1 : 0);
