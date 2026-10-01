import Foundation
import Combine
import CryptoKit

// Sken brez povezave (backend issue #86, 1. 10. 2026): orkestrator za enega kluba.
//
//  - Ob odprtju dogodka prenese javni kljuc (en na backend, kljuc.json) in seznam vstopnic (na dogodek), shrani na disk in
//    osvezuje seznam na ~2 min. Ce sta ze na disku, je skener pripravljen takoj, tudi brez povezave.
//  - Sken kode v2 se odloci LOKALNO (SkenOdlocitev). BREZ povezave je lokalna sodba dokoncna: zeleno takoj, zapis v trajno vrsto.
//    Z POVEZAVO je zelena sodba samo predlog (K2): vnos gre v vrsto in takoj prek scan-batch na streznik s kratkim rokom
//    (~2 s); odgovor streznika odloci (ok -> zeleno, already_used/transferred/... -> rdece), ob roku ali napaki velja lokalna sodba.
//  - Vrsta se poslje prek scan-batch takoj po skenu in vsako sekundo, ce kaj caka (eksponentno odlaganje ob napaki).
//    Streznik je razsodnik: ce je isto vstopnico pred nami spustil drug telefon brez povezave, pride `already_used` in to postane konflikt.
//  - Kode v1: s povezavo obstojec POST /business/tickets/scan (kratek rok), brez nje rumeno; vratar sme v1 spustiti sam (potrditev).

/// Odjemalec za sken. Zivi je v APIClient+Sken.swift; testi podtaknejo svojega. `klubId` je izrecen (glava X-Outly-Club), nil = ni znan.
protocol SkenApi: Sendable {
    func dogodki(token: String, klubId: Int?) async throws -> [SkenDogodek]
    func kljuc(token: String, klubId: Int?) async throws -> ScanKey
    /// Surov odgovor scan-list (SkenSeja ga zgosti in dekodira izven glavne niti).
    func seznam(token: String, klubId: Int?, dogodekId: Int) async throws -> Data
    func paket(token: String, klubId: Int?, vnosi: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult]
    func spletniSken(token: String, klubId: Int?, qr: String, rok: Double) async throws -> ScanResult
}

/// Nakljucen UUID, ustvarjen enkrat na namestitev (backend: predvidljiv device_id bi omogocil napacen `ok`).
enum SkenNaprava {
    static let kljuc = "outly.sken.deviceId"

    static func id(_ privzete: UserDefaults = .standard) -> String {
        if let v = privzete.string(forKey: kljuc), !v.isEmpty { return v }
        let nov = UUID().uuidString.lowercased()
        privzete.set(nov, forKey: kljuc)
        return nov
    }
}

enum SkenRok {
    /// Izvede `delo` z rokom. nil = rok je potekel (delo se prekine); .failure = delo je padlo pred rokom.
    static func zRokom<T: Sendable>(_ sekunde: Double, _ delo: @escaping @Sendable () async throws -> T) async -> Result<T, Error>? {
        await withTaskGroup(of: Result<T, Error>?.self) { skupina in
            skupina.addTask {
                do { return .success(try await delo()) } catch { return .failure(error) }
            }
            skupina.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(sekunde, 0) * 1_000_000_000))
                return nil
            }
            let prvi: Result<T, Error>?? = await skupina.next()
            skupina.cancelAll()
            return prvi ?? nil
        }
    }

    static func sha256(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class SkenSeja: ObservableObject {

    enum Priprava: Equatable {
        /// Dogodek ni izbran.
        case izbira
        /// Kljuc se prenasa in ga se ni na disku.
        case nalaga
        /// Javni kljuc je na napravi: lokalno preverjanje dela (seznam vstopnic je dodatek).
        case pripravljen
        /// Prenos kljuca ni uspel in na disku ga ni (sporocilo za vratarja).
        case manjkaPodatkov(String)
    }

    // MARK: Kar vidi zaslon

    @Published private(set) var dogodki: [SkenDogodek] = []
    @Published private(set) var dogodkiNalaga = false
    @Published private(set) var dogodkiNapaka: String?
    @Published private(set) var dogodek: SkenDogodek?
    @Published private(set) var priprava: Priprava = .izbira
    /// Ali je streznik dosegljiv: omrezje je gor IN zadnji klic ni padel zaradi izpada.
    @Published private(set) var povezava = true
    /// Skeni v vrsti, ki jih streznik se ni potrdil.
    @Published private(set) var cakajoce = 0
    @Published private(set) var zadnjiPrenos: Date?
    /// Seznam je starejsi od ~10 min (osvezevanje ne uspeva): vratar naj to vidi.
    @Published private(set) var seznamStar = false
    /// Nepotrjeni konflikti tega kluba (ob zacetku vsi iz diska).
    @Published private(set) var konflikti: [SkenKonflikt] = []
    /// false: zadnji zapis na disk ni uspel, skeni so samo v pomnilniku.
    @Published private(set) var zapisOK = true
    @Published private(set) var sprejeti = 0
    @Published private(set) var zavrnjeni = 0
    /// Tece preverjanje na strezniku (hitra pot ali spletni sken): zaslon kaze »Checking…«.
    @Published private(set) var preverjaNaStrezniku = false
    /// Streznik je vrnil 403: uporabnik ni vec clan ekipe tega kluba (seznami so pobrisani, neposlani skeni ostanejo).
    @Published private(set) var dostopOdvzet = false

    // MARK: Notranje

    let klubId: Int
    /// me.id; nastavi zaslon (vrsto sinhronizira samo uporabnik, ki je skeniral).
    var uporabnikId: Int?
    /// Dostopni zeton ob vsakem klicu (osvezi ga send()).
    var zeton: @MainActor () -> String = { "" }

    private let api: SkenApi
    private let disk: SkenDisk
    private let vrsta: SkenVrsta
    private let deviceId: String
    private let rokStreznika: Double
    private let rokSpletni: Double
    private let kljucOdmik: Double

    private var kljuc: ScanKey?
    private var kljucOb: Date?
    private var kljucPoskusOb = Date.distantPast
    private var kljucVTeku = false
    private var indeks: SkenIndeks?
    private var seznamHash: String?
    private var lokalni: [String: Date] = [:]

    private var omrezjeGor = true
    private var zadnjiKlicOK = true
    private var posiljanjeVTeku = false
    private var osvezitevZaDogodek: Int?
    private var zaporedneNapake = 0
    private var naslednjePosiljanje = Date.distantPast
    private var naslednjaOsvezitev = Date.distantPast
    private var zanka: Task<Void, Never>?

    static let osvezitevSekunde: ClosedRange<Double> = 105...135   // ~2 min z odmikom, da 1000 telefonov ne vleče naenkrat
    static let najdaljsiOdmik: Double = 120
    static let odmikOsvezitveOdNapake: Double = 15
    /// Seznam je »star«, ce ni bil osvezen toliko sekund (osvezevanje je na ~2 min).
    nonisolated static let seznamStarPoSekundah: Double = 10 * 60
    nonisolated static let kljucNajmanjMedPoskusi: Double = 20

    /// `vrsta`: privzeto ena skupna na disk (SkenVrsta.deljena). Dve seji z lastno kopijo vrste bi si prepisovali datoteke.
    /// Testi podajo svojo (nov zagon aplikacije = nova vrsta z diska).
    init(klubId: Int, uporabnikId: Int? = nil, api: SkenApi, disk: SkenDisk = SkenDisk(),
         deviceId: String = SkenNaprava.id(), vrsta: SkenVrsta? = nil,
         rokStreznika: Double = 2.0, rokSpletni: Double = 4.0, kljucOdmik: Double = SkenSeja.kljucNajmanjMedPoskusi) {
        self.klubId = klubId
        self.uporabnikId = uporabnikId
        self.api = api
        self.disk = disk
        self.deviceId = deviceId
        self.vrsta = vrsta ?? SkenVrsta.deljena(disk)
        self.rokStreznika = rokStreznika
        self.rokSpletni = rokSpletni
        self.kljucOdmik = kljucOdmik
        osveziStevce()
    }

    /// Klub za glavo X-Outly-Club; 0 = ni znan (streznik vzame prvo clanstvo).
    private var klubZaApi: Int? { klubId > 0 ? klubId : nil }

    // MARK: - Zivljenjski cikel

    /// Zazene 1-sekundni tik (posiljanje vrste, osvezevanje seznama). Idempotentno.
    func zacni() {
        guard zanka == nil else { return }
        zanka = Task { [weak self] in
            while !Task.isCancelled {
                guard let s = self else { return }
                s.tik()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func ustavi() {
        zanka?.cancel()
        zanka = nil
    }

    /// NWPathMonitor (zaslon) javi, ali je kaksna pot do omrezja. Ob vrnitvi omrezja takoj poskusimo vse.
    func omrezjeSpremenjeno(gor: Bool) {
        let bilo = povezava
        omrezjeGor = gor
        posodobiPovezavo()
        if gor && !bilo { takojOsvezi() }
    }

    /// Aplikacija je spet aktivna (npr. po zaklepu zaslona) ali se je vrnila povezava: takoj poskusi osvezitev in posiljanje.
    func takojOsvezi() {
        zaporedneNapake = 0
        naslednjePosiljanje = .distantPast
        naslednjaOsvezitev = .distantPast
    }

    /// Osvezitev in posiljanje tecesta vsako v svojem Tasku: pocasen prenos seznama ne sme zadrzati posiljanja skenov.
    private func tik() {
        let zdaj = Date()
        let star = Self.jeStar(zadnjiPrenos, zdaj: zdaj)
        if star != seznamStar { seznamStar = star }
        guard !dostopOdvzet else { return }
        if dogodek != nil, zdaj >= naslednjaOsvezitev, osvezitevZaDogodek == nil { Task { await osveziSeznam() } }
        if cakajoce > 0, zdaj >= naslednjePosiljanje, !posiljanjeVTeku { Task { await poslji() } }
    }

    /// Seznam je star, ce je bil nazadnje prenesen pred vec kot 10 min. Brez prenosa (nil) ni »star«, ampak »ni prenesen«.
    nonisolated static func jeStar(_ prenos: Date?, zdaj: Date) -> Bool {
        guard let prenos else { return false }
        return zdaj.timeIntervalSince(prenos) > seznamStarPoSekundah
    }

    // MARK: - Dogodki (izbira)

    /// Najprej shranjeni seznam (deluje brez povezave), nato osvezitev.
    func naloziDogodke() async {
        if dogodki.isEmpty, let shranjeni = disk.preberi([SkenDogodek].self, SkenDisk.imeDogodkov(klub: klubId)) {
            dogodki = shranjeni
        }
        dogodkiNalaga = true
        defer { dogodkiNalaga = false }
        do {
            let sveziSeznam = try await api.dogodki(token: zeton(), klubId: klubZaApi)
            zabeleziUspeh()
            dogodki = sveziSeznam
            dogodkiNapaka = nil
            disk.zapisi(sveziSeznam, SkenDisk.imeDogodkov(klub: klubId))
            disk.pocisti(klub: klubId, obdrzi: Set(sveziSeznam.map { $0.id }))
        } catch {
            if await jeOdvzemDostopa(error) { return }
            zabeleziNapako(error)
            dogodkiNapaka = dogodki.isEmpty ? error.userMessage : nil
        }
    }

    /// Dogodki, ki jih ponudimo vratarju: objavljeni in ne (davno) koncani, po zacetku.
    var ponujeniDogodki: [SkenDogodek] {
        let meja = Date().addingTimeInterval(-12 * 3600)
        return dogodki
            .filter { d in
                guard d.status == "published" else { return false }
                if d.lifecycle == "ended" {
                    let konec = SkenCas.razcleni(d.endAt) ?? SkenCas.razcleni(d.startAt) ?? .distantPast
                    return konec > meja   // vrata so lahko odprta se kaksno uro po koncu
                }
                return true
            }
            .sorted { (SkenCas.razcleni($0.startAt) ?? .distantFuture) < (SkenCas.razcleni($1.startAt) ?? .distantFuture) }
    }

    // MARK: - Odprt dogodek

    func odpri(_ d: SkenDogodek) async {
        dogodek = d
        sprejeti = 0
        zavrnjeni = 0
        indeks = nil
        seznamHash = nil
        lokalni = [:]
        zadnjiPrenos = nil
        seznamStar = false
        if kljuc == nil, let s = disk.preberi(SkenKljucShramba.self, SkenDisk.imeKljuca) {
            kljuc = s.kljuc
            kljucOb = s.prenesenoOb
        }
        let klub = klubId
        let disku = disk
        let shranjen = await Task.detached { () -> (ScanList, SkenSeznamMeta)? in
            guard let podatki = disku.surovo(SkenDisk.imeSeznama(klub: klub, dogodek: d.id)),
                  let meta = disku.preberi(SkenSeznamMeta.self, SkenDisk.imeMeta(klub: klub, dogodek: d.id)),
                  let l = try? JSONDecoder().decode(ScanList.self, from: podatki) else { return nil }
            return (l, meta)
        }.value
        guard dogodek?.id == d.id else { return }
        if let (l, meta) = shranjen, l.eventId == d.id || l.eventId == 0 {
            indeks = SkenIndeks(l)
            seznamHash = meta.hash
            zadnjiPrenos = meta.prenesenoOb
        }
        lokalni = disk.preberi(SkenLokalniSkeni.self, SkenDisk.imeLokalnih(klub: klubId, dogodek: d.id))?.casi ?? [:]
        priprava = jePripravljen ? .pripravljen : .nalaga
        naslednjaOsvezitev = .distantPast
        if kljuc?.surovi == nil { await osveziKljuc() }
        await osveziSeznam()
        posodobiPripravo()
    }

    func zapriDogodek() {
        dogodek = nil
        priprava = .izbira
    }

    private var jePripravljen: Bool { kljuc?.surovi != nil }

    private func posodobiPripravo() {
        guard dogodek != nil else { return }
        if jePripravljen { priprava = .pripravljen }
        else if case .nalaga = priprava { priprava = .manjkaPodatkov(String(localized: "The scanner key could not be downloaded.")) }
    }

    /// Prenese javni kljuc (en na backend) in ga shrani; neuspel poskus se ponovi najprej cez 20 s. Vrne true, ce imamo uporaben kljuc.
    @discardableResult
    func osveziKljuc() async -> Bool {
        guard !kljucVTeku, !dostopOdvzet else { return jePripravljen }
        guard Date().timeIntervalSince(kljucPoskusOb) >= kljucOdmik else { return jePripravljen }
        kljucVTeku = true
        kljucPoskusOb = Date()
        defer { kljucVTeku = false }
        do {
            let nov = try await api.kljuc(token: zeton(), klubId: klubZaApi)
            zabeleziUspeh()
            guard nov.surovi != nil else { return jePripravljen }
            kljucPoskusOb = .distantPast   // omejitev velja samo za neuspele poskuse: zamenjava kljuca ob prenosu seznama ne sme cakati
            kljuc = nov
            kljucOb = Date()
            disk.zapisi(SkenKljucShramba(kljuc: nov, prenesenoOb: kljucOb ?? Date()), SkenDisk.imeKljuca)
            posodobiPripravo()
            return true
        } catch {
            if await jeOdvzemDostopa(error) { return false }
            zabeleziNapako(error)
            return jePripravljen
        }
    }

    /// Prenese seznam, shrani na disk. Nespremenjen odgovor (enak SHA-256) se ne dekodira in ne zapisuje znova; dekodiranje je izven
    /// glavne niti. Ob napaki (omrezje, pokvarjen odgovor) ostane stari seznam.
    func osveziSeznam() async {
        guard let d = dogodek, osvezitevZaDogodek != d.id, !dostopOdvzet else { return }
        osvezitevZaDogodek = d.id
        defer { osvezitevZaDogodek = nil }
        naslednjaOsvezitev = Date().addingTimeInterval(Double.random(in: Self.osvezitevSekunde))
        do {
            let podatki = try await api.seznam(token: zeton(), klubId: klubZaApi, dogodekId: d.id)
            guard dogodek?.id == d.id else { return }   // vratar je medtem zamenjal dogodek
            zabeleziUspeh()
            let zdaj = Date()
            let hash = await Task.detached { SkenRok.sha256(podatki) }.value
            if hash == seznamHash, indeks != nil {
                // Nespremenjeno: samo osvezi cas prenosa (tudi na disku, da po ponovnem zagonu ni videti starejsi).
                zadnjiPrenos = zdaj
                seznamStar = false
                disk.zapisi(SkenSeznamMeta(hash: hash, prenesenoOb: zdaj), SkenDisk.imeMeta(klub: klubId, dogodek: d.id))
                return
            }
            let (seznam, idx) = try await Task.detached { () -> (ScanList, SkenIndeks) in
                let l = try JSONDecoder().decode(ScanList.self, from: podatki)
                return (l, SkenIndeks(l))
            }.value
            guard dogodek?.id == d.id else { return }
            indeks = idx
            seznamHash = hash
            zadnjiPrenos = zdaj
            seznamStar = false
            disk.zapisiSurovo(podatki, SkenDisk.imeSeznama(klub: klubId, dogodek: d.id))
            disk.zapisi(SkenSeznamMeta(hash: hash, prenesenoOb: zdaj), SkenDisk.imeMeta(klub: klubId, dogodek: d.id))
            // Kljuc primerjamo po `kid` ob vsakem prenosu (STATE.md: zamenjava QR_SECRET spremeni javni kljuc). Stari kljuc ostane,
            // dokler novega ne dobimo: kode z novim `kid` so takrat rumene, ne rdece (SkenOdlocitev).
            if !seznam.kid.isEmpty, kljuc?.kid != seznam.kid { await osveziKljuc() }
            posodobiPripravo()
        } catch {
            if await jeOdvzemDostopa(error) { return }
            zabeleziNapako(error)
            // Brez povezave ali s pokvarjenim odgovorom poskusi kmalu znova (vratar naj vidi, da se je povezava vrnila), ne cez 2 min.
            naslednjaOsvezitev = Date().addingTimeInterval(Self.odmikOsvezitveOdNapake)
            posodobiPripravo()
        }
    }

    // MARK: - Sken

    /// Odlocitev za eno kodo. Brez povezave je zeleno takoj; z njo odloci streznik (hitra pot, rok ~2 s).
    func skeniraj(_ surova: String) async -> SkenPrikaz {
        let qr = surova.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = dogodek else {
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "REFUSED"), podnaslov: String(localized: "Choose an event first."))
        }
        let sodba = SkenOdlocitev.odloci(qr: qr, dogodekId: d.id, kljuc: kljuc, indeks: indeks, lokalni: lokalni)
        switch sodba.barva {
        case .zeleno:
            return await sprejmiZeleno(qr: qr, sodba: sodba, dogodek: d)
        case .rdece:
            zavrnjeni += 1
            return SkenPrikaz.iz(sodba, qr: qr)
        case .rumeno:
            return await preveriRumeno(qr: qr, sodba: sodba, dogodek: d)
        }
    }

    /// Lokalno zelena koda v2. Z povezavo (K2) gre vnos najprej v vrsto (isti client_scan_id), nato takoj na streznik: dva vratarja,
    /// ki sta oba online, ne smeta spustiti iste kode. Brez povezave ali ob roku/napaki velja lokalna sodba (sprejeto tveganje, I14).
    private func sprejmiZeleno(qr: String, sodba: SkenSodba, dogodek d: SkenDogodek) async -> SkenPrikaz {
        let vnos = SkenVnos(qr: qr, serial: sodba.serial, eventId: d.id, klubId: klubId, uporabnikId: uporabnikId,
                            imetnik: opisImetnika(sodba.vstopnica))
        let hitro = povezava && !dostopOdvzet
        // Najprej vrsta, nato lokalni zapis: ce aplikacija umre vmes, sken ne sme izginiti (najslabse: ponovni sken je spet zelen,
        // streznik pa ga ujame kot already_used).
        vrsta.dodaj(vnos, zadrzi: hitro)
        let kljucLokalnih = sodba.serial ?? qr
        lokalni[kljucLokalnih] = vnos.scannedAt
        zapisiLokalne(d)
        osveziStevce()

        guard hitro else {
            sprejeti += 1
            if zaporedneNapake == 0 { Task { await poslji() } }
            return SkenPrikaz.iz(sodba, qr: qr)
        }

        preverjaNaStrezniku = true
        defer { preverjaNaStrezniku = false }
        let t = zeton()
        let klub = klubZaApi
        let naprava = deviceId
        let api = self.api
        let odgovor = await SkenRok.zRokom(rokStreznika) { try await api.paket(token: t, klubId: klub, vnosi: [vnos], deviceId: naprava) }
        switch odgovor {
        case .success(let rezultati)?:
            zabeleziUspeh()
            if let r = rezultati.first(where: { $0.clientScanId == vnos.clientScanId }), r.jeDokoncen {
                vrsta.odstrani(vnos.clientScanId)
                osveziStevce()
                if r.result == "ok" {
                    sprejeti += 1
                    // Streznik je potrdil: opomba »ni na seznamu, streznik preveri pozneje« ne velja vec.
                    return SkenPrikaz.iz(SkenSodba(razlog: .veljavna, serial: sodba.serial, vstopnica: sodba.vstopnica), qr: qr)
                }
                // Streznik gosta ni spustil: ni vstopa, ni konflikta; naslednji sken iste kode naj spet vpraša streznik.
                lokalni.removeValue(forKey: kljucLokalnih)
                zapisiLokalne(d)
                zavrnjeni += 1
                return SkenPrikaz.iz(streznik: r.result, usedAt: r.usedAt, sodba: sodba)
            }
        case .failure(let napaka)?:
            if await jeOdvzemDostopa(napaka) {} else { zabeleziNapako(napaka) }
        case nil:
            break   // rok je potekel: velja lokalna sodba
        }
        // Brez dokoncnega odgovora: vnos ostane v vrsti in ga periodicno posiljanje poslje (idempotentno po client_scan_id).
        vrsta.sprosti(vnos.clientScanId)
        sprejeti += 1
        return SkenPrikaz.iz(sodba, qr: qr)
    }

    /// Rumena koda (v1, ni kljuca, zastarel kljuc): z povezavo odloci streznik (POST /scan, kratek rok), brez nje (ali ob roku) vratar.
    private func preveriRumeno(qr: String, sodba: SkenSodba, dogodek d: SkenDogodek) async -> SkenPrikaz {
        if sodba.razlog == .kljucNeujema { Task { await osveziKljuc() } }
        guard povezava, !dostopOdvzet else { return SkenPrikaz.iz(sodba, qr: qr) }
        preverjaNaStrezniku = true
        defer { preverjaNaStrezniku = false }
        let t = zeton()
        let klub = klubZaApi
        let rok = rokSpletni
        let api = self.api
        let odgovor = await SkenRok.zRokom(rok) { try await api.spletniSken(token: t, klubId: klub, qr: qr, rok: rok) }
        switch odgovor {
        case .success(let r)?:
            zabeleziUspeh()
            if r.result == "ok" {
                sprejeti += 1
                lokalni[sodba.serial ?? qr] = Date()   // brez povezave ista koda ne sme spet na rumeno -> rdece "ze skenirano"
                zapisiLokalne(d)
            } else {
                zavrnjeni += 1
            }
            return SkenPrikaz.iz(r)
        case .failure(let napaka)?:
            if await jeOdvzemDostopa(napaka) {} else { zabeleziNapako(napaka) }
        case nil:
            break   // rok je potekel (npr. Wi-Fi brez interneta): rumeno, vratar odloci
        }
        return SkenPrikaz.iz(sodba, qr: qr)
    }

    /// Vratar je kodo v1 odlocil spustiti (po potrditvi). Gre v vrsto: streznik jo preveri naknadno. Samo za kodo v1 z berljivim
    /// telesom za ta dogodek; vse drugo se zavrne.
    func spustiRocno(qr surova: String) -> SkenPrikaz {
        let qr = surova.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = dogodek, case let .v1(telo) = SkenKoda.razcleni(qr), telo.eventId == d.id else {
            return SkenPrikaz.iz(SkenSodba(razlog: .neveljavna), qr: qr)
        }
        if let cas = lokalni[telo.serial] { return SkenPrikaz.iz(SkenSodba(razlog: .zeUporabljenaLokalno, serial: telo.serial, kdaj: cas), qr: qr) }
        let vnos = SkenVnos(qr: qr, serial: telo.serial, eventId: d.id, klubId: klubId, uporabnikId: uporabnikId)
        vrsta.dodaj(vnos)
        lokalni[telo.serial] = vnos.scannedAt
        zapisiLokalne(d)
        osveziStevce()
        sprejeti += 1
        if zaporedneNapake == 0 { Task { await poslji() } }
        return SkenPrikaz.spusceniRocno()
    }

    private func zapisiLokalne(_ d: SkenDogodek) {
        if !disk.zapisi(SkenLokalniSkeni(casi: lokalni), SkenDisk.imeLokalnih(klub: klubId, dogodek: d.id)) { zapisOK = false }
    }

    private func opisImetnika(_ v: ScanListTicket?) -> String? {
        guard let v else { return nil }
        var deli: [String] = []
        if let i = v.holderUsername, !i.isEmpty { deli.append(i) }
        if v.isVip { deli.append(VipOznaka.vrstica(tableLabel: v.tableLabel, packageName: v.packageName)) }
        return deli.isEmpty ? nil : deli.joined(separator: " · ")
    }

    // MARK: - Posiljanje vrste

    /// Poslje vse, kar caka (po paketih do 500). Ob napaki odlozi z eksponentnim odmikom (5 s ... 2 min).
    func poslji() async {
        guard !posiljanjeVTeku, !dostopOdvzet else { return }
        posiljanjeVTeku = true
        defer { posiljanjeVTeku = false }
        while true {
            let paket = vrsta.paket(klub: klubId, uporabnik: uporabnikId)
            if paket.isEmpty { zaporedneNapake = 0; osveziStevce(); return }
            do {
                let rezultati = try await api.paket(token: zeton(), klubId: klubZaApi, vnosi: paket, deviceId: deviceId)
                zabeleziUspeh()
                let odstranjeni = vrsta.uporabi(rezultati, poslani: paket)
                osveziStevce()
                if odstranjeni == 0 { odlozi(); return }   // streznik je odgovoril, a vse so `error`
                zaporedneNapake = 0
            } catch {
                if await jeOdvzemDostopa(error, poskusiPoslati: false) { return }
                zabeleziNapako(error)
                odlozi()
                return
            }
        }
    }

    /// Pocaka, da tece posiljanje konca (za teste; zaslon tega ne rabi).
    func pocakajPosiljanje() async {
        while posiljanjeVTeku { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    private func odlozi() {
        zaporedneNapake += 1
        let odmik = min(5 * pow(2.0, Double(zaporedneNapake - 1)), Self.najdaljsiOdmik)
        naslednjePosiljanje = Date().addingTimeInterval(odmik)
    }

    func potrdiKonflikt(_ k: SkenKonflikt) {
        vrsta.potrdiKonflikt(k.clientScanId)
        osveziStevce()
    }

    // MARK: - Dostop (403)

    /// Streznik je vrnil 403: uporabnik ni vec clan ekipe tega kluba. Najprej poskusimo poslati, kar caka (ce napaka ni ze od
    /// posiljanja), nato pobrisemo seznami in lokalne skene kluba (imena imetnikov). Neposlani vnosi OSTANEJO na disku.
    /// Vrne true, ce je bila napaka 403.
    private func jeOdvzemDostopa(_ napaka: Error, poskusiPoslati: Bool = true) async -> Bool {
        guard let a = napaka as? APIError, case let .requestFailed(koda, _) = a, koda == 403 else { return false }
        if poskusiPoslati, !posiljanjeVTeku, cakajoce > 0 { await poslji() }
        dostopOdvzet = true
        disk.pocistiKlub(klubId)
        indeks = nil
        seznamHash = nil
        lokalni = [:]
        dogodki = []
        zadnjiPrenos = nil
        return true
    }

    // MARK: - Stanje povezave

    private func osveziStevce() {
        cakajoce = vrsta.stevilo(klub: klubId, uporabnik: uporabnikId)
        konflikti = vrsta.nepotrjeniKonflikti(klub: klubId)
        zapisOK = vrsta.zapisUspel
    }

    private func zabeleziUspeh() {
        zadnjiKlicOK = true
        posodobiPovezavo()
    }

    private func zabeleziNapako(_ e: Error) {
        if Self.jeOmrezna(e) {
            zadnjiKlicOK = false
            posodobiPovezavo()
        }
    }

    private func posodobiPovezavo() {
        let nova = omrezjeGor && zadnjiKlicOK
        if povezava != nova { povezava = nova }
    }

    /// Napaka zaradi omrezja ali izpada streznika (ne zaradi vsebine zahteve, ne zaradi preklica).
    nonisolated static func jeOmrezna(_ e: Error) -> Bool { e.jeIzpadPovezave }
}
