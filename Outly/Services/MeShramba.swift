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

    /// Shranjen Me + `sub` zetona, s katerim je bil dobljen: Me drugega racuna (npr. po odjavi, ki se ni zgodila, ali menjavi racuna
    /// brez odjave) se ob branju zavrne.
    struct Zapis: Codable, Equatable {
        let sub: String
        let me: Me
    }

    /// Application Support/Seja (locena od Sken: pobrise se ob odjavi sama zase).
    static func standardniDisk() -> SkenDisk {
        SkenDisk(mapa: SkenDisk().mapa.deletingLastPathComponent().appendingPathComponent("Seja", isDirectory: true))
    }

    /// `sub` iz JWT (brez preverjanja podpisa: samo identiteta za primerjavo z lastnim zapisom, ne za odlocanje o dostopu).
    static func sub(izZetona token: String) -> String? {
        let deli = token.split(separator: ".", omittingEmptySubsequences: false)
        guard deli.count == 3, let d = Data(base64URL: String(deli[1])),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let sub = o["sub"] as? String, !sub.isEmpty else { return nil }
        return sub.lowercased()
    }

    @discardableResult
    static func shrani(_ me: Me, sub: String, disk: SkenDisk = standardniDisk()) -> Bool {
        disk.zapisi(Zapis(sub: sub.lowercased(), me: me), ime)
    }

    /// Zapis z diska (brez primerjave `sub`); SessionStore ga prebere enkrat ob zagonu in ga drzi v pomnilniku.
    static func preberiZapis(disk: SkenDisk = standardniDisk()) -> Zapis? {
        disk.preberi(Zapis.self, ime)
    }

    /// Me z diska, ce pripada racunu z `sub`; sicer nil.
    static func preberi(sub: String?, disk: SkenDisk = standardniDisk()) -> Me? {
        guard let sub, let z = preberiZapis(disk: disk), z.sub == sub.lowercased() else { return nil }
        return z.me
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
