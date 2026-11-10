import BackgroundTasks
import SwiftUI
import WidgetKit

@main
struct LifeApp: App {
    @Environment(\.scenePhase) private var fase
    @StateObject private var rete = Rete.s
    @StateObject private var preferenze = Preferenze.s
    private let demo = ProcessInfo.processInfo.environment["LIFE_DEMO"]

    init() {
        // JavaScript e archivio si preparano in parallelo, fuori dal thread principale
        DispatchQueue.global(qos: .userInteractive).async { _ = Logica.s }
        DispatchQueue.global(qos: .userInteractive).async { _ = Archivio.s }
        Notifiche.s.avvia()
        Notifiche.s.registraAttivita()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if demo == "login" {
                    Accesso()
                } else if rete.connesso || demo != nil {
                    Radice(demo: demo).onAppear(perform: avvia)
                } else {
                    Accesso()
                }
            }
            .onOpenURL { url in
                if rete.connesso || demo != nil { Instradatore.s.apri(url: url) }
            }
            // I pulsanti dei widget (Uscita, Entrata, Nuovo task) arrivano da qui
            .onAppear {
                LinkLife.gestore = { url in
                    if Rete.s.connesso || ProcessInfo.processInfo.environment["LIFE_DEMO"] != nil { Instradatore.s.apri(url: url) }
                }
                if let u = LinkLife.prendiInAttesa() { LinkLife.gestore?(u) }
            }
            .preferredColorScheme(preferenze.aspetto == "light" ? .light : preferenze.aspetto == "dark" ? .dark : nil)
            .tint(.accentoLife)
        }
        .onChange(of: fase) { _, nuova in
            switch nuova {
            case .active:
                if let u = LinkLife.prendiInAttesa() { LinkLife.gestore?(u) }
                Logica.s.visibile(true)
                Logica.s.battito()
                Archivio.s.segnaEventiSporchi()
                Archivio.s.avvia()
                Notifiche.s.aggiornaPermesso()
                Task { await AggiornaLogica.controlla() }
                Task { await collegaWidget() }
            case .background:
                Logica.s.visibile(false)
                Archivio.s.ferma()
                Archivio.s.salvaOra()
                Logica.s.salvaMemoriaOra()
                Notifiche.s.riprogramma()
                Notifiche.s.pianificaAttivita()
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
    }

    /// I widget parlano da soli col server, all'indirizzo personale di questo account.
    private func collegaWidget() async {
        guard rete.connesso, let r = try? await Rete.s.righe("widget_chiave", "select=indirizzo", da: 0, a: 0).first else { return }
        ClienteWidget.collega(indirizzo: r.indirizzo.str)
    }

    private func avvia() {
        Misure.s.traguardo("primo frame")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Logica.s.preparaLetture() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Misure.s.salva() }
        Task { await collegaWidget() }
        if demo != nil { Dimostrazione.carica() }
        Logica.s.avvia()
        Archivio.s.avvia()
        Notifiche.s.riprogramma()
    }
}

/// Life è il contenitore: la sua barra porta alla giornata, alle app e alla ricerca.
/// To do, Calendario e i moduli sono mini-app: ognuna si apre con la sua barra.
struct Radice: View {
    var demo: String? = nil
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var logica = Logica.s
    @ObservedObject private var notifiche = Notifiche.s
    @ObservedObject private var instradatore = Instradatore.s
    @ObservedObject private var fogli = Fogli.s
    @Namespace private var zoom
    @State private var editorEvento: NuovoEventoBersaglio?
    @State private var scheda = "oggi"
    @State private var impostazioni = false
    @State private var anteprimaWidget = false

    var body: some View {
        let _ = archivio.versione
        let _ = logica.versione
        let adesso = cosaAdesso()
        TabView(selection: $scheda) {
            Tab("Oggi", systemImage: "sun.max", value: "oggi") {
                NavigationStack { Home() }
            }
            Tab("App", systemImage: "square.grid.2x2", value: "app") {
                NavigationStack { GrigliaApp(zoom: zoom) }
            }
            Tab(value: "cerca", role: .search) {
                NavigationStack { VistaCerca() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: adesso != nil) {
            if let adesso {
                Button {
                    tocco()
                    instradatore.apri(adesso.modulo)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: adesso.modulo.icona).foregroundStyle(Color(hex: adesso.modulo.colore))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(adesso.titolo).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(adesso.sotto).font(.caption2).foregroundStyle(Color.secondarioLife).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .modifier(StratoAvvisi())
        .fullScreenCover(item: $instradatore.aperta) { a in
            MiniApp(modulo: a.modulo)
                .navigationTransition(.zoom(sourceID: a.idZoom, in: zoom))
        }
        .sheet(isPresented: $impostazioni) {
            NavigationStack { VistaImpostazioni() }
        }
        .sheet(isPresented: $anteprimaWidget) { AnteprimaWidget() }
        // I collegamenti (widget, notifiche) aprono subito il loro foglio, qui sulla Home. Se è aperta
        // una mini-app li mostra lei, che sta sopra: per questo qui valgono solo quando non ce n'è.
        .sheet(item: seFuori($instradatore.task)) { t in SchedaTask(idTask: t.id) }
        .sheet(isPresented: Binding(get: { instradatore.aperta == nil && instradatore.nuovoTask }, set: { instradatore.nuovoTask = $0 })) { NuovoTask(contesto: [:]) }
        .sheet(item: seFuori($instradatore.evento)) { link in
            EventoDaLink(link: link) { id in
                instradatore.evento = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editorEvento = NuovoEventoBersaglio(idEvento: id) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editorEvento) { b in EditorEvento(bersaglio: b) }
        .sheet(item: seFuori($fogli.aperto)) { f in FoglioFinanzeVista(foglio: f) }
        .onReceive(instradatore.$movimento) { tipo in
            guard let tipo, instradatore.aperta == nil else { return }
            instradatore.movimento = nil
            fogli.apri(.movimento(nil, tipo, nil))
        }
        .onChange(of: notifiche.daAprire) { _, apri in
            guard let apri else { return }
            notifiche.daAprire = nil
            if apri.hasPrefix("task:") {
                instradatore.apri(url: LinkLife.task(String(apri.dropFirst(5))))
            } else if apri.hasPrefix("evento:") {
                instradatore.apri(.calendario)
            }
        }
        .onAppear(perform: applicaDemo)
        // Ogni minuto il giorno può cambiare; i moduli lo sanno da qui
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            Logica.s.battito()
            Task { await AggiornaLogica.controlla() }
        }
        .task { await AggiornaLogica.controlla() }
    }

    private func seFuori<T>(_ b: Binding<T?>) -> Binding<T?> {
        Binding(get: { instradatore.aperta == nil ? b.wrappedValue : nil }, set: { b.wrappedValue = $0 })
    }

    /// Quello che conta adesso, sopra la barra: la cosa in ritardo o il prossimo evento di oggi.
    private func cosaAdesso() -> (modulo: Modulo, titolo: String, sotto: String)? {
        if let v = logica.chiama("home.quadro").prio.list.first, let m = Modulo.di(v.modulo.t) {
            return (m, v.nome.t, v.quando.str == "tardi" ? "In ritardo · \(m.nome)" : "Adesso · \(m.nome)")
        }
        let (da, a) = Tempo.intervallo(Tempo.oggi())
        let ora = Tempo.iso(Date())
        guard let e = Azioni.eventi(da: da, a: a).first(where: { !$0.all_day.vero && $0.end_at.t > ora }) else { return nil }
        return (.calendario, e.summary.t, "Alle \(Tempo.oraRoma(e.start_at.str) ?? "")")
    }

    private func applicaDemo() {
        guard let demo else { return }
        let parti = demo.split(separator: ":").map(String.init)
        let vista = parti.first ?? ""
        instradatore.schedaIniziale = parti.count > 1 ? parti[1] : nil
        switch vista {
        case "app", "cerca", "oggi": scheda = vista
        case "todo": instradatore.apri(.todo)
        case "calendario":
            if let modo = instradatore.schedaIniziale { Preferenze.s.modoCalendario = modo } else { Preferenze.s.modoCalendario = "day" }
            instradatore.schedaIniziale = nil
            instradatore.apri(.calendario)
        case "impostazioni": impostazioni = true
        case "widget": anteprimaWidget = true
        default:
            if let m = Modulo.di(vista) { instradatore.apri(m) }
        }
    }
}

struct TaskAperto: Identifiable {
    let task: J
    var id: String { task.id.t }
}

struct AvvisoBanner: View {
    let avviso: Logica.Avviso
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: avviso.tipo == "errore" ? "exclamationmark.triangle.fill" : avviso.tipo == "festa" ? "party.popper.fill" : "checkmark.circle.fill")
                .foregroundStyle(avviso.tipo == "errore" ? Color.pericoloLife : Color.successoLife)
            Text(avviso.testo).font(.subheadline).lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}
