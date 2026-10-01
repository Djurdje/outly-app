import Foundation

// K1 (pregled PR #45): hladen zagon aplikacije brez povezave. AuthGateView je pri session.me == nil kazal SessionLoadingView,
// GET /me brez povezave pade in uporabnik do skenerja ni mogel. Zato zadnji uspesni Me shranimo na disk (Application Support/Seja,
// izkljuceno iz varnostne kopije; BREZ zetonov) in ga ob izpadu povezave ali streznika uporabimo namesto klica.
// Ob odjavi in ob zavrnjeni seji se datoteka pobrise (SessionStore.clearLocalSession).

extension Error {
    /// Izpad povezave ali streznika (omrezna napaka, 408, 429, 5xx), NE zavrnitev zahteve (400, 401, 403, 404 ...).
    /// Preklic (`URLError.cancelled`, `CancellationError`) ni izpad: nastane, ko zaslon izgine ali sami prekinemo klic (pregled M12).
    var jeIzpadPovezave: Bool {
        if self is CancellationError { return false }
        if let u = self as? URLError { return u.code != .cancelled }
        if let a = self as? APIError, case let .requestFailed(koda, _) = a {
            return koda == -1 || koda == 408 || koda == 429 || koda >= 500
        }
        return false
    }
}

enum MeShramba {
    static let ime = "me.json"

    /// Application Support/Seja (locena od Sken: pobrise se ob odjavi sama zase).
    static func standardniDisk() -> SkenDisk {
        SkenDisk(mapa: SkenDisk().mapa.deletingLastPathComponent().appendingPathComponent("Seja", isDirectory: true))
    }

    @discardableResult
    static func shrani(_ me: Me, disk: SkenDisk = standardniDisk()) -> Bool {
        disk.zapisi(me, ime)
    }

    static func preberi(disk: SkenDisk = standardniDisk()) -> Me? {
        disk.preberi(Me.self, ime)
    }

    static func pobrisi(disk: SkenDisk = standardniDisk()) {
        disk.pobrisiVse()
    }

    /// Kaj naredi aplikacija, ko GET /me ne uspe: ob izpadu povezave/streznika shranjen Me (ce ga imamo), ob zavrnitvi
    /// (401/403, pokvarjen odgovor) nic — takrat odloca SessionStore (odjava ali napaka).
    static func nadomestniMe(ob napaka: Error, shranjen: Me?) -> Me? {
        napaka.jeIzpadPovezave ? shranjen : nil
    }
}
