import Foundation

// Trajna hramba za sken brez povezave: vrsta skenov za streznik + konflikti + lokalni skeni dogodka + prenesen seznam.
// Vse je v Application Support/Sken (JSON, ne UserDefaults: seznam vstopnic je lahko velik), izkljuceno iz varnostne kopije.
// Pisanje je sinhrono in atomarno: sken, ki je vratarju pokazal zeleno, mora preziveti tudi ubitje aplikacije.

/// Datotecni sloj. Mapa je nastavljiva, da jo testi usmerijo v zacasno mapo.
struct SkenDisk {
    let mapa: URL

    init(mapa: URL? = nil) {
        if let mapa {
            self.mapa = mapa
        } else {
            let osnova = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.mapa = osnova.appendingPathComponent("Sken", isDirectory: true)
        }
    }

    private func pripravi() {
        try? FileManager.default.createDirectory(at: mapa, withIntermediateDirectories: true)
        var url = mapa
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? url.setResourceValues(v)
    }

    func preberi<T: Decodable>(_ tip: T.Type, _ ime: String) -> T? {
        guard let d = try? Data(contentsOf: mapa.appendingPathComponent(ime)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    /// true, ce je zapis uspel.
    @discardableResult
    func zapisi<T: Encodable>(_ vrednost: T, _ ime: String) -> Bool {
        pripravi()
        guard let d = try? JSONEncoder().encode(vrednost) else { return false }
        do {
            try d.write(to: mapa.appendingPathComponent(ime), options: .atomic)
            return true
        } catch { return false }
    }

    func izbrisi(_ ime: String) {
        try? FileManager.default.removeItem(at: mapa.appendingPathComponent(ime))
    }

    func imena() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: mapa.path)) ?? []
    }
}

/// Sken, ki caka na streznik. Nastane SAMO ob lokalno zelenem skenu (ali vratarjevi odlocitvi za staro kodo).
struct SkenVnos: Codable, Equatable, Identifiable {
    /// Nov UUID za vsak sken (idempotentnost na strezniku: `batch|<device_id>|<client_scan_id>`).
    let clientScanId: String
    /// Surova koda; streznik jo ponovno preveri (podpis, dogodek, klub).
    let qr: String
    /// Serial iz kode v2; nil pri stari kodi v1 (ni preverljiva na telefonu).
    let serial: String?
    let eventId: Int
    let klubId: Int
    /// Kdo je skeniral (me.id); nil, ce ni bil znan. Vrsto sinhronizira samo isti uporabnik.
    let uporabnikId: Int?
    let scannedAt: Date
    /// Ime imetnika / miza iz seznama, za prikaz v konfliktih.
    let imetnik: String?
    var poskusi: Int = 0

    var id: String { clientScanId }

    enum CodingKeys: String, CodingKey {
        case clientScanId, qr, serial, eventId, klubId, uporabnikId, scannedAt, imetnik, poskusi
    }

    init(clientScanId: String = UUID().uuidString.lowercased(), qr: String, serial: String?, eventId: Int, klubId: Int,
         uporabnikId: Int?, scannedAt: Date = Date(), imetnik: String? = nil, poskusi: Int = 0) {
        self.clientScanId = clientScanId
        self.qr = qr
        self.serial = serial
        self.eventId = eventId
        self.klubId = klubId
        self.uporabnikId = uporabnikId
        self.scannedAt = scannedAt
        self.imetnik = imetnik
        self.poskusi = poskusi
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientScanId = try c.decode(String.self, forKey: .clientScanId)
        qr = try c.decode(String.self, forKey: .qr)
        serial = (try? c.decodeIfPresent(String.self, forKey: .serial)) ?? nil
        eventId = (try? c.decodeIfPresent(Int.self, forKey: .eventId)) ?? 0
        klubId = (try? c.decodeIfPresent(Int.self, forKey: .klubId)) ?? 0
        uporabnikId = (try? c.decodeIfPresent(Int.self, forKey: .uporabnikId)) ?? nil
        scannedAt = (try? c.decodeIfPresent(Date.self, forKey: .scannedAt)) ?? Date()
        imetnik = (try? c.decodeIfPresent(String.self, forKey: .imetnik)) ?? nil
        poskusi = (try? c.decodeIfPresent(Int.self, forKey: .poskusi)) ?? 0
    }
}

/// Sken, ki je bil lokalno zelen, streznik pa ga ni potrdil (npr. already_used: vstopnico je pred nami spustil drug telefon).
/// Ostane na disku, dokler ga vratar ne potrdi — ne brisemo tiho.
struct SkenKonflikt: Codable, Equatable, Identifiable {
    let clientScanId: String
    let serial: String?
    let eventId: Int
    let klubId: Int
    let scannedAt: Date
    /// Rezultat streznika: already_used, transferred, wrong_club, unknown, unpaid, refunded, void, invalid ...
    let result: String
    /// Kdaj je streznik zabelezil prvi (veljavni) sken.
    let streznikUsedAt: String?
    let imetnik: String?
    var potrjen: Bool = false

    var id: String { clientScanId }

    enum CodingKeys: String, CodingKey {
        case clientScanId, serial, eventId, klubId, scannedAt, result, streznikUsedAt, imetnik, potrjen
    }

    init(clientScanId: String, serial: String?, eventId: Int, klubId: Int, scannedAt: Date, result: String,
         streznikUsedAt: String?, imetnik: String?, potrjen: Bool = false) {
        self.clientScanId = clientScanId
        self.serial = serial
        self.eventId = eventId
        self.klubId = klubId
        self.scannedAt = scannedAt
        self.result = result
        self.streznikUsedAt = streznikUsedAt
        self.imetnik = imetnik
        self.potrjen = potrjen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientScanId = try c.decode(String.self, forKey: .clientScanId)
        serial = (try? c.decodeIfPresent(String.self, forKey: .serial)) ?? nil
        eventId = (try? c.decodeIfPresent(Int.self, forKey: .eventId)) ?? 0
        klubId = (try? c.decodeIfPresent(Int.self, forKey: .klubId)) ?? 0
        scannedAt = (try? c.decodeIfPresent(Date.self, forKey: .scannedAt)) ?? Date()
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? "invalid"
        streznikUsedAt = (try? c.decodeIfPresent(String.self, forKey: .streznikUsedAt)) ?? nil
        imetnik = (try? c.decodeIfPresent(String.self, forKey: .imetnik)) ?? nil
        potrjen = (try? c.decodeIfPresent(Bool.self, forKey: .potrjen)) ?? false
    }
}

/// Trajna vrsta skenov. Ena datoteka za vse klube (vnosi nosijo klubId), da vrsta prezivi zaprtje aplikacije.
@MainActor
final class SkenVrsta {
    private struct Vsebina: Codable {
        var vnosi: [SkenVnos] = []
        var konflikti: [SkenKonflikt] = []
    }

    static let datoteka = "vrsta.json"
    /// Streznik sprejme najvec 500 skenov na zahtevo.
    static let najvecVPaketu = 500

    private let disk: SkenDisk
    private(set) var vnosi: [SkenVnos]
    private(set) var konflikti: [SkenKonflikt]
    /// false, ce zadnji zapis na disk ni uspel (poln disk): skeni so le v pomnilniku — vratar to mora videti.
    private(set) var zapisUspel = true

    /// Ena vrsta na mapo v procesu: vse seje skenerja delijo isto kopijo v pomnilniku, zato si ne prepisujejo datoteke.
    private static var skupne: [String: SkenVrsta] = [:]

    static func deljena(_ disk: SkenDisk) -> SkenVrsta {
        if let v = skupne[disk.mapa.path] { return v }
        let nova = SkenVrsta(disk: disk)
        skupne[disk.mapa.path] = nova
        return nova
    }

    init(disk: SkenDisk) {
        self.disk = disk
        let v = disk.preberi(Vsebina.self, Self.datoteka) ?? Vsebina()
        vnosi = v.vnosi
        konflikti = v.konflikti
    }

    private func shrani() {
        zapisUspel = disk.zapisi(Vsebina(vnosi: vnosi, konflikti: konflikti), Self.datoteka)
    }

    /// Doda vnos. Idempotentno po `clientScanId`: drugi dodatek istega id-ja ne naredi nic (vrne false).
    @discardableResult
    func dodaj(_ v: SkenVnos) -> Bool {
        guard !vnosi.contains(where: { $0.clientScanId == v.clientScanId }) else { return false }
        vnosi.append(v)
        shrani()
        return true
    }

    /// Vnosi tega kluba (in uporabnika, ce je znan na obeh straneh), najstarejsi najprej.
    func cakajoci(klub: Int, uporabnik: Int?) -> [SkenVnos] {
        vnosi.filter { $0.klubId == klub && Self.istiUporabnik($0.uporabnikId, uporabnik) }
    }

    func stevilo(klub: Int, uporabnik: Int?) -> Int { cakajoci(klub: klub, uporabnik: uporabnik).count }

    func paket(klub: Int, uporabnik: Int?) -> [SkenVnos] {
        Array(cakajoci(klub: klub, uporabnik: uporabnik).prefix(Self.najvecVPaketu))
    }

    private static func istiUporabnik(_ a: Int?, _ b: Int?) -> Bool {
        guard let a, let b else { return true }
        return a == b
    }

    /// Obdela odgovor scan-batch. Dokoncni rezultati odstranijo vnos; `ok` je tiho, vse drugo (already_used, transferred,
    /// wrong_club ...) pomeni, da je bil gost spusceni na podlagi lokalno zelenega skena, streznik pa tega ne potrdi -> konflikt.
    /// `error` (in vnos brez rezultata) ostane v vrsti s povecanim stevcem poskusov. Vrne stevilo odstranjenih vnosov.
    @discardableResult
    func uporabi(_ rezultati: [ScanBatchResult], poslani: [SkenVnos]) -> Int {
        var odstranjeni = 0
        var spremenjeno = false
        let poId = Dictionary(rezultati.map { ($0.clientScanId, $0) }, uniquingKeysWith: { prvi, _ in prvi })
        for p in poslani {
            guard let idx = vnosi.firstIndex(where: { $0.clientScanId == p.clientScanId }) else { continue }  // ze obdelan (ponovitev)
            if let r = poId[p.clientScanId], r.jeDokoncen {
                let v = vnosi.remove(at: idx)
                odstranjeni += 1
                spremenjeno = true
                if r.result != "ok", !konflikti.contains(where: { $0.clientScanId == v.clientScanId }) {
                    konflikti.append(SkenKonflikt(clientScanId: v.clientScanId, serial: r.serial ?? v.serial, eventId: v.eventId,
                                                  klubId: v.klubId, scannedAt: v.scannedAt, result: r.result,
                                                  streznikUsedAt: r.usedAt, imetnik: v.imetnik))
                }
            } else {
                vnosi[idx].poskusi += 1
                spremenjeno = true
            }
        }
        if spremenjeno { shrani() }
        return odstranjeni
    }

    func nepotrjeniKonflikti(klub: Int) -> [SkenKonflikt] {
        konflikti.filter { $0.klubId == klub && !$0.potrjen }
    }

    func potrdiKonflikt(_ id: String) {
        guard let i = konflikti.firstIndex(where: { $0.clientScanId == id }) else { return }
        konflikti[i].potrjen = true
        shrani()
    }
}

// MARK: - Shramba dogodka

/// Prenesen javni kljuc + seznam dogodka (spremeni se na ~2 min, zato locena datoteka od lokalnih skenov).
struct SkenSeznamShramba: Codable, Equatable {
    var kljuc: ScanKey?
    var seznam: ScanList?
    var prenesenoOb: Date?
}

/// Lokalni skeni dogodka na tej napravi: serial -> cas. Ostanejo tudi po sinhronizaciji (vrsta jih odstrani),
/// da ponovni sken ostane rdec, dokler seznam ne pokaze `used`.
struct SkenLokalniSkeni: Codable, Equatable {
    var casi: [String: Date] = [:]
}

extension SkenDisk {
    static func imeSeznama(klub: Int, dogodek: Int) -> String { "seznam-\(klub)-\(dogodek).json" }
    static func imeLokalnih(klub: Int, dogodek: Int) -> String { "lokalni-\(klub)-\(dogodek).json" }
    static func imeDogodkov(klub: Int) -> String { "dogodki-\(klub).json" }

    /// Pobrise shrambo dogodkov, ki niso vec na seznamu dogodkov kluba (po uspesnem prenosu seznama dogodkov).
    func pocisti(klub: Int, obdrzi: Set<Int>) {
        for ime in imena() where ime.hasSuffix(".json") {
            for predpona in ["seznam-\(klub)-", "lokalni-\(klub)-"] where ime.hasPrefix(predpona) {
                let sredina = ime.dropFirst(predpona.count).dropLast(5)
                if let id = Int(sredina), !obdrzi.contains(id) { izbrisi(ime) }
            }
        }
    }
}
