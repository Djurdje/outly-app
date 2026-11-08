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
//  - Odjava (SessionStore.clearLocalSession) priprava PREKLICE pred brisanjem diska; tekoca priprava, ki bi se po odjavi vseeno koncala,
//    za seboj pobrise (SkenOdjava.pocisti), da prenesenih seznamov z imeni imetnikov ne ostane.

@MainActor
final class SkenPredpriprava {

    static let deljena = SkenPredpriprava()

    /// Najmanj toliko sekund med dvema pripravama istega kluba.
    nonisolated static let najmanjMedPripravami: Double = 10 * 60
    /// Vloge v klubu, ki smejo skenirati (backend: vse vloge v klubu razen natakarja).
    nonisolated static let skenirajoceVloge: Set<String> = ["owner", "manager", "doorman"]

    /// Pripravi en klub (klubId, uporabnikId, zeton). Privzeto prava priprava; testi podtaknejo svojo.
    typealias Pripravi = @MainActor (Int, Int?, @escaping @MainActor () -> String) async -> Void

    private let pripravi: Pripravi
    /// Ura telefona (testi jo podtaknejo).
    var ura: @MainActor () -> Date = { Date() }

    private var zadnje: [Int: Date] = [:]
    private var tek: Task<Void, Never>?
    /// Povecuje se ob vsakem preklicu: priprava, ki se je zacela pred njim, ne sme vec zapisati ali nadaljevati.
    private var generacija = 0

    init(pripravi: @escaping Pripravi = SkenPredpriprava.privzetaPriprava) {
        self.pripravi = pripravi
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
        guard let me, !zeton().isEmpty, tek == nil else { return nil }
        let zdaj = ura()
        let klubi = Self.zaPripravo(klubi: Self.klubiZaSken(me), zadnje: zadnje, zdaj: zdaj)
        guard !klubi.isEmpty else { return nil }
        for k in klubi { zadnje[k] = zdaj }   // tudi neuspel poskus steje (ne obremenjujemo backenda, ki je morda v tezavah)
        let moja = generacija
        let uporabnikId = me.id
        let naloga = Task { @MainActor [weak self] in
            guard let self else { return }
            for klub in klubi {
                guard self.generacija == moja else { break }
                await self.pripravi(klub, uporabnikId, zeton)
            }
            let preklicana = self.generacija != moja
            self.tek = nil
            // Odjava med pripravo: kar je priprava medtem zapisala na disk, ne sme ostati (seznami z imeni imetnikov).
            if preklicana, zeton().isEmpty { SkenOdjava.pocisti() }
        }
        tek = naloga
        return naloga
    }

    /// Odjava: tekoca priprava se preklice in ne zacne naslednjega kluba, omejitev se pozabi (naslednja prijava pripravi znova).
    /// Klicati PRED brisanjem diska (SkenOdjava.pocisti).
    func preklici() {
        generacija += 1
        zadnje.removeAll()
        tek?.cancel()
    }

    // MARK: - Prava priprava

    /// Ista pot kot skener: SkenSeja za klub, naloziDogodke() prenese dogodke, kljuc in sezname aktivnih dogodkov ter jih shrani.
    static func pripraviKlub(klubId: Int, uporabnikId: Int?, zeton: @escaping @MainActor () -> String,
                             api: SkenApi = SkenApiZivi(), disk: SkenDisk = SkenDisk()) async {
        let seja = SkenSeja(klubId: klubId, uporabnikId: uporabnikId, api: api, disk: disk)
        seja.zeton = zeton
        await seja.naloziDogodke()
    }

    static func privzetaPriprava(_ klubId: Int, _ uporabnikId: Int?, _ zeton: @escaping @MainActor () -> String) async {
        await pripraviKlub(klubId: klubId, uporabnikId: uporabnikId, zeton: zeton)
    }
}
