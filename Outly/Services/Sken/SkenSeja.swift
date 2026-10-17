import Foundation
import Combine
import CryptoKit

// Sken brez povezave (backend issue #86, 1. 10. 2026): orkestrator za enega kluba.
//
//  - Vratar NE izbira dogodka (8. 10. 2026): seja vodi MNOZICO AKTIVNIH dogodkov kluba (SkenOkno: -12 h ... +6 h po koncu), ki jo
//    vsako sekundo preracuna iz seznama dogodkov in ure telefona. Dogodek pove koda QR (event_id), odlocitev pa uporabi seznam
//    in lokalne skene TISTEGA dogodka; koda za dogodek izven mnozice je rdeca (»NOT TODAY'S EVENT«).
//  - Prenese javni kljuc (en na backend, kljuc.json) in seznam vstopnic VSAKEGA aktivnega dogodka, shrani na disk in
//    osvezuje seznam na ~2 min. Ce sta ze na disku, je skener pripravljen takoj, tudi brez povezave.
//  - Sken kode v2 se odloci LOKALNO (SkenOdlocitev). BREZ povezave je lokalna sodba dokoncna: zeleno takoj, zapis v trajno vrsto.
//    Z POVEZAVO je zelena sodba samo predlog (K2): vnos gre v vrsto in takoj prek scan-batch na streznik s kratkim rokom
//    (~2 s); odgovor streznika odloci (ok -> zeleno, already_used/transferred/... -> rdece), ob roku ali napaki velja lokalna sodba.
//  - Vrsta se poslje prek scan-batch takoj po skenu in vsako sekundo, ce kaj caka (eksponentno odlaganje z raztrosom ob napaki
//    IN ob delnem paketu: element z `error` pomeni zasedeno bazo, outly-app#108). Odmik velja samo za sinhronizacijo, ne za vrata.
//    Streznik je razsodnik: ce je isto vstopnico pred nami spustil drug telefon brez povezave, pride `already_used` in to postane konflikt.
//  - Kode v1: s povezavo obstojec POST /business/tickets/scan (kratek rok), brez nje rumeno; vratar sme v1 spustiti sam (potrditev).

/// Odjemalec za sken. Zivi je v APIClient+Sken.swift; testi podtaknejo svojega. `klubId` je izrecen (glava X-Outly-Club), nil = ni znan.
protocol SkenApi: Sendable {
    func dogodki(token: String, klubId: Int?) async throws -> [SkenDogodek]
    func kljuc(token: String, klubId: Int?) async throws -> ScanKey
    /// Surov odgovor scan-list (SkenSeja ga zgosti in dekodira izven glavne niti).
    /// `sveze`: zahtevek mimo predpomnilnika (ob 304 je `generated_at` star), da se ura telefona lahko presodi.
    func seznam(token: String, klubId: Int?, dogodekId: Int, sveze: Bool) async throws -> Data
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
    /// Izvede `delo` z rokom. nil = rok je potekel; .failure = delo je padlo pred rokom.
    ///
    /// NI strukturirana tekma (withTaskGroup bi pocakal na vse otroke): `send()` ob 401 caka refreshAccessToken() v nestrukturiranem
    /// Tasku, ki preklica ne dobi (Supabase rok 30 s), zato bi vrata stala do 30 s. Tu odlocitev razresi PRVI, ki konca (delo ali
    /// casovnik); pocasno delo tece v ozadju naprej, rezultat se ne uporabi (vnos v vrsti ostane, posiljanje je idempotentno).
    static func zRokom<T: Sendable>(_ sekunde: Double, _ delo: @escaping @Sendable () async throws -> T) async -> Result<T, Error>? {
        await withCheckedContinuation { (k: CheckedContinuation<Result<T, Error>?, Never>) in
            // RokVrata NI genericen razred: genericen razred z deinit je v Release (-O, Xcode 26.6 / Swift 6.3.3)
            // sesul prevajalnik v EarlyPerfInliner (gradnja master 2. 10. 2026). Rezultat zato potuje kot Any.
            let vrata = RokVrata { izid in k.resume(returning: izid as? Result<T, Error>) }
            let opravilo = Task {
                let r: Result<T, Error>
                do { r = .success(try await delo()) } catch { r = .failure(error) }
                vrata.razresi(r, rok: false)
            }
            let casovnik = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(sekunde, 0) * 1_000_000_000))
                vrata.razresi(nil, rok: true)
            }
            vrata.pripni(opravilo: opravilo, casovnik: casovnik)
        }
    }

    static func sha256(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
}

/// Razresi continuation natanko enkrat (prvi klic); drugi klic ne naredi nic.
/// Namenoma negenericen (glej SkenRok.zRokom): izid je Any? (Result<T, Error> ali nil ob roku).
private final class RokVrata: @unchecked Sendable {
    private let zapah = NSLock()
    private var razresitev: ((Any?) -> Void)?
    private var opravilo: Task<Void, Never>?
    private var casovnik: Task<Void, Never>?

    init(_ razresitev: @escaping (Any?) -> Void) { self.razresitev = razresitev }

    /// Opravilo in casovnik se pripneta po zagonu; ce je odlocitev ze padla, ju takoj preklicemo.
    func pripni(opravilo: Task<Void, Never>, casovnik: Task<Void, Never>) {
        zapah.lock()
        self.opravilo = opravilo
        self.casovnik = casovnik
        let koncano = (razresitev == nil)
        zapah.unlock()
        if koncano { opravilo.cancel(); casovnik.cancel() }
    }

    func razresi(_ izid: Any?, rok: Bool) {
        zapah.lock()
        let f = razresitev
        razresitev = nil
        let o = opravilo, c = casovnik
        zapah.unlock()
        guard let f else { return }
        f(rok ? nil : izid)
        if rok { o?.cancel() } else { c?.cancel() }
    }
}

@MainActor
final class SkenSeja: ObservableObject {

    enum Priprava: Equatable {
        /// Dogodki se nalagajo ali se ne ve, ali je kaj aktivnega, ali pa kljuc se prihaja.
        case nalaga
        /// Nobenega aktivnega dogodka (zaslon »No event right now«).
        case brezDogodka
        /// Vsaj en dogodek je aktiven in javni kljuc je na napravi: lokalno preverjanje dela (seznam vstopnic je dodatek).
        case pripravljen
        /// Prenos kljuca ni uspel in na disku ga ni (sporocilo za vratarja).
        case manjkaPodatkov(String)
    }

    /// Kar seja ve o enem aktivnem dogodku. Zivi, dokler je dogodek v oknu; seznam in lokalni skeni ostanejo tudi na disku.
    private struct DogodekStanje {
        var indeks: SkenIndeks?
        var seznamHash: String?
        var zadnjiPrenos: Date?
        /// serial (male crke) -> cas lokalnega skena na tej napravi (iz diska ob nastanku zapisa).
        var lokalni: [String: Date]
        var naslednjaOsvezitev = Date.distantPast
        var osvezitevVTeku = false
        /// Zaporedna stevilka vstopa v okno: zaostal rezultat ali `defer` starega vstopa istega dogodka ne sme posegati v nov vstop.
        let generacija: Int
        /// Zadnji PRESEZEN seznam tega dogodka kaze, da ura telefona ni prava.
        var uraNapacna = false
    }

    // MARK: Kar vidi zaslon

    /// Vsi dogodki kluba (z diska, nato s streznika).
    @Published private(set) var dogodki: [SkenDogodek] = []
    @Published private(set) var dogodkiNalaga = false
    /// Seznam dogodkov je bil vsaj enkrat prebran (z diska ali s streznika, tudi ce neuspesno): do takrat ni »No event right now«.
    @Published private(set) var dogodkiNalozeni = false
    @Published private(set) var dogodkiNapaka: String?
    /// Kdaj je bil seznam dogodkov nazadnje prenesen s streznika (ali, ob hladnem zagonu, shranjen na disk).
    @Published private(set) var dogodkiPosodobljeni: Date?
    /// Ura telefona se za vec kot 5 min razlikuje od ure streznika (po `generated_at` svezega seznama). Okna ne popravljamo sami.
    @Published private(set) var uraNapacna = false
    /// Dogodki v casovnem oknu, po zacetku. Prazno = skener je zaprt.
    @Published private(set) var aktivni: [SkenDogodek] = []
    /// Naslednji dogodek, ki se mu okno se ni odprlo (za zaslon brez aktivnega dogodka).
    @Published private(set) var naslednji: SkenDogodek?
    @Published private(set) var priprava: Priprava = .nalaga
    /// Ali je streznik dosegljiv: omrezje je gor IN zadnji klic ni padel zaradi izpada.
    @Published private(set) var povezava = true
    /// Skeni v vrsti, ki jih streznik se ni potrdil.
    @Published private(set) var cakajoce = 0
    /// Prenos seznama NAJSTAREJSEGA med aktivnimi dogodki; nil, ce kateri se ni bil prenesen.
    @Published private(set) var zadnjiPrenos: Date?
    /// Seznam kateregakoli aktivnega dogodka je starejsi od ~10 min (osvezevanje ne uspeva): vratar naj to vidi.
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
    /// Ura telefona. Testi jo podtaknejo (okno, vstop/izstop dogodka, osvezitve brez cakanja na pravi cas).
    var ura: @MainActor () -> Date = { Date() }

    private let api: SkenApi
    private let disk: SkenDisk
    private let vrsta: SkenVrsta
    private let deviceId: String
    private let rokStreznika: Double
    private let rokSpletni: Double
    private let kljucOdmik: Double

    /// Okna objavljenih dogodkov, razclenjena ob vsaki spremembi `dogodki` (tik ne razclenjuje nizov vsako sekundo).
    private var okna: [SkenOkno.Okno] = []
    private var kljuc: ScanKey?
    private var kljucOb: Date?
    private var kljucPoskusOb = Date.distantPast
    private var kljucVTeku = false
    /// Zadnji poskus prenosa kljuca je padel (ali je kljuc neuporaben) in kljuca ni na disku.
    private var kljucPoskusNeuspel = false
    private var kljucIzDiskaPreverjen = false
    /// Aktivni dogodki po id-ju. Ključi so natanko id-ji iz `aktivni`.
    private var stanja: [Int: DogodekStanje] = [:]
    private var zadnjaGeneracija = 0
    /// Branje seznama dogodka z diska (izven glavne niti); sken pocaka nanj, da ne odloca brez znanega seznama.
    private var nalaganjaIzDiska: [Int: (generacija: Int, naloga: Task<Void, Never>)] = [:]
    private var zaporedneNapakeDogodkov = 0
    /// Kdaj je zavrnjena koda nazadnje sprozila ponovno nalaganje dogodkov (najvec 1x na minuto).
    private var zadnjeNalaganjeZaradiKode = Date.distantPast

    private var omrezjeGor = true
    private var zadnjiKlicOK = true
    private var posiljanjeVTeku = false
    private var dogodkiVTeku = false
    private var zaporedneNapake = 0
    private var naslednjePosiljanje = Date.distantPast
    /// Trenutni odmik posiljanja je postavil STREZNIK (paket z `error`, 5xx/429/408): baza je zasedena. Takega odmika vrnitev v
    /// ospredje / omrezja in odhod z zaslona ne preskocita (1000 telefonov bi ga sicer obslo hkrati). Odmik zaradi omrezja (ni odgovora)
    /// pa se ob vrnitvi povezave preskoci: skeni naj gredo takoj.
    private var odmikZaradiStreznika = false
    /// Prvi prenos dogodkov naredi `naloziDogodke()`; od takrat jih osvezuje tik.
    private var naslednjaOsvezitevDogodkov = Date.distantFuture
    private var zanka: Task<Void, Never>?

    static let osvezitevSekunde: ClosedRange<Double> = 105...135   // ~2 min z odmikom, da 1000 telefonov ne vleče naenkrat
    /// Seznam dogodkov se osvezuje redkeje (novi, preklicani, prestavljeni dogodki); odmik tudi tu razprsi telefone.
    static let osvezitevDogodkovSekunde: ClosedRange<Double> = 540...660
    /// Ob napaki GET /business/events (tezka poizvedba): 30 s, 60 s, 120 s ... najvec 300 s, z jitterjem +-25 %.
    static let odmikDogodkovOdNapake: Double = 30
    static let najdaljsiOdmikDogodkov: Double = 300
    /// Ob vrnitvi povezave / aplikacije v ospredje se osvezitev razprsi po toliko sekundah (vrnitev Wi-Fi: vsi telefoni hkrati).
    static let razprsitevSekunde: ClosedRange<Double> = 0...15
    /// Seznam vstopnic dogodka, ki ga ustvari tik ob vstopu v okno (T - 12 h), se prvic prenese v tem razponu.
    static let razprsitevVstopaSekunde: ClosedRange<Double> = 0...30
    /// Najmanj toliko med dvema nalaganjema dogodkov zaradi zavrnjene kode.
    static let najmanjMedNalaganjiZaradiKode: Double = 60
    /// Seznam dogodkov, starejsi od tega, se ob zavrnjeni kodi za ZNAN dogodek osvezi (neznan dogodek: vedno, glej spodaj).
    static let seznamDogodkovStarPoSekundah: Double = 5 * 60
    /// Najdlje, kolikor sken caka na branje seznama dogodka z diska.
    static let rokBranjaIzDiska: Double = 1.0
    /// Razlika ure telefona in `generated_at`, nad katero opozorimo.
    nonisolated static let dovoljenaRazlikaUre: Double = 5 * 60
    /// Odmik posiljanja vrste (outly-app#108): osnova 5 s, 10, 20, 40, nato 50 s; raztros +-20 % (`odmikPosiljanja`), torej najvec 60 s.
    static let odmikPosiljanjaOd: Double = 5
    static let najvecjaOsnovaOdmika: Double = 50
    static let najdaljsiOdmik: Double = 60
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
    /// Izjema: odmik, ki ga je postavil streznik (zasedena baza), ostane; posiljanje gre ob njegovem izteku (najvec ~60 s), skeniranje
    /// na vratih pa od tega ni odvisno (lokalna odlocitev / hitra pot).
    func takojOsvezi() {
        if !odmikZaradiStreznika || ura() >= naslednjePosiljanje {
            zaporedneNapake = 0
            odmikZaradiStreznika = false
            naslednjePosiljanje = .distantPast
        }
        // Posiljanje vrste gre takoj; osvezitve (seznam dogodkov, seznami vstopnic) z jitterjem 0-15 s, da se ob vrnitvi Wi-Fi na lokaciji
        // 1000 telefonov ne zbudi v isti sekundi.
        let zdaj = ura()
        for id in stanja.keys { stanja[id]?.naslednjaOsvezitev = zdaj.addingTimeInterval(Double.random(in: Self.razprsitevSekunde)) }
        if naslednjaOsvezitevDogodkov != .distantFuture {
            naslednjaOsvezitevDogodkov = zdaj.addingTimeInterval(Double.random(in: Self.razprsitevSekunde))
        }
    }

    /// Osvezitev in posiljanje tecesta vsako v svojem Tasku: pocasen prenos seznama ne sme zadrzati posiljanja skenov.
    func tik() {
        let zdaj = ura()
        uskladiAktivne(zdaj: zdaj, razprsi: true)   // dogodek, ki je vstopil v okno ali ga zapustil, se doda / odstrani
        guard !dostopOdvzet else { return }
        if zdaj >= naslednjaOsvezitevDogodkov, !dogodkiVTeku { Task { await osveziDogodke() } }
        if !aktivni.isEmpty, kljuc?.surovi == nil, !kljucVTeku, zdaj.timeIntervalSince(kljucPoskusOb) >= kljucOdmik {
            Task { await osveziKljuc() }   // neuspel poskus se ponovi najprej cez `kljucOdmik`
        }
        for d in aktivni {
            guard let s = stanja[d.id], zdaj >= s.naslednjaOsvezitev, !s.osvezitevVTeku else { continue }
            let id = d.id
            Task { await osveziSeznam(id) }
        }
        if cakajoce > 0, zdaj >= naslednjePosiljanje, !posiljanjeVTeku { Task { await poslji() } }
    }

    /// Seznam je star, ce je bil nazadnje prenesen pred vec kot 10 min. Brez prenosa (nil) ni »star«, ampak »ni prenesen«.
    nonisolated static func jeStar(_ prenos: Date?, zdaj: Date) -> Bool {
        guard let prenos else { return false }
        return zdaj.timeIntervalSince(prenos) > seznamStarPoSekundah
    }

    // MARK: - Dogodki in aktivna mnozica

    /// Najprej shranjeni seznam dogodkov (deluje brez povezave), nato osvezitev; nato pripravi aktivne dogodke
    /// (seznam vstopnic z diska, kljuc, prenos seznamov). Zaslon to poklice ob odprtju skenerja in za »Reload«.
    func naloziDogodke() async {
        if dogodki.isEmpty, let shranjeni = disk.preberi([SkenDogodek].self, SkenDisk.imeDogodkov(klub: klubId)) {
            postaviDogodke(shranjeni)
            dogodkiPosodobljeni = disk.spremenjeno(SkenDisk.imeDogodkov(klub: klubId))
            dogodkiNalozeni = true
            uskladiAktivne()
        }
        dogodkiNalaga = true
        defer { dogodkiNalaga = false }
        await osveziDogodke()
        await pripraviAktivne()
    }

    /// Prenese seznam dogodkov kluba, shrani na disk in preracuna aktivne. Ob napaki ostane stari seznam (ali prazen s sporocilom).
    func osveziDogodke() async {
        guard !dogodkiVTeku, !dostopOdvzet else { return }
        dogodkiVTeku = true
        defer { dogodkiVTeku = false }
        naslednjaOsvezitevDogodkov = ura().addingTimeInterval(Double.random(in: Self.osvezitevDogodkovSekunde))
        do {
            let sveziSeznam = try await api.dogodki(token: zeton(), klubId: klubZaApi)
            zabeleziUspeh()
            zaporedneNapakeDogodkov = 0
            postaviDogodke(sveziSeznam)
            dogodkiPosodobljeni = ura()
            dogodkiNapaka = nil
            dogodkiNalozeni = true
            disk.zapisi(sveziSeznam, SkenDisk.imeDogodkov(klub: klubId))
            disk.pocisti(klub: klubId, obdrzi: Set(sveziSeznam.map { $0.id }))
            uskladiAktivne()
        } catch {
            if await jeOdvzemDostopa(error) { return }
            zabeleziNapako(error)
            dogodkiNapaka = dogodki.isEmpty ? error.userMessage : nil
            dogodkiNalozeni = true
            zaporedneNapakeDogodkov += 1
            naslednjaOsvezitevDogodkov = ura().addingTimeInterval(Self.odmikDogodkovPoNapakah(zaporedneNapakeDogodkov))
            uskladiAktivne()
        }
    }

    /// Eksponentni odmik ponovnega poskusa GET /business/events: 30 s, 60 s, 120 s, 240 s, nato 300 s; jitter +-25 % (`jitter` je za teste).
    static func odmikDogodkovPoNapakah(_ napake: Int, jitter: Double = Double.random(in: 0.75...1.25)) -> Double {
        let osnova = min(odmikDogodkovOdNapake * pow(2.0, Double(max(napake, 1) - 1)), najdaljsiOdmikDogodkov)
        return min(osnova * jitter, najdaljsiOdmikDogodkov)
    }

    /// Preracuna mnozico aktivnih dogodkov iz `dogodki` in ure. Dogodek, ki je vstopil v okno, dobi stanje (lokalni skeni z diska,
    /// seznam vstopnic z diska izven glavne niti; prenos s streznika naredi tik); dogodek, ki je izstopil, se odstrani iz pomnilnika
    /// (datoteke na disku ostanejo). Sinhrono in poceni: kliceta ga tik (vsako sekundo) in sken (da je mnozica sveza).
    /// `razprsi`: samo tik. Stanje, ki ga tik ustvari ob vstopu dogodka v okno (T - 12 h), prvic prenese seznam cez 0-30 s (ne vsi telefoni
    /// v isti sekundi); ob odprtju skenerja in pri odgovoru strezniga ostane prenos takoj. Seznam z diska se uporabi vedno takoj.
    func uskladiAktivne(zdaj zdajPodan: Date? = nil, razprsi: Bool = false) {
        let zdaj = zdajPodan ?? ura()
        let nova = SkenOkno.aktivniIz(okna: okna, zdaj: zdaj)
        if nova != aktivni { aktivni = nova }
        let sledeci = SkenOkno.naslednjiIz(okna: okna, zdaj: zdaj)
        if sledeci != naslednji { naslednji = sledeci }

        let idji = Set(nova.map { $0.id })
        for id in Array(stanja.keys) where !idji.contains(id) {
            stanja.removeValue(forKey: id)
            nalaganjaIzDiska.removeValue(forKey: id)?.naloga.cancel()
        }
        if !nova.isEmpty { ucitajKljucIzDiska() }
        for d in nova where stanja[d.id] == nil {
            let lokalni = disk.preberi(SkenLokalniSkeni.self, SkenDisk.imeLokalnih(klub: klubId, dogodek: d.id))?.casi ?? [:]
            zadnjaGeneracija += 1
            var stanje = DogodekStanje(lokalni: lokalni, generacija: zadnjaGeneracija)
            if razprsi { stanje.naslednjaOsvezitev = zdaj.addingTimeInterval(Double.random(in: Self.razprsitevVstopaSekunde)) }
            stanja[d.id] = stanje
            zazeniNalaganjeIzDiska(d.id, generacija: zadnjaGeneracija)
        }
        osveziPovzetek(zdaj: zdaj)
        posodobiPripravo()
    }

    /// Za teste: kdaj tik naslednjic osvezi seznam dogodkov.
    var osvezitevDogodkovOb: Date { naslednjaOsvezitevDogodkov }

    /// Za teste: kdaj se seznam dogodka naslednjic osvezi po tiku.
    func naslednjaOsvezitevSeznama(dogodek id: Int) -> Date? { stanja[id]?.naslednjaOsvezitev }

    private func postaviDogodke(_ seznam: [SkenDogodek]) {
        dogodki = seznam
        okna = SkenOkno.okna(seznam)
    }

    private func ucitajKljucIzDiska() {
        guard kljuc == nil, !kljucIzDiskaPreverjen else { return }
        kljucIzDiskaPreverjen = true
        if let shranjen = disk.preberi(SkenKljucShramba.self, SkenDisk.imeKljuca) {
            kljuc = shranjen.kljuc
            kljucOb = shranjen.prenesenoOb
        }
    }

    /// Seznam vstopnic dogodka z diska: branje in dekodiranje izven glavne niti. Prenos s streznika, ki je prisel prej, ima prednost.
    private func zazeniNalaganjeIzDiska(_ id: Int, generacija: Int) {
        let klub = klubId
        let disku = disk
        let naloga = Task { [weak self] in
            let shranjen = await Task.detached { () -> (ScanList, SkenSeznamMeta)? in
                guard let podatki = disku.surovo(SkenDisk.imeSeznama(klub: klub, dogodek: id)),
                      let meta = disku.preberi(SkenSeznamMeta.self, SkenDisk.imeMeta(klub: klub, dogodek: id)),
                      let l = try? JSONDecoder().decode(ScanList.self, from: podatki) else { return nil }
                return (l, meta)
            }.value
            guard let self else { return }
            // Samo svoj zapis: dogodek je med branjem lahko izstopil in znova vstopil (nov vstop ima svojo nalogo).
            if self.nalaganjaIzDiska[id]?.generacija == generacija { self.nalaganjaIzDiska.removeValue(forKey: id) }
            guard self.stanja[id]?.generacija == generacija else { return }
            guard let (l, meta) = shranjen, l.eventId == id || l.eventId == 0, self.stanja[id]?.indeks == nil else { return }
            self.stanja[id]?.indeks = SkenIndeks(l)
            self.stanja[id]?.seznamHash = meta.hash
            self.stanja[id]?.zadnjiPrenos = meta.prenesenoOb
            self.osveziPovzetek()
        }
        nalaganjaIzDiska[id] = (generacija, naloga)
    }

    /// Pocaka, da je seznam dogodka prebran z diska (le branje datoteke, brez omrezja).
    /// Z gornjo mejo (1 s): pocasen disk ne sme zadrzati odlocitve na vratih; ob roku se odloca z znanim (lahko se praznim) seznamom.
    private func pocakajNalaganjeIzDiska(_ id: Int) async {
        guard let n = nalaganjaIzDiska[id] else { return }
        let naloga = n.naloga
        _ = await SkenRok.zRokom(Self.rokBranjaIzDiska) { await naloga.value }
    }

    /// Prebere seznam vsakega aktivnega dogodka z diska, poskrbi za kljuc in prenese sezname.
    func pripraviAktivne() async {
        uskladiAktivne()
        let idji = aktivni.map { $0.id }
        for id in idji { await pocakajNalaganjeIzDiska(id) }
        posodobiPripravo()
        if !idji.isEmpty, kljuc?.surovi == nil { await osveziKljuc() }
        for id in idji { await osveziSeznam(id) }
        posodobiPripravo()
    }

    /// `zadnjiPrenos` (najstarejsi med aktivnimi) in `seznamStar` (kateri koli star). Objavi samo spremembo.
    private func osveziPovzetek(zdaj zdajPodan: Date? = nil) {
        let zdaj = zdajPodan ?? ura()
        let casi = aktivni.map { stanja[$0.id]?.zadnjiPrenos }
        let najstarejsi: Date? = casi.contains(where: { $0 == nil }) ? nil : casi.compactMap { $0 }.min()
        if najstarejsi != zadnjiPrenos { zadnjiPrenos = najstarejsi }
        let star = casi.contains { Self.jeStar($0, zdaj: zdaj) }
        if star != seznamStar { seznamStar = star }
        let uraSlaba = aktivni.contains { stanja[$0.id]?.uraNapacna == true }
        if uraSlaba != uraNapacna { uraNapacna = uraSlaba }
    }

    /// Ura telefona se od `generated_at` svezega seznama razlikuje za vec kot 5 min (v obe smeri). Neberljiv `generated_at` ni dokaz.
    static func jeUraNapacna(generatedAt: String, zdaj: Date) -> Bool {
        guard let streznik = SkenCas.razcleni(generatedAt) else { return false }
        return abs(zdaj.timeIntervalSince(streznik)) > dovoljenaRazlikaUre
    }

    private var jePripravljen: Bool { kljuc?.surovi != nil }

    private func posodobiPripravo() {
        let nova: Priprava
        if aktivni.isEmpty {
            nova = dogodkiNalozeni ? .brezDogodka : .nalaga
        } else if jePripravljen {
            nova = .pripravljen
        } else if kljucPoskusNeuspel {
            nova = .manjkaPodatkov(String(localized: "The scanner key could not be downloaded."))
        } else {
            nova = .nalaga
        }
        if nova != priprava { priprava = nova }
    }

    /// Prenese javni kljuc (en na backend) in ga shrani; neuspel poskus se ponovi najprej cez 20 s. Vrne true, ce imamo uporaben kljuc.
    @discardableResult
    func osveziKljuc() async -> Bool {
        ucitajKljucIzDiska()
        guard !kljucVTeku, !dostopOdvzet else { return jePripravljen }
        guard ura().timeIntervalSince(kljucPoskusOb) >= kljucOdmik else { return jePripravljen }
        kljucVTeku = true
        kljucPoskusOb = ura()
        defer { kljucVTeku = false }
        do {
            let nov = try await api.kljuc(token: zeton(), klubId: klubZaApi)
            zabeleziUspeh()
            guard nov.surovi != nil else {
                kljucPoskusNeuspel = true
                posodobiPripravo()
                return jePripravljen
            }
            kljucPoskusOb = .distantPast   // omejitev velja samo za neuspele poskuse: zamenjava kljuca ob prenosu seznama ne sme cakati
            kljuc = nov
            kljucOb = ura()
            kljucPoskusNeuspel = false
            disk.zapisi(SkenKljucShramba(kljuc: nov, prenesenoOb: kljucOb ?? ura()), SkenDisk.imeKljuca)
            posodobiPripravo()
            return true
        } catch {
            if await jeOdvzemDostopa(error) { return false }
            zabeleziNapako(error)
            kljucPoskusNeuspel = true
            posodobiPripravo()
            return jePripravljen
        }
    }

    /// Prenese seznam vstopnic dogodka, shrani na disk. Nespremenjen odgovor (enak SHA-256) se ne dekodira in ne zapisuje znova;
    /// dekodiranje je izven glavne niti. Ob napaki (omrezje, pokvarjen odgovor) ostane stari seznam. Dogodek, ki je medtem izstopil
    /// iz okna, rezultata ne dobi (stanje je odstranjeno).
    func osveziSeznam(_ id: Int) async {
        guard let st = stanja[id], !st.osvezitevVTeku, !dostopOdvzet else { return }
        let gen = st.generacija
        // Vse po cakanju velja samo za TA vstop dogodka v okno: dogodek je lahko medtem izstopil in znova vstopil (nov vstop ima svoje
        // stanje, svoj prenos in svojo oznako osvezitve).
        func jeSvoj() -> Bool { stanja[id]?.generacija == gen }
        stanja[id]?.osvezitevVTeku = true
        defer { if jeSvoj() { stanja[id]?.osvezitevVTeku = false } }
        // Dokler opozorilo za uro gori, gre prenos mimo predpomnilnika: ob 304 bi prišel star `generated_at` in opozorilo se ne bi
        // moglo ugasniti, ko uporabnik uro popravi. Sicer (ETag/304) ostane promet majhen.
        let sveze = st.uraNapacna
        stanja[id]?.naslednjaOsvezitev = ura().addingTimeInterval(Double.random(in: Self.osvezitevSekunde))
        do {
            let podatki = try await api.seznam(token: zeton(), klubId: klubZaApi, dogodekId: id, sveze: sveze)
            guard jeSvoj() else { return }
            zabeleziUspeh()
            let zdaj = ura()
            let hash = await Task.detached { SkenRok.sha256(podatki) }.value
            guard jeSvoj(), let trenutno = stanja[id] else { return }
            if hash == trenutno.seznamHash, trenutno.indeks != nil {
                // Nespremenjeno (streznik/URLSession ob 304 vrne shranjen odgovor): samo osvezi cas prenosa (tudi na disku, da po
                // ponovnem zagonu ni videti starejsi). `generated_at` takega odgovora je star, zato ure tu ne presojamo; razen ce je
                // bil prenos zahtevan mimo predpomnilnika (`sveze`): odgovor je 200 s svezim `generated_at`.
                if sveze {
                    let generiran = await Task.detached { () -> String? in
                        (try? JSONDecoder().decode(SkenGeneriran.self, from: podatki))?.generatedAt
                    }.value
                    guard jeSvoj() else { return }
                    if let generiran { stanja[id]?.uraNapacna = Self.jeUraNapacna(generatedAt: generiran, zdaj: zdaj) }
                }
                stanja[id]?.zadnjiPrenos = zdaj
                osveziPovzetek()
                disk.zapisi(SkenSeznamMeta(hash: hash, prenesenoOb: zdaj), SkenDisk.imeMeta(klub: klubId, dogodek: id))
                return
            }
            let (seznam, idx) = try await Task.detached { () -> (ScanList, SkenIndeks) in
                let l = try JSONDecoder().decode(ScanList.self, from: podatki)
                return (l, SkenIndeks(l))
            }.value
            guard jeSvoj() else { return }
            stanja[id]?.indeks = idx
            stanja[id]?.seznamHash = hash
            stanja[id]?.zadnjiPrenos = zdaj
            // Spremenjena vsebina je prisla s streznika (200), torej je `generated_at` svez: razlika od ure telefona je napaka ure.
            stanja[id]?.uraNapacna = Self.jeUraNapacna(generatedAt: seznam.generatedAt, zdaj: zdaj)
            osveziPovzetek()
            disk.zapisiSurovo(podatki, SkenDisk.imeSeznama(klub: klubId, dogodek: id))
            disk.zapisi(SkenSeznamMeta(hash: hash, prenesenoOb: zdaj), SkenDisk.imeMeta(klub: klubId, dogodek: id))
            // Kljuc primerjamo po `kid` ob vsakem prenosu (STATE.md: zamenjava QR_SECRET spremeni javni kljuc). Stari kljuc ostane,
            // dokler novega ne dobimo: kode z novim `kid` so takrat rumene, ne rdece (SkenOdlocitev).
            if !seznam.kid.isEmpty, kljuc?.kid != seznam.kid { await osveziKljuc() }
            posodobiPripravo()
        } catch {
            if await jeOdvzemDostopa(error) { return }
            zabeleziNapako(error)
            // Brez povezave ali s pokvarjenim odgovorom poskusi kmalu znova (vratar naj vidi, da se je povezava vrnila), ne cez 2 min.
            if jeSvoj() { stanja[id]?.naslednjaOsvezitev = ura().addingTimeInterval(Self.odmikOsvezitveOdNapake) }
            posodobiPripravo()
        }
    }

    // MARK: - Sken

    /// Odlocitev za eno kodo. Dogodek pove koda; mora biti med aktivnimi (sicer rdece »NOT TODAY'S EVENT«). Brez povezave je zeleno
    /// takoj; z njo odloci streznik (hitra pot, rok ~2 s). Edino cakanje pred odlocitvijo je branje seznama dogodka z diska.
    func skeniraj(_ surova: String) async -> SkenPrikaz {
        let qr = surova.trimmingCharacters(in: .whitespacesAndNewlines)
        // Streznik je ze povedal, da uporabnik ni vec v ekipi kluba: z lokalnim kljucem bi se kode se vedno dale zeleno spustiti.
        if dostopOdvzet { zavrnjeni += 1; return SkenPrikaz.brezDostopa() }
        uskladiAktivne()   // dogodek je lahko vstopil v okno po zadnjem tiku
        switch SkenKoda.razcleni(qr) {
        case let .v1(telo), let .v2(telo, _, _): await pocakajNalaganjeIzDiska(telo.eventId)
        case .neznano: break
        }
        let sodba = SkenOdlocitev.odloci(qr: qr, aktivni: Set(aktivni.map { $0.id }), kljuc: kljuc,
                                         indeksi: stanja.compactMapValues { $0.indeks }, lokalni: stanja.mapValues { $0.lokalni })
        switch sodba.barva {
        case .rdece:
            zavrnjeni += 1
            if sodba.razlog == .nijeZaDanes { osveziDogodkeZaradiKode(dogodekId: sodba.dogodekId) }
            return SkenPrikaz.iz(sodba, qr: qr)
        case .zeleno, .rumeno:
            guard let id = sodba.dogodekId, let d = aktivni.first(where: { $0.id == id }) else {
                zavrnjeni += 1   // ne more se zgoditi: zeleno/rumeno nastane samo za aktiven dogodek
                return SkenPrikaz.iz(SkenSodba(razlog: .nijeZaDanes, serial: sodba.serial), qr: qr)
            }
            if sodba.barva == .zeleno { return await sprejmiZeleno(qr: qr, sodba: sodba, dogodek: d) }
            return await preveriRumeno(qr: qr, sodba: sodba, dogodek: d)
        }
    }

    /// Zavrnjena koda za dogodek, ki ni aktiven, je lahko posledica zastarelega seznama dogodkov (klub je dogodek objavil ali prestavil
    /// med vecerom). Seznam dogodkov zato znova nalozimo, ampak samo ce ima to smisel: dogodek je med shranjenimi NEZNAN, ali je znan,
    /// a je seznam starejsi od ~5 min; najvec 1x na minuto; z backoffom, ce je zadnje nalaganje padlo (padel streznik ne dobi klica
    /// na minuto). Tece v ozadju (Task): rdece se pokaze takoj, naslednji sken je pravilen, ko seznam pride.
    private func osveziDogodkeZaradiKode(dogodekId: Int?) {
        let zdaj = ura()
        guard povezava, !dostopOdvzet, !dogodkiVTeku,
              zdaj.timeIntervalSince(zadnjeNalaganjeZaradiKode) >= Self.najmanjMedNalaganjiZaradiKode,
              zaporedneNapakeDogodkov == 0 || zdaj >= naslednjaOsvezitevDogodkov else { return }
        let znan = dogodekId.map { id in dogodki.contains { $0.id == id } } ?? false
        if znan {
            guard let posodobljeni = dogodkiPosodobljeni,
                  zdaj.timeIntervalSince(posodobljeni) > Self.seznamDogodkovStarPoSekundah else { return }
        }
        zadnjeNalaganjeZaradiKode = zdaj
        Task { await osveziDogodke() }
    }

    /// Spremeni lokalne skene dogodka (v pomnilniku, ce je dogodek se aktiven, sicer z diska) in jih zapise na disk. Dogodek je lahko
    /// med cakanjem na streznik izstopil iz okna: zapis se vseeno ne sme izgubiti.
    private func spremeniLokalne(_ dogodekId: Int, _ f: (inout [String: Date]) -> Void) {
        var l = stanja[dogodekId]?.lokalni
            ?? disk.preberi(SkenLokalniSkeni.self, SkenDisk.imeLokalnih(klub: klubId, dogodek: dogodekId))?.casi ?? [:]
        f(&l)
        stanja[dogodekId]?.lokalni = l
        if !disk.zapisi(SkenLokalniSkeni(casi: l), SkenDisk.imeLokalnih(klub: klubId, dogodek: dogodekId)) { zapisOK = false }
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
        spremeniLokalne(d.id) { $0[kljucLokalnih] = vnos.scannedAt }
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
                spremeniLokalne(d.id) { $0.removeValue(forKey: kljucLokalnih) }
                zavrnjeni += 1
                return SkenPrikaz.iz(streznik: r.result, usedAt: r.usedAt, sodba: sodba)
            }
        case .failure(let napaka)?:
            if await jeOdvzemDostopa(napaka, poskusiPoslati: false) {
                // Gost ni bil spuscen: vnosa ne obdrzimo kot »sprejetega«; brezDostopa pove vratarju, zakaj je rdece.
                vrsta.odstrani(vnos.clientScanId)
                osveziStevce()
                zavrnjeni += 1
                return SkenPrikaz.brezDostopa()
            }
            zabeleziNapako(napaka)
        case nil:
            zabeleziRok()   // pocasen streznik = kot brez povezave: naslednji skeni ne cakajo vsak po 2 s (vrne ga uspesen klic)
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
                let kljucLokalnih = sodba.serial ?? qr
                let ob = ura()
                spremeniLokalne(d.id) { $0[kljucLokalnih] = ob }   // brez povezave ista koda ne sme spet na rumeno -> rdece "ze skenirano"
            } else {
                zavrnjeni += 1
            }
            return SkenPrikaz.iz(r)
        case .failure(let napaka)?:
            if await jeOdvzemDostopa(napaka, poskusiPoslati: false) {
                zavrnjeni += 1
                return SkenPrikaz.brezDostopa()
            }
            zabeleziNapako(napaka)
        case nil:
            zabeleziRok()   // rok je potekel (npr. Wi-Fi brez interneta): rumeno, vratar odloci
        }
        return SkenPrikaz.iz(sodba, qr: qr)
    }

    /// Vratar je kodo v1 odlocil spustiti (po potrditvi). Gre v vrsto: streznik jo preveri naknadno. Samo za kodo v1 z berljivim
    /// telesom za AKTIVEN dogodek (dogodek pove koda; izven okna je »NOT TODAY'S EVENT«); vse drugo se zavrne.
    func spustiRocno(qr surova: String) -> SkenPrikaz {
        let qr = surova.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case let .v1(telo) = SkenKoda.razcleni(qr) else {
            return SkenPrikaz.iz(SkenSodba(razlog: .neveljavna), qr: qr)
        }
        uskladiAktivne()
        guard aktivni.contains(where: { $0.id == telo.eventId }) else {
            return SkenPrikaz.iz(SkenSodba(razlog: .nijeZaDanes, serial: telo.serial, dogodekId: telo.eventId), qr: qr)
        }
        // event_id v kodi v1 ni podpisan: ista vstopnica je lahko ze skenirana pod DRUGIM aktivnim dogodkom (negativni dokaz).
        if let cas = SkenOdlocitev.lokalniSkenKjerkoli(serial: telo.serial, aktivni: Set(aktivni.map { $0.id }),
                                                          lokalni: stanja.mapValues { $0.lokalni }, najprej: telo.eventId) {
            return SkenPrikaz.iz(SkenSodba(razlog: .zeUporabljenaLokalno, serial: telo.serial, kdaj: cas), qr: qr)
        }
        let vnos = SkenVnos(qr: qr, serial: telo.serial, eventId: telo.eventId, klubId: klubId, uporabnikId: uporabnikId)
        vrsta.dodaj(vnos)
        spremeniLokalne(telo.eventId) { $0[telo.serial] = vnos.scannedAt }
        osveziStevce()
        sprejeti += 1
        if zaporedneNapake == 0 { Task { await poslji() } }
        return SkenPrikaz.spusceniRocno()
    }

    private func opisImetnika(_ v: ScanListTicket?) -> String? {
        guard let v else { return nil }
        var deli: [String] = []
        if let i = v.holderUsername, !i.isEmpty { deli.append(i) }
        if v.isVip { deli.append(VipOznaka.vrstica(tableLabel: v.tableLabel, packageName: v.packageName)) }
        return deli.isEmpty ? nil : deli.joined(separator: " · ")
    }

    // MARK: - Posiljanje vrste

    /// Poslje vse, kar caka (po paketih do 500). Ob napaki ALI delnem paketu (kateri koli element brez dokoncnega rezultata, npr.
    /// `error` po SKEN_BATCH_ROK_MS na backendu, outly-app#108) odlozi z eksponentnim odmikom z raztrosom (~5 s ... 60 s); preostanek
    /// NE gre takoj znova. Uspesen paket brez `error` odmik ponastavi. Klic sam odmika ne preverja (tik in `posljiObOdhodu` ga).
    func poslji() async {
        guard !posiljanjeVTeku, !dostopOdvzet else { return }
        posiljanjeVTeku = true
        defer { posiljanjeVTeku = false }
        while true {
            let paket = vrsta.paket(klub: klubId, uporabnik: uporabnikId)
            if paket.isEmpty { zaporedneNapake = 0; odmikZaradiStreznika = false; osveziStevce(); return }
            do {
                let rezultati = try await api.paket(token: zeton(), klubId: klubZaApi, vnosi: paket, deviceId: deviceId)
                zabeleziUspeh()
                let odstranjeni = vrsta.uporabi(rezultati, poslani: paket)
                osveziStevce()
                // Delni paket (backend ob zasedeni bazi po SKEN_BATCH_ROK_MS vrne `error` za preostanek, ali rezultat manjka): preostanek
                // takoj znova bi vsak telefon tolkel po zaklenjeni bazi. Odmik, nato tik poslje znova.
                // Tudi brez `error` lahko vnos ostane v vrsti (zapis konflikta na disk ni uspel, SkenVrsta.uporabi `obdrzi`): brez odmika bi
                // `while` isti vnos posiljal v nedogled.
                let delni = Self.jeDelniPaket(rezultati, poslani: paket)
                if delni || odstranjeni < paket.count {
                    if !delni && odstranjeni > 0 {
                        // Napredek brez `error` (vnos je ostal le zaradi neuspelega zapisa na disk): osnovni odmik brez stopnjevanja.
                        odloziOsnovno(zaradiStreznika: false)
                    } else {
                        // `error` VEDNO stopnjuje, tudi z napredkom: backend vrne `error` po roku sele po ~5 s obdelave, zato ima delni
                        // paket ob zasedeni bazi skoraj vedno napredek; osnovni ~5 s bi pomenil ~200 zahtev/s iz 1000 telefonov.
                        // Sprejeta posledica: en trajno pokvarjen vnos upocasni sinhronizacijo do ~60 s.
                        odlozi(zaradiStreznika: delni)
                    }
                    return
                }
                zaporedneNapake = 0
                odmikZaradiStreznika = false
            } catch {
                if await jeOdvzemDostopa(error, poskusiPoslati: false) { return }
                zabeleziNapako(error)
                odlozi(zaradiStreznika: Self.jePreobremenitev(error))
                return
            }
        }
    }

    /// Pocaka, da tece posiljanje konca (za teste; zaslon tega ne rabi).
    func pocakajPosiljanje() async {
        while posiljanjeVTeku { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    /// Zadnji poskus ob odhodu z zaslona skenerja. Odmik, ki ga je postavil streznik (zasedena baza), spostuje: vnosi so na disku in
    /// gredo ob naslednjem odprtju skenerja (ali ob odjavi); ob odmiku zaradi omrezja poskusi takoj (povezava je morda spet tu,
    /// neuspel klic bazi ne skodi).
    func posljiObOdhodu() async {
        if odmikZaradiStreznika && ura() < naslednjePosiljanje { return }
        await poslji()
    }

    /// Za teste: kdaj tik najprej spet poslje vrsto.
    var posiljanjeOdlozenoDo: Date { naslednjePosiljanje }

    /// Kateri koli poslan vnos nima dokoncnega rezultata (`error` ali manjka v odgovoru).
    static func jeDelniPaket(_ rezultati: [ScanBatchResult], poslani: [SkenVnos]) -> Bool {
        let dokoncni = Set(rezultati.filter { $0.jeDokoncen }.map { $0.clientScanId })
        return poslani.contains { !dokoncni.contains($0.clientScanId) }
    }

    /// Streznik je preobremenjen: odgovoril je s 5xx, 429 ali 408, ali pa ni odgovoril v roku (URLError.timedOut: pocasen streznik,
    /// ne izpad omrezja; tak odmik vrnitev v ospredje ne preskoci). Ostale URLError (ni povezave) niso preobremenitev.
    static func jePreobremenitev(_ e: Error) -> Bool {
        if let u = e as? URLError { return u.code == .timedOut }
        guard let a = e as? APIError, case let .requestFailed(koda, _) = a else { return false }
        return koda == 408 || koda == 429 || koda >= 500
    }

    /// Odmik posiljanja po `napake` zaporednih neuspehih: 5 s, 10, 20, 40, nato 50 s, krat raztros (0,8-1,2): 1000 telefonov, ki so
    /// dobili `error` v isti sekundi, ne pride nazaj v isti sekundi. Najvec 60 s. `raztros` je za teste.
    static func odmikPosiljanja(_ napake: Int, raztros: Double = Double.random(in: 0.8...1.2)) -> Double {
        let osnova = min(odmikPosiljanjaOd * pow(2.0, Double(max(napake, 1) - 1)), najvecjaOsnovaOdmika)
        return min(osnova * raztros, najdaljsiOdmik)
    }

    /// Stopnjevan odmik: zaporedni neuspeh brez napredka. Razlog zadnjega odmika doloci, ali ga vrnitev v ospredje sme preskociti.
    private func odlozi(zaradiStreznika: Bool) {
        zaporedneNapake += 1
        odmikZaradiStreznika = zaradiStreznika
        naslednjePosiljanje = ura().addingTimeInterval(Self.odmikPosiljanja(zaporedneNapake))
    }

    /// Osnovni odmik (~5 s) brez stopnjevanja: paket je napredoval brez `error`, a vnos je ostal v vrsti (neuspel zapis konflikta).
    private func odloziOsnovno(zaradiStreznika: Bool) {
        zaporedneNapake = 1
        odmikZaradiStreznika = zaradiStreznika
        naslednjePosiljanje = ura().addingTimeInterval(Self.odmikPosiljanja(1))
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
        guard Self.jeOdvzemDostopaNapaka(napaka) else { return false }
        if poskusiPoslati, !posiljanjeVTeku, cakajoce > 0 { await poslji() }
        dostopOdvzet = true
        disk.pocistiKlub(klubId)
        SkenOdjava.pocistiPredpomnilnik()   // scan-list z imeni imetnikov je tudi v URLCache
        postaviDogodke([])
        uskladiAktivne()   // brez dogodkov ni aktivnih: pobrise stanja (seznami, lokalni skeni v pomnilniku) in povzetek
        return true
    }

    /// Pravi odgovori backenda (index.js requireClub): za IZRECEN klub, v katerem uporabnik ni, 404 »Club not found.« (besedilo ali JSON);
    /// brez glave kluba 403 »Forbidden.«. NE: 403 »Email not verified.« (drugo vprasanje), 403 »Your role in the club does not allow
    /// this.« (clan je, samo vloga ne sme), 404 »Event not found.« (dogodka ni, klub pa je).
    nonisolated static func jeOdvzemDostopaNapaka(_ napaka: Error) -> Bool {
        guard let a = napaka as? APIError, case let .requestFailed(koda, besedilo) = a else { return false }
        if koda == 404 { return besedilo.contains("Club not found") }
        if koda == 403 { return besedilo.trimmingCharacters(in: .whitespacesAndNewlines) == "Forbidden." }
        return false
    }

    // MARK: - Stanje povezave

    private func osveziStevce() {
        vrsta.ponoviNeuspele()   // neuspel zapis na disk se poskusi znova ob vsakem skenu, dokler ni potrjen
        cakajoce = vrsta.stevilo(klub: klubId, uporabnik: uporabnikId)
        konflikti = vrsta.nepotrjeniKonflikti(klub: klubId, uporabnik: uporabnikId)
        zapisOK = vrsta.zapisUspel
    }

    private func zabeleziUspeh() {
        zadnjiKlicOK = true
        posodobiPovezavo()
    }

    /// Rok je potekel: streznik je prepocasen za vrata, zato velja kot nedosegljiv, dokler ga uspesen klic ne povrne.
    private func zabeleziRok() {
        zadnjiKlicOK = false
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

/// Samo `generated_at` iz scan-list (ura telefona se presoja brez polnega dekodiranja seznama).
struct SkenGeneriran: Decodable {
    let generatedAt: String?

    enum CodingKeys: String, CodingKey { case generatedAt = "generated_at" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = (try? c.decodeIfPresent(String.self, forKey: .generatedAt)) ?? nil
    }
}
