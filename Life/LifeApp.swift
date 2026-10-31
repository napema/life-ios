import BackgroundTasks
import SwiftUI

@main
struct LifeApp: App {
    @Environment(\.scenePhase) private var fase
    @StateObject private var rete = Rete.s
    @StateObject private var preferenze = Preferenze.s
    private let demo = ProcessInfo.processInfo.environment["LIFE_DEMO"]

    init() {
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
            .preferredColorScheme(preferenze.aspetto == "light" ? .light : preferenze.aspetto == "dark" ? .dark : nil)
            .tint(.accentoLife)
        }
        .onChange(of: fase) { _, nuova in
            switch nuova {
            case .active:
                Logica.s.visibile(true)
                Logica.s.battito()
                Archivio.s.segnaEventiSporchi()
                Archivio.s.avvia()
                Notifiche.s.aggiornaPermesso()
            case .background:
                Logica.s.visibile(false)
                Archivio.s.ferma()
                Archivio.s.salvaOra()
                Logica.s.salvaMemoriaOra()
                Notifiche.s.riprogramma()
                Notifiche.s.pianificaAttivita()
            default:
                break
            }
        }
    }

    private func avvia() {
        if demo != nil { Dimostrazione.carica() }
        Logica.s.avvia()
        Archivio.s.avvia()
        Notifiche.s.riprogramma()
    }
}

/// Le schede in basso, come MobileShell.tsx.
struct Radice: View {
    var demo: String? = nil
    @ObservedObject private var archivio = Archivio.s
    @ObservedObject private var logica = Logica.s
    @ObservedObject private var annulla = Annulla.s
    @ObservedObject private var notifiche = Notifiche.s
    @State private var scheda = "home"
    @State private var modulo: Modulo?
    @State private var taskDaNotifica: J?
    @State private var impostazioni = false

    var body: some View {
        let oggi = Tempo.oggi()
        let inRitardo = Azioni.tasks.filter { Azioni.inOggi($0, oggi) && Azioni.inRitardo($0, oggi) }.count
        TabView(selection: $scheda) {
            NavigationStack { Home(apriModulo: { modulo = $0 }, cambiaScheda: { scheda = $0 }) }
                .tabItem { Label("App", systemImage: "square.grid.2x2") }
                .tag("home")
            NavigationStack { VistaOggi() }
                .tabItem { Label("Oggi", systemImage: "star.fill") }
                .badge(inRitardo)
                .tag("oggi")
            NavigationStack { VistaCalendario() }
                .tabItem { Label("Calendario", systemImage: "calendar") }
                .tag("calendario")
            NavigationStack { VistaProgrammate() }
                .tabItem { Label("Programmate", systemImage: "calendar.badge.clock") }
                .tag("programmate")
            NavigationStack { VistaListe() }
                .tabItem { Label("Liste", systemImage: "list.bullet") }
                .tag("liste")
        }
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
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 62)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: annulla.etichetta)
        .animation(.spring(duration: 0.3), value: logica.avviso)
        .fullScreenCover(item: $modulo) { m in
            VistaModulo(modulo: m)
        }
        .sheet(item: Binding(get: { taskDaNotifica.map { TaskAperto(task: $0) } }, set: { taskDaNotifica = $0?.task })) { a in
            SchedaTask(idTask: a.task.id.t)
        }
        .sheet(isPresented: $impostazioni) {
            NavigationStack { VistaImpostazioni() }
        }
        .onChange(of: notifiche.daAprire) { _, apri in
            guard let apri else { return }
            notifiche.daAprire = nil
            if apri.hasPrefix("task:"), let t = archivio.riga("tasks", String(apri.dropFirst(5))) {
                taskDaNotifica = t
            } else if apri.hasPrefix("evento:") {
                scheda = "calendario"
            }
        }
        .onAppear(perform: applicaDemo)
        // Ogni minuto il giorno può cambiare; i moduli lo sanno da qui
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in Logica.s.battito() }
    }

    private func applicaDemo() {
        guard let demo else { return }
        switch demo {
        case "oggi", "calendario", "programmate", "liste", "home": scheda = demo
        case "finanze", "abitudini", "mobilita", "pasti": modulo = Modulo.di(demo)
        case "training": modulo = Modulo.di("allenamenti")
        case "impostazioni": scheda = "liste"; impostazioni = true
        default: break
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
