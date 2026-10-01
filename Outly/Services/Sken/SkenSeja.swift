import Foundation
import Combine

// Sken brez povezave (backend issue #86, 1. 10. 2026): orkestrator za enega kluba.
//
//  - Ob odprtju dogodka prenese javni kljuc in seznam vstopnic, shrani oboje na disk in ju osvezuje na ~2 min.
//    Ce je seznam ze na disku, je skener pripravljen takoj, tudi brez povezave.
//  - Sken kode v2 se odloci LOKALNO (SkenOdlocitev): zeleno takoj, zapis v trajno vrsto, brez cakanja na streznik.
//  - Vrsta se poslje prek scan-batch takoj po skenu in vsako sekundo, ce kaj caka (eksponentno odlaganje ob napaki).
//    Streznik je razsodnik: ce je isto vstopnico pred nami spustil drug telefon, pride `already_used` in to postane konflikt.
//  - Kode v1 (in primeri brez podatkov): s povezavo gre sken na obstojec POST /business/tickets/scan, brez nje rumeno.

/// Odjemalec za sken. Zivi je v APIClient+Sken.swift; testi podtaknejo svojega.
protocol SkenApi {
    func dogodki(token: String) async throws -> [SkenDogodek]
    func kljuc(token: String) async throws -> ScanKey
    func seznam(token: String, dogodekId: Int) async throws -> ScanList
    func paket(token: String, vnosi: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult]
    func spletniSken(token: String, qr: String) async throws -> ScanResult
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

@MainActor
final class SkenSeja: ObservableObject {

    enum Priprava: Equatable {
        /// Dogodek ni izbran.
        case izbira
        /// Kljuc/seznam se prenasata in ju se ni na disku.
        case nalaga
        /// Kljuc in seznam sta na napravi: lokalno preverjanje dela.
        case pripravljen
        /// Prenos ni uspel in na disku ni nic (sporocilo za vratarja).
        case manjkaPodatkov(String)
    }

    // MARK: Kar vidi zaslon

    @Published private(set) var dogodki: [SkenDogodek] = []
    @Published private(set) var dogodkiNalaga = false
    @Published private(set) var dogodkiNapaka: String?
    @Published private(set) var dogodek: SkenDogodek?
    @Published private(set) var priprava: Priprava = .izbira
    /// Ali je streznik dosegljiv: omrezje je gor IN zadnji klic ni padel.
    @Published private(set) var povezava = true
    /// Skeni v vrsti, ki jih streznik se ni potrdil.
    @Published private(set) var cakajoce = 0
    @Published private(set) var zadnjiPrenos: Date?
    /// Nepotrjeni konflikti tega kluba (ob zacetku vsi iz diska).
    @Published private(set) var konflikti: [SkenKonflikt] = []
    /// false: zadnji zapis na disk ni uspel, skeni so samo v pomnilniku.
    @Published private(set) var zapisOK = true
    @Published private(set) var sprejeti = 0
    @Published private(set) var zavrnjeni = 0
    /// Tece spletni sken (stara koda ali ni podatkov, a je povezava): zaslon kaze »Checking…«.
    @Published private(set) var preverjaNaStrezniku = false

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

    private var kljuc: ScanKey?
    private var indeks: SkenIndeks?
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

    /// `vrsta`: privzeto ena skupna na disk (SkenVrsta.deljena). Dve seji z lastno kopijo vrste bi si prepisovali datoteko
    /// (stara seja, ki se dokonca zadnje posiljanje, bi pobrisala sken, ki ga je medtem dodala nova). Testi podajo svojo.
    init(klubId: Int, uporabnikId: Int? = nil, api: SkenApi, disk: SkenDisk = SkenDisk(),
         deviceId: String = SkenNaprava.id(), vrsta: SkenVrsta? = nil) {
        self.klubId = klubId
        self.uporabnikId = uporabnikId
        self.api = api
        self.disk = disk
        self.deviceId = deviceId
        self.vrsta = vrsta ?? SkenVrsta.deljena(disk)
        osveziStevce()
    }

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
        if gor && !bilo {
            zaporedneNapake = 0
            naslednjePosiljanje = .distantPast
            naslednjaOsvezitev = .distantPast
        }
    }

    /// Aplikacija je spet aktivna (npr. po zaklepu zaslona): takoj poskusi osvezitev in posiljanje.
    func takojOsvezi() {
        zaporedneNapake = 0
        naslednjePosiljanje = .distantPast
        naslednjaOsvezitev = .distantPast
    }

    /// Osvezitev in posiljanje tecesta vsako v svojem Tasku: pocasen prenos seznama ne sme zadrzati posiljanja skenov.
    private func tik() {
        let zdaj = Date()
        if dogodek != nil, zdaj >= naslednjaOsvezitev, osvezitevZaDogodek == nil { Task { await osveziSeznam() } }
        if cakajoce > 0, zdaj >= naslednjePosiljanje, !posiljanjeVTeku { Task { await poslji() } }
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
            let sveziSeznam = try await api.dogodki(token: zeton())
            zabeleziUspeh()
            dogodki = sveziSeznam
            dogodkiNapaka = nil
            disk.zapisi(sveziSeznam, SkenDisk.imeDogodkov(klub: klubId))
            disk.pocisti(klub: klubId, obdrzi: Set(sveziSeznam.map { $0.id }))
        } catch {
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
                    return konec > meja   // vrata so lahko odprta se kakšno uro po koncu
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
        kljuc = nil
        indeks = nil
        lokalni = [:]
        zadnjiPrenos = nil
        if let s = disk.preberi(SkenSeznamShramba.self, SkenDisk.imeSeznama(klub: klubId, dogodek: d.id)) {
            kljuc = s.kljuc
            if let l = s.seznam, l.eventId == d.id || l.eventId == 0 { indeks = SkenIndeks(l) }
            zadnjiPrenos = s.prenesenoOb
        }
        lokalni = disk.preberi(SkenLokalniSkeni.self, SkenDisk.imeLokalnih(klub: klubId, dogodek: d.id))?.casi ?? [:]
        priprava = jePripravljen ? .pripravljen : .nalaga
        naslednjaOsvezitev = .distantPast
        await osveziSeznam()
    }

    func zapriDogodek() {
        dogodek = nil
        priprava = .izbira
    }

    private var jePripravljen: Bool { kljuc?.surovi != nil && indeks != nil }

    /// Prenese seznam (in kljuc, ce ga ni ali se kid ne ujema), shrani na disk. Ob napaki ostane stara shramba.
    func osveziSeznam() async {
        guard let d = dogodek, osvezitevZaDogodek != d.id else { return }
        osvezitevZaDogodek = d.id
        defer { osvezitevZaDogodek = nil }
        naslednjaOsvezitev = Date().addingTimeInterval(Double.random(in: Self.osvezitevSekunde))
        do {
            let seznam = try await api.seznam(token: zeton(), dogodekId: d.id)
            guard dogodek?.id == d.id else { return }   // vratar je medtem zamenjal dogodek
            zabeleziUspeh()
            // Kljuc primerjamo po `kid` ob vsakem prenosu (STATE.md: zamenjava QR_SECRET spremeni javni kljuc).
            if kljuc == nil || kljuc?.kid != seznam.kid || kljuc?.surovi == nil {
                if let nov = try? await api.kljuc(token: zeton()), nov.surovi != nil {
                    kljuc = nov
                } else if kljuc?.kid != seznam.kid {
                    kljuc = nil   // star kljuc bi zavrnil nove kode; raje rumeno (preveri streznik) kot napacno rdece
                }
            }
            guard dogodek?.id == d.id else { return }
            indeks = SkenIndeks(seznam)
            let zdaj = Date()
            zadnjiPrenos = zdaj
            disk.zapisi(SkenSeznamShramba(kljuc: kljuc, seznam: seznam, prenesenoOb: zdaj),
                        SkenDisk.imeSeznama(klub: klubId, dogodek: d.id))
            priprava = jePripravljen ? .pripravljen : .manjkaPodatkov(String(localized: "The scanner key could not be downloaded."))
        } catch {
            zabeleziNapako(error)
            // Brez povezave poskusi kmalu znova (vratar naj vidi, da se je povezava vrnila), ne cez 2 min.
            if Self.jeOmrezna(error) { naslednjaOsvezitev = Date().addingTimeInterval(Self.odmikOsvezitveOdNapake) }
            if case .nalaga = priprava { priprava = .manjkaPodatkov(error.userMessage) }
        }
    }

    // MARK: - Sken

    /// Odlocitev za eno kodo. Zeleno = takoj, brez omrezja; sinhronizacija tece v ozadju.
    func skeniraj(_ surova: String) async -> SkenPrikaz {
        let qr = surova.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = dogodek else {
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "REFUSED"), podnaslov: String(localized: "Choose an event first."))
        }
        let sodba = SkenOdlocitev.odloci(qr: qr, dogodekId: d.id, kljuc: kljuc?.surovi, indeks: indeks, lokalni: lokalni)
        switch sodba.barva {
        case .zeleno:
            zapisiSken(qr: qr, serial: sodba.serial, kljucLokalnih: sodba.serial ?? qr, imetnik: opisImetnika(sodba.vstopnica), dogodek: d)
            sprejeti += 1
            return SkenPrikaz.iz(sodba, qr: qr)
        case .rdece:
            zavrnjeni += 1
            return SkenPrikaz.iz(sodba, qr: qr)
        case .rumeno:
            // Stara koda ali ni podatkov: s povezavo naj odloci streznik (obstojec spletni sken), brez nje odloci vratar.
            guard povezava else { return SkenPrikaz.iz(sodba, qr: qr) }
            preverjaNaStrezniku = true
            defer { preverjaNaStrezniku = false }
            do {
                let r = try await api.spletniSken(token: zeton(), qr: qr)
                zabeleziUspeh()
                if r.result == "ok" {
                    sprejeti += 1
                    lokalni[sodba.serial ?? qr] = Date()   // brez povezave ista koda ne sme spet na rumeno -> rdece "ze skenirano"
                    disk.zapisi(SkenLokalniSkeni(casi: lokalni), SkenDisk.imeLokalnih(klub: klubId, dogodek: d.id))
                } else {
                    zavrnjeni += 1
                }
                return SkenPrikaz.iz(r)
            } catch {
                zabeleziNapako(error)
                return SkenPrikaz.iz(sodba, qr: qr)
            }
        }
    }

    /// Vratar je rumeno kodo (v1 / ni podatkov) odlocil spustiti. Gre v vrsto: streznik jo preveri naknadno.
    func spustiRocno(qr surova: String) -> SkenPrikaz {
        let qr = surova.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = dogodek else { return SkenPrikaz.spusceniRocno() }
        var serial: String? = nil
        if case let .v2(telo, _, _) = SkenKoda.razcleni(qr) { serial = telo.serial }
        zapisiSken(qr: qr, serial: serial, kljucLokalnih: serial ?? qr, imetnik: nil, dogodek: d)
        sprejeti += 1
        return SkenPrikaz.spusceniRocno()
    }

    private func zapisiSken(qr: String, serial: String?, kljucLokalnih: String, imetnik: String?, dogodek d: SkenDogodek) {
        let vnos = SkenVnos(qr: qr, serial: serial, eventId: d.id, klubId: klubId, uporabnikId: uporabnikId, imetnik: imetnik)
        // Najprej vrsta, nato lokalni zapis: ce aplikacija umre vmes, sken ne sme izginiti (najslabse: ponovni sken je spet zelen,
        // streznik pa ga ujame kot already_used).
        vrsta.dodaj(vnos)
        lokalni[kljucLokalnih] = vnos.scannedAt
        disk.zapisi(SkenLokalniSkeni(casi: lokalni), SkenDisk.imeLokalnih(klub: klubId, dogodek: d.id))
        osveziStevce()
        if zaporedneNapake == 0 { Task { await poslji() } }
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
        guard !posiljanjeVTeku else { return }
        posiljanjeVTeku = true
        defer { posiljanjeVTeku = false }
        while true {
            let paket = vrsta.paket(klub: klubId, uporabnik: uporabnikId)
            if paket.isEmpty { zaporedneNapake = 0; osveziStevce(); return }
            do {
                let rezultati = try await api.paket(token: zeton(), vnosi: paket, deviceId: deviceId)
                zabeleziUspeh()
                let odstranjeni = vrsta.uporabi(rezultati, poslani: paket)
                osveziStevce()
                if odstranjeni == 0 { odlozi(); return }   // streznik je odgovoril, a vse so `error`
                zaporedneNapake = 0
            } catch {
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

    /// Napaka zaradi omrezja ali izpada streznika (ne zaradi vsebine zahteve).
    static func jeOmrezna(_ e: Error) -> Bool {
        if e is URLError { return true }
        if let a = e as? APIError, case let .requestFailed(koda, _) = a {
            return koda == -1 || koda == 408 || koda == 429 || koda >= 500
        }
        return false
    }
}
