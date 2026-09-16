import SwiftUI
import Foundation
import Combine

/// Jezik aplikacije: "en" ali "sl". Preklop deluje takoj, brez ponovnega zagona.
///
/// Kako: Bundle.main dobi ob zagonu podrazred (`JezikovniBundle`), ki vse prevode bere iz
/// izbranega `<koda>.lproj` (Xcode ga zgradi iz `Localizable.xcstrings`). Skozi to gredo
/// SwiftUI `Text("...")`, `navigationTitle`, `String(localized:)` in `NSLocalizedString`.
/// Ob menjavi koren aplikacije dobi nov `.id`, zato se vsi pogledi zgradijo znova.
///
/// Privzeto: jezik naprave (slovenscina -> "sl", vse ostalo -> "en"). Izbira je v UserDefaults.
final class Jezik: ObservableObject {
    static let kljuc = "outly_jezik"
    /// En vnos na jezik: koda + ime VEDNO v svojem jeziku (se ne prevaja). Nov jezik = nova vrstica tu,
    /// zaslon Language (MyAccount) in privzeti() ju uporabita samodejno.
    static let seznam: [(koda: String, ime: String)] = [
        ("en", "English"),
        ("sl", "Slovenščina"),
    ]
    static var podprti: [String] { seznam.map(\.koda) }
    static let shared = Jezik()

    @Published private(set) var koda: String
    /// Zavihek, na katerega naj se MainTabView postavi po preklopu (Profil = 3), sicer nil.
    @Published var zavihekPoPreklopu: Int?

    /// Bundle izbranega jezika; nil = privzeti (Bundle.main brez podrazreda).
    private static var jezikovniBundle: Bundle?

    private init() {
        let shranjen = UserDefaults.standard.string(forKey: Jezik.kljuc)
        let zacetna = (shranjen.flatMap { Jezik.podprti.contains($0) ? $0 : nil }) ?? Jezik.privzeti()
        koda = zacetna
        Jezik.nastaviBundle(za: zacetna)
        _ = object_setClass(Bundle.main, JezikovniBundle.self)
    }

    /// Jezik naprave: "sl" samo, ce je prvi jezik uporabnika slovenscina.
    static func privzeti() -> String {
        let prvi = Locale.preferredLanguages.first ?? "en"
        return prvi.lowercased().hasPrefix("sl") ? "sl" : "en"
    }

    /// Locale za datume in stevilke (Text(date, format:), DateFormatter).
    var locale: Locale { Locale(identifier: koda == "sl" ? "sl_SI" : "en_GB") }

    var jeSlovenscina: Bool { koda == "sl" }

    /// Ime trenutnega jezika v njegovem jeziku (za prikaz v Nastavitve -> Language).
    var ime: String { Jezik.seznam.first { $0.koda == koda }?.ime ?? koda }

    /// Zamenja jezik. `zavihek`: na kateri zavihek naj se aplikacija postavi po ponovni gradnji.
    func nastavi(_ nova: String, zavihek: Int? = nil) {
        guard Jezik.podprti.contains(nova), nova != koda else { return }
        Jezik.nastaviBundle(za: nova)
        UserDefaults.standard.set(nova, forKey: Jezik.kljuc)
        // Da se po naslednjem zagonu tudi sistemski deli (deljenje, izbirniki) ujemajo.
        UserDefaults.standard.set([nova], forKey: "AppleLanguages")
        zavihekPoPreklopu = zavihek
        koda = nova
    }

    private static func nastaviBundle(za koda: String) {
        if let pot = Bundle.main.path(forResource: koda, ofType: "lproj"), let b = Bundle(path: pot) {
            jezikovniBundle = b
        } else {
            jezikovniBundle = nil
        }
    }

    /// Prevod za kodo zunaj SwiftUI (npr. sporocila napak). Enako kot String(localized:).
    static func prevod(_ kljuc: String) -> String {
        Bundle.main.localizedString(forKey: kljuc, value: nil, table: nil)
    }

    fileprivate static func lokaliziraj(_ key: String, value: String?, table: String?) -> String? {
        jezikovniBundle?.localizedString(forKey: key, value: value, table: table)
    }
}

/// Podrazred, ki ga ob zagonu dobi Bundle.main (object_setClass). Ne ustvarjaj ga sam.
private final class JezikovniBundle: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let s = Jezik.lokaliziraj(key, value: value, table: tableName) { return s }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

// MARK: - Pogledi za preklop

/// Majhen tekstovni gumb (prijava/registracija): pokaze DRUGI jezik, klik preklopi.
struct JezikGumb: View {
    @EnvironmentObject private var jezik: Jezik

    var body: some View {
        Button {
            jezik.nastavi(jezik.jeSlovenscina ? "en" : "sl")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(verbatim: jezik.jeSlovenscina ? "English" : "Slovenščina")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color.white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
}
