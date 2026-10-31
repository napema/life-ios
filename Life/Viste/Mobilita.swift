import AVFoundation
import PhotosUI
import SwiftUI

// Mobilità: la sessione di oggi, la settimana, il programma, i progressi, l'assessment.
// Programma e sessioni sono quelli di ATLAS (nel bundle JS); il player è nativo.

func mob(_ f: String, _ a: J...) -> J { Logica.s.chiama("mobilita.\(f)", argomenti: a) }
private let accentoMob = Color(hex: "#30B0C7")
private func minuti(_ s: Double) -> Int { max(1, Int((s / 60).rounded())) }
private let radiceClip = "https://life-assets.vercel.app/atlas-clip/"

private let nomiTipo: [String: (String, String)] = [
    "post-corsa": ("Post-corsa", "Hai corso: questa sostituisce il quotidiano, non si somma."),
    "quotidiano": ("Quotidiano", "Sul tappeto, la sera. Non deve farti sudare."),
    "loaded": ("Loaded mobility", "È il giorno di palestra. È allenamento vero: mai il giorno dopo le gambe."),
    "minima": ("Dose minima", "Per i giorni storti. Meglio due minuti che zero."),
]

private let bersagli = [("deep-squat", "Deep squat", "Profilo"), ("pike", "Pike / forward fold", "Profilo"), ("overhead-shoulder", "Overhead shoulder", "Profilo"), ("farfalla", "Simmetria farfalla", "Frontale"), ("collo", "Simmetria collo", "Frontale")]

/// Le foto stanno nei file dell'app, su questo dispositivo.
enum FotoMobilita {
    static var cartella: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("foto-mobilita", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func ultima(_ bersaglio: String, _ foto: [J]) -> UIImage? {
        guard let r = foto.filter({ !$0.del.vero && $0.bersaglioId.t == bersaglio }).max(by: { $0.up.d < $1.up.d }) else { return nil }
        return UIImage(contentsOfFile: cartella.appendingPathComponent("\(r.id.t).jpg").path)
    }

    /// Stessa compressione del sito: 1400 px di lato massimo, qualità 0,82.
    static func salva(_ bersaglio: String, _ dati: Data) {
        guard let img = UIImage(data: dati) else { return }
        let scala = min(1, 1400 / max(img.size.width, img.size.height))
        let misura = CGSize(width: img.size.width * scala, height: img.size.height * scala)
        let ridotta = UIGraphicsImageRenderer(size: misura).image { _ in img.draw(in: CGRect(origin: .zero, size: misura)) }
        let id = "\(bersaglio)-\(Int(Date().timeIntervalSince1970 * 1000))"
        try? ridotta.jpegData(compressionQuality: 0.82)?.write(to: cartella.appendingPathComponent("\(id).jpg"))
        mob("registraFoto", .str(bersaglio), .str(id))
    }
}

struct VistaMobilita: View {
    @ObservedObject private var logica = Logica.s
    @State private var scheda = "oggi"
    @State private var player: IdTesto?
    @State private var assessment = false

    var body: some View {
        let _ = logica.versione
        return Pagina {
            Picker("Scheda", selection: $scheda) {
                Text("Oggi").tag("oggi")
                Text("Progressi").tag("progressi")
                Text("Altro").tag("altro")
            }
            .pickerStyle(.segmented)
            switch scheda {
            case "progressi": progressi
            case "altro": altro
            default: oggi
            }
        }
        .navigationTitle("Mobilità")
        .fullScreenCover(item: $player) { p in PlayerMobilita(tipo: p.id) }
        .sheet(isPresented: $assessment) { Assessment() }
    }

    // MARK: Oggi

    @ViewBuilder
    private var oggi: some View {
        let state = mob("ponte.getState")
        let iso = mob("sessione.oggiISO")
        let gc = state.giornoCorrente.data == iso ? state.giornoCorrente : J.null
        let haCorso = gc.haCorso.vero
        let tipo = gc.forza.str ?? mob("sessione.tipoDelGiorno", state, .bool(haCorso)).t
        let passi = mob("sessione.costruisciSessione", state, .str(tipo)).passi
        let settimana = mob("sessione.settimanaEffettiva", state)
        let fase = mob("esercizi.fasePerSettimana", settimana)
        let moduli = mob("sessione.riepilogoModuli", passi).list
        let durata = passi.list.reduce(0) { $0 + $1.durataSec.d }
        let fatte = Set(state.storicoSessioni.list.map(\.data.t))
        let fattaOggi = fatte.contains(iso.t)
        let inizio = mob("sessione.addGiorni", iso, .num(-mob("sessione.giornoSettimana", iso).d)).t
        let palestra = state.programma.giornoPalestra.int ?? 2
        let giorni = (0..<7).map { i in (i, Tempo.piuGiorni(inizio, i)) }
        let nFatte = giorni.filter { fatte.contains($0.1) }.count
        let gruppi = mob("esercizi.rotazionePerSettimana", settimana).gruppi.list.compactMap { mob("esercizi.GRUPPI")[$0.t].nome.str }.joined(separator: " · ")
        let scrivi: (J, J) -> Void = { corso, forza in
            mob("scrivi", ["giornoCorrente"], ["data": iso, "haCorso": corso, "forza": forza])
        }

        Sezione("Hai corso oggi?") {
            Picker("Hai corso", selection: Binding(get: { haCorso }, set: { scrivi(.bool($0), nil) })) {
                Text("No").tag(false)
                Text("Sì, ho corso").tag(true)
            }
            .pickerStyle(.segmented)
        }
        Text("È l'unica cosa che devi dirmi: il resto lo decido io.").font(.caption).foregroundStyle(Color.secondarioLife)

        Blocco(eti: "Questa settimana", etiDx: "Settimana \(settimana.int ?? 1) · \(nFatte) di 7") {
            HStack {
                ForEach(giorni, id: \.0) { i, g in
                    let fatta = fatte.contains(g)
                    VStack(spacing: 3) {
                        Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.caption2).foregroundStyle(Color.secondarioLife)
                        ZStack {
                            Circle().fill(fatta ? Color.successoLife : .clear)
                            Circle().stroke(g == iso.t && !fatta ? accentoMob : .clear, lineWidth: 2)
                            if fatta {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                            } else {
                                Text("\(Tempo.parti(g).2)").font(.footnote).monospacedDigit().opacity(g > iso.t ? 0.4 : 1)
                            }
                        }
                        .frame(width: 32, height: 32)
                        Circle().fill(i == palestra ? accentoMob : .clear).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Il puntino segna il giorno di palestra.\(mob("sessione.streakAncoraValida", state).vero ? "" : " Più di 3 giorni fermi: lo streak riparte, il programma no.")").font(.caption).foregroundStyle(Color.secondarioLife)
        }

        Blocco(eti: nomiTipo[tipo]?.0 ?? "Sessione") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(minuti(durata))").font(.system(size: 44, weight: .semibold)).monospacedDigit().foregroundStyle(accentoMob)
                Text("min").foregroundStyle(Color.secondarioLife)
            }
            Text("\(passi.list.count) esercizi\(fattaOggi ? " · già fatta oggi" : "")").font(.footnote).foregroundStyle(Color.secondarioLife)
            if let p = nomiTipo[tipo]?.1 { Text(p).font(.subheadline) }
            ForEach(moduli, id: \.nome) { m in
                RigaFin(titolo: m.nome.t, sotto: m.muscoli.list.prefix(4).map(\.t).joined(separator: " · "), valore: "\(minuti(m.durataSec.d)) min")
            }
            PulsantePieno(testo: fattaOggi ? "Rifai" : "Inizia", colore: accentoMob, icona: "play.fill") { player = IdTesto(id: tipo) }
            if tipo != "minima" {
                PulsantePieno(testo: "Non ce la faccio — 2 minuti", colore: Color(uiColor: .systemGray)) { scrivi(.bool(haCorso), "minima") }
            } else if gc.forza.t == "minima" {
                PulsantePieno(testo: "Ho tempo — sessione completa", colore: Color(uiColor: .systemGray)) { scrivi(.bool(haCorso), nil) }
            }
        }

        Sezione("Il programma nel tempo") {
            Carta(padding: 12) {
                ForEach(mob("esercizi.PROGRESSIONE").list, id: \.self) { f in
                    let ora = f == fase
                    let da = f.settimane[0].int ?? 0
                    let a = f.settimane[1].int ?? 0
                    HStack(spacing: 10) {
                        Text(a == 99 ? "\(da)+" : "\(da)–\(a)").font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(ora ? accentoMob : Color.primary).frame(width: 46, alignment: .leading)
                        Text(f.note.t).font(.caption).foregroundStyle(Color.secondarioLife)
                        Spacer()
                        Text("\(f.minuti.int ?? 0) min").font(.footnote).monospacedDigit()
                    }
                    .padding(6)
                    .background(ora ? accentoMob.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .opacity((settimana.int ?? 1) > a ? 0.5 : 1)
                }
            }
        }
        Text("Il tempo sale solo se la settimana precedente è stata fatta almeno al 70%. Adesso: \(fase.minuti.int ?? 0) minuti, gruppi sopra soglia collo · \(gruppi).").font(.caption).foregroundStyle(Color.secondarioLife)
    }

    // MARK: Progressi

    private func descrivi(_ id: String, _ m: J) -> String? {
        switch id {
        case "deep-squat":
            guard let p = m.profonditaLivello.str else { return nil }
            let e = ["sopra-parallelo": "Sopra il parallelo", "parallelo": "Al parallelo", "sotto-parallelo": "Sotto il parallelo"]
            return (e[p] ?? p) + (m.talloniATerra == true ? " · talloni a terra" : m.talloniATerra == false ? " · talloni sollevati" : "")
        case "pike": return m.distanzaDitaPavimentoCm.isNull ? nil : "\(m.distanzaDitaPavimentoCm.t) cm dal pavimento"
        case "overhead-shoulder": return m.distanzaPolsoMuroCm.isNull ? nil : "\(m.distanzaPolsoMuroCm.t) cm dal muro\(m.lombarePiatta == true ? " · lombare piatta" : "")"
        case "farfalla":
            if m.altezzaGinocchioSxCm.isNull || m.altezzaGinocchioDxCm.isNull { return nil }
            return "Sx \(m.altezzaGinocchioSxCm.t) cm · Dx \(m.altezzaGinocchioDxCm.t) cm · differenza \(abs(m.altezzaGinocchioSxCm.d - m.altezzaGinocchioDxCm.d)) cm"
        case "collo": return m.angoloDxGradi.isNull || m.angoloSxGradi.isNull ? nil : "Dx \(m.angoloDxGradi.t)° · Sx \(m.angoloSxGradi.t)°"
        default: return nil
        }
    }

    @ViewBuilder
    private var progressi: some View {
        let state = mob("ponte.getState")
        let oggi = mob("sessione.oggiISO").t
        let fatte = Set(state.storicoSessioni.list.map(\.data.t))
        let finestra = Set((0..<7).map { Tempo.piuGiorni(oggi, -$0) })
        let volumi = state.storicoSessioni.list.filter { finestra.contains($0.data.t) }.reduce(into: [String: Double]()) { m, s in
            for (g, v) in s.volumePerGruppo.dict { m[g, default: 0] += v.d }
        }
        let gruppi = volumi.sorted { $0.value > $1.value }
        let sotto = gruppi.filter { $0.value < 300 }.count
        let datiBersagli = state.assessment.baselineTest3.bersagli
        let ultimaFoto = bersagli.compactMap { datiBersagli[$0.0].fotoData.str }.max()
        let nomi = ["gluteo": "Glutei", "anca-laterale": "Anca laterale", "quadricipite": "Quadricipiti", "obliqui": "Obliqui", "adduttori": "Adduttori", "femorali": "Femorali", "caviglia": "Caviglia", "caviglia-anca": "Caviglia e anca", "soleo": "Soleo", "addominali": "Addominali", "dorsali": "Dorsali", "spalle": "Spalle", "gran-dorsale": "Gran dorsale", "rotatori-anca": "Rotatori d'anca", "piriforme-gluteo": "Piriforme e gluteo", "collo-laterale": "Collo (laterale)", "collo-scaleno": "Collo (scaleni)"]

        Blocco(eti: "Costanza") {
            HStack {
                Dato(etichetta: "giorni di fila", valore: state.streak.giorniConsecutivi.t, colore: accentoMob)
                Dato(etichetta: "sessioni totali", valore: "\(state.storicoSessioni.list.count)")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(0..<28, id: \.self) { i in
                    let g = Tempo.piuGiorni(oggi, -(27 - i))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(fatte.contains(g) ? Color.successoLife : Color(uiColor: .tertiarySystemFill))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(g == oggi ? accentoMob : .clear, lineWidth: 2))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            Text("È la metrica che conta davvero: il programma riesce se i giorni si accumulano, non se guadagni gradi in fretta.").font(.caption).foregroundStyle(Color.secondarioLife)
        }
        Sezione("Volume, ultimi 7 giorni") {
            if gruppi.isEmpty {
                Text("Nessuna sessione negli ultimi 7 giorni: qui comparirà quanto lavoro ha ricevuto ogni gruppo muscolare.").font(.footnote).foregroundStyle(Color.secondarioLife)
            } else {
                Carta {
                    ForEach(gruppi, id: \.key) { g, sec in
                        VStack(spacing: 3) {
                            HStack {
                                Text(nomi[g] ?? g).font(.footnote)
                                Spacer()
                                Text(String(format: "%d:%02d / 5:00", Int(sec) / 60, Int(sec) % 60)).font(.footnote).monospacedDigit().foregroundStyle(Color.secondarioLife)
                            }
                            Barra(valore: sec / 300, colore: sec < 300 ? arancioneAvviso : accentoMob)
                        }
                    }
                }
                Text("Soglia di adattamento: 5 minuti a settimana per gruppo. \(sotto > 0 ? "\(sotto) \(sotto == 1 ? "gruppo è" : "gruppi sono") sotto soglia: normale nei primi giorni, si riempie con la costanza." : "Tutti i gruppi sono sopra soglia.")").font(.caption).foregroundStyle(Color.secondarioLife)
            }
        }
        Sezione("I cinque bersagli") {
            Carta(padding: 12) {
                ForEach(bersagli, id: \.0) { b in
                    HStack(spacing: 10) {
                        if let img = FotoMobilita.ultima(b.0, state.foto.list) {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "camera").foregroundStyle(Color.secondarioLife).frame(width: 40, height: 40).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.1).font(.subheadline)
                            Text(descrivi(b.0, datiBersagli[b.0].misure) ?? "Baseline non ancora inserita").font(.caption).foregroundStyle(Color.secondarioLife)
                        }
                    }
                }
            }
        }
        Text({
            guard let f = ultimaFoto else { return "Aggiungi le foto baseline dall'assessment: sono il termine di paragone per capire se stai migliorando." }
            let passati = mob("sessione.giorniTra", .str(String(f.prefix(10))), .str(oggi)).int ?? 0
            let mancano = 21 - passati
            return mancano > 0 ? "Prossimo controllo fotografico tra \(mancano) giorni. Stessa posa, stessa distanza, stessa luce." : "È ora di rifare le foto: sono passati \(passati) giorni. Stessa posa, stessa distanza, stessa luce."
        }()).font(.caption).foregroundStyle(Color.secondarioLife)
    }

    // MARK: Altro

    @ViewBuilder
    private var altro: some View {
        let s = mob("dati.stato")
        let p = s.meta.programma
        let a = s.meta.assessment
        let settimana = mob("sessione.settimanaEffettiva", mob("ponte.getState"))
        let oggi = mob("sessione.oggiISO")
        let forza = s.giornoCorrente.data == oggi ? s.giornoCorrente.forza : J.null
        Sezione("Il programma") {
            Carta(padding: 12) {
                RigaFin(titolo: "Settimana", valore: "\(settimana.int ?? 1) (effettiva)")
                RigaFin(titolo: "Sessioni", valore: "\(mob("dati.sessioniVive").list.count) in totale")
                if p.inizioProgramma.vero {
                    RigaFin(titolo: "Iniziato", valore: dataUmana(p.inizioProgramma.t))
                } else {
                    RigaFin(titolo: "Fai partire il programma da oggi", accento: true) {
                        mob("meta", ["programma", "inizioProgramma"], oggi)
                        avviso("Programma avviato.")
                    }
                }
            }
        }
        Text("La settimana effettiva sale solo se il blocco precedente è stato fatto almeno al 70% dei giorni.").font(.caption).foregroundStyle(Color.secondarioLife)
        Sezione("Giorno di palestra") {
            Picker("Giorno", selection: Binding(get: { p.giornoPalestra.int ?? 2 }, set: { v in
                mob("meta", ["programma", "giornoPalestra"], .n(v))
                avviso("Salvato.")
            })) {
                ForEach(Array(["lun", "mar", "mer", "gio", "ven", "sab", "dom"].enumerated()), id: \.offset) { i, g in Text(g).tag(i) }
            }
            .pickerStyle(.segmented)
        }
        Text("In quel giorno l'app propone la sessione sotto carico invece del quotidiano. Mai il giorno dopo le gambe.").font(.caption).foregroundStyle(Color.secondarioLife)
        Sezione("L'aggancio") {
            Carta {
                TextField("Subito dopo la doccia serale", text: Binding(get: { p.aggancio.t }, set: { mob("meta", ["programma", "aggancio"], .str($0)) }))
            }
        }
        Text("Un'abitudine attaccata a una cosa che fai già regge molto più di una attaccata a un orario.").font(.caption).foregroundStyle(Color.secondarioLife)
        Sezione("Assessment") {
            Carta(padding: 12) {
                RigaFin(titolo: "Completato", valore: a.completato.vero ? "sì" : "no")
                RigaFin(titolo: "Lato lateralizzato", valore: a.esitoTest2.latoLateralizzato.str?.uppercased() ?? "non rilevato")
                RigaFin(titolo: "Baseline fotografica", valore: a.baselineTest3.completatoIl.str.map(dataUmana) ?? "mai fatta")
                RigaFin(titolo: a.completato.vero ? "Rifai l'assessment" : "Fai l'assessment", accento: true, freccia: true) { assessment = true }
            }
        }
        Sezione("Oggi") {
            Carta(padding: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mob("dati.TIPI_SESSIONE").dict.sorted { $0.key < $1.key }, id: \.key) { k, v in
                            Pillola(testo: v.nome.t, attiva: forza.str == k, colore: accentoMob) {
                                mob("dati.segnaGiorno", ["data": oggi, "forza": .str(k)])
                                avviso("Oggi: \(v.nome.t).")
                            }
                        }
                    }
                }
                if !forza.isNull {
                    RigaFin(titolo: "Lascia decidere all'app", accento: true) {
                        mob("dati.segnaGiorno", ["data": oggi, "forza": nil])
                        avviso("Scelta automatica.")
                    }
                }
            }
        }
        Text("Di norma è l'app a decidere che sessione fare. Da qui puoi forzarla per oggi.").font(.caption).foregroundStyle(Color.secondarioLife)
    }
}

// MARK: - Player

/// La clip che gira in loop, muta.
struct ClipVideo: UIViewRepresentable {
    let url: URL

    final class Vista: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var livello: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> Vista {
        let v = Vista()
        v.livello.videoGravity = .resizeAspect
        v.backgroundColor = .black
        carica(v)
        return v
    }

    func updateUIView(_ v: Vista, context: Context) {
        if ((v.livello.player?.currentItem?.asset) as? AVURLAsset)?.url != url { carica(v) }
    }

    private func carica(_ v: Vista) {
        let p = AVQueuePlayer()
        p.isMuted = true
        v.looper = AVPlayerLooper(player: p, templateItem: AVPlayerItem(url: url))
        v.livello.player = p
        p.play()
    }
}

/// I bip passano da AVAudioPlayer in categoria «playback»: si sentono anche col Silenzioso.
final class Bip {
    static let s = Bip()
    private var giocatori: [String: AVAudioPlayer] = [:]
    private let voci: [String: (Double, Double, Double)] = ["inizio": (1180, 0.12, 0.22), "fine": (760, 0.18, 0.22), "meno3": (560, 0.09, 0.10), "meno2": (700, 0.09, 0.15), "meno1": (880, 0.09, 0.22)]

    func prepara() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func suona(_ nome: String) {
        if giocatori[nome] == nil, let v = voci[nome], let p = try? AVAudioPlayer(data: wav(v.0, v.1, v.2)) { giocatori[nome] = p }
        giocatori[nome]?.currentTime = 0
        giocatori[nome]?.play()
    }

    private func wav(_ f: Double, _ durata: Double, _ guadagno: Double) -> Data {
        let sr = 22050
        let n = Int(Double(sr) * durata)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + n * 2))
        d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sr))
        u32(UInt32(sr * 2))
        u16(2)
        u16(16)
        d.append(contentsOf: Array("data".utf8))
        u32(UInt32(n * 2))
        for i in 0..<n {
            let t = Double(i) / Double(sr)
            let inviluppo = min(1, min(t / 0.008, (durata - t) / 0.03))
            let s = sin(2 * .pi * f * t) * guadagno * max(0, inviluppo)
            u16(UInt16(bitPattern: Int16(s * 32767)))
        }
        return d
    }
}

struct PlayerMobilita: View {
    let tipo: String
    @State private var fase = "vuota"
    @State private var lavoro: [J] = []
    @State private var passi: [J] = []
    @State private var indice = 0
    @State private var residui = 0
    @State private var inPausa = false
    @State private var ripresa: J = .null
    @State private var esito: J = .null
    @Environment(\.dismiss) private var chiudi
    private let battito = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var step: J { passi.indices.contains(indice) ? passi[indice] : .null }
    private var totaleSec: Double { passi.reduce(0) { $0 + $1.durataSec.d } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { esci() } label: { Image(systemName: "xmark").frame(width: 36, height: 36).background(Color(uiColor: .tertiarySystemFill), in: Circle()) }
                Spacer()
                if fase == "corso", !step.isNull {
                    Text("\(dettaglio.numero.int ?? indice + 1) di \(lavoro.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                Spacer()
                if fase == "corso" {
                    Button { inPausa.toggle() } label: { Image(systemName: inPausa ? "play.fill" : "pause.fill").frame(width: 36, height: 36).background(Color(uiColor: .tertiarySystemFill), in: Circle()) }
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if fase == "corso" {
                let resto = passi.dropFirst(indice + 1).reduce(0) { $0 + $1.durataSec.d } + Double(max(residui, 0))
                Barra(valore: totaleSec > 0 ? (totaleSec - resto) / totaleSec : 0, colore: accentoMob, altezza: 4).padding(.horizontal, 16)
            }
            contenuto
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear(perform: inizia)
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(battito) { _ in tick() }
    }

    private var dettaglio: J { step.tipo.t == "prep" ? step.rif : step }

    @ViewBuilder
    private var contenuto: some View {
        switch fase {
        case "ripresa":
            centro("clock", Color(hex: "#0A84FF")) {
                Text("Avevi lasciato a metà").font(.title.bold())
                let n = min(ripresa.numero.int ?? 1, lavoro.count)
                Text("Eri all'esercizio \(n) di \(lavoro.count): \(lavoro.indices.contains(n - 1) ? lavoro[n - 1].nome.t : "").").font(.subheadline).foregroundStyle(Color.secondarioLife).multilineTextAlignment(.center)
            }
            VStack(spacing: 8) {
                PulsantePieno(testo: "Riprendi da qui", colore: accentoMob) { avvia(da: ripresa) }
                PulsantePieno(testo: "Ricomincia da capo", colore: Color(uiColor: .systemGray)) {
                    mob("scrivi", ["sessioneInCorso"], nil)
                    avvia(da: nil)
                }
            }
            .padding(16)
        case "collo":
            let g1 = mob("esercizi.G1")
            centro("exclamationmark.triangle", Color(hex: "#FF9500")) {
                Text("Prima del modulo collo").font(.title.bold())
                Text(g1.avviso.t).font(.subheadline).multilineTextAlignment(.center)
                Text("Intensità \(g1.intensita.t). Compare una sola volta.").font(.caption).foregroundStyle(Color.secondarioLife)
            }
            PulsantePieno(testo: "Ho capito, continua", colore: accentoMob) {
                mob("scrivi", ["programma", "avvisoColloMostrato"], true)
                avvia(da: nil)
            }
            .padding(16)
        case "fine":
            centro("checkmark", .successoLife) {
                Text("Fatta").font(.largeTitle.bold())
                Text("\(esito.minuti.int ?? 0) minuti · \(esito.streak.int ?? 0) \(esito.streak.int == 1 ? "giorno" : "giorni") di fila.").font(.subheadline).foregroundStyle(Color.secondarioLife)
                Text("Due buchi a settimana sono dentro il piano.").font(.caption).foregroundStyle(Color.secondarioLife)
            }
            PulsantePieno(testo: "Chiudi", colore: accentoMob) { chiudi() }.padding(16)
        case "corso":
            corso
        default:
            Spacer()
            Text("Nessun esercizio per questa sessione.").font(.headline)
            Spacer()
        }
    }

    private func centro<C: View>(_ icona: String, _ colore: Color, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icona).font(.largeTitle).foregroundStyle(colore).frame(width: 64, height: 64).background(colore.opacity(0.18), in: Circle())
            c()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var corso: some View {
        let d = dettaglio
        let inPrep = step.tipo.t == "prep"
        let stato = inPrep ? "Preparati" : d.faseRipetuta.t == "pausa" ? "Rilascia" : d.faseRipetuta.t == "lavoro" ? "Spingi" : "Tieni la posizione"
        let conClip = d.idEsercizio.vero && mob("clip.CLIP").list.contains(d.idEsercizio)
        let nomeLato = d.lato.t == "dx" ? "destro" : "sinistro"
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if conClip, let u = URL(string: "\(radiceClip)\(d.idEsercizio.t).mp4") {
                    ClipVideo(url: u).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stato.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(inPrep ? arancioneAvviso : accentoMob)
                        Text("\(d.nome.t)\(d.lato.vero ? " — \(nomeLato)" : "")").font(.title2.bold())
                    }
                    Spacer()
                    Text("\(max(residui, 0))").font(.system(size: 56, weight: .semibold)).monospacedDigit()
                }
                if step.cambioLato.vero {
                    Label("Cambia lato: ora il \(nomeLato)", systemImage: "arrow.right").font(.subheadline).foregroundStyle(Color(hex: "#0A84FF")).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: "#0A84FF").opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                let c = chips(d)
                if !c.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(c.indices, id: \.self) { i in
                                Text(c[i].0).font(.caption).padding(.horizontal, 8).padding(.vertical, 3).foregroundStyle(c[i].1 ?? Color.primary).background((c[i].1 ?? Color.secondary).opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
                ForEach(Array(d.passi.list.enumerated()), id: \.offset) { i, t in
                    Text("\(i + 1). \(t.t)").font(.body)
                }
                if d.nota.vero { Text(d.nota.t).font(.caption).foregroundStyle(Color.secondarioLife) }
            }
            .padding(16)
        }
        PulsantePieno(testo: inPrep ? "Sono pronto" : "Avanti", colore: accentoMob) { prossimo() }.padding(16)
    }

    private func chips(_ d: J) -> [(String, Color?)] {
        let menta = Color(hex: "#30B0C7")
        let blu = Color(hex: "#0A84FF")
        let arancio = Color(hex: "#FF9500")
        var c: [(String, Color?)] = []
        if d.fonte.vero { c.append((d.fonte.t, menta)) }
        switch d.tag.t {
        case "M": c.append(("Attivo", menta))
        case "S": c.append(("Passivo", blu))
        case "R": c.append(("Rilascio", arancio))
        default: break
        }
        if d.badgeExtra.vero { c.append((d.badgeExtra.t, arancio)) }
        if d.lato.vero { c.append(("Lato \(d.lato.t == "dx" ? "destro" : "sinistro")\(d.extra.vero ? " · extra" : "")", blu)) }
        if d.carico.vero { c.append(("\(d.carico.t) kg", arancio)) }
        if d.ripetizioni.vero { c.append((d.ripetizioni.t, arancio)) }
        if d.serve.vero { c.append((d.serve.t, nil)) }
        for m in d.muscoli.list { c.append((m.t, nil)) }
        return c
    }

    private func inizia() {
        Bip.s.prepara()
        let state = mob("ponte.getState")
        lavoro = mob("sessione.costruisciSessione", state, .str(tipo)).passi.list
        guard !lavoro.isEmpty else { return }
        let p = state.sessioneInCorso
        if p.tipo.t == tipo, p.data == mob("sessione.oggiISO"), p.indice.d > 0 {
            ripresa = p
            fase = "ripresa"
            return
        }
        if !state.programma.avvisoColloMostrato.vero, lavoro.contains(where: { $0.gruppo.t == "G1" }) {
            fase = "collo"
            return
        }
        avvia(da: nil)
    }

    private func avvia(da: J?) {
        let visti = mob("ponte.getState").programma.videoVistiObbligatori
        passi = mob("sessione.conPreparazione", .arr(lavoro), visti.isNull ? [] : visti).list
        indice = 0
        if let i = da?.indice.int, i > 0, i < passi.count { indice = i }
        residui = step.durataSec.int ?? 0
        fase = "corso"
        inPausa = false
        UIApplication.shared.isIdleTimerDisabled = true
        Bip.s.suona("inizio")
    }

    private func tick() {
        guard fase == "corso", !inPausa else { return }
        residui -= 1
        if residui > 0, residui <= 3 { Bip.s.suona("meno\(residui)") }
        if residui <= 0 {
            Bip.s.suona(step.beep.t == "inizio" ? "inizio" : "fine")
            prossimo()
        }
    }

    private func prossimo() {
        if indice + 1 >= passi.count {
            let r = mob("sessione.registraCompletamento", .arr(lavoro), .str(tipo))
            esito = r
            avviso("Sessione registrata.")
            UIApplication.shared.isIdleTimerDisabled = false
            fase = "fine"
            return
        }
        indice += 1
        residui = step.durataSec.int ?? 0
    }

    private func esci() {
        if fase == "corso" {
            // Il punto in cui eri, come salvaPunto sul sito
            mob("scrivi", ["sessioneInCorso"], ["tipo": .str(tipo), "data": mob("sessione.oggiISO"), "indice": .n(indice), "numero": dettaglio.numero, "secondiResidui": .n(max(residui, 0))])
        }
        chiudi()
    }
}

// MARK: - Assessment

private let testAssessment: [(n: String, yt: String, up: Bool, verso: Bool, nome: String, q: String, perche: String)] = [
    ("01", "gQXcV3_JQdU", false, true, "Rotazione interna d'anca", "Su quale lato l'anca ruota di più verso l'interno?", "La rotazione interna è la posizione dell'appoggio medio. È migliore dove stai piantato."),
    ("02", "gQXcV3_JQdU", false, false, "Rotazione esterna d'anca", "Su quale lato l'anca ruota di più verso l'esterno?", "La rotazione esterna appartiene alla fase di volo. È migliore sul lato che eviti."),
    ("03", "O9nkFMg65QE", false, true, "Straight leg raise", "Da supino, quale gamba tesa sale più in alto?", "Oltre i 45° circa, alzare la gamba tesa è di fatto rotazione interna d'anca."),
    ("04", "9S10ShpPKto", false, false, "Flessione d'anca", "Quale ginocchio arriva più vicino al petto?", "La flessione profonda d'anca esprime rotazione esterna: è migliore sul lato da cui scappi."),
    ("05", "yodnktUmDLk", true, false, "Rotazione interna di spalla", "Quale spalla ruota di più verso l'interno?", "Il tronco è ruotato: la rotazione interna di spalla è migliore sul lato da cui scappi."),
    ("06", "00Yc2iLr1C8", true, true, "Rotazione esterna di spalla", "Quale spalla ruota di più verso l'esterno?", "Speculare al test 05: la rotazione esterna è migliore sul lato lateralizzato."),
    ("07", "xoI7lEcBspU", true, true, "Abduzione di spalla", "Quale braccio sale più in alto lateralmente?", "L'abduzione misura quanto bene il tronco riesce a girarsi verso quel lato."),
]

struct Assessment: View {
    @ObservedObject private var logica = Logica.s
    @State private var parte = "t1"
    @Environment(\.dismiss) private var chiudi

    private struct Conto {
        var fatti = 0
        var lato = "dx"
        var punteggio = 0
        var up: String?
        var low: String?
        var doppio = false
    }

    private func conta(_ r: [J]) -> Conto {
        var sx = 0, dx = 0, upSx = 0, upDx = 0, lowSx = 0, lowDx = 0, fatti = 0
        for (i, t) in testAssessment.enumerated() {
            guard i < r.count, let v = r[i].str else { continue }
            let voto = t.verso ? v : (v == "sx" ? "dx" : "sx")
            fatti += 1
            if voto == "sx" {
                sx += 1
                if t.up { upSx += 1 } else { lowSx += 1 }
            } else {
                dx += 1
                if t.up { upDx += 1 } else { lowDx += 1 }
            }
        }
        let lato = dx >= sx ? "dx" : "sx"
        let up: String? = upSx == 3 ? "sx" : upDx == 3 ? "dx" : nil
        let low: String? = lowSx >= 3 ? "sx" : lowDx >= 3 ? "dx" : nil
        return Conto(fatti: fatti, lato: lato, punteggio: lato == "dx" ? dx : sx, up: up, low: low, doppio: up != nil && low != nil && up != low)
    }

    var body: some View {
        let _ = logica.versione
        let a = mob("ponte.getState").assessment
        return Foglio(titolo: "Assessment") {
            Pagina {
                Picker("Parte", selection: $parte) {
                    Text("1 · Nervo").tag("t1")
                    Text("2 · Lato").tag("t2")
                    Text("3 · Bersagli").tag("t3")
                }
                .pickerStyle(.segmented)
                switch parte {
                case "t1": test1(a)
                case "t2": test2(a)
                default: test3(a)
                }
                PulsantePieno(testo: "Completa l'assessment", colore: accentoMob) {
                    mob("scrivi", ["assessment", "completato"], true)
                    mob("scrivi", ["metaUp"], .num(Date().timeIntervalSince1970 * 1000))
                    avviso("Assessment completato.")
                    chiudi()
                }
                Text("Si può tornare qui in qualsiasi momento: i valori già inseriti restano.").font(.caption).foregroundStyle(Color.secondarioLife).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
    }

    private func campoCm(_ et: String, _ v: J, unita: String = "cm", _ scrivi: @escaping (J) -> Void) -> some View {
        HStack {
            Text(et).font(.subheadline)
            Spacer()
            CampoNumero(valore: v.d, unita: unita, decimali: true) { n in scrivi(.num(n)) }
        }
    }

    private func esitoBox<C: View>(_ attesa: Bool, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) { c() }
            .font(.footnote)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(attesa ? Color(uiColor: .tertiarySystemFill) : accentoMob.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func test1(_ a: J) -> some View {
        let t = a.esitoTest1
        Text("Flessione in avanti in tre versioni consecutive, a freddo. In ciascuna misura la distanza fra le dita e il pavimento, in centimetri (0 o negativo se lo tocchi o lo superi).").font(.footnote).foregroundStyle(Color.secondarioLife)
        Carta(padding: 12) {
            ForEach([("variante1Cm", "1 — Normale, mento neutro"), ("variante2Cm", "2 — Mento al petto"), ("variante3Cm", "3 — Mento al petto + caviglie flesse")], id: \.0) { k, et in
                campoCm(et, t[k]) { v in
                    var n = t
                    n[k] = v
                    var esito: J = nil
                    if let x = n.variante1Cm.num, let y = n.variante2Cm.num, let z = n.variante3Cm.num { esito = y - x >= 2 && z - x >= 2 ? "neurale" : "muscolare" }
                    mob("scrivi", ["assessment", "esitoTest1"], ["variante1Cm": n.variante1Cm, "variante2Cm": n.variante2Cm, "variante3Cm": n.variante3Cm, "esito": esito])
                }
            }
        }
        esitoBox(!t.esito.vero) {
            if t.esito.t == "neurale" {
                Text("Tensione neurale").fontWeight(.semibold)
                Text("Il range peggiora nettamente in 2 e 3. Il modulo posteriore userà nerve flossing dello sciatico, non allungamento prolungato dei femorali.")
            } else if t.esito.t == "muscolare" {
                Text("Lunghezza muscolare").fontWeight(.semibold)
                Text("Il range resta sostanzialmente uguale. Modulo posteriore standard: statico 30\" più attivo.")
            } else {
                Text("Compila tutte e tre le misure per vedere l'esito.")
            }
        }
    }

    @ViewBuilder
    private func test2(_ a: J) -> some View {
        let r = a.esitoTest2.risposte.list
        let v = conta(r)
        Text("Guarda il video, misura tutti e due i lati e segna quello migliore: con più escursione, non quello che fa male. A freddo, non dopo l'allenamento.").font(.footnote).foregroundStyle(Color.secondarioLife)
        ForEach(Array(testAssessment.enumerated()), id: \.offset) { i, t in
            Carta(padding: 12) {
                Text("TEST \(t.n)").font(.caption2.weight(.semibold)).foregroundStyle(Color.secondarioLife)
                if let u = URL(string: "https://www.youtube.com/watch?v=\(t.yt)") {
                    Link(destination: u) { Label(t.nome, systemImage: "play.rectangle").font(.footnote) }.tint(accentoMob)
                }
                Text(t.q).font(.subheadline.weight(.semibold))
                Text(t.perche).font(.caption).foregroundStyle(Color.secondarioLife)
                HStack {
                    Pillola(testo: "Sinistro", attiva: i < r.count && r[i].t == "sx", colore: accentoMob) { rispondi(r, i, "sx") }
                    Pillola(testo: "Destro", attiva: i < r.count && r[i].t == "dx", colore: accentoMob) { rispondi(r, i, "dx") }
                }
            }
        }
        esitoBox(v.fatti < testAssessment.count) {
            if v.fatti >= testAssessment.count {
                Text("Sei lateralizzato a \(v.lato == "dx" ? "DESTRA" : "SINISTRA")").fontWeight(.semibold)
                Text("\(v.punteggio) test su \(testAssessment.count) puntano al lato \(v.lato == "dx" ? "destro" : "sinistro"): incastrato in appoggio su quel lato, scappi dall'altro.\(v.punteggio == 4 ? " 4 su 7 è il minimo leggibile: vale la pena rimisurare i test in disaccordo." : "")\(v.doppio ? " Doppio twist: spalle a \(v.up == "dx" ? "destra" : "sinistra"), anche a \(v.low == "dx" ? "destra" : "sinistra")." : "")")
            } else {
                Text("In attesa dei sette test").fontWeight(.semibold)
                Text("Ne mancano \(testAssessment.count - v.fatti) su \(testAssessment.count).")
            }
        }
    }

    private func rispondi(_ r0: [J], _ i: Int, _ val: String) {
        var r = r0
        while r.count <= i { r.append(nil) }
        r[i] = r[i].t == val ? nil : .str(val)
        let c = conta(r)
        let esito: J = c.fatti < testAssessment.count
            ? ["risposte": .arr(r), "latoLateralizzato": nil, "punteggio": nil, "doppioTwist": false, "latoSopra": nil, "latoSotto": nil]
            : ["risposte": .arr(r), "latoLateralizzato": .str(c.lato), "punteggio": .n(c.punteggio), "doppioTwist": .bool(c.doppio), "latoSopra": c.doppio ? .opz(c.up) : nil, "latoSotto": c.doppio ? .opz(c.low) : nil]
        mob("scrivi", ["assessment", "esitoTest2"], esito)
    }

    @ViewBuilder
    private func test3(_ a: J) -> some View {
        let dati = a.baselineTest3.bersagli
        let foto = mob("ponte.getState").foto.list
        Text("Stessa posa, stessa distanza, stessa luce: sarà il riferimento per il confronto ogni tre settimane. Le foto restano su questo dispositivo.").font(.footnote).foregroundStyle(Color.secondarioLife)
        ForEach(bersagli, id: \.0) { b in
            let m = dati[b.0].misure
            let scrivi: (String, J) -> Void = { k, v in mob("scrivi", ["assessment", "baselineTest3", "bersagli", .str(b.0), "misure", .str(k)], v) }
            Sezione(b.1, coda: { Text(b.2) }) {
                Carta(padding: 12) {
                    switch b.0 {
                    case "deep-squat":
                        Text("Profondità").font(.footnote).foregroundStyle(Color.secondarioLife)
                        HStack {
                            ForEach([("sopra-parallelo", "Sopra"), ("parallelo", "Al parallelo"), ("sotto-parallelo", "Sotto")], id: \.0) { o in
                                Pillola(testo: o.1, attiva: m.profonditaLivello.t == o.0, colore: accentoMob) { scrivi("profonditaLivello", .str(o.0)) }
                            }
                        }
                        sino("Talloni a terra", m.talloniATerra) { scrivi("talloniATerra", .bool($0)) }
                    case "pike":
                        campoCm("Dita-pavimento", m.distanzaDitaPavimentoCm) { scrivi("distanzaDitaPavimentoCm", $0) }
                    case "overhead-shoulder":
                        campoCm("Polso-muro", m.distanzaPolsoMuroCm) { scrivi("distanzaPolsoMuroCm", $0) }
                        sino("Lombare piatta al muro", m.lombarePiatta) { scrivi("lombarePiatta", .bool($0)) }
                    case "farfalla":
                        campoCm("Ginocchio sinistro", m.altezzaGinocchioSxCm) { scrivi("altezzaGinocchioSxCm", $0) }
                        campoCm("Ginocchio destro", m.altezzaGinocchioDxCm) { scrivi("altezzaGinocchioDxCm", $0) }
                    default:
                        Text("Se compaiono vertigini, formicolii alle braccia, cefalea o dolore, fermati.").font(.caption).foregroundStyle(Color.secondarioLife)
                        campoCm("Orecchio-spalla destro", m.angoloDxGradi, unita: "°") { scrivi("angoloDxGradi", $0) }
                        campoCm("Orecchio-spalla sinistro", m.angoloSxGradi, unita: "°") { scrivi("angoloSxGradi", $0) }
                    }
                    SceltaFoto(bersaglio: b.0, foto: foto)
                }
            }
        }
    }

    private func sino(_ t: String, _ v: J, _ scrivi: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(t).font(.footnote).foregroundStyle(Color.secondarioLife)
            Spacer()
            Pillola(testo: "Sì", attiva: v == true, colore: accentoMob) { scrivi(true) }
            Pillola(testo: "No", attiva: v == false, colore: accentoMob) { scrivi(false) }
        }
    }
}

private struct SceltaFoto: View {
    let bersaglio: String
    let foto: [J]
    @State private var scelta: PhotosPickerItem?

    var body: some View {
        let img = FotoMobilita.ultima(bersaglio, foto)
        PhotosPicker(selection: $scelta, matching: .images) {
            HStack(spacing: 10) {
                if let img {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "camera").foregroundStyle(Color.secondarioLife).frame(width: 48, height: 48).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
                Text(img != nil ? "Sostituisci la foto" : "Aggiungi la foto").font(.subheadline)
            }
        }
        .tint(accentoMob)
        .onChange(of: scelta) { _, nuova in
            guard let nuova else { return }
            Task { @MainActor in
                if let d = try? await nuova.loadTransferable(type: Data.self) {
                    FotoMobilita.salva(bersaglio, d)
                    avviso("Foto salvata.")
                }
                scelta = nil
            }
        }
    }
}
