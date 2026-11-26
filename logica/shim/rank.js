// Rank nell'app iOS: lo stesso modulo del sito (moduli/rank), e un «quadro» già calcolato
// così la schermata SwiftUI deve solo disegnare. Le proposte dal calendario si confermano dal sito.
import * as dati from '../../../src/atlas/moduli/rank/dati';
import * as analisi from '../../../src/atlas/moduli/rank/analisi';
import { giornoDi } from '../../../src/atlas/moduli/rank/contratto';
import { giornoCorrente } from '../../../src/atlas/core/contesto';
import * as motore from '../../../src/atlas/moduli/rank/motore';
import * as ot from '../../../src/atlas/moduli/rank/ontrack';

const giorni = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 86_400_000);

function voce(x, oggi) {
  const p = x.p;
  return {
    id: p.id, titolo: p.titolo, binario: p.binario, giorno: x.giorno, ora: p.ora,
    fra: x.giorno ? giorni(oggi, x.giorno) : null,
    voto: p.voto, risultato: p.risultato, obiettivo: p.obiettivo, note: p.note, esito: dati.conEsito(p),
    esitoIl: p.esitoIl,
  };
}

function riassunto(s) {
  return {
    voti: s.voti.map((x) => ({ id: x.p.id, titolo: x.p.titolo, v: x.v, voto: x.p.voto, giorno: x.giorno, i: x.i, retta: s.retta ? s.retta(x.i) : null })),
    media: s.media, pendenza: s.pendenza, scarto: s.scarto,
  };
}

export function quadro() {
  const oggi = giornoCorrente();
  const lista = dati.prove().map((p) => ({ p, giorno: giornoDi(p) })).sort((a, b) => (a.giorno ?? '9999').localeCompare(b.giorno ?? '9999'));
  const studio = analisi.analisiVoti(lista);
  const fisiche = analisi.analisiVoti(lista, true);
  const c = analisi.analisiCorsa(oggi);
  const cfg = dati.config();
  const lode = cfg.lode ?? 30;
  const senza = lista.filter((x) => !dati.conEsito(x.p));
  const restanti = senza.filter((x) => x.p.binario !== 'fisica').length;
  const obiettivo = cfg.mediaObiettivo ?? null;
  const valore = (v) => (v >= 31 ? lode : v);

  const conVoto = lista.filter((x) => x.p.voto != null);
  const mediaTutti = conVoto.length ? conVoto.reduce((t, x) => t + valore(x.p.voto), 0) / conVoto.length : null;
  const mediaPer = (b) => {
    const sub = conVoto.filter((x) => x.p.binario === b);
    return { media: sub.length ? sub.reduce((t, x) => t + valore(x.p.voto), 0) / sub.length : null, n: sub.length };
  };

  // On track: le prove in preparazione col loro stato, la frase, la nota e il requisito di oggi
  const mq = motore.quadro(oggi);
  const ontrack = mq.aperte.map((s) => ({
    id: s.id, titolo: s.titolo, tipo: s.tipo, stato: s.stato, nomeStato: s.stato ? ot.NOMI_STATO[s.stato] : null, colore: s.stato ? ot.COLORI_STATO[s.stato] : '#8E8E93',
    quando: ot.traGiorni(s.fraGiorni), frase: ot.frase(s), nota: ot.nota(s),
    fase: s.tipo === 'studio' ? s.fase : s.tipo === 'esercizio' ? 'test' : null, unitaTipo: s.tipo === 'studio' ? s.unitaTipo : s.tipo === 'esercizio' ? (s.misura === 'tempo' ? 'secondi' : 'ripetizioni') : null,
    richiesto: s.tipo === 'studio' ? s.richiestoOggi : null, fatteOggi: s.tipo === 'studio' ? s.fatteOggi : null, fatte: s.tipo === 'studio' ? s.fatte : null, totali: s.tipo === 'studio' ? s.totali : null,
  }));

  const inArrivoLista = senza.filter((x) => !x.giorno || x.giorno >= oggi);

  return {
    oggi,
    lode,
    ontrack,
    conflitti: mq.conflitti.map((x) => x.testo),
    schema: mq.schema,
    daRegistrare: senza.filter((x) => x.giorno && x.giorno < oggi).map((x) => voce(x, oggi)),
    inArrivo: inArrivoLista.map((x) => voce(x, oggi)),
    fatte: lista.filter((x) => dati.conEsito(x.p)).map((x) => voce(x, oggi)).reverse(),
    studio: riassunto(studio),
    fisiche: riassunto(fisiche),
    ciSonoFisiche: lista.some((x) => x.p.binario === 'fisica'),
    mediaTutti,
    totaleVoti: conVoto.length,
    mediaEsami: dati.mediaEsami(),
    mediaAccertamenti: mediaPer('accertamento'),
    mediaFisiche: mediaPer('fisica'),
    obiettivo,
    restanti,
    traguardo: obiettivo ? analisi.cosaServe(studio.voti.map((x) => x.v), restanti, obiettivo) : null,
    corsa: c
      ? {
          stima: c.stima ? c.stima.secondi : null,
          obiettivo: c.obiettivo,
          ef: c.ef.length ? c.ef[c.ef.length - 1].ef : null,
          efPct: c.efPct,
          forma: c.forma, fitness: c.fitness, fatica: c.fatica, fitnessDelta: c.fitnessDelta,
          giorniSenza: c.giorniSenza, ultimaKm: c.ultima.km, ultimaSecondi: c.ultima.secondi,
          equiv: c.equiv.map((x) => ({ data: x.c.data, t5: x.t5 })),
          settimane: c.settimane,
          corse: c.corse.length,
        }
      : null,
  };
}

/** L'esito: voto (anche per le prove fisiche) e, per le fisiche, il tempo se te lo ricordi. */
export function registra(id, voto, tempo) {
  const t = (tempo || '').trim();
  dati.registraEsito(id, { voto: voto ?? null, risultato: t, risultatoNum: t ? dati.numeroRisultato(t) : null }, giornoCorrente());
}

/** Crea una nuova prova (o registra direttamente un voto passato) da iPhone. */
export function crea(binario, titolo, data, voto, risultato, note) {
  const t = String(titolo || '').trim();
  if (!t) return;
  const b = binario === 'esame' || binario === 'fisica' ? binario : 'accertamento';
  const base = dati.provaVuota(b);
  const g = String(data || '').trim() || giornoCorrente();
  const r = String(risultato || '').trim();
  const haEsito = voto != null || Boolean(r);
  dati.salvaProva({
    ...base,
    titolo: t,
    materia: t,
    data: g,
    voto: voto ?? null,
    risultato: r,
    risultatoNum: r ? dati.numeroRisultato(r) : null,
    esitoIl: haEsito ? g : null,
    note: String(note || '').trim(),
  });
}

export const obiettivo = (v) => dati.impostaConfig({ mediaObiettivo: v ?? null });
export const impostaLode = (v) => dati.impostaConfig({ lode: Number(v) || 30 });
export const mmss = analisi.mmss;
/** Un avanzamento (pagine, capitoli…) per una prova, oggi. */
export const avanza = (id, unita) => dati.registraAvanzamento(id, Math.round(Number(unita) || 0), giornoCorrente(), 'manuale');
/** Le notifiche di oggi e di domani (l'app le programma come promemoria locali). */
export const notifiche = () => {
  const oggi = giornoCorrente();
  return [...motore.notifiche(oggi), ...motore.notifiche(ot.piu(oggi, 1))];
};
export { dati, ot };
