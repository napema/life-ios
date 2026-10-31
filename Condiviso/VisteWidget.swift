import AppIntents
import SwiftUI
import WidgetKit

/// Il cerchietto di un task sul widget: lo completa senza aprire l'app.
struct CompletaTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Completa il task"
    static var isDiscoverable = false

    @Parameter(title: "Task")
    var id: String

    init() {}
    init(id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        await ClienteWidget.completa(id)
        return .result()
    }
}

private func coloreWidget(_ hex: String?, _ riserva: Color = .gray) -> Color {
    guard var s = hex, s.hasPrefix("#"), s.count == 7 else { return riserva }
    s.removeFirst()
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

private func oraAdesso(_ data: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: data)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

extension DatiWidget {
    func eventiDavanti(_ data: Date) -> [Evento] {
        let ora = oraAdesso(data)
        return eventi.filter { ($0.fine ?? "99") > ora }
    }

    func prossimiDavanti(_ data: Date) -> [Evento] {
        let ora = oraAdesso(data)
        return prossimi.filter { $0.data != oggi || ($0.fine ?? "99") > ora }
    }

    /// Il prossimo di oggi: se ora sei dentro un evento, quello che comincia quando finisce.
    func prossimoDiOggi(_ data: Date) -> Evento? {
        let ora = oraAdesso(data)
        let conOra = eventi.filter { $0.inizio != nil }
        let finiscono = conOra.filter { ($0.inizio ?? "") <= ora && ($0.fine ?? "") > ora }.compactMap(\.fine)
        let da = finiscono.max() ?? ora
        return conOra.filter { ($0.inizio ?? "") >= da }.min { ($0.inizio ?? "") < ($1.inizio ?? "") }
    }

    var giornoSettimana: String { titolo.split(separator: " ").first.map(String.init) ?? "" }
    var numeroGiorno: String {
        let p = titolo.split(separator: " ")
        return p.count > 1 ? String(p[1]) : ""
    }
}

struct VoceWidget: TimelineEntry {
    let date: Date
    let dati: DatiWidget?
}

// MARK: - I pezzi

struct RigaEventoWidget: View {
    let e: DatiWidget.Evento
    let oggi: String
    var misura: CGFloat = 13
    var conGiorno = false
    var body: some View {
        Link(destination: LinkLife.evento(e, oggi: oggi)) {
            HStack(spacing: 7) {
                Capsule().fill(coloreWidget(e.colore)).frame(width: 3.5, height: misura * 2.2).widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.titolo).font(.system(size: misura, weight: .semibold)).lineLimit(1)
                    Text(sotto).font(.system(size: misura - 2)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private var sotto: String {
        let orario = e.inizio.map { "\($0) – \(e.fine ?? "")" } ?? "tutto il giorno"
        if conGiorno, let g = e.giorno { return "\(g) · \(orario)" }
        return orario
    }
}

struct RigaTaskWidget: View {
    let t: DatiWidget.Task
    var misura: CGFloat = 13
    var body: some View {
        HStack(spacing: 7) {
            if let id = t.id {
                Button(intent: CompletaTaskIntent(id: id)) { cerchio }.buttonStyle(.plain)
            } else {
                cerchio
            }
            Link(destination: LinkLife.task(t.id)) {
                HStack(spacing: 4) {
                    Text(t.titolo).font(.system(size: misura)).foregroundStyle(t.inRitardo == true ? Color.red : Color.primary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let o = t.ora { Text(o).font(.system(size: misura - 2, weight: .medium)).monospacedDigit().foregroundStyle(.secondary) }
                }
            }
        }
    }
    private var cerchio: some View {
        Circle()
            .strokeBorder(t.inRitardo == true ? Color.red : coloreWidget(t.colore), lineWidth: 1.5)
            .frame(width: misura + 4, height: misura + 4)
            .contentShape(Rectangle().inset(by: -5))
            .widgetAccentable()
    }
}

private struct Vuoto: View {
    let testo: String
    var body: some View {
        Text(testo).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Finché l'app non ha collegato il widget.
struct DaCollegareWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "link").foregroundStyle(.tint)
            Text("Apri Life").font(.headline)
            Text("per collegare il widget").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GiornoGrande: View {
    let d: DatiWidget
    var misura: CGFloat = 30
    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(d.giornoSettimana.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(.red).widgetAccentable()
            Text(d.numeroGiorno).font(.system(size: misura, weight: .bold))
        }
    }
}

// MARK: - Le viste della Home

struct VistaOggiWidget: View {
    let v: VoceWidget
    @Environment(\.widgetFamily) private var famiglia
    var body: some View {
        if let d = v.dati {
            let eventi = d.eventiDavanti(v.date)
            switch famiglia {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 5) {
                    GiornoGrande(d: d)
                    if eventi.isEmpty, d.task.isEmpty { Vuoto(testo: "Niente in programma") }
                    ForEach(eventi.prefix(2), id: \.self) { RigaEventoWidget(e: $0, oggi: d.oggi, misura: 12) }
                    if eventi.count < 2 {
                        ForEach(d.task.prefix(2 - eventi.count), id: \.self) { RigaTaskWidget(t: $0, misura: 12) }
                    }
                    Spacer(minLength: 0)
                }
                .widgetURL(LinkLife.calendario)
            case .systemMedium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading) {
                        GiornoGrande(d: d)
                        Spacer(minLength: 0)
                        Text("\(d.task.count) task").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .frame(width: 72, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(eventi.prefix(4), id: \.self) { RigaEventoWidget(e: $0, oggi: d.oggi, misura: 12) }
                        ForEach(d.task.prefix(max(0, 4 - eventi.count)), id: \.self) { RigaTaskWidget(t: $0, misura: 13) }
                        if eventi.isEmpty, d.task.isEmpty { Vuoto(testo: "Niente oggi") }
                        Spacer(minLength: 0)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .bottom) {
                        GiornoGrande(d: d, misura: 26)
                        Spacer()
                        Text("\(d.eventi.count) eventi · \(d.task.count) task").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Text("CALENDARIO").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    if eventi.isEmpty { Vuoto(testo: "Niente in calendario") }
                    ForEach(eventi.prefix(4), id: \.self) { RigaEventoWidget(e: $0, oggi: d.oggi) }
                    Text("DA FARE").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    if d.task.isEmpty { Vuoto(testo: "Tutto fatto") }
                    ForEach(d.task.prefix(6), id: \.self) { RigaTaskWidget(t: $0) }
                    Spacer(minLength: 0)
                }
            }
        } else {
            DaCollegareWidget()
        }
    }
}

struct VistaEventiWidget: View {
    let v: VoceWidget
    @Environment(\.widgetFamily) private var famiglia
    var body: some View {
        if let d = v.dati {
            let lista = d.prossimiDavanti(v.date)
            let quanti = famiglia == .systemSmall ? 3 : famiglia == .systemMedium ? 3 : 8
            VStack(alignment: .leading, spacing: 6) {
                Text("PROSSIMI").font(.system(size: 11, weight: .bold)).foregroundStyle(.red).widgetAccentable()
                if lista.isEmpty { Vuoto(testo: "Niente in arrivo") }
                ForEach(lista.prefix(quanti), id: \.self) { RigaEventoWidget(e: $0, oggi: d.oggi, misura: 12.5, conGiorno: true) }
                Spacer(minLength: 0)
            }
            .widgetURL(lista.first.map { LinkLife.evento($0, oggi: d.oggi) } ?? LinkLife.calendario)
        } else {
            DaCollegareWidget()
        }
    }
}

struct VistaTodoWidget: View {
    let v: VoceWidget
    @Environment(\.widgetFamily) private var famiglia
    var body: some View {
        if let d = v.dati {
            let quanti = famiglia == .systemSmall ? 4 : famiglia == .systemMedium ? 4 : 11
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TO DO · OGGI").font(.system(size: 11, weight: .bold)).foregroundStyle(.green).widgetAccentable()
                    Spacer()
                    Text("\(d.task.count)").font(.system(size: 15, weight: .bold))
                }
                if d.task.isEmpty { Vuoto(testo: "Tutto fatto") }
                ForEach(d.task.prefix(quanti), id: \.self) { RigaTaskWidget(t: $0, misura: famiglia == .systemSmall ? 12 : 13) }
                if d.task.count > quanti { Text("+\(d.task.count - quanti)").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .widgetURL(LinkLife.todo)
        } else {
            DaCollegareWidget()
        }
    }
}

/// Lo stile del widget di Promemoria: cerchio, nome della lista, numero grande.
struct VistaPromemoriaWidget: View {
    let v: VoceWidget
    @Environment(\.widgetFamily) private var famiglia
    var body: some View {
        if let d = v.dati {
            let n = d.task.count
            VStack(alignment: .leading, spacing: famiglia == .systemSmall ? 4 : 8) {
                HStack {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.blue, in: Circle())
                        .widgetAccentable()
                    if famiglia != .systemSmall { Text("Oggi").font(.headline).foregroundStyle(.blue) }
                    Spacer()
                    Text("\(n)").font(.system(size: 26, weight: .bold, design: .rounded))
                }
                if famiglia == .systemSmall { Text("Oggi").font(.headline).foregroundStyle(.blue) }
                if n == 0 { Vuoto(testo: "Tutto fatto") }
                if famiglia == .systemMedium {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) { ForEach(d.task.prefix(3), id: \.self) { RigaTaskWidget(t: $0) } }
                        VStack(alignment: .leading, spacing: 7) { ForEach(d.task.dropFirst(3).prefix(3), id: \.self) { RigaTaskWidget(t: $0) } }
                    }
                } else {
                    ForEach(d.task.prefix(famiglia == .systemSmall ? 2 : 9), id: \.self) { RigaTaskWidget(t: $0, misura: famiglia == .systemSmall ? 12.5 : 14) }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(LinkLife.todo)
        } else {
            DaCollegareWidget()
        }
    }
}

struct MeseWidget: View {
    let d: DatiWidget
    var body: some View {
        let celle: [Int?] = Array(repeating: nil, count: d.mese.primoGiornoSettimana) + (1...max(1, d.mese.giorni)).map { Optional($0) }
        let oggi = Int(d.oggi.suffix(2)) ?? 0
        let conEventi = Set(d.mese.conEventi ?? [])
        VStack(alignment: .leading, spacing: 3) {
            Text(d.mese.nome.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.red).widgetAccentable()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                ForEach(["L", "M", "M", "G", "V", "S", "D"].indices, id: \.self) { i in
                    Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(celle.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        if let n = celle[i] {
                            Text("\(n)")
                                .font(.system(size: 10, weight: n == oggi ? .bold : .medium))
                                .foregroundStyle(n == oggi ? Color.white : (i % 7 >= 5 ? Color.secondary : Color.primary))
                                .frame(width: 15, height: 15)
                                .background(n == oggi ? Color.red : Color.clear, in: Circle())
                            Circle().fill(n != oggi && conEventi.contains(n) ? Color.secondary : Color.clear).frame(width: 2.5, height: 2.5)
                        } else {
                            Color.clear.frame(height: 17.5)
                        }
                    }
                }
            }
        }
    }
}

struct VistaCalendarioWidget: View {
    let v: VoceWidget
    @Environment(\.widgetFamily) private var famiglia
    var body: some View {
        if let d = v.dati {
            let eventi = d.prossimiDavanti(v.date)
            switch famiglia {
            case .systemSmall:
                MeseWidget(d: d).widgetURL(LinkLife.calendario)
            case .systemMedium:
                HStack(alignment: .top, spacing: 12) {
                    MeseWidget(d: d).frame(maxWidth: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        if eventi.isEmpty { Vuoto(testo: "Niente in arrivo") }
                        ForEach(eventi.prefix(3), id: \.self) { RigaEventoWidget(e: $0, oggi: d.oggi, misura: 12, conGiorno: true) }
                        Spacer(minLength: 0)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    MeseWidget(d: d)
                    if eventi.isEmpty { Vuoto(testo: "Niente in arrivo") }
                    ForEach(eventi.prefix(3), id: \.self) { RigaEventoWidget(e: $0, oggi: d.oggi, misura: 12.5, conGiorno: true) }
                    Spacer(minLength: 0)
                }
            }
        } else {
            DaCollegareWidget()
        }
    }
}

/// Finanze: i due pulsanti, grandi. Aprono Life sul foglio giusto.
struct VistaFinanzeWidget: View {
    @Environment(\.widgetFamily) private var famiglia
    var body: some View {
        let layout = famiglia == .systemSmall ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            pulsante("Uscita", "minus", .red, LinkLife.uscita)
            pulsante("Entrata", "plus", .green, LinkLife.entrata)
        }
    }

    private func pulsante(_ t: String, _ icona: String, _ c: Color, _ url: URL) -> some View {
        Button(intent: OpenURLIntent(url)) {
            Label(t, systemImage: icona)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(c, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schermata di blocco

struct BloccoEventoWidget: View {
    let v: VoceWidget
    @Environment(\.widgetFamily) private var famiglia
    var body: some View {
        let d = v.dati
        let e = d?.prossimoDiOggi(v.date)
        Group {
            switch famiglia {
            case .accessoryInline:
                Text(e.map { "\($0.inizio ?? "") \($0.titolo)" } ?? "Niente più in calendario")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -1) {
                        Text(e?.inizio?.prefix(2) ?? "–").font(.system(size: 18, weight: .bold, design: .rounded))
                        Text(e?.inizio?.suffix(2) ?? "oggi").font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 0) {
                    if let e {
                        Label("\(e.inizio ?? "") – \(e.fine ?? "")", systemImage: "calendar").font(.system(size: 12, weight: .bold))
                        Text(e.titolo).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        if let s = e.luogo ?? e.calendario { Text(s).font(.system(size: 12)).lineLimit(1) }
                    } else {
                        Text("Oggi").font(.system(size: 13, weight: .bold))
                        Text("Niente più in calendario").font(.system(size: 13)).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(e.flatMap { x in d.map { LinkLife.evento(x, oggi: $0.oggi) } } ?? LinkLife.calendario)
    }
}

struct BloccoTodoWidget: View {
    let v: VoceWidget
    @Environment(\.widgetFamily) private var famiglia
    var body: some View {
        let task = v.dati?.task ?? []
        Group {
            switch famiglia {
            case .accessoryInline:
                Text(task.isEmpty ? "Tutto fatto" : "\(task.count) da fare oggi")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -1) {
                        Text(task.isEmpty ? "✓" : "\(task.count)").font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("to do").font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("TO DO · OGGI").font(.system(size: 12, weight: .bold))
                        Spacer()
                        Text("\(task.count)").font(.system(size: 16, weight: .bold))
                    }
                    if task.isEmpty { Text("Tutto fatto").font(.system(size: 14)) }
                    ForEach(task.prefix(2), id: \.self) { t in
                        Text("○ \(t.titolo)").font(.system(size: 13)).lineLimit(1)
                    }
                }
            }
        }
        .widgetURL(task.first.flatMap { $0.id }.map { LinkLife.task($0) } ?? LinkLife.todo)
    }
}
