import Foundation

/// GET /business/events/:id/tickets z ovojnico (#277 N1, outly-backend ARCHITECTURE »Seznam vstopnic dogodka za vrata«).
/// Ovojnica se vklopi, ko je poslan vsaj eden od `limit`, `offset`, `q`; brez njih backend vrne golo polje (najvec 1000 vrstic) —
/// to dekodiramo tudi (star backend), takrat so stevci izracunani iz vrstic in `hasMore` je false.
struct SeznamVstopnicDogodka: Decodable {
    /// Stevci VSEH vstopnic dogodka (vkljucno VIP in guest lista), neodvisno od `q` / `limit` / `offset`.
    struct Stevci: Decodable, Equatable {
        var all: Int = 0
        /// `valid` + `used`.
        var sold: Int = 0
        /// `used`.
        var checkedIn: Int = 0
        /// `valid`.
        var expected: Int = 0
        var refunded: Int = 0
        var void: Int = 0

        enum CodingKeys: String, CodingKey {
            case all, sold, expected, refunded, void
            case checkedIn = "checked_in"
        }

        init(all: Int = 0, sold: Int = 0, checkedIn: Int = 0, expected: Int = 0, refunded: Int = 0, void: Int = 0) {
            self.all = all
            self.sold = sold
            self.checkedIn = checkedIn
            self.expected = expected
            self.refunded = refunded
            self.void = void
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            all       = (try? c.decodeIfPresent(Int.self, forKey: .all)) ?? 0
            sold      = (try? c.decodeIfPresent(Int.self, forKey: .sold)) ?? 0
            checkedIn = (try? c.decodeIfPresent(Int.self, forKey: .checkedIn)) ?? 0
            expected  = (try? c.decodeIfPresent(Int.self, forKey: .expected)) ?? 0
            refunded  = (try? c.decodeIfPresent(Int.self, forKey: .refunded)) ?? 0
            void      = (try? c.decodeIfPresent(Int.self, forKey: .void)) ?? 0
        }

        /// Star backend (golo polje): isti pomen kot na strezniku, izracunan iz vrstic.
        static func izVrstic(_ vrstice: [APITicket]) -> Stevci {
            let used = vrstice.filter { $0.status == "used" }.count
            let valid = vrstice.filter { $0.status == "valid" }.count
            return Stevci(all: vrstice.count, sold: used + valid, checkedIn: used, expected: valid,
                          refunded: vrstice.filter { $0.status == "refunded" }.count,
                          void: vrstice.filter { $0.status == "void" }.count)
        }
    }

    var tickets: [APITicket]
    var counts: Stevci
    /// Zadetki `q` (brez `q` = `counts.all`).
    var total: Int
    var hasMore: Bool
    /// Naslednji `offset` ali nil.
    var nextOffset: Int?
    /// false = star backend je vrnil golo polje (brez ovojnice).
    var ovojnica: Bool

    enum CodingKeys: String, CodingKey {
        case tickets, counts, total
        case hasMore = "has_more"
        case nextOffset = "next_offset"
    }

    init(tickets: [APITicket], counts: Stevci, total: Int, hasMore: Bool, nextOffset: Int?, ovojnica: Bool = true) {
        self.tickets = tickets
        self.counts = counts
        self.total = total
        self.hasMore = hasMore
        self.nextOffset = nextOffset
        self.ovojnica = ovojnica
    }

    init(from decoder: Decoder) throws {
        if let polje = try? decoder.singleValueContainer().decode([APITicket].self) {
            self.init(tickets: polje, counts: .izVrstic(polje), total: polje.count, hasMore: false, nextOffset: nil, ovojnica: false)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let vrstice = try c.decodeIfPresent([APITicket].self, forKey: .tickets) ?? []
        let stevci = (try? c.decodeIfPresent(Stevci.self, forKey: .counts)) ?? Stevci.izVrstic(vrstice)
        let naslednji = (try? c.decodeIfPresent(Int.self, forKey: .nextOffset)) ?? nil
        // `has_more` brez `next_offset` bi nalaganje naprej zaciklalo: brez naslednjega odmika ni »Load more«.
        let vec = ((try? c.decodeIfPresent(Bool.self, forKey: .hasMore)) ?? false) && naslednji != nil
        self.init(tickets: vrstice, counts: stevci,
                  total: (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? vrstice.count,
                  hasMore: vec, nextOffset: vec ? naslednji : nil, ovojnica: true)
    }
}

extension APIClient {
    /// Velikost strani seznama vstopnic za vrata (pogodba #277 N1: `?limit=200`).
    nonisolated static let stranVstopnicVrata = 200
    /// Najvec, kar backend sprejme v `limit` (osvezitev po vpisu obdrzi ze nalozene strani).
    nonisolated static let najvecVstopnicVrata = 1000
    /// Backend `q`: obrezan, 1-64 znakov (JS dolzina = UTF-16 enote), brez kontrolnih znakov (sicer 400 `invalid_q`).
    nonisolated static let najvecIskanjeVstopnic = 64

    /// Poizvedba za GET /business/events/:id/tickets: vedno `limit` (vklopi ovojnico s stevci), `offset` samo > 0, `q` samo neprazen.
    /// `q` je ociscen (obrezan, brez kontrolnih znakov, najvec 64 UTF-16 enot), da streznik ne vrne 400 `invalid_q`.
    static func poizvedbaVstopnicDogodka(limit: Int = APIClient.stranVstopnicVrata, offset: Int = 0, q: String = "") -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(min(max(limit, 0), najvecVstopnicVrata)))]
        if offset > 0 { items.append(URLQueryItem(name: "offset", value: String(offset))) }
        let iskanje = ocistiIskanjeVstopnic(q)
        if !iskanje.isEmpty { items.append(URLQueryItem(name: "q", value: iskanje)) }
        return items
    }

    /// Obrezan niz brez kontrolnih znakov, skrajsan na najvec 64 UTF-16 enot (cel znak, ne pol emojija).
    static func ocistiIskanjeVstopnic(_ q: String) -> String {
        let brez = String(String.UnicodeScalarView(q.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        var t = brez.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.utf16.count > najvecIskanjeVstopnic { t.removeLast() }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// GET /business/events/:id/tickets?limit=&offset=&q= — ena stran seznama za vrata (owner, manager, doorman).
    /// 503 `search_timeout` (seznam je zaseden) gre kot napaka: zaslon pove »poskusi znova« (`userMessage`).
    func fetchEventTicketsStran(token: String, eventId: Int, offset: Int = 0, q: String = "",
                                limit: Int = APIClient.stranVstopnicVrata) async throws -> SeznamVstopnicDogodka {
        let data = try await send(path: "business/events/\(eventId)/tickets", method: "GET", token: token,
                                  query: APIClient.poizvedbaVstopnicDogodka(limit: limit, offset: offset, q: q))
        return try decode(SeznamVstopnicDogodka.self, from: data)
    }
}

/// Kaj naredi »Try again« po napaki na seznamu vstopnic na vratih (EventTicketsView).
enum VrataPonovitev: Equatable {
    /// Prva stran za trenutno iskanje (napaka pri prvem nalaganju ali sprememba iskanja).
    case prvaStran
    /// Naslednja stran (napaka pri »Load more«).
    case naslednjaStran
    /// Osvezitev vseh ze nalozenih vrstic (napaka po »Check in«): vratar ne izgubi mesta na seznamu.
    case osvezitev
}

/// Kaj pokaze vrstica vstopnice po vpisu, ki ni uspel (EventTicketsView): vratar napako vidi NA vrstici, ne glede na to, kje je seznam.
enum VrataVrsticaNapaka: Equatable {
    /// Klic je padel pred odgovorom (brez povezave, 5xx ...): vpis NI uspel.
    case neuspelo
    /// Timeout ali prekinjena povezava po posiljanju: vpis je MORDA uspel (»Not confirmed – tap to retry«).
    case nepotrjeno
    /// Streznik je vpis zavrnil (neveljavna, napacen klub, neplacana, ni danes, razveljavljena, vracilo, odpovedan dogodek, spor pri
    /// banki ...); nosi sporocilo streznika.
    case zavrnjeno(String)
    /// Po neuspehu (izpad, negotov izid, zavrnitev) je streznik vstopnico vrnil kot `used` - morda jo je vpisal DRUG vratar ali
    /// kamera s kopijo kode, zato to NI potrditev nasega vpisa: oranzno »Checked in at HH:MM – check the guest«, dokler vratar ne
    /// tapne vrstice (potrdi, da je gosta preveril). Nosi `used_at` strezniga (nil = ura ni znana).
    case vpisanaMedNapako(String?)

    var jeVpisanaMedNapako: Bool {
        if case .vpisanaMedNapako = self { return true }
        return false
    }

    /// Zavrnitev se z ponovnim dotikom vrstice ne popravi; izpad povezave da.
    var jeZavrnitev: Bool {
        if case .zavrnjeno = self { return true }
        return false
    }
}

/// Kaj naredi dotik vrstice z napako (EventTicketsView).
enum VrataDotik: Equatable {
    /// Izpad povezave / negotov izid: vpis se ponovi (POST).
    case ponoviVpis
    /// Zavrnitev streznika ali vpisana med napako: dotik vrstice ne naredi nicesar. Opozorilo »vpisana med napako« se potrdi
    /// SAMO z izrecnim gumbom na vrstici (`potrdiPregled`), ne z nehotenim dotikom med drsenjem; gumb ne poslje POST-a.
    case nic
}

/// Stevec nalaganj seznama na vratih: odgovor starejsega nalaganja (iskanje, »Try again«, osvezitev po vpisu) ne sme prepisati
/// novejsega stanja in ne sme sprostiti `isLoading`, ce tece novejse. Stevec, ne boolean: vec Taskov teče hkrati.
struct VrataNalaganje: Equatable {
    private(set) var zadnje = 0

    /// Novo nalaganje: vrne njegov id in s tem razveljavi vsa starejsa.
    mutating func zacni() -> Int {
        zadnje += 1
        return zadnje
    }

    func jeZadnje(_ id: Int) -> Bool { id == zadnje }
}

/// Stanje seznama vstopnic na vratih (EventTicketsView), cista logika za strani in iskanje (testi: Racun18InVrataTests).
/// Vrstice in `naslednjiOdmik` veljajo za iskanje `q`, za katero so bile nalozene: ko uporabnik tipka (premor pred novim
/// nalaganjem), »Load more« ne sme vzeti NOVEGA `q` s STARIM odmikom.
struct VrataSeznam {
    private(set) var vrstice: [APITicket] = []
    /// Stevci vseh vstopnic dogodka (`counts`); nil = se ni nalozeno.
    private(set) var stevci: SeznamVstopnicDogodka.Stevci?
    /// Zadetki iskanja (`total`).
    private(set) var zadetkov = 0
    private(set) var naslednjiOdmik: Int?
    /// Ocisceno iskanje, za katero veljajo vrstice in odmik; nil = nic nalozeno.
    private(set) var q: String?
    /// Vstopnice, vpisane na tem telefonu, preden je osvezitev seznama prisla (vrata ne cakajo na seznam). Osvezitev odstrani samo
    /// tiste, ki jih streznik ze vrne kot `used`; ostale optimisticne »IN« obdrzi (osvezitev je lahko izpred vpisa).
    private(set) var vpisani = Set<Int>()
    /// Vstopnice, pri katerih rocni vpis ni uspel (omrezje, streznik): vrstica sama pokaze »Not checked in – tap to retry«,
    /// ne glede na to, kje je seznam zdrsnjen. Pobrise ga uspesen (ponovni) vpis ali streznik, ki vstopnico vrne kot `used`.
    private(set) var napakeVpisa: [Int: VrataVrsticaNapaka] = [:]
    /// Status vstopnice (`status`) ob zavrnitvi: ko osvezitev pokaze drug status, je zavrnitev zastarela in se pobrise.
    private var statusPriZavrnitvi: [Int: String] = [:]

    static func kljuc(_ iskanje: String) -> String { APIClient.ocistiIskanjeVstopnic(iskanje) }

    /// Odmik za »Load more«, samo ce seznam velja za trenutno iskanje (sicer nil: gumba ni, klic se ne poslje).
    func odmikNaprej(iskanje: String) -> Int? {
        q == Self.kljuc(iskanje) ? naslednjiOdmik : nil
    }

    /// Je vstopnica vpisana: po streznikovem seznamu (`status == "used"`) ali po vpisu na tem telefonu (samo dokler streznik
    /// pravi `valid`: vmes vracilo ali razveljavitev ni »IN«).
    func jeVpisana(_ t: APITicket) -> Bool { t.isUsed || (vpisani.contains(t.id) && t.status == "valid") }

    /// Preklic (Task preklican, URLSession `.cancelled`) ni napaka streznika ali omrezja: stanje na zaslonu se ne sme spremeniti.
    static func jePreklic(_ napaka: Error) -> Bool {
        if napaka is CancellationError { return true }
        if let u = napaka as? URLError, u.code == .cancelled { return true }
        return false
    }

    /// VIP razdelek po napaki nalaganja: preklic obdrzi prejsnje stanje (razdelek nad seznamom ne izgine in vrstice ne skocijo
    /// pod prstom vratarja), prava napaka (npr. 404 na starem strezniku) razdelek skrije.
    static func vipPoNapaki<T>(_ napaka: Error, prejsnji: T?) -> T? { jePreklic(napaka) ? prejsnji : nil }

    /// Vrstica pokaze napako vpisa: vpis je padel in vstopnica (po strezniku in po telefonu) se ni vpisana.
    func imaNapakoVpisa(_ t: APITicket) -> Bool { napakaVrstice(t) != nil }

    /// Napaka, ki jo pokaze vrstica (nil = ni napake ali je vstopnica ze vpisana).
    /// Pravilo: vstopnica, ki je po strezniku `used`, in ima KAKRSNOKOLI napako (ali vpis v teku), je NIKOLI nil in nikoli zelen »IN«:
    /// vedno `.vpisanaMedNapako(used_at)` (oranzno), dokler vratar ne potrdi z gumbom.
    func napakaVrstice(_ t: APITicket) -> VrataVrsticaNapaka? {
        if let n = napakeVpisa[t.id] {
            if n.jeVpisanaMedNapako { return n }
            if t.isUsed { return .vpisanaMedNapako(t.usedAt) }
            return jeVpisana(t) ? nil : n
        }
        if t.isUsed, vTeku.contains(t.id) { return .vpisanaMedNapako(t.usedAt) }
        return nil
    }

    /// Kaj stori dotik vrstice z dano napako.
    static func dotik(_ n: VrataVrsticaNapaka) -> VrataDotik {
        switch n {
        case .neuspelo, .nepotrjeno: return .ponoviVpis
        case .vpisanaMedNapako, .zavrnjeno: return .nic
        }
    }

    /// Vratar je z IZRECNIM gumbom na vrstici potrdil, da je gosta preveril: stanje `.vpisanaMedNapako` se pocisti, vrstica ostane
    /// navaden »IN«. Brez POST-a.
    mutating func potrdiPregled(_ id: Int) {
        if napakeVpisa[id]?.jeVpisanaMedNapako == true { napakeVpisa[id] = nil }
    }

    /// Vstopnice, za katere je POST vpisa na poti. Prejsnja napaka se ne brise, dokler izid ni znan; osvezitev, ki vrne tako vstopnico
    /// kot `used` (npr. vpis drugega gosta sprozi osvezitev), jo pretvori v `.vpisanaMedNapako`, ne v tihi zeleni »IN«.
    private(set) var vTeku = Set<Int>()

    /// Zacetek vpisa: vrne prejsnjo napako (ostane na vrstici do izida).
    mutating func zacniVpis(_ id: Int) -> VrataVrsticaNapaka? {
        vTeku.insert(id)
        return napakeVpisa[id]
    }

    /// Konec vpisa (ok, napaka ali preklic).
    mutating func koncajVpis(_ id: Int) { vTeku.remove(id) }

    /// Vpis je (po neuspehu) ze izvedel nekdo drug: POST te naprave je vrnil `already_used` po negotovem izidu. Vrstica je »IN«,
    /// a oranzna z opozorilom.
    mutating func oznaciVpisanoMedNapako(_ id: Int, usedAt: String?) {
        vpisani.insert(id)
        napakeVpisa[id] = .vpisanaMedNapako(usedAt)
        statusPriZavrnitvi[id] = nil
    }

    /// Id-ji vstopnic, ki jih je zadnja osvezitev pretvorila v `.vpisanaMedNapako` in zanje se ni bilo haptike.
    private(set) var novaOpozorila: [Int] = []

    /// Pogled enkrat sprozi `haptika(.warning)`, ce je vrnjen seznam neprazen.
    mutating func prevzemiNovaOpozorila() -> [Int] {
        defer { novaOpozorila = [] }
        return novaOpozorila
    }

    /// Po zamenjavi/pripetju vrstic: vstopnica z napako, ki jo streznik vrne kot `used`, NE postane tiho »IN« (lahko jo je vpisal drug
    /// vratar ali kamera s kopijo). Postane `.vpisanaMedNapako(used_at)` in ostane, dokler vratar ne tapne vrstice. Vrne nove id-je.
    @discardableResult
    private mutating func uskladiNapake() -> [Int] {
        var nova: [Int] = []
        for t in vrstice where t.isUsed {
            let n = napakeVpisa[t.id]
            if n?.jeVpisanaMedNapako == true { continue }
            // Napaka ali vpis v teku (POST se ni vrnil): `used` iz osvezitve ni potrditev nasega vpisa.
            guard n != nil || vTeku.contains(t.id) else { continue }
            napakeVpisa[t.id] = .vpisanaMedNapako(t.usedAt)
            statusPriZavrnitvi[t.id] = nil
            nova.append(t.id)
        }
        // Zavrnitev velja za status vstopnice ob zavrnitvi: drug status (npr. valid -> refunded) jo naredi zastarelo.
        for (id, napaka) in napakeVpisa where napaka.jeZavrnitev {
            if let prej = statusPriZavrnitvi[id], let zdaj = vrstice.first(where: { $0.id == id })?.status, zdaj != prej {
                napakeVpisa[id] = nil
            }
        }
        statusPriZavrnitvi = statusPriZavrnitvi.filter { napakeVpisa[$0.key]?.jeZavrnitev == true }
        novaOpozorila.append(contentsOf: nova)
        return nova
    }

    /// Vpis te vstopnice ni uspel (izjema pri klicu ali zavrnitev streznika): napaka ostane NA vrstici.
    mutating func oznaciNapakoVpisa(_ id: Int, _ napaka: VrataVrsticaNapaka = .neuspelo) {
        // Opozorilo »vpisana med napako« ne sme postati manj resno (POST, ki pride za osvezitvijo, ga ne prepise z izpadom/zavrnitvijo).
        if napakeVpisa[id]?.jeVpisanaMedNapako == true { return }
        napakeVpisa[id] = napaka
        statusPriZavrnitvi[id] = napaka.jeZavrnitev ? vrstice.first(where: { $0.id == id })?.status : nil
    }

    /// Nov poskus vpisa se zacne: vrstica je spet nevtralna (vrtavka), ob novi napaki spet rdeca.
    mutating func pobrisiNapakoVpisa(_ id: Int) {
        napakeVpisa[id] = nil
        statusPriZavrnitvi[id] = nil
    }

    /// Kaj pokaze vrstica po izjemi pri vpisu: timeout in prekinjena povezava = vpis je morda uspel, vse ostalo = ni uspel.
    static func napakaIzIzjeme(_ napaka: Error) -> VrataVrsticaNapaka {
        if let u = napaka as? URLError, u.code == .timedOut || u.code == .networkConnectionLost { return .nepotrjeno }
        return .neuspelo
    }

    /// Zavrnitev streznika za vrstico; nil samo ob `ok`. Tudi `already_used` je zavrnitev: gosta s ze uporabljeno kodo ne spustimo.
    static func zavrnitev(_ r: ScanResult) -> VrataVrsticaNapaka? {
        vpisaniRezultat(r.result) ? nil : .zavrnjeno(r.message.isEmpty ? r.result : r.message)
    }

    /// `already_used` po napaki z negotovim izidom (timeout): strezniku ne moremo verjeti, da je to NAS prejsnji poskus (vmes je
    /// lahko vstopnico vpisal drug vratar ali kamera s kopijo kode). Vrstica je »IN« (streznik pravi used), pas je opozorilo z uro
    /// in ne uspeh; vratar preveri gosta. Brez predhodnega `.nepotrjeno` ostane navaden rdec »already used«.
    static func jeOpozoriloPoNepotrjenem(_ r: ScanResult, prejsnja: VrataVrsticaNapaka?) -> Bool {
        prejsnja == .nepotrjeno && r.result == "already_used"
    }

    /// Ura vpisa (HH:mm) iz `used_at` strezniga v casovnem pasu naprave; nil, ce casa ni ali ni veljaven.
    static func uraVpisa(_ usedAt: String?, casovniPas: TimeZone = .current) -> String? {
        guard let niz = usedAt, let cas = DateParsing.isoFrac.date(from: niz) ?? DateParsing.iso.date(from: niz) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = casovniPas
        f.dateFormat = "HH:mm"
        return f.string(from: cas)
    }

    /// Rezultat vpisa (POST /business/tickets/scan), po katerem je vstopnica vpisana s TEM klicem: samo `ok`. `already_used` ni
    /// uspeh te naprave (vpisal jo je nekdo drug ali prej).
    static func vpisaniRezultat(_ result: String) -> Bool { result == "ok" }

    /// Takoj po uspesnem vpisu: vrstica pokaze »IN«, se preden pride osvezitev seznama (drugi dotik ne poslje se enega vpisa).
    mutating func oznaciVpisano(_ id: Int) {
        vpisani.insert(id)
        pobrisiNapakoVpisa(id)
    }

    /// Kaj sme »Try again« zares narediti: zelena ponovitev velja samo, ce seznam se velja za trenutno iskanje. Sicer (vmes
    /// spremenjeno iskanje, ni vec naslednje strani) pade na prvo stran, da gumb nikoli ni mrtev.
    func ponovitev(_ zelena: VrataPonovitev, iskanje: String) -> VrataPonovitev {
        switch zelena {
        case .prvaStran: return .prvaStran
        case .naslednjaStran: return odmikNaprej(iskanje: iskanje) != nil ? .naslednjaStran : .prvaStran
        case .osvezitev: return q == Self.kljuc(iskanje) ? .osvezitev : .prvaStran
        }
    }

    /// Prva stran za iskanje (zamenja vse).
    @discardableResult
    mutating func zamenjaj(_ stran: SeznamVstopnicDogodka, iskanje: String) -> [Int] {
        zamenjajKose([stran], iskanje: iskanje)
    }

    /// Osvezitev po vpisu v vec kosih (`kosiOsvezitve`): vrstice zdruzene brez podvojenih, stevci in odmik iz zadnjega kosa.
    @discardableResult
    mutating func zamenjajKose(_ strani: [SeznamVstopnicDogodka], iskanje: String) -> [Int] {
        guard let zadnja = strani.last else { return [] }
        var znani = Set<Int>()
        vrstice = strani.flatMap(\.tickets).filter { znani.insert($0.id).inserted }
        stevci = zadnja.counts
        zadetkov = zadnja.total
        naslednjiOdmik = zadnja.nextOffset
        q = Self.kljuc(iskanje)
        let streznikVpisani = Set(vrstice.filter(\.isUsed).map(\.id))
        vpisani.subtract(streznikVpisani)
        return uskladiNapake()
    }

    /// Pripne naslednjo stran. false (nic se ne spremeni), ce je vmes drugo iskanje ali stran ni za trenutni odmik (dvojni dotik).
    @discardableResult
    mutating func pripni(_ stran: SeznamVstopnicDogodka, iskanje: String, odmik: Int) -> Bool {
        guard q == Self.kljuc(iskanje), naslednjiOdmik == odmik else { return false }
        let znani = Set(vrstice.map(\.id))
        vrstice.append(contentsOf: stran.tickets.filter { !znani.contains($0.id) })
        stevci = stran.counts
        zadetkov = stran.total
        // Odmik se mora premakniti naprej, sicer bi gumb vedno nalozil isto stran.
        if let n = stran.nextOffset, n > odmik { naslednjiOdmik = n } else { naslednjiOdmik = nil }
        uskladiNapake()
        return true
    }

    /// Kosi za osvezitev po »Check in«: vse ze nalozene vrstice (najmanj ena stran), v kosih po najvec 1000 (meja `limit`),
    /// da vratar pri vec kot 1000 nalozenih ne izgubi mesta na seznamu.
    static func kosiOsvezitve(nalozenih: Int) -> [(offset: Int, limit: Int)] {
        let skupaj = max(APIClient.stranVstopnicVrata, nalozenih)
        var kosi: [(offset: Int, limit: Int)] = []
        var odmik = 0
        while odmik < skupaj {
            let l = min(APIClient.najvecVstopnicVrata, skupaj - odmik)
            kosi.append((offset: odmik, limit: l))
            odmik += l
        }
        return kosi
    }
}
