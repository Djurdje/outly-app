import Foundation

/// Ena vrstica seznama vstopnic (TicketsView): posamezna vstopnica ali VIP miza, tj. vec VIP
/// vstopnic istega narocila, ki se v seznamu razpre (Martin, 4. 10. 2026: 10 VIP vstopnic eno
/// pod drugo je nepregledno).
enum PostavkaVstopnic: Identifiable {
    case ena(APITicket)
    case miza(orderId: Int, vstopnice: [APITicket])

    var id: String {
        switch self {
        case .ena(let t): return "t\(t.id)"
        case .miza(let orderId, _): return "m\(orderId)"
        }
    }

    /// VIP vstopnice istega narocila zdruzi v eno postavko na mestu prve; vrstni red sicer ostane.
    /// Skupina z eno samo vstopnico (npr. prejeta od prijatelja) ostane navadna vrstica.
    /// Navadne vstopnice se ne zdruzujejo.
    static func zdruzi(_ seznam: [APITicket]) -> [PostavkaVstopnic] {
        var poNarocilu: [Int: [APITicket]] = [:]
        for t in seznam where t.isVip { poNarocilu[t.orderId, default: []].append(t) }

        var rezultat: [PostavkaVstopnic] = []
        var dodana = Set<Int>()
        for t in seznam {
            if t.isVip, let skupina = poNarocilu[t.orderId], skupina.count > 1 {
                if dodana.insert(t.orderId).inserted {
                    rezultat.append(.miza(orderId: t.orderId, vstopnice: skupina))
                }
            } else {
                rezultat.append(.ena(t))
            }
        }
        return rezultat
    }
}
