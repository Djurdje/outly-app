import SwiftUI

/// Izbira dogodka za razdelek »Last week's biggest hits«.
/// Samo dogodek, ki se je ze zacel (start <= zdaj), v zadnjih 7 dneh in s prodanimi vstopnicami;
/// prihajajoci dogodek nikoli (Martin, 9. 11. 2026: razdelek je pokazal QUICKIE, ki je sele 27. 11.).
enum HitTedna {
    static func izberi(iz dogodki: [APIEvent], zdaj: Date = Date()) -> APIEvent? {
        let teden = zdaj.addingTimeInterval(-7 * 24 * 3600)
        return dogodki
            .filter { e in
                guard e.soldCount > 0, let zacetek = e.startDate else { return false }
                return zacetek <= zdaj && zacetek >= teden
            }
            .max(by: { $0.soldCount < $1.soldCount })
    }
}

/// Element za `fullScreenCover(item:)` na Home: posnetek je del elementa, zato ga vsebina dobi ze ob prvem prikazu.
struct FiltriPredstavitev: Identifiable {
    let id = UUID()
    let posnetek: UIImage?
}
