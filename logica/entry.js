// Il bundle che gira dentro l'app iOS (JavaScriptCore): la logica di Life, la stessa del sito.
// Le schermate SwiftUI la chiamano con `__chiama("finanze.calcolo.pocketConSaldi", "[]")`.
import './shim/ambiente.js';

import * as abitudiniCalcolo from '@atlas/abitudini/calcolo.js';
import * as abitudiniDati from '@atlas/abitudini/dati.js';
import * as allenamentiAnalisi from '@atlas/allenamenti/analisi.js';
import * as allenamentiCalcolo from '@atlas/allenamenti/calcolo.js';
import * as allenamentiDati from '@atlas/allenamenti/dati.js';
import * as allenamentiFit from '@atlas/allenamenti/fit.js';
import * as allenamentiGarmin from '@atlas/allenamenti/garmin.js';
import * as allenamentiHevy from '@atlas/allenamenti/hevy.js';
import * as allenamentiImporta from '@atlas/allenamenti/importa.js';
import * as allenamentiMuscoli from '@atlas/allenamenti/muscoli.js';
import * as allenamentiPassi from '@atlas/allenamenti/passi.js';
import * as finanzeAnalisi from '@atlas/finanze/analisi.js';
import * as finanzeCalcolo from '@atlas/finanze/calcolo.js';
import * as finanzeChiusura from '@atlas/finanze/chiusura.js';
import * as finanzeDati from '@atlas/finanze/dati.js';
import * as finanzeEsporta from '@atlas/finanze/esporta.js';
import * as finanzeGruppi from '@atlas/finanze/gruppi.js';
import * as finanzeImporta from '@atlas/finanze/importa.js';
import * as finanzePaga from '@atlas/finanze/paga.js';
import * as finanzePesa from '@atlas/finanze/pesa.js';
import * as finanzePiano from '@atlas/finanze/piano.js';
import * as finanzeRevolut from '@atlas/finanze/revolut.js';
import * as finanzeTravasi from '@atlas/finanze/travasi.js';
import * as mobilitaClip from '@atlas/mobilita/clip.js';
import * as mobilitaDati from '@atlas/mobilita/dati.js';
import * as mobilitaEsercizi from '@atlas/mobilita/esercizi.js';
import * as mobilitaPonte from '@atlas/mobilita/ponte.js';
import * as mobilitaSessione from '@atlas/mobilita/sessione.js';
import * as pastiCalcolo from '@atlas/pasti/calcolo.js';
import * as pastiDati from '@atlas/pasti/dati.js';
import * as pastiImporta from '@atlas/pasti/importa.js';
import * as pastiPiano from '@atlas/pasti/piano.js';
import * as sezioneDati from '../../src/atlas/moduli/sezione/dati';
import * as rank from './shim/rank.js';

import * as ui from '../../src/atlas/core/ui';
import { ascolta, EVENTI } from '../../src/atlas/core/bus';
import { giornoCorrente } from '../../src/atlas/core/contesto';
import { osservaTutto } from '../../src/atlas/core/storage';
import { sincronizzaTutto } from '../../src/atlas/core/sync';
import { tinta } from '../../src/atlas/core/tinte';
import * as parser from '../../src/lib/parser/parse';
import * as ricorrenze from '../../src/lib/recurrence';
import * as calendarioDaTitolo from '../../src/lib/calendarioDaTitolo';
import { avviaPosta } from '../../src/atlas/posta';
import { avviaPonteTraining } from '../../src/atlas/ponteCalendario';
import { avviaRiepilogoClaude } from '../../src/atlas/riepilogoClaude';
import { CONTRATTI, MODULI_DATI } from './shim/registro.js';
import * as stipendio from './shim/stipendio.js';
import * as giornata from '../../src/atlas/viste/oggi/giornata';
import { ponteFinanze, scrittoreMeta } from './ponte.js';

/** La home: le carte di oggi di tutti i moduli e il quadro della giornata (come Launcher.tsx). */
function schede() {
  return MODULI_DATI.map((voce) => {
    let dati = null;
    try {
      dati = CONTRATTI[voce.id].oggi?.() ?? null;
    } catch (e) {
      console.error(`[home] ${voce.id}`, e); // un modulo che non risponde non ferma la home
    }
    return { voce, contratto: CONTRATTI[voce.id], dati };
  });
}
const home = {
  oggi: () => Object.fromEntries(schede().map((s) => [s.voce.id, s.dati])),
  quadro: () => {
    const q = giornata.quadro(schede());
    const { conDati: _c, fatti: _f, ...resto } = q;
    return { ...resto, verdetto: giornata.verdetto(q) };
  },
  saluto: giornata.saluto,
  costanza: giornata.costanza,
  fraseSerie: giornata.fraseSerie,
  /** Spunta una voce della giornata, come `fai` nel launcher. */
  fai: (v) => {
    const c = CONTRATTI[v.modulo];
    if (v.parti && v.parti.length > 1) c?.spuntaParti?.(v.habitId, v.parti);
    else if (v.parteId) c?.spuntaParte?.(v.habitId, v.parteId);
    else c?.spunta?.(v.habitId);
  },
};

function aPercorsoSuPosto(radice, percorso, valore) {
  let qui = radice;
  for (let i = 0; i < percorso.length - 1; i++) qui = qui[percorso[i]] ??= {};
  qui[percorso[percorso.length - 1]] = valore;
}

const L = {
  ui,
  tinta,
  parser,
  ricorrenze,
  calendarioDaTitolo,
  home,
  contratti: CONTRATTI,
  abitudini: { calcolo: abitudiniCalcolo, dati: abitudiniDati },
  allenamenti: {
    analisi: allenamentiAnalisi,
    calcolo: allenamentiCalcolo,
    dati: allenamentiDati,
    /** Un dato della corsa già formattato: le etichette del sito contengono funzioni. */
    dato: (chiave, valore) => {
      const e = allenamentiAnalisi.ETICHETTE[chiave];
      return e ? { nome: e.nome, valore: String(e.f(valore)), unita: e.unita ?? '' } : null;
    },
    /** Il .FIT dell'allenamento, in base64, da condividere dal lato nativo. */
    fitBase64: (nome, passi) => {
      const b = allenamentiFit.fileAllenamento(nome, passi);
      let t = '';
      for (const x of b) t += String.fromCharCode(x);
      return globalThis.btoa ? globalThis.btoa(t) : globalThis.Nativo.base64(t);
    },
    zonaColore: (fc) => allenamentiAnalisi.zonaDi(fc),
    garmin: allenamentiGarmin,
    hevy: allenamentiHevy,
    importa: allenamentiImporta,
    muscoli: allenamentiMuscoli,
    passi: allenamentiPassi,
  },
  finanze: {
    analisi: finanzeAnalisi,
    calcolo: finanzeCalcolo,
    chiusura: finanzeChiusura,
    dati: finanzeDati,
    esporta: finanzeEsporta,
    gruppi: finanzeGruppi,
    importa: finanzeImporta,
    paga: finanzePaga,
    pesa: finanzePesa,
    piano: finanzePiano,
    revolut: finanzeRevolut,
    stipendio,
    travasi: finanzeTravasi,
    indovina: (nota) => finanzeCalcolo.autoCategoria(nota, { normalizza: finanzeDati.normalizza, categoriaPerId: finanzeDati.categoriaPerId }) ?? null,
    ponte: ponteFinanze({ scriviMeta: finanzeDati.scriviMeta, scriviProfili: finanzeDati.scriviProfili, statoFn: finanzeDati.stato }),
  },
  mobilita: {
    /** Scrive un valore a un percorso dello stato piatto (updateState con una funzione, sul sito). */
    scrivi: (percorso, valore) => mobilitaPonte.updateState((s) => aPercorsoSuPosto(s, percorso, valore)),
    meta: (percorso, valore) => mobilitaDati.scriviMeta((m) => aPercorsoSuPosto(m, percorso, valore)),
    /** Le foto stanno nei file dell'app: qui solo il riferimento, come fa foto.js. */
    registraFoto: (bersaglioId, id) => {
      const dataISO = new Date().toISOString();
      mobilitaPonte.updateState((s) => {
        s.foto = s.foto || [];
        s.foto.push({ id, up: Date.now(), bersaglioId, data: dataISO, path: `foto/${id}.jpg`, caricata: false });
        s.assessment.baselineTest3.bersagli[bersaglioId].fotoData = dataISO;
        s.metaUp = Date.now();
      });
    },
    clip: mobilitaClip,
    dati: mobilitaDati, esercizi: mobilitaEsercizi, ponte: mobilitaPonte, sessione: mobilitaSessione },
  pasti: { calcolo: pastiCalcolo, dati: pastiDati, importa: pastiImporta, piano: pastiPiano },
  sezione: { dati: sezioneDati },
  rank,
};
globalThis.Logica = L;

// ─── Il ponte verso Swift ──────────────────────────────────────────────────

/** Solo dati: quello che non si serializza (funzioni, Map) sparisce; Set e Map diventano liste. */
const sostituto = (_k, v) => {
  if (typeof v === 'function') return undefined;
  if (v instanceof Set) return [...v];
  if (v instanceof Map) return Object.fromEntries(v);
  return v;
};

function trova(percorso) {
  const parti = percorso.split('.');
  let qui = L;
  let sopra = null;
  for (const p of parti) {
    if (qui === undefined || qui === null) throw new Error(`Non esiste: ${percorso}`);
    sopra = qui;
    qui = qui[p];
  }
  return [qui, sopra];
}

/** Chiama una funzione (o legge un valore) della logica. Risponde JSON: {ok} o {errore}. */
globalThis.__chiama = (percorso, argomenti) => {
  try {
    const [f, sopra] = trova(percorso);
    const a = argomenti ? JSON.parse(argomenti) : [];
    const r = typeof f === 'function' ? f.apply(sopra, a) : f;
    if (r && typeof r.then === 'function') {
      // Le risposte promesse le aspetta chi usa __chiamaAsync
      return JSON.stringify({ ok: null }, sostituto);
    }
    return JSON.stringify({ ok: r === undefined ? null : r }, sostituto);
  } catch (e) {
    console.error(`[${percorso}]`, e);
    return JSON.stringify({ errore: e?.message || String(e) });
  }
};

globalThis.__chiamaAsync = (percorso, argomenti, fatto) => {
  try {
    const [f, sopra] = trova(percorso);
    Promise.resolve(f.apply(sopra, argomenti ? JSON.parse(argomenti) : []))
      .then((r) => fatto(JSON.stringify({ ok: r === undefined ? null : r }, sostituto)))
      .catch((e) => fatto(JSON.stringify({ errore: e?.message || String(e) })));
  } catch (e) {
    fatto(JSON.stringify({ errore: e?.message || String(e) }));
  }
};

// Quando un dato cambia, le schermate si ridisegnano (un segnale solo, come useAtlas sul sito)
let toccoInArrivo = false;
function tocca() {
  if (toccoInArrivo) return;
  toccoInArrivo = true;
  queueMicrotask(() => {
    toccoInArrivo = false;
    globalThis.Nativo.datiCambiati();
  });
}
osservaTutto(tocca);
ascolta(EVENTI.GIORNO_CAMBIATO, tocca);
ascolta(EVENTI.DATI_ARRIVATI, tocca);

let avviato = false;
globalThis.__avvia = () => {
  if (avviato) return;
  avviato = true;
  for (const m of MODULI_DATI) {
    try {
      CONTRATTI[m.id].avviaSync?.({ ridisegna: tocca });
    } catch (e) {
      console.error(`[atlas] modulo "${m.id}" non avviato`, e);
    }
  }
  let lavagna;
  const pianificaLavagna = () => {
    clearTimeout(lavagna);
    lavagna = setTimeout(() => {
      for (const [id, c] of Object.entries(CONTRATTI)) {
        try {
          c.pubblicaSullaLavagna?.();
        } catch (e) {
          console.error(`[atlas] lavagna di "${id}"`, e);
        }
      }
    }, 50);
  };
  osservaTutto(pianificaLavagna);
  ascolta(EVENTI.DATI_ARRIVATI, pianificaLavagna);
  avviaPosta();
  avviaPonteTraining();
  avviaRiepilogoClaude();
};

globalThis.__sincronizza = () => sincronizzaTutto();
globalThis.__battito = () => {
  giornoCorrente();
  tocca();
};
