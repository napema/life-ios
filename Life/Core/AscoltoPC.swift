import CoreLocation
import Foundation
import UserNotifications

/// «Il PC ti ha mandato un file» senza notifiche push: con l'Apple ID gratuito Apple non le permette.
/// Life resta sveglia in sottofondo grazie alla posizione (precisione di 3 km: consuma pochissimo,
/// la posizione non si usa né si salva) e ogni 20 secondi guarda il vassoio; se dal PC è arrivato
/// qualcosa, parte una notifica di Life. Se iOS chiude l'app, i cambi di posizione importanti la
/// risvegliano. Si spegne dalle Impostazioni di Life.
final class AscoltoPC: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let s = AscoltoPC()
    private let gestore = CLLocationManager()
    private var timer: Timer?
    @Published private(set) var stato: CLAuthorizationStatus = .notDetermined
    @Published var attivo: Bool {
        didSet {
            UserDefaults.standard.set(attivo, forKey: "ascoltoPC")
            if attivo { avvia() } else { ferma() }
        }
    }

    override init() {
        attivo = UserDefaults.standard.object(forKey: "ascoltoPC") as? Bool ?? true
        super.init()
        gestore.delegate = self
        gestore.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        gestore.distanceFilter = kCLDistanceFilterNone
        gestore.pausesLocationUpdatesAutomatically = false
        gestore.activityType = .other
        stato = gestore.authorizationStatus
    }

    func avvia() {
        guard attivo else { return }
        if Notifiche.s.permesso == .notDetermined { Notifiche.s.chiediPermesso() }
        switch gestore.authorizationStatus {
        case .notDetermined:
            gestore.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            gestore.requestAlwaysAuthorization()
            parti()
        case .authorizedAlways:
            parti()
        default:
            break
        }
    }

    private func parti() {
        gestore.allowsBackgroundLocationUpdates = true
        gestore.showsBackgroundLocationIndicator = false
        gestore.startUpdatingLocation()
        gestore.startMonitoringSignificantLocationChanges()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 20, repeats: true) { _ in
            Task { @MainActor in await Notifiche.s.controllaVassoio() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { @MainActor in await Notifiche.s.controllaVassoio() }
    }

    private func ferma() {
        timer?.invalidate()
        timer = nil
        gestore.stopUpdatingLocation()
        gestore.stopMonitoringSignificantLocationChanges()
        gestore.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        DispatchQueue.main.async {
            self.stato = s
            guard self.attivo else { return }
            if s == .authorizedWhenInUse { m.requestAlwaysAuthorization() }
            if s == .authorizedWhenInUse || s == .authorizedAlways { self.parti() }
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {}
    func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {}
}
