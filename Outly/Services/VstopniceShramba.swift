import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Zadnji uspesen seznam mojih vstopnic (GET /me/tickets) na disku: gost v kleti brez signala mora videti QR kodo.
// Application Support (ne UserDefaults), zascita datoteke »do prvega odklepa« (.completeUntilFirstUserAuthentication),
// izkljuceno iz varnostne kopije. Shranijo se samo veljavne vstopnice s kodo: porabljena, vrnjena, preklicana ali prenesena
// (te v /me/tickets ni vec) se ob naslednji uspesni osvezitvi umakne tudi z diska.
// Ob odjavi, zavrnjeni seji in brisanju racuna se datoteka izbrise (SkenOdjava.pocisti).

struct VstopniceShramba {
    /// Kar je na disku: cigav je seznam, kdaj je bil prenesen, vstopnice.
    struct Posnetek: Codable {
        var uporabnikId: Int?
        var shranjeno: Date
        var vstopnice: [APITicket]
    }

    let mapa: URL
    private static let ime = "vstopnice.json"

    init(mapa: URL? = nil) {
        if let mapa {
            self.mapa = mapa
        } else {
            let osnova = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.mapa = osnova.appendingPathComponent("Vstopnice", isDirectory: true)
        }
    }

    var datoteka: URL { mapa.appendingPathComponent(Self.ime) }

    /// Kaj gre na disk: samo veljavne vstopnice s QR kodo.
    static func zaShranjevanje(_ vstopnice: [APITicket]) -> [APITicket] {
        vstopnice.filter { $0.status == "valid" && !$0.qr.isEmpty }
    }

    /// Zapise posnetek (prepise prejsnjega). true, ce je zapis uspel.
    @discardableResult
    func shrani(_ vstopnice: [APITicket], uporabnikId: Int?, zdaj: Date = Date()) -> Bool {
        zapisi(Posnetek(uporabnikId: uporabnikId, shranjeno: zdaj, vstopnice: Self.zaShranjevanje(vstopnice)))
    }

    /// Shranjen posnetek ali nil. Posnetka drugega uporabnika ne vrne (varovalo, ce brisanje ob odjavi ne bi uspelo).
    func preberi(uporabnikId: Int?) -> Posnetek? {
        guard let d = try? Data(contentsOf: datoteka),
              let p = try? JSONDecoder().decode(Posnetek.self, from: d) else { return nil }
        if let u = uporabnikId, let s = p.uporabnikId, u != s { return nil }
        return p
    }

    /// Vstopnica je bila prenesena: z diska takoj, tudi ce osvezitev seznama potem ne uspe.
    func odstrani(vstopnicaId: Int) {
        guard let d = try? Data(contentsOf: datoteka),
              var p = try? JSONDecoder().decode(Posnetek.self, from: d),
              p.vstopnice.contains(where: { $0.id == vstopnicaId }) else { return }
        p.vstopnice.removeAll { $0.id == vstopnicaId }
        zapisi(p)
    }

    func pobrisi() {
        try? FileManager.default.removeItem(at: datoteka)
    }

    @discardableResult
    private func zapisi(_ p: Posnetek) -> Bool {
        guard let d = try? JSONEncoder().encode(p) else { return false }
        do {
            try FileManager.default.createDirectory(at: mapa, withIntermediateDirectories: true)
            var url = mapa
            var v = URLResourceValues()
            v.isExcludedFromBackup = true
            try? url.setResourceValues(v)
            try d.write(to: datoteka, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Ali ob tej napaki pokazemo shranjen seznam: omrezje, rok, strezniska napaka. Ne ob zavrnjeni prijavi (401/403/404)
    /// ali prekinjenem nalaganju.
    static func pokaziShranjeno(ob napaka: Error) -> Bool {
        if napaka is CancellationError { return false }
        if let u = napaka as? URLError { return u.code != .cancelled }
        if let api = napaka as? APIError, case let .requestFailed(code, _) = api {
            return ![401, 403, 404].contains(code)
        }
        return true
    }
}
