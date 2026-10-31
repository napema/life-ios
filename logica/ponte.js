// Le scritture che sul sito passano una funzione (scriviMeta(fn), scriviProfili(fn)…): da Swift si
// può passare solo un dato, quindi si scrive un valore a un percorso, con le stesse funzioni di ATLAS.
function aPercorso(radice, percorso, valore) {
  let qui = radice;
  for (let i = 0; i < percorso.length - 1; i++) {
    const k = percorso[i];
    // Copie, come fa il sito: la fusione fra dispositivi confronta i blocchi
    qui[k] = Array.isArray(qui[k]) ? [...qui[k]] : { ...(qui[k] || {}) };
    qui = qui[k];
  }
  const ultimo = percorso[percorso.length - 1];
  if (valore === null || valore === undefined) delete qui[ultimo];
  else qui[ultimo] = valore;
}

export const scrittoreMeta = (scriviMeta) => (percorso, valore) => scriviMeta((s) => aPercorso(s, percorso, valore));

export function ponteFinanze({ scriviMeta, scriviProfili, statoFn }) {
  return {
    meta: scrittoreMeta(scriviMeta),
    profili: (percorso, valore) => scriviProfili((s) => aPercorso(s, percorso, valore)),
    /** «vita» acceso o spento su una categoria del profilo. */
    alternaVita: (chiave, catId) =>
      scriviProfili((st) => {
        const cc = new Set(st.profili[chiave].cassaCats);
        if (cc.has(catId)) cc.delete(catId);
        else cc.add(catId);
        st.profili[chiave].cassaCats = [...cc];
      }),
    /** La spunta del giorno di paga, con l'ora: si fonde fra dispositivi per ultima modifica. */
    spuntaPaga: (dataStip, id, on) =>
      scriviMeta((s) => {
        const m = { ...(s.config.pagaSpunte || {}) };
        m[dataStip] = { ...(m[dataStip] || {}), [id]: { on, t: Date.now() } };
        s.config.pagaSpunte = m;
      }),
    /** Le voci dell'obiettivo. */
    obiettivo: (campo, valore) =>
      scriviMeta((st) => {
        st.config.obiettivo = { ...(st.config.obiettivo || {}), [campo]: valore };
      }),
    soglia: (k, v) =>
      scriviMeta((st) => {
        st.soglie = { ...(st.soglie || {}), [k]: v };
      }),
    dimenticaRegole: () =>
      scriviMeta((st) => {
        st.rules = {};
      }),
    stato: () => statoFn(),
  };
}
