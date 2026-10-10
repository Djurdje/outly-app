import Foundation
import Combine

/// Cakajoci cilj dotika na potisno obvestilo. Zivi zunaj pogledov, ker dotik na HLADNEM zagonu pride (v
/// `OutlyAppDelegate`) prej, kot obstaja MainTabView: cilj ostane tu, dokler ga `PushPrehod` (v MainTabView) ne prevzame.
/// Ob odjavi se pobrise (`SessionStore.clearLocalSession`), da ga ne bi prevzel drug uporabnik.
@MainActor
final class PushUsmerjevalnik: ObservableObject {
    static let deljen = PushUsmerjevalnik()
    private init() {}

    /// Cilj, ki caka na prevzem (nastavi ga `postavi`, prevzame `prevzemi`).
    @Published private(set) var cakajoci: PushCilj?
    private var prejeto = Date.distantPast

    /// Cilj, ki caka dlje od tega (npr. dotik pred prijavo, ki je nikoli ni bilo), se zavrze: drug uporabnik ga ne sme prevzeti.
    static let najvecCakanja: TimeInterval = 15 * 60

    /// Klice delegat ob dotiku na obvestilo.
    func postavi(_ cilj: PushCilj) {
        prejeto = Date()
        cakajoci = cilj
    }

    /// Prevzame cakajoci cilj (in ga pobrise). nil = ni cilja ali je prestar.
    func prevzemi() -> PushCilj? {
        guard let cilj = cakajoci else { return nil }
        cakajoci = nil
        return Date().timeIntervalSince(prejeto) <= Self.najvecCakanja ? cilj : nil
    }

    func pocisti() {
        if cakajoci != nil { cakajoci = nil }
    }
}

extension Notification.Name {
    /// Potisno obvestilo je prispelo, medtem ko je aplikacija odprta: Home osvezi stevec na zvoncu (en GET /me).
    static let outlyPushPrispel = Notification.Name("si.outly.push.prispel")
}
