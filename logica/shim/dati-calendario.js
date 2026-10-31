// Calendari ed eventi per il ponte Training ↔ Calendario: stanno nell'archivio nativo.
const tabella = (nome) => ({ toArray: async () => JSON.parse(globalThis.Nativo.tabella(nome) || '[]') });
export const db = { calendars: tabella('calendars'), events: tabella('events') };

export async function queueWrite(nome, righe) {
  globalThis.Nativo.scriviRighe(nome, JSON.stringify(Array.isArray(righe) ? righe : [righe]));
}

// Il nativo avvisa quando gli eventi cambiano
const iscritti = new Set();
export const liveQuery = () => ({
  subscribe: ({ next }) => {
    iscritti.add(next);
    return { unsubscribe: () => iscritti.delete(next) };
  },
});
globalThis.__eventiCambiati = () => iscritti.forEach((f) => f());
