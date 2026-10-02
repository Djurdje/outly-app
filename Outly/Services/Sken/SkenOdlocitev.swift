import Foundation

// Odlocitev o skenirani kodi, cisto lokalna (brez omrezja, brez stranskih ucinkov): kljuc -> podpis -> dogodek -> prenesena ->
// ze skenirana na tej napravi -> stanje po seznamu. Zapis v vrsto in prikaz sta drugje (SkenSeja).
// Z povezavo je lokalna sodba za zeleno samo PREDLOG: dokoncno odloci streznik (SkenSeja, K2).

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
        /// Veljaven podpis za ta dogodek, a vstopnice ni na seznamu (kupljena po prenosu seznama) -> zeleno z opombo (brez povezave).
        case veljavnaNiNaSeznamu
        /// Ze skenirana na TEJ napravi -> rdece.
        case zeUporabljenaLokalno
        /// Seznam pravi `used` (drug telefon ali splet) -> rdece.
        case zeUporabljena
        /// Vstopnica je bila prenesena, ta koda je stara -> rdece.
        case prenesena
        case vrnjena
        case preklicana
        /// Narocilo ni placano (seznam jo vrne s statusom `unpaid`) -> rdece.
        case neplacana
        /// Koda je za drug dogodek -> rdece.
        case napacenDogodek
        /// Podpis ne ustreza ali koda ni berljiva -> rdece.
        case neveljavna
        /// Koda v1: telefon je ne more preveriti -> rumeno, potrebna povezava (ali vratarjeva odlocitev).
        case staraKoda
        /// Ni javnega kljuca (se ni bil prenesen) -> rumeno, potrebna povezava.
        case manjkaPodatkov
        /// Koda je podpisana s kljucem, ki ga telefon nima (strezniska skrivnost je bila zamenjana) -> rumeno, kljuc je treba osveziti.
        case kljucNeujema
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
        case .staraKoda, .manjkaPodatkov, .kljucNeujema: return .rumeno
        default: return .rdece
        }
    }

    /// Zeleno = vstopnico je treba zapisati v vrsto.
    var spusti: Bool { barva == .zeleno }
}

enum SkenOdlocitev {
    /// - Parameters:
    ///   - kljuc: javni kljuc (z `kid`) ali nil, ce ga se nimamo.
    ///   - indeks: seznam dogodka ali nil, ce ga se nimamo.
    ///   - lokalni: serial (male crke) -> cas lokalnega skena na tej napravi.
    static func odloci(qr: String, dogodekId: Int, kljuc: ScanKey?, indeks: SkenIndeks?, lokalni: [String: Date]) -> SkenSodba {
        switch SkenKoda.razcleni(qr) {
        case .neznano:
            return SkenSodba(razlog: .neveljavna)

        case let .v1(telo):
            // Pristnosti kode v1 telefon ne more preveriti, zato je privzeto rumeno. Negativne podatke pa smemo uporabiti
            // (rdece nikoli ne skodi): drug dogodek, prenesena, ze skenirana, stanje po seznamu.
            let serial = telo.serial
            if telo.eventId != dogodekId { return SkenSodba(razlog: .napacenDogodek, serial: serial) }
            if let rdece = rdecaIzPodatkov(serial: serial, indeks: indeks, lokalni: lokalni) { return rdece }
            return SkenSodba(razlog: .staraKoda, serial: serial)

        case let .v2(telo, sporocilo, podpis):
            let serial = telo.serial
            guard let javni = kljuc?.surovi, let kljuc else { return SkenSodba(razlog: .manjkaPodatkov, serial: serial) }
            // Koda, podpisana z drugim kljucem, kot ga imamo: to ni ponaredek, ampak zastarel kljuc -> rumeno in osvezi (M10).
            if let k = telo.kid, !kljuc.kid.isEmpty, k != kljuc.kid { return SkenSodba(razlog: .kljucNeujema, serial: serial) }
            guard SkenPodpis.preveri(sporocilo: sporocilo, podpis: podpis, javniKljuc: javni) else {
                return SkenSodba(razlog: .neveljavna)
            }
            guard telo.eventId == dogodekId else { return SkenSodba(razlog: .napacenDogodek, serial: serial) }
            if let rdece = rdecaIzPodatkov(serial: serial, indeks: indeks, lokalni: lokalni) { return rdece }
            // Podpis in dogodek sta preverjena, seznama pa ni (ali vstopnice ni na njem): zeleno z opombo.
            guard let v = indeks?.vstopnice[serial] else {
                return SkenSodba(razlog: .veljavnaNiNaSeznamu, serial: serial)
            }
            return SkenSodba(razlog: .veljavna, serial: serial, vstopnica: v)
        }
    }

    /// Rdeca sodba iz prenesenih serial-ov, lokalnih skenov in stanja po seznamu; nil = nic ne govori proti vstopu.
    private static func rdecaIzPodatkov(serial: String, indeks: SkenIndeks?, lokalni: [String: Date]) -> SkenSodba? {
        if indeks?.prenesene.contains(serial) == true { return SkenSodba(razlog: .prenesena, serial: serial) }
        if let cas = lokalni[serial] { return SkenSodba(razlog: .zeUporabljenaLokalno, serial: serial, kdaj: cas) }
        guard let v = indeks?.vstopnice[serial] else { return nil }
        switch v.status {
        case "valid": return nil
        case "used": return SkenSodba(razlog: .zeUporabljena, serial: serial, kdaj: SkenCas.razcleni(v.usedAt), vstopnica: v)
        case "refunded": return SkenSodba(razlog: .vrnjena, serial: serial, vstopnica: v)
        case "void": return SkenSodba(razlog: .preklicana, serial: serial, vstopnica: v)
        case "unpaid": return SkenSodba(razlog: .neplacana, serial: serial, vstopnica: v)
        default: return SkenSodba(razlog: .neveljavna, serial: serial, vstopnica: v)
        }
    }
}
