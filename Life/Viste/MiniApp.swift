import SwiftUI

/// Da dove arrivano i tocchi su widget e notifiche: decide quale mini-app aprire e su cosa.
final class Instradatore: ObservableObject {
    static let s = Instradatore()

    struct Apertura: Identifiable, Equatable {
        let modulo: Modulo
        var sorgente = ""
        var id: String { modulo.id }
        var idZoom: String { "\(sorgente).\(modulo.id)" }
    }
    struct LinkEvento: Identifiable, Equatable {
        let id: String
        let giorno: String
    }
    struct LinkTask: Identifiable, Equatable {
        let id: String
    }

    @Published var aperta: Apertura?
    @Published var task: LinkTask?
    @Published var evento: LinkEvento?
    @Published var nuovoTask = false
    @Published var movimento: String?
    /// La scheda con cui si apre la prossima mini-app.
    var schedaIniziale: String?

    func apri(_ m: Modulo, da sorgente: String = "") {
        if aperta?.modulo != m { aperta = Apertura(modulo: m, sorgente: sorgente) }
    }

    func apri(url: URL) {
        guard url.scheme == "life" else { return }
        let parti = url.pathComponents.filter { $0 != "/" }
        switch url.host() ?? "" {
        case "todo": apri(.todo)
        case "calendario": apri(.calendario)
        case "nuovo-task":
            apri(.todo)
            nuovoTask = true
        case "task":
            apri(.todo)
            if let id = parti.first { task = LinkTask(id: id) }
        case "evento":
            apri(.calendario)
            if let id = parti.first { evento = LinkEvento(id: id, giorno: parti.count > 1 ? parti[1] : Tempo.oggi()) }
        case "finanze":
            apri(Modulo.di("finanze") ?? .todo)
            movimento = parti.first == "entrata" ? "in" : "out"
        case "modulo":
            if let id = parti.first, let m = Modulo.di(id) { apri(m) }
        default: break
        }
    }
}

/// Le schede di ogni mini-app: la barra in basso è la sua, non quella di Life.
private struct SchedaApp: Identifiable {
    let id: String
    let titolo: String
    let icona: String
}

/// Una schermata della mini-app: ha la sua navigazione e il ritorno a Life.
private struct Schermata<Contenuto: View>: View {
    let chiudi: () -> Void
    @ViewBuilder var contenuto: () -> Contenuto
    var body: some View {
        NavigationStack {
            contenuto()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            tocco()
                            chiudi()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Torna a Life")
                    }
                }
        }
    }
}

/// Ogni modulo è un'app dentro Life: si apre a tutto schermo, con la sua barra e il suo colore.
struct MiniApp: View {
    let modulo: Modulo
    @Environment(\.dismiss) private var esci
    @ObservedObject private var instradatore = Instradatore.s
    @ObservedObject private var fogli = Fogli.s
    @ObservedObject private var preferenze = Preferenze.s
    @State private var scheda: String
    @State private var editorEvento: NuovoEventoBersaglio?

    init(modulo: Modulo) {
        self.modulo = modulo
        let iniziale = Instradatore.s.schedaIniziale
        Instradatore.s.schedaIniziale = nil
        _scheda = State(initialValue: iniziale ?? MiniApp.schede(modulo.id).first?.id ?? "")
    }

    private static func schede(_ id: String) -> [SchedaApp] {
        let altro = SchedaApp(id: "altro", titolo: "Altro", icona: "slider.horizontal.3")
        switch id {
        case "todo":
            return [
                SchedaApp(id: "oggi", titolo: "Oggi", icona: "star.fill"),
                SchedaApp(id: "programmate", titolo: "Programmate", icona: "calendar.badge.clock"),
                SchedaApp(id: "liste", titolo: "Liste", icona: "list.bullet"),
            ]
        case "finanze":
            return [
                SchedaApp(id: "home", titolo: "Riepilogo", icona: "eurosign.circle"),
                SchedaApp(id: "movimenti", titolo: "Movimenti", icona: "list.bullet.rectangle"),
                SchedaApp(id: "analisi", titolo: "Analisi", icona: "chart.bar.fill"),
                altro,
            ]
        case "abitudini":
            return [
                SchedaApp(id: "oggi", titolo: "Oggi", icona: "checkmark.circle"),
                SchedaApp(id: "progressi", titolo: "Progressi", icona: "chart.line.uptrend.xyaxis"),
                altro,
            ]
        case "allenamenti":
            return [
                SchedaApp(id: "settimana", titolo: "Settimana", icona: "calendar"),
                SchedaApp(id: "andamento", titolo: "Andamento", icona: "chart.xyaxis.line"),
                altro,
            ]
        case "mobilita":
            return [
                SchedaApp(id: "oggi", titolo: "Oggi", icona: "figure.flexibility"),
                SchedaApp(id: "progressi", titolo: "Progressi", icona: "chart.line.uptrend.xyaxis"),
                altro,
            ]
        case "pasti":
            return [
                SchedaApp(id: "oggi", titolo: "Oggi", icona: "fork.knife"),
                SchedaApp(id: "settimana", titolo: "Settimana", icona: "calendar"),
                altro,
            ]
        default:
            return []
        }
    }

    var body: some View {
        Group {
            switch modulo.id {
            case "calendario": calendario
            case "finanze":
                schedeApp
                    .tabViewBottomAccessory { BarraGestiFinanze() }
                    .sheet(item: $fogli.aperto) { f in FoglioFinanzeVista(foglio: f) }
                    .onReceive(instradatore.$movimento) { tipo in
                        guard let tipo else { return }
                        instradatore.movimento = nil
                        fogli.apri(.movimento(nil, tipo, nil))
                    }
            default: schedeApp
            }
        }
        .tint(Color(hex: modulo.colore))
        .modifier(StratoAvvisi())
        .sheet(item: $instradatore.task) { t in SchedaTask(idTask: t.id) }
        .sheet(isPresented: $instradatore.nuovoTask) { NuovoTask(contesto: [:]) }
        .sheet(item: $instradatore.evento) { link in
            if let e = trova(link) {
                DettaglioEvento(evento: e) { id in
                    instradatore.evento = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editorEvento = NuovoEventoBersaglio(idEvento: id) }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $editorEvento) { b in EditorEvento(bersaglio: b) }
    }

    private func trova(_ link: Instradatore.LinkEvento) -> J? {
        let (da, a) = Tempo.intervallo(link.giorno)
        StatoCalendario.s.ancora = link.giorno
        return Azioni.eventi(da: da, a: a).first { $0.id.t == link.id || $0.own_event_id.t == link.id }
    }

    private var schedeApp: some View {
        TabView(selection: $scheda) {
            ForEach(MiniApp.schede(modulo.id)) { s in
                Tab(s.titolo, systemImage: s.icona, value: s.id) {
                    Schermata(chiudi: { esci() }) { contenuto(s.id) }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    @ViewBuilder
    private func contenuto(_ s: String) -> some View {
        switch modulo.id {
        case "todo":
            switch s {
            case "programmate": VistaProgrammate()
            case "liste": VistaListe()
            default: VistaOggi()
            }
        case "finanze": VistaFinanze(scheda: s)
        case "abitudini": VistaAbitudini(scheda: s)
        case "allenamenti": VistaTraining(scheda: s)
        case "mobilita": VistaMobilita(scheda: s)
        case "pasti": VistaPasti(scheda: s)
        default: EmptyView()
        }
    }

    /// Calendario: la barra sceglie come guardare il tempo.
    private var calendario: some View {
        TabView(selection: $preferenze.modoCalendario) {
            Tab("Giorno", systemImage: "calendar.day.timeline.left", value: "day") {
                Schermata(chiudi: { esci() }) { VistaCalendario() }
            }
            Tab("3 giorni", systemImage: "rectangle.split.3x1", value: "three") {
                Schermata(chiudi: { esci() }) { VistaCalendario() }
            }
            Tab("Settimana", systemImage: "calendar.badge.clock", value: "week") {
                Schermata(chiudi: { esci() }) { VistaCalendario() }
            }
            Tab("Mese", systemImage: "calendar", value: "month") {
                Schermata(chiudi: { esci() }) { VistaCalendario() }
            }
        }
    }
}

/// I gesti di tutti i giorni di Finanze, sopra la barra.
struct BarraGestiFinanze: View {
    @ObservedObject private var fogli = Fogli.s
    var body: some View {
        HStack(spacing: 4) {
            Button { fogli.apri(.movimento(nil, "out", nil)) } label: { Label("Uscita", systemImage: "minus").fontWeight(.semibold) }
                .foregroundStyle(Color(hex: "#FF9500"))
            Spacer(minLength: 6)
            Button { fogli.apri(.movimento(nil, "in", nil)) } label: { Label("Entrata", systemImage: "plus") }
            Spacer(minLength: 6)
            Button { fogli.apri(.previsto) } label: { Image(systemName: "calendar") }.accessibilityLabel("Previsti")
            Button { fogli.apri(.lista) } label: { Image(systemName: "clock") }.accessibilityLabel("Lista d'attesa")
            Button { fogli.apri(.movimento(nil, "giro", nil)) } label: { Image(systemName: "arrow.left.arrow.right") }.accessibilityLabel("Giroconto")
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

/// «Annulla» e gli avvisi stanno sopra qualsiasi mini-app.
struct StratoAvvisi: ViewModifier {
    @ObservedObject private var logica = Logica.s
    @ObservedObject private var annulla = Annulla.s

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let a = logica.avviso {
                    AvvisoBanner(avviso: a)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .overlay(alignment: .bottom) {
                if let e = annulla.etichetta {
                    HStack(spacing: 12) {
                        Text(e).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Annulla") { annulla.esegui() }.font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: annulla.etichetta)
            .animation(.spring(duration: 0.3), value: logica.avviso)
    }
}

// MARK: - La scheda «App»

/// Tutte le mini-app, ognuna col suo stato di oggi.
struct GrigliaApp: View {
    let zoom: Namespace.ID
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var logica = Logica.s

    private func stato(_ m: Modulo, _ carte: J, _ oggi: String) -> String {
        switch m.id {
        case "todo":
            let n = Azioni.tasks.filter { Azioni.inOggi($0, oggi) }.count
            return n == 0 ? "Tutto fatto" : "\(n) da fare"
        case "calendario":
            let (da, a) = Tempo.intervallo(oggi)
            let ora = Tempo.iso(Date())
            guard let e = Azioni.eventi(da: da, a: a).first(where: { !$0.all_day.vero && $0.end_at.t > ora }) else { return "Niente più oggi" }
            return "\(Tempo.oraRoma(e.start_at.str) ?? "") \(e.summary.t)"
        default:
            let c = carte[m.id]
            return c.oggiPuoi.str ?? c.valore.str ?? ""
        }
    }

    var body: some View {
        let _ = archivio.versione
        let _ = logica.versione
        let carte = logica.chiama("home.oggi")
        let oggi = Tempo.oggi()
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Modulo.app) { m in
                    Button {
                        tocco()
                        Instradatore.s.apri(m, da: "griglia")
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            IconaApp(modulo: m, lato: 52)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.nome).font(.headline).foregroundStyle(Color.primary)
                                Text(stato(m, carte, oggi).isEmpty ? " " : stato(m, carte, oggi)).font(.footnote).foregroundStyle(Color.secondarioLife).lineLimit(1)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "griglia.\(m.id)", in: zoom)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.sfondoLife)
        .navigationTitle("App")
        .toolbar { BottoneImpostazioni() }
    }
}

struct IconaApp: View {
    let modulo: Modulo
    var lato: CGFloat = 60
    var body: some View {
        Image(systemName: modulo.icona)
            .font(.system(size: lato * 0.43, weight: .medium))
            .foregroundStyle(Color(hex: modulo.colore))
            .frame(width: lato, height: lato)
            .background(Color(hex: modulo.colore).opacity(0.14), in: RoundedRectangle(cornerRadius: lato * 0.24, style: .continuous))
    }
}

struct BottoneImpostazioni: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { VistaImpostazioni() } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Impostazioni")
        }
    }
}

// MARK: - La ricerca di tutta Life

struct VistaCerca: View {
    @State private var testo = ""
    @ObservedObject private var archivio = Archivio.s

    var body: some View {
        let _ = archivio.versione
        let q = testo.trimmingCharacters(in: .whitespaces).lowercased()
        let app = q.isEmpty ? Modulo.app : Modulo.app.filter { $0.nome.lowercased().contains(q) }
        let task = q.isEmpty ? [] : Azioni.tasks.filter { $0.title.t.lowercased().contains(q) }.prefix(20)
        let eventi = q.isEmpty ? [] : cercaEventi(q)
        let movimenti = q.isEmpty ? [] : cercaMovimenti(q)
        List {
            if !app.isEmpty {
                Section("App") {
                    ForEach(app) { m in
                        Button { Instradatore.s.apri(m) } label: {
                            HStack(spacing: 12) {
                                IconaApp(modulo: m, lato: 32)
                                Text(m.nome).foregroundStyle(Color.primary)
                            }
                        }
                    }
                }
            }
            if !task.isEmpty {
                Section("To do") {
                    ForEach(Array(task), id: \.id) { t in
                        Button { Instradatore.s.apri(url: LinkLife.task(t.id.str)) } label: {
                            riga("checkmark.square.fill", "#34C759", t.title.t, Azioni.giorno(t))
                        }
                    }
                }
            }
            if !eventi.isEmpty {
                Section("Calendario") {
                    ForEach(eventi, id: \.self) { e in
                        Button {
                            let giorno = Tempo.dataRoma(Tempo.data(e.start_at.t) ?? Date())
                            Instradatore.s.apri(.calendario)
                            Instradatore.s.evento = Instradatore.LinkEvento(id: e.id.t, giorno: giorno)
                        } label: {
                            riga("calendar", "#FF453A", e.summary.t, Tempo.data(e.start_at.t).map { Tempo.dataRoma($0) })
                        }
                    }
                }
            }
            if !movimenti.isEmpty {
                Section("Finanze") {
                    ForEach(movimenti, id: \.self) { m in
                        Button { Modulo.di("finanze").map { Instradatore.s.apri($0) } } label: {
                            riga("eurosign.circle.fill", "#FF9500", m.nota.t, "\(m.data.t) · \(euro(m.imp))")
                        }
                    }
                }
            }
            if !q.isEmpty, app.isEmpty, task.isEmpty, eventi.isEmpty, movimenti.isEmpty {
                ContentUnavailableView.search(text: testo)
            }
        }
        .navigationTitle("Cerca")
        .searchable(text: $testo, prompt: "Task, eventi, movimenti, app")
    }

    private func riga(_ icona: String, _ colore: String, _ titolo: String, _ sotto: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icona).foregroundStyle(Color(hex: colore)).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(titolo.isEmpty ? "Senza titolo" : titolo).foregroundStyle(Color.primary).lineLimit(1)
                if let sotto, !sotto.isEmpty { Text(sotto).font(.caption).foregroundStyle(Color.secondarioLife) }
            }
        }
    }

    private func cercaEventi(_ q: String) -> [J] {
        let oggi = Tempo.oggi()
        let (da, _) = Tempo.intervallo(Tempo.piuGiorni(oggi, -30))
        let (_, a) = Tempo.intervallo(Tempo.piuGiorni(oggi, 120))
        return Array(Azioni.eventi(da: da, a: a).filter { $0.summary.t.lowercased().contains(q) }.prefix(20))
    }

    private func cercaMovimenti(_ q: String) -> [J] {
        let tutti = Logica.s.chiama("finanze.dati.movimentiVivi").list
        return Array(tutti.filter { $0.nota.t.lowercased().contains(q) }.sorted { $0.data.t > $1.data.t }.prefix(20))
    }
}

// MARK: - I widget visti dentro l'app (per controllarli sul simulatore)

struct AnteprimaWidget: View {
    private var voce: VoceWidget { VoceWidget(date: Date(), dati: .esempio) }

    private func cornice<C: View>(_ larghezza: CGFloat, _ altezza: CGFloat, @ViewBuilder _ c: () -> C) -> some View {
        c()
            .padding(14)
            .frame(width: larghezza, height: altezza, alignment: .topLeading)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                cornice(358, 170) { VistaOggiWidget(v: voce).environment(\.widgetFamily, .systemMedium) }
                cornice(358, 170) { VistaPromemoriaWidget(v: voce).environment(\.widgetFamily, .systemMedium) }
                HStack(spacing: 12) {
                    cornice(170, 170) { VistaTodoWidget(v: voce).environment(\.widgetFamily, .systemSmall) }
                    cornice(170, 170) { VistaCalendarioWidget(v: voce).environment(\.widgetFamily, .systemSmall) }
                }
                HStack(spacing: 12) {
                    cornice(170, 170) { VistaFinanzeWidget().environment(\.widgetFamily, .systemSmall) }
                    cornice(170, 170) { VistaEventiWidget(v: voce).environment(\.widgetFamily, .systemSmall) }
                }
                cornice(358, 76) { BloccoEventoWidget(v: voce).environment(\.widgetFamily, .accessoryRectangular) }
            }
            .padding()
        }
        .background(Color.sfondoLife)
    }
}
