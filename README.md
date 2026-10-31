# Life per iPhone

L'app nativa di Life, in SwiftUI. I dati sono gli stessi del sito e dell'app di Windows (Supabase);
la logica di Finanze, Abitudini, Training, Mobilità e Pasti è quella del sito, nel file
`Life/Risorse/logica.js`, che gira dentro l'app con JavaScriptCore.

## Installazione (una volta sola, circa 15 minuti)

Serve il PC con Windows e il cavo dell'iPhone solo per questa prima volta.

1. Su iPhone: **Impostazioni → Privacy e sicurezza → Modalità sviluppatore**, accendila e riavvia.
2. Installa **LocalDevVPN** dall'App Store.
3. Sul PC installa **iTunes** ([dal Microsoft Store](https://apple.co/ms), serve a Windows per vedere l'iPhone) e **iloader** ([download per Windows](https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.exe)). Collega l'iPhone col cavo, tocca **Autorizza** sul telefono, apri iloader, accedi con l'Apple ID, scegli il telefono e poi **Install SideStore**.
4. Su iPhone: **Impostazioni → Generali → VPN e gestione dispositivo**, tocca il tuo account e autorizzalo.
5. Accendi **LocalDevVPN**, apri **SideStore** e accedi con lo stesso Apple ID.
6. In SideStore, scheda **My Apps**, tocca il contatore **7 DAYS** per il primo rinnovo.
7. Installa Life: scarica `Life.ipa` dall'indirizzo qui sotto, poi in SideStore tocca **+** e sceglilo.
8. Apri Life e accedi con la tua email (codice o password, come sul sito).

Indirizzi:

- IPA: `https://github.com/napema/life-ios/releases/download/ultima/Life.ipa`
- Sorgente per SideStore: `https://github.com/napema/life-ios/releases/download/ultima/sorgente.json`

## Rinnovo ogni 7 giorni

SideStore rinnova da solo in background, se **LocalDevVPN è accesa** e c'è il Wi-Fi. Se salta, apri
SideStore e tocca il contatore. Se la firma scade Life non si apre finché non rinnovi, ma i dati
restano su Supabase.

## Aggiornamenti

Ogni modifica pubblicata su `main` viene compilata da GitHub e pubblicata nella release `ultima`.
In SideStore compare **Update** se hai aggiunto la sorgente; altrimenti riscarichi l'IPA e lo riapri
con SideStore, che lo installa sopra quello che c'è.

## Notifiche

Con un Apple ID gratuito Apple non concede le push da server: i promemoria sono notifiche locali,
programmate a ogni sincronizzazione (le 60 più vicine). Quelli creati dal PC arrivano sull'iPhone
quando apri Life o quando iOS le concede di aggiornarsi in background.

## Sviluppo

- `node ios/logica/costruisci.mjs`: ricostruisce `logica.js` e `Config.swift` dal codice del sito.
- `node ios/logica/prova.mjs`: prova la logica senza iPhone.
- `node ios/logica/controlla.mjs`: controlla che ogni funzione chiamata dallo Swift esista.
- Il progetto Xcode si genera da `project.yml` con XcodeGen, sul Mac di GitHub (`.github/workflows/compila.yml`).
