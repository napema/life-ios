import SwiftUI

/// L'accesso: codice via email oppure password. Stesso account del sito.
struct Accesso: View {
    @ObservedObject private var rete = Rete.s
    @State private var email = ""
    @State private var codice = ""
    @State private var password = ""
    @State private var modo = Modo.email
    @State private var occupato = false
    @State private var errore: String?

    enum Modo { case email, codice, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 60)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentoLife)
                Text("Life").font(.largeTitle.bold())

                VStack(spacing: 12) {
                    if modo != .codice {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .campo()
                    }
                    if modo == .password {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .campo()
                        PulsantePieno(testo: occupato ? "Accesso…" : "Accedi") { esegui { try await rete.accedi(email: pulita, password: password) } }
                        Button("Accedi con il codice via email") { modo = .email }.font(.subheadline)
                    }
                    if modo == .email {
                        PulsantePieno(testo: occupato ? "Invio…" : "Inviami il codice") {
                            esegui {
                                try await rete.inviaCodice(email: pulita)
                                modo = .codice
                            }
                        }
                        Button("Ho già un link o un codice") { modo = .codice }.font(.subheadline)
                        Button("Accedi con la password") { modo = .password }.font(.subheadline)
                    }
                    if modo == .codice {
                        Text(email.isEmpty ? "Incolla il link dell'email." : "Ti ho scritto a \(email). Scrivi il codice o incolla il link dell'email.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondarioLife)
                            .multilineTextAlignment(.center)
                        TextField("Codice o link", text: $codice)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .campo()
                        PulsantePieno(testo: occupato ? "Verifica…" : "Accedi") { verifica() }
                        Button("Usa un'altra email") { modo = .email }.font(.subheadline)
                    }
                }
                if let errore {
                    Text(errore).font(.subheadline).foregroundStyle(Color.pericoloLife).multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
        }
        .background(Color.sfondoLife)
        .disabled(occupato)
    }

    private var pulita: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func verifica() {
        let v = codice.trimmingCharacters(in: .whitespacesAndNewlines)
        esegui {
            if v.lowercased().hasPrefix("http") || v.contains("#") {
                try await rete.verificaLink(v)
            } else {
                try await rete.verificaCodice(email: pulita, codice: v.filter(\.isNumber))
            }
        }
    }

    private func esegui(_ fai: @escaping () async throws -> Void) {
        occupato = true
        errore = nil
        Task { @MainActor in
            do {
                try await fai()
            } catch {
                errore = error.localizedDescription
            }
            occupato = false
        }
    }
}

extension View {
    /// Un campo di testo pieno, alto da toccare.
    func campo() -> some View {
        padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.cartaLife, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
