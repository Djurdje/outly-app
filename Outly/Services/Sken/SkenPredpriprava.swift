import Foundation

// Priprava skenerja v ozadju (outly-backend#406, 8. 11. 2026): kljuc, dogodki in seznami vstopnic se prenesejo, takoj ko je uporabnik
// prijavljen in je v klubu z vlogo, ki sme skenirati - ne sele ob odprtju skenerja. Novo nameslena aplikacija ali nov vratar ob izpadu
// backenda ob 23:00 tako ima podatke na disku in skener dela kot ob ze prenesenih podatkih.
//
//  - Isti klici in ista shramba kot pri skenerju: za vsak klub se zazene navadna SkenSeja (brez 1-sekundnega tika, brez zaslona) in
//    poklice naloziDogodke(). Format na disku se ne spreminja; shranjen seznam se zamenja SAMO z uspesno prenesenim (to pocne SkenSeja).
//  - Sprozilca: GET /me uspel (prijava, refreshMe) in vrnitev aplikacije v ospredje. Najvec 1x na 10 min na klub (v pomnilniku, zato
//    hladen zagon vedno pripravi znova). Napake so tihe; vratar ob odprtju skenerja dobi isto kot prej.
//  - Brez BGTask in brez novih dovoljenj: samo, ko je aplikacija v ospredju.
//  - Odjava (SessionStore.clearLocalSession) priprava PREKLICE pred brisanjem diska. Tekoca priprava, ki se po preklicu vseeno konca
//    (zahtevek ali zapis na disk preklica ne doseze), za vsak klub, ki ga je zacela, VEDNO pobrise njegove sezname (ne glede na zeton:
//    ob takojsnji prijavi drugega uporabnika zeton ni prazen). Nova priprava (drug uporabnik) pocaka, da stara konca in pocisti.
//  - Za klub, za katerega je skener odprt (SkenSeja.zacni/ustavi), priprava ne teece: backend dovoli le 2 hkratna scan-list na platformo.
//  - Prekinjen (preklic) ali brezomrezen poskus ne porabi 10-minutnega okna; uspeh ali odgovor streznika ga porabi.

@MainActor
final class SkenPredpriprava {

    static let deljena = SkenPredpriprava()

    /// Najmanj toliko sekund med dvema pripravama istega kluba.
    nonisolated static let najmanjMedPripravami: Double = 10 * 60
    /// Vloge v klubu, ki smejo skenirati (backend: vse vloge v klubu razen natakarja).
    nonisolated static let skenirajoceVloge: Set<String> = ["owner", "manager", "doorman"]

    /// Pripravi en klub (klubId, uporabnikId, zeton). Vrne true, ce je poskus porabil okno (vsak izid razen preklica in izpada
    /// omrezja), false, ce je bil prekinjen ali brez omrezja. Privzeto prava priprava; testi podtaknejo svojo.
    typealias Pripravi = @MainActor (Int, Int?, @escaping @MainActor () -> String) async -> Bool
    /// Pobrise podatke kluba z diska (seznami z imeni imetnikov, lokalni skeni) in predpomnilnik odgovorov. Neposlani vnosi ostanejo.
    typealias Pocisti = @MainActor (Int) -> Void

    private let pripravi: Pripravi
    private let pocisti: Pocisti
    /// Pobrise sezname starejse od 3 dni (zasebnost). Teče ob vsakem sprozilcu, tudi ce skenerja nihce nikoli ne odpre.
    private let ociStare: @MainActor () -> Void
    /// Ura telefona (testi jo podtaknejo).
    var ura: @MainActor () -> Date = { Date() }

    private var zadnje: [Int: Date] = [:]
    private var tek: Task<Void, Never>?
    /// Zadnja preklicana priprava, ki se morda se konca: nova pocaka nanjo (njeno ciscenje ne sme pobrisati zapisov nove).
    private var preklicana: Task<Void, Never>?
    /// Odprti skenerji: seja -> klub. Sibka referenca: seja, ki izgine brez ustavi(), ne more ostati zapisana (priprava zanjo ne sme za vedno mirovati).
    private struct OdprtSkener { weak var seja: AnyObject?; let klub: Int }
    private var odprti: [ObjectIdentifier: OdprtSkener] = [:]
    /// Povecuje se ob vsakem preklicu: priprava, ki se je zacela pred njim, ne sme vec zapisati ali nadaljevati.
    private var generacija = 0

    init(pripravi: @escaping Pripravi = SkenPredpriprava.privzetaPriprava,
         pocisti: @escaping Pocisti = SkenPredpriprava.privzetoCiscenje,
         ociStare: @escaping @MainActor () -> Void = SkenPredpriprava.privzetoCiscenjeStarih) {
        self.pripravi = pripravi
        self.pocisti = pocisti
        self.ociStare = ociStare
    }

    // MARK: - Skener odprt

    /// SkenSeja.zacni(): skener tega kluba je odprt, priprava zanj ne teece (skener sam prenasa). Idempotentno po seji.
    /// ZNANA OMEJITEV: skener, odprt MED pripravo istega kluba, povzroci en dodaten scan-list (tekoci zahtevek priprave se ne prekine);
    /// priprave ne prekinjamo s ciscenjem, ker bi pobrisala skenerjeve podatke.
    func skenerOdprt(_ klub: Int, seja: AnyObject) { odprti[ObjectIdentifier(seja)] = OdprtSkener(seja: seja, klub: klub) }

    /// SkenSeja.ustavi(). Brez prejsnjega odprtja ne naredi nicesar.
    func skenerZaprt(seja: AnyObject) { odprti.removeValue(forKey: ObjectIdentifier(seja)) }

    func jeSkenerOdprt(_ klub: Int) -> Bool {
        for (id, o) in odprti where o.seja == nil { odprti.removeValue(forKey: id) }   // seja je izginila brez ustavi()
        return odprti.values.contains { $0.klub == klub }
    }

    // MARK: - Izbira klubov (cista logika)

    /// Klubi, v katerih ima uporabnik vlogo, ki sme skenirati. Star backend brez `clubs`: en klub iz `club_id` / `club_role`
    /// (0 = klub ni znan, streznik vzame prvo clanstvo, kot pri skenerju).
    static func klubiZaSken(_ me: Me) -> [Int] {
        var klubi: [Int] = []
        for c in me.clubs where skenirajoceVloge.contains(c.role) && c.clubId > 0 && !klubi.contains(c.clubId) {
            klubi.append(c.clubId)
        }
        if klubi.isEmpty, let vloga = me.clubRole, skenirajoceVloge.contains(vloga) {
            klubi.append(me.clubId ?? 0)
        }
        return klubi
    }

    /// Od `klubi` obdrzi tiste, ki jih ni treba preskociti: priprava je bila nazadnje pred vec kot `najmanj` sekundami (ali se nikoli).
    nonisolated static func zaPripravo(klubi: [Int], zadnje: [Int: Date], zdaj: Date, najmanj: Double = najmanjMedPripravami) -> [Int] {
        klubi.filter { klub in
            guard let bilo = zadnje[klub] else { return true }
            return zdaj.timeIntervalSince(bilo) >= najmanj
        }
    }

    // MARK: - Sprozilec in preklic

    /// Pripravi sken brez povezave za vse primerne klube, ki jih je treba osveziti. Ne blokira klicatelja; vrne opravilo (testi nanj
    /// pocakajo), nil = nic za narediti. Klubi gredo po vrsti, ne vzporedno (en klub = 2 + N klicev; backend omejuje hkratne scan-list).
    /// `zeton`: dostopni zeton ob vsakem klicu; prazen zeton = odjavljen.
    @discardableResult
    func sprozi(me: Me?, zeton: @escaping @MainActor () -> String) -> Task<Void, Never>? {
        ociStare()   // pred vsem drugim: tudi lastnik/manager, ki skenerja ne odpre, ne hrani starih seznamov
        guard let me, !zeton().isEmpty, tek == nil else { return nil }
        let zdaj = ura()
        let klubi = Self.zaPripravo(klubi: Self.klubiZaSken(me).filter { !jeSkenerOdprt($0) }, zadnje: zadnje, zdaj: zdaj)
        guard !klubi.isEmpty else { return nil }
        let moja = generacija
        let uporabnikId = me.id
        let prejsnja = preklicana
        let naloga = Task { @MainActor [weak self] in
            await prejsnja?.value   // preklicana priprava prej konca in pocisti za seboj
            for klub in klubi {
                guard let self, self.generacija == moja else { break }
                guard !self.jeSkenerOdprt(klub) else { continue }   // skener se je odprl med pripravo drugega kluba
                let porabljeno = await self.pripravi(klub, uporabnikId, zeton)
                if self.generacija != moja {
                    // odjava med pripravo: zapis seznama preklica ne doseze, ne glede na zeton. Ce je medtem odprt skener tega kluba,
                    // je podatke prenesel skener sam (uporabnik je isti, ki ga je odprl): ne brisemo.
                    if !self.jeSkenerOdprt(klub) { self.pocisti(klub) }
                    break
                }
                if porabljeno, !Task.isCancelled { self.zadnje[klub] = self.ura() }
            }
            guard let self else { return }
            if self.generacija == moja { self.tek = nil }
        }
        tek = naloga
        return naloga
    }

    /// Odjava: tekoca priprava se preklice in ne zacne naslednjega kluba, omejitev se pozabi (naslednja prijava pripravi znova).
    /// Stara priprava NE zadrzuje nove (drug uporabnik): nova pocaka, da stara konca in za seboj pocisti. Klicati PRED brisanjem diska.
    func preklici() {
        generacija += 1
        zadnje.removeAll()
        if let t = tek {
            t.cancel()
            preklicana = t
            tek = nil
        }
    }

    // MARK: - Prava priprava

    /// Ista pot kot skener: SkenSeja za klub, naloziDogodke() prenese dogodke, kljuc in sezname aktivnih dogodkov ter jih shrani.
    /// Vrne true, ce poskus porabi 10-minutno okno: VSAK izid (uspeh, 4xx/5xx, 429/503, rok) razen preklica in izpada omrezja
    /// (`URLError.notConnectedToInternet`, `.networkConnectionLost`, `.cancelled`). Razvrstitev gleda napake dejanskih klicev
    /// (ovoj nad SkenApi), ne `SkenSeja.povezava` (ta pade tudi ob 5xx in 408, backend v tezavah pa ne sme dobiti klicev ob vsakem refreshMe).
    static func pripraviKlub(klubId: Int, uporabnikId: Int?, zeton: @escaping @MainActor () -> String,
                             api: SkenApi = SkenApiZivi(), disk: SkenDisk = SkenDisk()) async -> Bool {
        let zapis = ZapisovalecNapak(api)
        let seja = SkenSeja(klubId: klubId, uporabnikId: uporabnikId, api: zapis, disk: disk)
        seja.zeton = zeton
        await seja.naloziDogodke()
        return !Task.isCancelled && !zapis.bilPrekinjen
    }

    static func privzetaPriprava(_ klubId: Int, _ uporabnikId: Int?, _ zeton: @escaping @MainActor () -> String) async -> Bool {
        await pripraviKlub(klubId: klubId, uporabnikId: uporabnikId, zeton: zeton)
    }

    static func privzetoCiscenje(_ klubId: Int) {
        SkenDisk().pocistiKlub(klubId)
        SkenOdjava.pocistiPredpomnilnik()
    }

    /// Napaka, zaradi katere poskus ne porabi okna: preklic ali izpad omrezja (ne odgovor strezniga, ne rok).
    nonisolated static func jePrekinitev(_ napaka: Error) -> Bool {
        if napaka is CancellationError { return true }
        guard let u = napaka as? URLError else { return false }
        return u.code == .cancelled || u.code == .notConnectedToInternet || u.code == .networkConnectionLost
    }

    // MARK: - Zasebnost: seznami starejsi od 3 dni

    /// Politika zasebnosti: seznami z imeni imetnikov ne ostanejo na napravi dlje kot 3 dni od zadnjega prenosa. VRATA IMAJO PREDNOST
    /// (dvojni vstop): brez seznama in lokalnih skenov bi ista vstopnica brez povezave spet postala zelena.
    ///  - Seznam, meta in lokalni skeni dogodka se brisejo SAMO, ce je dogodek po zadnjem znanem seznamu dogodkov kluba ZAPRT
    ///    (`SkenOkno.odprtoDo` < zdaj) IN je zadnji prenos starejsi od 3 dni.
    ///  - Dogodka ni v seznamu (ali seznama dogodkov ni): brisemo samo, ce je prenos starejsi od 3 dni IN je datoteka dogodkov (brez nje
    ///    sama datoteka seznama/skenov) starejsa od 3 dni + 18 h. 18 h = najdaljsa doba, ki jo skener dogodka sploh lahko pokriva, ce za
    ///    dogodek nimamo podatkov (12 h pred zacetkom + 6 h po koncu, SkenOkno); starejsi seznam dogodkov bi lahko izpustil dogodek, ki se tece.
    ///  - Lokalni skeni se brisejo PO ZAPISIH (kot splet, shramba.js `pocistiStareSkene`): samo tisti, starejsi od 3 dni, ki nimajo
    ///    neposlanega vnosa v vrsti. Vrsta neposlanih in konflikti se ne dotakneta.
    static let najvecjaStarostSekunde: Double = 3 * 86400
    static let najdaljseOknoSkenaSekunde: Double = 18 * 3600

    static func privzetoCiscenjeStarih() {
        let disk = SkenDisk()
        pocistiStare(disk: disk, neposlani: SkenVrsta.deljena(disk).vnosi)
    }

    private struct KljucDogodka: Hashable { let klub: Int; let dogodek: Int }

    static func pocistiStare(disk: SkenDisk, neposlani: [SkenVnos], zdaj: Date = Date()) {
        let meja = zdaj.addingTimeInterval(-najvecjaStarostSekunde)
        let mejaBrezDogodka = zdaj.addingTimeInterval(-(najvecjaStarostSekunde + najdaljseOknoSkenaSekunde))
        let vsa = disk.imena().filter { $0.hasSuffix(".json") }
        var kljuci = Set<KljucDogodka>()
        for ime in vsa {
            for predpona in ["seznam-", "meta-", "lokalni-"] where ime.hasPrefix(predpona) {
                let deli = ime.dropFirst(predpona.count).dropLast(5).split(separator: "-")
                if deli.count == 2, let k = Int(deli[0]), let e = Int(deli[1]) { kljuci.insert(KljucDogodka(klub: k, dogodek: e)) }
            }
        }
        var dogodkiKlubov: [Int: [SkenDogodek]?] = [:]
        func dogodki(_ klub: Int) -> [SkenDogodek]? {
            if let v = dogodkiKlubov[klub] { return v }
            let v = disk.preberi([SkenDogodek].self, SkenDisk.imeDogodkov(klub: klub))
            dogodkiKlubov[klub] = .some(v)
            return v
        }
        /// Sme dogodek v brisanje glede na dogodke? `zasilni`: cas datoteke, ki velja, ce datoteke dogodkov ni.
        func smeBrisati(_ k: KljucDogodka, zasilni: Date?) -> Bool {
            if let d = dogodki(k.klub)?.first(where: { $0.id == k.dogodek }), let konec = SkenOkno.odprtoDo(d) { return konec < zdaj }
            let referenca = disk.spremenjeno(SkenDisk.imeDogodkov(klub: k.klub)) ?? zasilni ?? .distantPast
            return referenca < mejaBrezDogodka
        }
        for k in kljuci {
            let imeSeznama = SkenDisk.imeSeznama(klub: k.klub, dogodek: k.dogodek)
            let imeMeta = SkenDisk.imeMeta(klub: k.klub, dogodek: k.dogodek)
            let imeLokalnih = SkenDisk.imeLokalnih(klub: k.klub, dogodek: k.dogodek)
            if let mtimeSeznama = disk.spremenjeno(imeSeznama) {
                let prenos = disk.preberi(SkenSeznamMeta.self, imeMeta)?.prenesenoOb ?? mtimeSeznama
                if prenos < meja, smeBrisati(k, zasilni: mtimeSeznama) { disk.izbrisi(imeSeznama); disk.izbrisi(imeMeta) }
            } else if let meta = disk.preberi(SkenSeznamMeta.self, imeMeta) {
                // meta brez seznama: ostanek, brez imen; pobrisemo po istem pravilu
                if meta.prenesenoOb < meja, smeBrisati(k, zasilni: disk.spremenjeno(imeMeta)) { disk.izbrisi(imeMeta) }
            }
            if let mtimeLokalnih = disk.spremenjeno(imeLokalnih), smeBrisati(k, zasilni: mtimeLokalnih),
               var lokalni = disk.preberi(SkenLokalniSkeni.self, imeLokalnih) {
                let cakajoci = Set(neposlani.filter { $0.klubId == k.klub && $0.eventId == k.dogodek }.compactMap { $0.serial?.lowercased() })
                let prej = lokalni.casi.count
                lokalni.casi = lokalni.casi.filter { $0.value >= meja || cakajoci.contains($0.key.lowercased()) }
                if lokalni.casi.isEmpty { disk.izbrisi(imeLokalnih) }
                else if lokalni.casi.count != prej { disk.zapisi(lokalni, imeLokalnih) }
            }
        }
    }
}

/// Ovoj nad SkenApi: beleži, ali je kateri klic padel zaradi preklica ali izpada omrezja (poskus tedaj ne porabi okna).
final class ZapisovalecNapak: SkenApi, @unchecked Sendable {
    private let api: SkenApi
    private let zapah = NSLock()
    private var prekinjen = false

    init(_ api: SkenApi) { self.api = api }

    var bilPrekinjen: Bool {
        zapah.lock()
        defer { zapah.unlock() }
        return prekinjen
    }

    private func zabelezi(_ napaka: Error) {
        guard SkenPredpriprava.jePrekinitev(napaka) else { return }
        zapah.lock()
        prekinjen = true
        zapah.unlock()
    }

    private func preveri<T>(_ delo: () async throws -> T) async throws -> T {
        do { return try await delo() } catch { zabelezi(error); throw error }
    }

    func dogodki(token: String, klubId: Int?) async throws -> [SkenDogodek] { try await preveri { try await api.dogodki(token: token, klubId: klubId) } }
    func kljuc(token: String, klubId: Int?) async throws -> ScanKey { try await preveri { try await api.kljuc(token: token, klubId: klubId) } }
    func seznam(token: String, klubId: Int?, dogodekId: Int, sveze: Bool) async throws -> Data {
        try await preveri { try await api.seznam(token: token, klubId: klubId, dogodekId: dogodekId, sveze: sveze) }
    }
    func paket(token: String, klubId: Int?, vnosi: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult] {
        try await preveri { try await api.paket(token: token, klubId: klubId, vnosi: vnosi, deviceId: deviceId) }
    }
    func spletniSken(token: String, klubId: Int?, qr: String, rok: Double) async throws -> ScanResult {
        try await preveri { try await api.spletniSken(token: token, klubId: klubId, qr: qr, rok: rok) }
    }
}
