import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Il vassoio condiviso col notch di Life sul PC (il «Beam» di Droppy): foto, file e testi passano
// da qui al PC e dal PC a qui. Le righe stanno nella tabella `vassoio`, i file nello spazio privato
// «vassoio» di Supabase, sotto la cartella dell'utente. Dopo 3 giorni si puliscono da sole.

private let bluVassoio = Color(hex: "#0A84FF")

struct VistaVassoio: View {
    @State private var righe: [J] = []
    @State private var carico = false
    @State private var lavoro: String?
    @State private var errore: String?
    @State private var foto: [PhotosPickerItem] = []
    @State private var scegliFile = false
    @State private var scaricati: [String: URL] = [:]

    var body: some View {
        Pagina {
            Carta {
                Text("Manda al PC").font(.subheadline.weight(.semibold))
                Text("Arriva nel vassoio del notch di Life, sul PC.").font(.footnote).foregroundStyle(Color.secondarioLife)
                HStack(spacing: 8) {
                    PhotosPicker(selection: $foto, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                        Label("Foto", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { scegliFile = true } label: {
                        Label("File", systemImage: "doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { Task { await inviaTesto() } } label: {
                        Label("Appunti", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .tint(bluVassoio)
                if let lavoro {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(lavoro).font(.footnote).foregroundStyle(Color.secondarioLife)
                    }
                }
                if let errore {
                    Text(errore).font(.footnote).foregroundStyle(Color.pericoloLife)
                }
            }

            let dalPc = righe.filter { $0.da.t == "pc" }
            Sezione("Dal PC") {
                Carta(padding: 6) {
                    if dalPc.isEmpty {
                        Text(carico ? "Niente per ora. Dal notch: clic destro su un file → Invia a iPhone." : "Carico…")
                            .font(.footnote).foregroundStyle(Color.secondarioLife).padding(10)
                    }
                    ForEach(dalPc, id: \.id) { r in rigaPc(r) }
                }
            }
            let inviati = righe.filter { $0.da.t == "iphone" }
            if !inviati.isEmpty {
                Sezione("Inviati al PC") {
                    Carta(padding: 6) {
                        ForEach(inviati, id: \.id) { r in
                            HStack(spacing: 10) {
                                Image(systemName: r.testo.isNull ? "doc" : "text.quote").foregroundStyle(Color.secondarioLife).frame(width: 28)
                                Text(r.testo.str ?? r.nome.t).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(r.ritirato_pc.vero ? "Arrivato" : "In attesa").font(.caption).foregroundStyle(r.ritirato_pc.vero ? Color.successoLife : Color.secondarioLife)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                    }
                }
            }
            Text("I file restano 3 giorni, poi si cancellano da soli. Massimo 50 MB a file.").font(.caption).foregroundStyle(Color.secondarioLife).padding(.horizontal, 4)
        }
        .navigationTitle("Vassoio")
        .refreshable { await carica() }
        .task { await carica() }
        .onChange(of: foto) { _, nuove in
            guard !nuove.isEmpty else { return }
            Task { await inviaFoto(nuove) }
        }
        .fileImporter(isPresented: $scegliFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { esito in
            if case .success(let urls) = esito { Task { await inviaFile(urls) } }
        }
    }

    private func rigaPc(_ r: J) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer").foregroundStyle(bluVassoio).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.nome.t).font(.subheadline).lineLimit(1)
                Text(peso(r.byte.d)).font(.caption).foregroundStyle(Color.secondarioLife)
            }
            Spacer()
            if let url = scaricati[r.id.t] {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            } else {
                Button("Scarica") { Task { await scarica(r) } }.font(.subheadline.weight(.semibold)).foregroundStyle(bluVassoio)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func peso(_ b: Double) -> String {
        b < 1024 * 1024 ? "\(Int(b / 1024)) KB" : String(format: "%.1f MB", b / 1024 / 1024).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Rete

    private var base: String { Config.supabaseUrl }

    private func carica() async {
        do {
            righe = try await Rete.s.righe("vassoio", "select=*&order=creato.desc", da: 0, a: 99)
            errore = nil
        } catch {
            errore = "Non riesco a leggere il vassoio: \(error.localizedDescription)"
        }
        carico = true
    }

    private func percorsoUrl(_ p: String) -> String {
        p.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
    }

    private func invia(dati: Data, nome: String) async throws {
        guard let uid = Rete.s.sessione?.userId else { throw ErroreRete(messaggio: "Accedi a Life") }
        let id = UUID().uuidString.lowercased()
        let percorso = "\(uid)/\(id)/\(nome)"
        _ = try await Rete.s.chiedi("\(base)/storage/v1/object/vassoio/\(percorsoUrl(percorso))", metodo: "POST", corpo: dati, intestazioni: ["Content-Type": "application/octet-stream", "x-upsert": "true"])
        let riga: J = ["id": .str(id), "nome": .str(nome), "percorso": .str(percorso), "byte": .num(Double(dati.count)), "da": "iphone"]
        _ = try await Rete.s.chiedi("\(base)/rest/v1/vassoio", metodo: "POST", corpo: J.arr([riga]).codificato)
    }

    private func inviaFoto(_ elementi: [PhotosPickerItem]) async {
        lavoro = "Invio \(elementi.count) al PC…"
        errore = nil
        for (i, e) in elementi.enumerated() {
            do {
                guard let dati = try await e.loadTransferable(type: Data.self) else { continue }
                let ext = e.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                try await invia(dati: dati, nome: "Foto \(Tempo.oggi()) \(i + 1).\(ext)")
            } catch {
                errore = error.localizedDescription
            }
        }
        foto = []
        lavoro = nil
        UINotificationFeedbackGenerator().notificationOccurred(errore == nil ? .success : .error)
        await carica()
    }

    private func inviaFile(_ urls: [URL]) async {
        lavoro = "Invio \(urls.count) al PC…"
        errore = nil
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            do {
                let dati = try Data(contentsOf: u)
                try await invia(dati: dati, nome: u.lastPathComponent)
            } catch {
                errore = error.localizedDescription
            }
        }
        lavoro = nil
        UINotificationFeedbackGenerator().notificationOccurred(errore == nil ? .success : .error)
        await carica()
    }

    private func inviaTesto() async {
        guard let testo = UIPasteboard.general.string, !testo.isEmpty else {
            errore = "Negli appunti non c'è testo"
            return
        }
        do {
            let riga: J = ["nome": "Testo", "testo": .str(testo), "da": "iphone"]
            _ = try await Rete.s.chiedi("\(base)/rest/v1/vassoio", metodo: "POST", corpo: J.arr([riga]).codificato)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await carica()
        } catch {
            errore = error.localizedDescription
        }
    }

    private func scarica(_ r: J) async {
        lavoro = "Scarico \(r.nome.t)…"
        do {
            let (dati, _) = try await Rete.s.chiedi("\(base)/storage/v1/object/vassoio/\(percorsoUrl(r.percorso.t))", metodo: "GET")
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vassoio", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(r.nome.t)
            try dati.write(to: url, options: .atomic)
            scaricati[r.id.t] = url
            _ = try? await Rete.s.chiedi("\(base)/rest/v1/vassoio?id=eq.\(r.id.t)", metodo: "PATCH", corpo: (J.obj(["ritirato_iphone": J.bool(true)])).codificato)
        } catch {
            errore = error.localizedDescription
        }
        lavoro = nil
    }
}
