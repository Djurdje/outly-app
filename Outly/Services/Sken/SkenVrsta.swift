import Foundation

// Trajna hramba za sken brez povezave: vrsta skenov za streznik + konflikti + lokalni skeni dogodka + prenesen seznam.
// Vse je v Application Support/Sken (JSON, ne UserDefaults: seznam vstopnic je lahko velik), izkljuceno iz varnostne kopije.
// Pisanje je sinhrono in atomarno: sken, ki je vratarju pokazal zeleno, mora preziveti tudi ubitje aplikacije.
//
// Vrsta: ENA DATOTEKA NA VNOS (Sken/vrsta/<client_scan_id>.json). Dodajanje zapise samo en majhen vnos (ne cele vrste ob vsakem
// skenu), odstranjen vnos je izbrisana datoteka, pokvarjena datoteka pa ne potegne s seboj ostalih (pregled P5, M8).

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

    func podmapa(_ ime: String) -> SkenDisk { SkenDisk(mapa: mapa.appendingPathComponent(ime, isDirectory: true)) }

    private func pripravi() {
        try? FileManager.default.createDirectory(at: mapa, withIntermediateDirectories: true)
        var url = mapa
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? url.setResourceValues(v)
    }

    func surovo(_ ime: String) -> Data? {
        try? Data(contentsOf: mapa.appendingPathComponent(ime))
    }

    func preberi<T: Decodable>(_ tip: T.Type, _ ime: String) -> T? {
        guard let d = surovo(ime) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    /// true, ce je zapis uspel.
    @discardableResult
    func zapisi<T: Encodable>(_ vrednost: T, _ ime: String) -> Bool {
        guard let d = try? JSONEncoder().encode(vrednost) else { return false }
        return zapisiSurovo(d, ime)
    }

    @discardableResult
    func zapisiSurovo(_ d: Data, _ ime: String) -> Bool {
        pripravi()
        do {
            try d.write(to: mapa.appendingPathComponent(ime), options: .atomic)
            return true
        } catch { return false }
    }

    func izbrisi(_ ime: String) {
        try? FileManager.default.removeItem(at: mapa.appendingPathComponent(ime))
    }

    /// Cas zadnje spremembe datoteke (npr. kdaj je bil prenesen seznam dogodkov); nil, ce datoteke ni.
    func spremenjeno(_ ime: String) -> Date? {
        let atributi = try? FileManager.default.attributesOfItem(atPath: mapa.appendingPathComponent(ime).path)
        return atributi?[.modificationDate] as? Date
    }

    func imena() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: mapa.path)) ?? []
    }

    /// Pobrise celo mapo (z vsebino).
    func pobrisiVse() {
        try? FileManager.default.removeItem(at: mapa)
    }

    /// Pokvarjene vsebine ne brisemo: shranimo jo pod `<predpona>.pokvarjena-<cas>-<n>.json` poleg ostalih datotek (za sum o vzroku in rocno obnovo).
    func shraniPokvarjeno(_ predpona: String, _ vsebina: Data) {
        let cas = Int(Date().timeIntervalSince1970)
        var n = 0
        while FileManager.default.fileExists(atPath: mapa.appendingPathComponent("\(predpona).pokvarjena-\(cas)-\(n).json").path) { n += 1 }
        zapisiSurovo(vsebina, "\(predpona).pokvarjena-\(cas)-\(n).json")
    }
}

/// Sken, ki caka na streznik. Nastane SAMO ob lokalno zelenem skenu (ali vratarjevi odlocitvi za staro kodo).
struct SkenVnos: Codable, Equatable, Identifiable {
    /// Nov UUID za vsak sken (idempotentnost na strezniku: `batch|<device_id>|<client_scan_id>`).
    let clientScanId: String
    /// Surova koda; streznik jo ponovno preveri (podpis, dogodek, klub).
    let qr: String
    /// Serial iz kode; nil, ce ga ni bilo mogoce prebrati.
    let serial: String?
    let eventId: Int
    let klubId: Int
    /// Kdo je skeniral (me.id); nil, ce ni bil znan. Vrsto sinhronizira samo isti uporabnik.
    let uporabnikId: Int?
    let scannedAt: Date
    /// Ime imetnika / miza iz seznama, za prikaz v konfliktih (po odjavi se pobrise).
    var imetnik: String?
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
/// Ostane na disku, dokler ga vratar ne potrdi — ne brisemo tiho. Potrjene obrezemo po 30 dneh.
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
    /// Kdo je skeniral (me.id); konflikte (z imeni imetnikov) vidi samo ta uporabnik. nil = star zapis brez uporabnika.
    let uporabnikId: Int?

    var id: String { clientScanId }

    enum CodingKeys: String, CodingKey {
        case clientScanId, serial, eventId, klubId, scannedAt, result, streznikUsedAt, imetnik, potrjen, uporabnikId
    }

    init(clientScanId: String, serial: String?, eventId: Int, klubId: Int, scannedAt: Date, result: String,
         streznikUsedAt: String?, imetnik: String?, potrjen: Bool = false, uporabnikId: Int? = nil) {
        self.clientScanId = clientScanId
        self.serial = serial
        self.eventId = eventId
        self.klubId = klubId
        self.scannedAt = scannedAt
        self.result = result
        self.streznikUsedAt = streznikUsedAt
        self.imetnik = imetnik
        self.potrjen = potrjen
        self.uporabnikId = uporabnikId
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
        uporabnikId = (try? c.decodeIfPresent(Int.self, forKey: .uporabnikId)) ?? nil
    }
}

/// Trajna vrsta skenov (po klubih in uporabnikih; vnosi nosijo klubId in uporabnikId), preziveti mora zaprtje aplikacije.
@MainActor
final class SkenVrsta {
    nonisolated static let mapaVnosov = "vrsta"
    nonisolated static let datotekaKonfliktov = "konflikti.json"
    nonisolated static let predponaPokvarjenih = "vrsta"
    /// Streznik sprejme najvec 500 skenov na zahtevo.
    nonisolated static let najvecVPaketu = 500
    /// Potrjene konflikte obrezemo po toliko dneh (od skena).
    nonisolated static let potrjeneObdrzimoDni = 30

    private let disk: SkenDisk
    private let diskVnosov: SkenDisk
    private(set) var vnosi: [SkenVnos] = []
    private(set) var konflikti: [SkenKonflikt] = []
    /// Vnosi, katerih zapis na disk ni uspel, in ali zapis konfliktov ni uspel: ostane, dokler jih ponovni zapis ne potrdi (ne
    /// prepise ga naslednji uspesen zapis drugega vnosa).
    private var neuspeliVnosi: Set<String> = []
    private var konfliktiNeshranjeni = false
    /// false, ce kak zapis na disk ni (se) uspel (poln disk): skeni so le v pomnilniku — vratar to mora videti.
    var zapisUspel: Bool { neuspeliVnosi.isEmpty && !konfliktiNeshranjeni }
    /// Koliko datotek vrste je bilo ob nalaganju pokvarjenih (premaknjene na stran, ne izbrisane).
    private(set) var pokvarjenihDatotek = 0
    /// Vnosi, ki jih trenutno odloca hitra pot (sken z odgovorom streznika): periodicno posiljanje jih preskoci.
    private var zadrzani: Set<String> = []

    /// Ena vrsta na mapo v procesu: vse seje skenerja delijo isto kopijo v pomnilniku, zato si ne prepisujejo datotek.
    private static var skupne: [String: SkenVrsta] = [:]

    static func deljena(_ disk: SkenDisk) -> SkenVrsta {
        if let v = skupne[disk.mapa.path] { return v }
        let nova = SkenVrsta(disk: disk)
        skupne[disk.mapa.path] = nova
        return nova
    }

    init(disk: SkenDisk, zdaj: Date = Date()) {
        self.disk = disk
        self.diskVnosov = disk.podmapa(Self.mapaVnosov)
        nalozi(zdaj: zdaj)
    }

    // MARK: Nalaganje

    private func nalozi(zdaj: Date) {
        // Vnosi: vsaka datoteka posebej; pokvarjena gre na stran, ostale se ohranijo.
        var nalozeni: [SkenVnos] = []
        for ime in diskVnosov.imena() where ime.hasSuffix(".json") {
            guard let d = diskVnosov.surovo(ime) else { continue }
            if let v = try? JSONDecoder().decode(SkenVnos.self, from: d), v.clientScanId + ".json" == ime {
                nalozeni.append(v)
            } else {
                disk.shraniPokvarjeno(Self.predponaPokvarjenih, d)
                diskVnosov.izbrisi(ime)
                pokvarjenihDatotek += 1
            }
        }
        vnosi = nalozeni.sorted { $0.scannedAt < $1.scannedAt }

        // Konflikti: ena datoteka (tabela); elementi se dekodirajo posamicno.
        if let d = disk.surovo(Self.datotekaKonfliktov) {
            if let tabela = (try? JSONSerialization.jsonObject(with: d)) as? [Any] {
                var dobri: [SkenKonflikt] = []
                var slabi = 0
                for e in tabela {
                    if let podatki = try? JSONSerialization.data(withJSONObject: e),
                       let k = try? JSONDecoder().decode(SkenKonflikt.self, from: podatki) { dobri.append(k) } else { slabi += 1 }
                }
                konflikti = dobri
                if slabi > 0 { disk.shraniPokvarjeno("konflikti", d); pokvarjenihDatotek += 1; shraniKonflikte() }
            } else {
                disk.shraniPokvarjeno("konflikti", d)
                pokvarjenihDatotek += 1
            }
        }
        obrezi(zdaj: zdaj)
    }

    /// Potrjeni konflikti, starejsi od 30 dni, se pobrisejo; nepotrjeni ostanejo, dokler jih vratar ne potrdi.
    func obrezi(zdaj: Date = Date()) {
        let meja = zdaj.addingTimeInterval(-Double(Self.potrjeneObdrzimoDni) * 86400)
        let ostali = konflikti.filter { !($0.potrjen && $0.scannedAt < meja) }
        if ostali.count != konflikti.count {
            konflikti = ostali
            shraniKonflikte()
        }
    }

    // MARK: Zapis

    @discardableResult
    private func shraniKonflikte() -> Bool {
        let ok: Bool
        if konflikti.isEmpty {
            disk.izbrisi(Self.datotekaKonfliktov)
            ok = true
        } else {
            ok = disk.zapisi(konflikti, Self.datotekaKonfliktov)
        }
        konfliktiNeshranjeni = !ok
        return ok
    }

    /// Doda vnos. Idempotentno po `clientScanId`: drugi dodatek istega id-ja ne naredi nic (vrne false).
    /// `zadrzi`: vnos ostane v vrsti, a ga periodicno posiljanje preskoci, dokler ga ne sprosti hitra pot (`sprosti`/`odstrani`).
    @discardableResult
    func dodaj(_ v: SkenVnos, zadrzi: Bool = false) -> Bool {
        guard !vnosi.contains(where: { $0.clientScanId == v.clientScanId }) else { return false }
        vnosi.append(v)
        if zadrzi { zadrzani.insert(v.clientScanId) }
        zapisiVnos(v)
        return true
    }

    private func zapisiVnos(_ v: SkenVnos) {
        if diskVnosov.zapisi(v, v.clientScanId + ".json") { neuspeliVnosi.remove(v.clientScanId) } else { neuspeliVnosi.insert(v.clientScanId) }
    }

    /// Ponovno zapise, kar se ni uspelo zapisati (npr. disk je bil poln); klice SkenSeja ob vsakem skenu. Poceni, ce ni nicesar.
    func ponoviNeuspele() {
        guard !neuspeliVnosi.isEmpty || konfliktiNeshranjeni else { return }
        for id in Array(neuspeliVnosi) {
            if let v = vnosi.first(where: { $0.clientScanId == id }) { zapisiVnos(v) } else { neuspeliVnosi.remove(id) }
        }
        if konfliktiNeshranjeni { shraniKonflikte() }
    }

    func sprosti(_ id: String) { zadrzani.remove(id) }

    /// Odstrani vnos brez konflikta (hitra pot: streznik je sken zavrnil ali potrdil, gost ni bil spuscen na pol poti).
    func odstrani(_ id: String) {
        zadrzani.remove(id)
        neuspeliVnosi.remove(id)
        guard let idx = vnosi.firstIndex(where: { $0.clientScanId == id }) else { return }
        vnosi.remove(at: idx)
        diskVnosov.izbrisi(id + ".json")
    }

    // MARK: Poizvedbe

    /// Vnosi tega kluba (in uporabnika, ce je znan na obeh straneh), najstarejsi najprej; brez zadrzanih.
    func cakajoci(klub: Int, uporabnik: Int?) -> [SkenVnos] {
        vnosi.filter { $0.klubId == klub && Self.istiUporabnik($0.uporabnikId, uporabnik) }
    }

    /// Vsi neposlani vnosi (vseh klubov in uporabnikov).
    var steviloVseh: Int { vnosi.count }

    func stevilo(klub: Int, uporabnik: Int?) -> Int { cakajoci(klub: klub, uporabnik: uporabnik).count }

    func paket(klub: Int, uporabnik: Int?) -> [SkenVnos] {
        Array(cakajoci(klub: klub, uporabnik: uporabnik).filter { !zadrzani.contains($0.clientScanId) }.prefix(Self.najvecVPaketu))
    }

    /// Klubi, v katerih ima ta uporabnik neposlane vnose (za posiljanje ob odjavi: zeton velja samo za njega).
    func neposlaniKlubi(uporabnik: Int) -> [Int] {
        var videni = Set<Int>()
        var izhod: [Int] = []
        for v in vnosi where v.uporabnikId == uporabnik {
            if videni.insert(v.klubId).inserted { izhod.append(v.klubId) }
        }
        return izhod
    }

    private static func istiUporabnik(_ a: Int?, _ b: Int?) -> Bool {
        guard let a, let b else { return true }
        return a == b
    }

    // MARK: Odgovor strezniga

    /// Obdela odgovor scan-batch. Dokoncni rezultati odstranijo vnos; `ok` je tiho, vse drugo (already_used, transferred,
    /// wrong_club ...) pomeni, da je bil gost spusceni na podlagi lokalno zelenega skena, streznik pa tega ne potrdi -> konflikt.
    /// `error` (in vnos brez rezultata) ostane v vrsti s povecanim stevcem poskusov. Vrne stevilo odstranjenih vnosov.
    @discardableResult
    func uporabi(_ rezultati: [ScanBatchResult], poslani: [SkenVnos]) -> Int {
        let poId = Dictionary(rezultati.map { ($0.clientScanId, $0) }, uniquingKeysWith: { prvi, _ in prvi })
        var koncani: [String] = []
        var novi: [SkenKonflikt] = []
        for p in poslani {
            guard let idx = vnosi.firstIndex(where: { $0.clientScanId == p.clientScanId }) else { continue }  // ze obdelan (ponovitev)
            if let r = poId[p.clientScanId], r.jeDokoncen {
                let v = vnosi[idx]
                if r.result != "ok", !konflikti.contains(where: { $0.clientScanId == v.clientScanId }) {
                    novi.append(SkenKonflikt(clientScanId: v.clientScanId, serial: r.serial ?? v.serial, eventId: v.eventId,
                                             klubId: v.klubId, scannedAt: v.scannedAt, result: r.result,
                                             streznikUsedAt: r.usedAt, imetnik: v.imetnik, uporabnikId: v.uporabnikId))
                }
                koncani.append(v.clientScanId)
            } else {
                vnosi[idx].poskusi += 1
                zapisiVnos(vnosi[idx])
            }
        }
        // 1. Konflikti na disk PRED brisanjem vnosov: ubitje (ali napaka zapisa) vmes pusti vnos, ponovno posiljanje je idempotentno in
        //    konflikt nastane znova; v obratnem vrstnem redu bi se konflikt izgubil, gost pa je ze bil spuscen.
        var obdrzi = Set<String>()
        if !novi.isEmpty {
            let prej = konflikti
            konflikti.append(contentsOf: novi)
            if !shraniKonflikte() {
                konflikti = prej
                obdrzi = Set(novi.map { $0.clientScanId })
                for id in obdrzi { if let i = vnosi.firstIndex(where: { $0.clientScanId == id }) { vnosi[i].poskusi += 1 } }
            }
        }
        // 2. Sele zdaj brisanje vnosov.
        var odstranjeni = 0
        for id in koncani where !obdrzi.contains(id) {
            zadrzani.remove(id)
            neuspeliVnosi.remove(id)
            diskVnosov.izbrisi(id + ".json")
            vnosi.removeAll { $0.clientScanId == id }
            odstranjeni += 1
        }
        return odstranjeni
    }

    /// Nepotrjeni konflikti kluba; z `uporabnik` samo tega uporabnika (imena imetnikov vidi samo, kdor je skeniral).
    func nepotrjeniKonflikti(klub: Int, uporabnik: Int? = nil) -> [SkenKonflikt] {
        konflikti.filter { $0.klubId == klub && !$0.potrjen && Self.istiUporabnik($0.uporabnikId, uporabnik) }
    }

    func potrdiKonflikt(_ id: String) {
        guard let i = konflikti.firstIndex(where: { $0.clientScanId == id }) else { return }
        konflikti[i].potrjen = true
        obrezi()
        shraniKonflikte()
    }

    // MARK: Odjava

    /// Ob odjavi: konflikti (z imeni) gredo, neposlani vnosi ostanejo (za isti racun ob ponovni prijavi), brez imen imetnikov.
    func pocistiPoOdjavi() {
        konflikti = []
        disk.izbrisi(Self.datotekaKonfliktov)
        for i in vnosi.indices where vnosi[i].imetnik != nil {
            vnosi[i].imetnik = nil
            zapisiVnos(vnosi[i])
        }
    }
}

// MARK: - Shramba dogodka

/// Javni kljuc je en na backend (ne na dogodek): ena datoteka `kljuc.json` za vse dogodke in klube.
struct SkenKljucShramba: Codable, Equatable {
    var kljuc: ScanKey
    var prenesenoOb: Date
}

/// Prenesen seznam dogodka; `hash` je SHA-256 surovega odgovora (nespremenjen odgovor se ne dekodira in ne zapisuje znova).
struct SkenSeznamMeta: Codable, Equatable {
    var hash: String
    var prenesenoOb: Date
}

/// Lokalni skeni dogodka na tej napravi: serial -> cas. Ostanejo tudi po sinhronizaciji (vrsta jih odstrani),
/// da ponovni sken ostane rdec, dokler seznam ne pokaze `used`.
struct SkenLokalniSkeni: Codable, Equatable {
    var casi: [String: Date] = [:]
}

extension SkenDisk {
    static let imeKljuca = "kljuc.json"
    static func imeSeznama(klub: Int, dogodek: Int) -> String { "seznam-\(klub)-\(dogodek).json" }
    static func imeMeta(klub: Int, dogodek: Int) -> String { "meta-\(klub)-\(dogodek).json" }
    static func imeLokalnih(klub: Int, dogodek: Int) -> String { "lokalni-\(klub)-\(dogodek).json" }
    static func imeDogodkov(klub: Int) -> String { "dogodki-\(klub).json" }

    /// Pobrise shrambo dogodkov, ki niso vec na seznamu dogodkov kluba (po uspesnem prenosu seznama dogodkov).
    func pocisti(klub: Int, obdrzi: Set<Int>) {
        for ime in imena() where ime.hasSuffix(".json") {
            for predpona in ["seznam-\(klub)-", "meta-\(klub)-", "lokalni-\(klub)-"] where ime.hasPrefix(predpona) {
                let sredina = ime.dropFirst(predpona.count).dropLast(5)
                if let id = Int(sredina), !obdrzi.contains(id) { izbrisi(ime) }
            }
        }
    }

    /// Pobrise vse, kar je vezano na klub (seznami, lokalni skeni, dogodki). Vrsta neposlanih vnosov ostane.
    func pocistiKlub(_ klub: Int) {
        pocisti(klub: klub, obdrzi: [])
        izbrisi(Self.imeDogodkov(klub: klub))
    }

    /// Pobrise vse razen vrste neposlanih vnosov (`vrsta/`), ki jo ob odjavi obdrzimo.
    func pocistiVsePoOdjavi() {
        for ime in imena() {
            if ime == SkenVrsta.mapaVnosov { continue }   // pokvarjene datoteke gredo z ostalim (lahko vsebujejo imena imetnikov)
            izbrisi(ime)
        }
    }
}
