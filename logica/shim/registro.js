// I moduli di ATLAS dentro l'app nativa: stessi contratti di src/atlas/registro.ts, senza React.
import * as finanze from '@atlas/finanze/contratto.js';
import * as abitudini from '@atlas/abitudini/contratto.js';
import * as allenamenti from '@atlas/allenamenti/contratto.js';
import * as mobilita from '@atlas/mobilita/contratto.js';
import * as pasti from '@atlas/pasti/contratto.js';
import * as sezione from '../../../src/atlas/moduli/sezione/contratto';
import * as rank from '../../../src/atlas/moduli/rank/contratto';

export const CONTRATTI = { finanze, abitudini, allenamenti, mobilita, pasti, sezione, rank };
export const MODULI_DATI = [
  { id: 'finanze', nome: 'Finanze' },
  { id: 'abitudini', nome: 'Abitudini' },
  { id: 'allenamenti', nome: 'Training' },
  { id: 'mobilita', nome: 'Mobilità' },
  { id: 'pasti', nome: 'Pasti' },
  { id: 'sezione', nome: 'Sezione' },
  { id: 'rank', nome: 'Rank' },
];
export const prendiContratto = async (id) => CONTRATTI[id] ?? null;
