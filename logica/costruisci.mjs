// Costruisce ios/Life/Risorse/logica.js (la logica di Life per JavaScriptCore) e Config.swift.
//   node ios/logica/costruisci.mjs
// Da rilanciare quando cambia la logica dei moduli, prima di pubblicare l'app iOS.
import { build } from 'esbuild';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const qui = path.dirname(fileURLToPath(import.meta.url));
const radice = path.resolve(qui, '../..');
const src = path.join(radice, 'src');
const shim = (f) => path.join(qui, 'shim', f);

// Al posto di ciò che esiste solo nel browser (React, Dexie, supabase-js)
const SOSTITUTI = new Map([
  [path.join(src, 'lib/supabase'), shim('supabase.js')],
  [path.join(src, 'lib/config'), shim('config.js')],
  [path.join(src, 'atlas/core/avvisi'), shim('avvisi.js')],
  [path.join(src, 'atlas/registro'), shim('registro.js')],
  [path.join(src, 'atlas/viste/finanze/Stipendio'), shim('stipendio.js')],
  [path.join(src, 'data/db'), shim('dati-calendario.js')],
  [path.join(src, 'data/sync'), shim('dati-calendario.js')],
]);

const sostituzioni = {
  name: 'life-ios',
  setup(b) {
    b.onResolve({ filter: /^dexie$/ }, () => ({ path: shim('dati-calendario.js') }));
    b.onResolve({ filter: /^@atlas\// }, (a) => ({ path: path.join(src, 'atlas/moduli', a.path.slice(7)) }));
    b.onResolve({ filter: /^\.\.?\// }, (a) => {
      if (!a.resolveDir) return null;
      const assoluto = path.resolve(a.resolveDir, a.path);
      const senza = assoluto.replace(/\.(js|ts|tsx)$/, '');
      if (SOSTITUTI.has(senza)) return { path: SOSTITUTI.get(senza) };
      // I moduli importano «../../core/ui.js»: nel nucleo di Life è ui.ts
      if (assoluto.startsWith(path.join(src, 'atlas/core')) && assoluto.endsWith('.js') && existsSync(`${senza}.ts`)) return { path: `${senza}.ts` };
      return null;
    });
  },
};

await build({
  entryPoints: [path.join(qui, 'entry.js')],
  bundle: true,
  format: 'iife',
  target: 'es2020',
  platform: 'neutral',
  mainFields: ['module', 'main'],
  legalComments: 'none',
  minify: true,
  define: { 'import.meta.env.DEV': 'false', 'import.meta.env': '{}' },
  plugins: [sostituzioni],
  outfile: path.join(qui, '../Life/Risorse/logica.js'),
  logLevel: 'warning',
});

// La configurazione pubblica: l'URL e la chiave anon di Supabase, gli stessi che il sito ha nel bundle
const env = Object.fromEntries(
  readFileSync(path.join(radice, '.env.local'), 'utf8')
    .split(/\r?\n/)
    .map((r) => r.match(/^\s*([A-Z_]+)\s*=\s*"?([^"]*)"?\s*$/))
    .filter(Boolean)
    .map((m) => [m[1], m[2]]),
);
if (!env.VITE_SUPABASE_URL || !env.VITE_SUPABASE_ANON_KEY) throw new Error('Mancano VITE_SUPABASE_URL o VITE_SUPABASE_ANON_KEY in .env.local');
writeFileSync(
  path.join(qui, '../Life/Core/Config.swift'),
  `// Generato da ios/logica/costruisci.mjs. La chiave anon è pubblica: è la stessa del sito.
enum Config {
    static let supabaseUrl = "${env.VITE_SUPABASE_URL}"
    static let supabaseKey = "${env.VITE_SUPABASE_ANON_KEY}"
}
`,
);
console.log('logica.js e Config.swift pronti');
