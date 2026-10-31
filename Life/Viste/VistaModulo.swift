import SwiftUI

/// Il guscio dei moduli: si apre a tutto schermo dalla home, con «App» per tornare.
struct VistaModulo: View {
    let modulo: Modulo
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            Group {
                switch modulo.id {
                case "finanze": VistaFinanze()
                case "abitudini": VistaAbitudini()
                case "allenamenti": VistaTraining()
                case "mobilita": VistaMobilita()
                case "pasti": VistaPasti()
                default: EmptyView()
                }
            }
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        tocco()
                        chiudi()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                            Text("App")
                        }
                    }
                }
            }
        }
        .tint(Color(hex: modulo.colore))
        .overlay(alignment: .top) {
            AvvisoModulo()
        }
    }
}

/// Gli avvisi dei moduli sopra a tutto (la Radice sta sotto il modulo a schermo intero).
private struct AvvisoModulo: View {
    @ObservedObject private var logica = Logica.s
    var body: some View {
        if let a = logica.avviso {
            AvvisoBanner(avviso: a).transition(.move(edge: .top).combined(with: .opacity)).padding(.top, 4)
        }
    }
}
