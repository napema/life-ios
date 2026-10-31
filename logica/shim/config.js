// URL e chiave pubblica di Supabase (le mette il lato nativo: Config.swift)
export const CONFIG = {
  get supabaseUrl() {
    return globalThis.Nativo.configurazione('url');
  },
  get supabaseKey() {
    return globalThis.Nativo.configurazione('chiave');
  },
};
export const getConfig = () => ({ supabaseUrl: CONFIG.supabaseUrl, supabaseKey: CONFIG.supabaseKey });
export const isTauri = false;
export const isIOS = true;
export const isStandalone = true;
