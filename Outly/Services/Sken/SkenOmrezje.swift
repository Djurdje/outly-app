import Foundation
import Network

/// Opazuje, ali je kaksna pot do omrezja (NWPathMonitor). To NE pomeni, da je streznik dosegljiv:
/// to ugotavlja SkenSeja po uspehu/neuspehu klicev. Monitor po preklicu ni ponovno uporaben, zato ga zacni() vsakic naredi znova.
final class SkenOmrezje {
    private var monitor: NWPathMonitor?
    private let vrsta = DispatchQueue(label: "si.outly.sken.omrezje")

    func zacni(_ naSpremembo: @escaping @MainActor (Bool) -> Void) {
        ustavi()
        let m = NWPathMonitor()
        m.pathUpdateHandler = { pot in
            let gor = pot.status == .satisfied
            Task { @MainActor in naSpremembo(gor) }
        }
        m.start(queue: vrsta)
        monitor = m
    }

    func ustavi() {
        monitor?.cancel()
        monitor = nil
    }
}
