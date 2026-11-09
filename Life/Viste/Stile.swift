import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 3 {
            self.init(red: Double((v >> 8) & 0xF) / 15, green: Double((v >> 4) & 0xF) / 15, blue: Double(v & 0xF) / 15)
        } else {
            self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        }
    }

    /// Colore di progetti e calendari: esadecimale o chiave storica.
    static func life(_ c: String?) -> Color {
        let chiavi = ["blue": "#0A84FF", "purple": "#AF52DE", "green": "#34C759", "orange": "#FF9500", "pink": "#FF2D55", "yellow": "#FFCC00", "gray": "#8E8E93"]
        guard let c, !c.isEmpty else { return Color(hex: "#8E8E93") }
        return Color(hex: c.hasPrefix("#") ? c : chiavi[c] ?? "#8E8E93")
    }

    static let accentoLife = Color(hex: "#0A84FF")
    static let sfondoLife = Color(uiColor: .systemGroupedBackground)
    static let cartaLife = Color(uiColor: .secondarySystemGroupedBackground)
    static let secondarioLife = Color(uiColor: .secondaryLabel)
    static let terziarioLife = Color(uiColor: .tertiaryLabel)
    static let lineaLife = Color(uiColor: .separator)
    static let pericoloLife = Color(hex: "#FF453A")
    static let successoLife = Color(hex: "#34C759")
    static let rosaLife = Color(hex: "#F23D5C")
}

/// I moduli: nome, colore e icona (come src/atlas/registro.ts).
struct Modulo: Identifiable, Hashable {
    let id: String
    let nome: String
    let colore: String
    let icona: String

    /// Moduli in pausa: spariscono dalla home ma i dati restano (come IN_PAUSA in src/atlas/registro.ts).
    /// Sezione: in pausa dal 9/11, fuori servizio. Per riattivarlo basta toglierlo da qui.
    static let inPausa: Set<String> = ["sezione"]
    static let elenco = [
        Modulo(id: "finanze", nome: "Finanze", colore: "#FF9500", icona: "eurosign.circle.fill"),
        Modulo(id: "abitudini", nome: "Abitudini", colore: "#5E5CE6", icona: "checkmark.seal.fill"),
        Modulo(id: "allenamenti", nome: "Training", colore: "#FF453A", icona: "figure.run"),
        Modulo(id: "mobilita", nome: "Mobilità", colore: "#30B0C7", icona: "figure.flexibility"),
        Modulo(id: "pasti", nome: "Pasti", colore: "#FF2D55", icona: "fork.knife"),
        Modulo(id: "sezione", nome: "Sezione", colore: "#A2845E", icona: "person.3.fill"),
    ]
    static let tutti = elenco.filter { !inPausa.contains($0.id) }
    static let todo = Modulo(id: "todo", nome: "To do", colore: "#34C759", icona: "checkmark.square.fill")
    static let calendario = Modulo(id: "calendario", nome: "Calendario", colore: "#FF453A", icona: "calendar")
    /// Tutte le mini-app di Life, con la stessa dignità.
    static let app = [todo, calendario] + tutti
    static func di(_ id: String) -> Modulo? { ([todo, calendario] + elenco).first { $0.id == id } }
}

/// Una carta con gli angoli stondati, come le liste raggruppate di iOS.
struct Carta<Contenuto: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var contenuto: () -> Contenuto
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { contenuto() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Titoletto di sezione in stile iOS.
struct Sezione<Contenuto: View, Coda: View>: View {
    let titolo: String
    var coda: Coda
    @ViewBuilder var contenuto: () -> Contenuto

    init(_ titolo: String, @ViewBuilder coda: () -> Coda, @ViewBuilder contenuto: @escaping () -> Contenuto) {
        self.titolo = titolo
        self.coda = coda()
        self.contenuto = contenuto
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(titolo).font(.title3.weight(.semibold))
                Spacer()
                coda.font(.footnote).foregroundStyle(Color.secondarioLife)
            }
            .padding(.horizontal, 4)
            contenuto()
        }
    }
}

extension Sezione where Coda == EmptyView {
    init(_ titolo: String, @ViewBuilder contenuto: @escaping () -> Contenuto) {
        self.init(titolo, coda: { EmptyView() }, contenuto: contenuto)
    }
}

/// Riga etichetta · valore.
struct RigaValore: View {
    let etichetta: String
    let valore: String
    var colore: Color? = nil
    var body: some View {
        HStack {
            Text(etichetta).foregroundStyle(Color.secondarioLife)
            Spacer()
            Text(valore).monospacedDigit().foregroundStyle(colore ?? Color.primary)
        }
        .font(.subheadline)
    }
}

/// L'anello di avanzamento.
struct Anello: View {
    let valore: Double
    var misura: CGFloat = 46
    var spessore: CGFloat = 6
    var colore: Color = .accentoLife
    var body: some View {
        ZStack {
            Circle().stroke(colore.opacity(0.18), lineWidth: spessore)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, valore.isNaN ? 0 : valore))))
                .stroke(colore, style: StrokeStyle(lineWidth: spessore, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: valore)
        }
        .frame(width: misura, height: misura)
    }
}

/// Barra di avanzamento sottile.
struct Barra: View {
    let valore: Double
    var colore: Color = .accentoLife
    var altezza: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(colore.opacity(0.16))
                Capsule().fill(colore).frame(width: g.size.width * CGFloat(min(1, max(0, valore.isNaN ? 0 : valore))))
            }
        }
        .frame(height: altezza)
    }
}

/// Una pillola selezionabile.
struct Pillola: View {
    let testo: String
    var attiva: Bool = false
    var colore: Color = .accentoLife
    var azione: () -> Void = {}
    var body: some View {
        Button(action: { tocco(); azione() }) {
            Text(testo)
                .font(.footnote.weight(attiva ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .foregroundStyle(attiva ? Color.white : Color.primary)
                .background(attiva ? colore : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Un grosso numero con la sua etichetta.
struct Dato: View {
    let etichetta: String
    let valore: String
    var colore: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(etichetta).font(.caption).foregroundStyle(Color.secondarioLife)
            Text(valore).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(colore ?? Color.primary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pulsante d'azione pieno.
struct PulsantePieno: View {
    let testo: String
    var colore: Color = .accentoLife
    var icona: String? = nil
    var azione: () -> Void
    var body: some View {
        Button(action: { tocco(); azione() }) {
            HStack(spacing: 6) {
                if let icona { Image(systemName: icona) }
                Text(testo).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(colore, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

func tocco() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

/// Foglio con «Annulla» e «Fatto» in alto, usato da tutti i moduli.
struct Foglio<Contenuto: View>: View {
    let titolo: String
    var fatto: String = "Fatto"
    var puoFare: Bool = true
    var azione: (() -> Void)? = nil
    @ViewBuilder var contenuto: () -> Contenuto
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            contenuto()
                .navigationTitle(titolo)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(azione == nil ? "Chiudi" : "Annulla") { chiudi() }
                    }
                    if let azione {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(fatto) {
                                azione()
                                chiudi()
                            }
                            .fontWeight(.semibold)
                            .disabled(!puoFare)
                        }
                    }
                }
        }
    }
}

/// Il contenitore ordinato delle schermate dei moduli.
struct Pagina<Contenuto: View>: View {
    @ViewBuilder var contenuto: () -> Contenuto
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { contenuto() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
        }
        .background(Color.sfondoLife)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Un importo in euro scritto a mano → centesimi (stessa regola del sito).
func centesimi(_ testo: String) -> Int? { Logica.s.chiama("ui.centesimi", .str(testo)).int }
func euro(_ c: Double, segno: Bool = false, tondo: Bool = false) -> String {
    Logica.s.chiama("ui.euro", .num(c), ["segno": .bool(segno), "tondo": .bool(tondo)]).t
}
func euro(_ v: J, segno: Bool = false, tondo: Bool = false) -> String { euro(v.d, segno: segno, tondo: tondo) }
