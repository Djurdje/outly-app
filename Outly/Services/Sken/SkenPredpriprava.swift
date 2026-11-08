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

    /// Pripravi en klub (klubId, uporabnikId, zeton). Vrne true, ce je poskus porabil okno (streznik je odgovoril), false, ce je bil
    /// prekinjen ali brez omrezja. Privzeto prava priprava; testi podtaknejo svojo.
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
    /// Klubi, za katere je odprt skener (stevec odprtij).
    private var odprti: [Int: Int] = [:]
    /// Povecuje se ob vsakem preklicu: priprava, ki se je zacela pred njim, ne sme vec zapisati ali nadaljevati.
    private var generacija = 0

    init(pripravi: @escaping Pripravi = SkenPredpriprava.privzetaPriprava,
         pocisti: @escaping Pocisti = SkenPredpriprava.privzetoCiscenje,
         ociStare: @escaping @MainActor () -> Void = { SkenDisk().pocistiStare() }) {
        self.pripravi = pripravi
        self.pocisti = pocisti
        self.ociStare = ociStare
    }

    // MARK: - Skener odprt

    /// SkenSeja.zacni(): skener tega kluba je odprt, priprava zanj ne teece (skener sam prenasa).
    func skenerOdprt(_ klub: Int) { odprti[klub, default: 0] += 1 }

    /// SkenSeja.ustavi().
    func skenerZaprt(_ klub: Int) {
        guard let n = odprti[klub] else { return }
        if n <= 1 { odprti.removeValue(forKey: klub) } else { odprti[klub] = n - 1 }
    }

    func jeSkenerOdprt(_ klub: Int) -> Bool { odprti[klub] != nil }

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
                    self.pocisti(klub)   // odjava med pripravo: zapis seznama preklica ne doseze, ne glede na zeton
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
    /// Vrne true, ce poskus porabi okno: streznik je odgovoril (ali je poskus napravil napako, ki ni izpad). false: preklic ali
    /// brez omrezja (`povezava` pade ob omrezni napaki, roku in 5xx).
    static func pripraviKlub(klubId: Int, uporabnikId: Int?, zeton: @escaping @MainActor () -> String,
                             api: SkenApi = SkenApiZivi(), disk: SkenDisk = SkenDisk()) async -> Bool {
        let seja = SkenSeja(klubId: klubId, uporabnikId: uporabnikId, api: api, disk: disk)
        seja.zeton = zeton
        await seja.naloziDogodke()
        return seja.povezava && !Task.isCancelled
    }

    static func privzetaPriprava(_ klubId: Int, _ uporabnikId: Int?, _ zeton: @escaping @MainActor () -> String) async -> Bool {
        await pripraviKlub(klubId: klubId, uporabnikId: uporabnikId, zeton: zeton)
    }

    static func privzetoCiscenje(_ klubId: Int) {
        SkenDisk().pocistiKlub(klubId)
        SkenOdjava.pocistiPredpomnilnik()
    }
}
