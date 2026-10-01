import Foundation

// Odlocitev o skenirani kodi, cisto lokalno (brez omrezja, brez stranskih ucinkov): podpis -> dogodek -> prenesena ->
// ze skenirana na tej napravi -> stanje po seznamu. Zapis v vrsto in prikaz sta drugje (SkenSeja).

/// Seznam dogodka, pripravljen za iskanje (serial-i z malimi crkami).
struct SkenIndeks {
    let vstopnice: [String: ScanListTicket]
    let prenesene: Set<String>

    init(_ seznam: ScanList) {
        vstopnice = Dictionary(seznam.tickets.map { ($0.serial.lowercased(), $0) }, uniquingKeysWith: { prvi, _ in prvi })
        prenesene = Set(seznam.transferredSerials.map { $0.lowercased() })
    }
}

struct SkenSodba: Equatable {
    enum Razlog: Equatable {
        /// Veljaven podpis, vstopnica na seznamu in nepovzeta -> zeleno.
        case veljavna
        /// Veljaven podpis za ta dogodek, a vstopnice ni na seznamu (kupljena po prenosu seznama) -> zeleno z opombo.
        case veljavnaNiNaSeznamu
        /// Ze skenirana na TEJ napravi -> rdece.
        case zeUporabljenaLokalno
        /// Seznam pravi `used` (drug telefon ali splet) -> rdece.
        case zeUporabljena
        /// Vstopnica je bila prenesena, ta koda je stara -> rdece.
        case prenesena
        case vrnjena
        case preklicana
        /// Koda je za drug dogodek -> rdece.
        case napacenDogodek
        /// Podpis ne ustreza ali koda ni berljiva -> rdece.
        case neveljavna
        /// Koda v1: telefon je ne more preveriti -> rumeno, potrebna povezava.
        case staraKoda
        /// Ni kljuca ali seznama (se nista prenesena) -> rumeno, potrebna povezava.
        case manjkaPodatkov
    }

    enum Barva { case zeleno, rdece, rumeno }

    let razlog: Razlog
    var serial: String? = nil
    /// Kdaj je bila vstopnica ze uporabljena (lokalno ali po seznamu).
    var kdaj: Date? = nil
    /// Vstopnica iz seznama (VIP, miza, imetnik), ce je na njem.
    var vstopnica: ScanListTicket? = nil

    var barva: Barva {
        switch razlog {
        case .veljavna, .veljavnaNiNaSeznamu: return .zeleno
        case .staraKoda, .manjkaPodatkov: return .rumeno
        default: return .rdece
        }
    }

    /// Zeleno = vstopnico je treba zapisati v vrsto.
    var spusti: Bool { barva == .zeleno }
}

enum SkenOdlocitev {
    /// - Parameters:
    ///   - kljuc: surovi javni kljuc (32 B) ali nil, ce ga se nimamo.
    ///   - indeks: seznam dogodka ali nil, ce ga se nimamo.
    ///   - lokalni: serial (male crke) -> cas lokalnega skena na tej napravi; pri kodi v1 je kljuc sama (obrezana) koda.
    static func odloci(qr: String, dogodekId: Int, kljuc: Data?, indeks: SkenIndeks?, lokalni: [String: Date]) -> SkenSodba {
        switch SkenKoda.razcleni(qr) {
        case .neznano:
            return SkenSodba(razlog: .neveljavna)
        case .v1:
            // Kode v1 ne moremo preveriti, a ce je bila na tej napravi ze spuscena (rocno ali prek spleta), je to rdece.
            if let cas = lokalni[qr.trimmingCharacters(in: .whitespacesAndNewlines)] {
                return SkenSodba(razlog: .zeUporabljenaLokalno, kdaj: cas)
            }
            return SkenSodba(razlog: .staraKoda)
        case let .v2(telo, sporocilo, podpis):
            guard let kljuc, let indeks else { return SkenSodba(razlog: .manjkaPodatkov, serial: telo.serial) }
            guard SkenPodpis.preveri(sporocilo: sporocilo, podpis: podpis, javniKljuc: kljuc) else {
                return SkenSodba(razlog: .neveljavna)
            }
            let serial = telo.serial
            guard telo.eventId == dogodekId else { return SkenSodba(razlog: .napacenDogodek, serial: serial) }
            if indeks.prenesene.contains(serial) { return SkenSodba(razlog: .prenesena, serial: serial) }
            if let cas = lokalni[serial] { return SkenSodba(razlog: .zeUporabljenaLokalno, serial: serial, kdaj: cas) }
            guard let v = indeks.vstopnice[serial] else {
                return SkenSodba(razlog: .veljavnaNiNaSeznamu, serial: serial)
            }
            switch v.status {
            case "valid": return SkenSodba(razlog: .veljavna, serial: serial, vstopnica: v)
            case "used": return SkenSodba(razlog: .zeUporabljena, serial: serial, kdaj: SkenCas.razcleni(v.usedAt), vstopnica: v)
            case "refunded": return SkenSodba(razlog: .vrnjena, serial: serial, vstopnica: v)
            case "void": return SkenSodba(razlog: .preklicana, serial: serial, vstopnica: v)
            default: return SkenSodba(razlog: .neveljavna, serial: serial, vstopnica: v)
            }
        }
    }
}
