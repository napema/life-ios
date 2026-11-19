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
  const senza = lista.filter((x) => !dati.conEsito(x.p));
  const restanti = senza.filter((x) => x.p.binario !== 'fisica').length;
  const obiettivo = cfg.mediaObiettivo ?? null;
  // On track: le prove in preparazione col loro stato, la frase, la nota e il requisito di oggi
  const mq = motore.quadro(oggi);
  const ontrack = mq.aperte.map((s) => ({
    id: s.id, titolo: s.titolo, tipo: s.tipo, stato: s.stato, nomeStato: s.stato ? ot.NOMI_STATO[s.stato] : null, colore: s.stato ? ot.COLORI_STATO[s.stato] : '#8E8E93',
    quando: ot.traGiorni(s.fraGiorni), frase: ot.frase(s), nota: ot.nota(s),
    fase: s.tipo === 'studio' ? s.fase : s.tipo === 'esercizio' ? 'test' : null, unitaTipo: s.tipo === 'studio' ? s.unitaTipo : s.tipo === 'esercizio' ? (s.misura === 'tempo' ? 'secondi' : 'ripetizioni') : null,
    richiesto: s.tipo === 'studio' ? s.richiestoOggi : null, fatteOggi: s.tipo === 'studio' ? s.fatteOggi : null, fatte: s.tipo === 'studio' ? s.fatte : null, totali: s.tipo === 'studio' ? s.totali : null,
  }));
  return {
    oggi,
    ontrack,
    conflitti: mq.conflitti.map((c) => c.testo),
    schema: mq.schema,
    daRegistrare: senza.filter((x) => x.giorno && x.giorno < oggi).map((x) => voce(x, oggi)),
    inArrivo: senza.filter((x) => !x.giorno || x.giorno >= oggi).map((x) => voce(x, oggi)),
    fatte: lista.filter((x) => dati.conEsito(x.p)).map((x) => voce(x, oggi)).reverse(),
    studio: riassunto(studio),
    fisiche: riassunto(fisiche),
    ciSonoFisiche: lista.some((x) => x.p.binario === 'fisica'),
    mediaEsami: dati.mediaEsami(),
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
export const obiettivo = (v) => dati.impostaConfig({ mediaObiettivo: v ?? null });
export const mmss = analisi.mmss;
/** Un avanzamento (pagine, capitoli…) per una prova, oggi. */
export const avanza = (id, unita) => dati.registraAvanzamento(id, Math.round(Number(unita) || 0), giornoCorrente(), 'manuale');
/** Le notifiche di oggi e di domani (l'app le programma come promemoria locali). */
export const notifiche = () => {
  const oggi = giornoCorrente();
  return [...motore.notifiche(oggi), ...motore.notifiche(ot.piu(oggi, 1))];
};
export { dati, ot };
