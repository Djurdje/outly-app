import Foundation

/// Razdelitev VIP vstopnic prijateljem takoj po nakupu mize (8. 10. 2026). Cista logika, locena od pogleda zaradi testov:
/// meja izbranih, izbira vstopnic za posiljanje, zaporedno posiljanje z zbiranjem izidov.
/// Ena vstopnica VEDNO ostane kupcu: pri mizi z N vstopnicami je najvec N-1 prijateljev, posiljanje pa gre od DRUGE vstopnice naprej.
enum VipRazdelitev {

    /// Vstopnice, ki so se na voljo kupcu: veljavne in ne ze poslane naprej (po vrnitvi s Stripa je lahko narocilo ze deloma razdeljeno).
    static func moje(_ vstopnice: [APITicket]) -> [APITicket] {
        vstopnice.filter { $0.status == "valid" && !$0.transferred }
    }

    /// Najvec prijateljev za izbiro: N-1 (kupcu ostane ena vstopnica); 0 pri eni sami vstopnici.
    static func najvecPrijateljev(vstopnic: Int) -> Int {
        max(0, vstopnic - 1)
    }

    /// Meja izbire za nakup (po `moje`).
    static func meja(_ vstopnice: [APITicket]) -> Int {
        najvecPrijateljev(vstopnic: moje(vstopnice).count)
    }

    /// Vstopnice za posiljanje: vse razen PRVE (ta ostane kupcu), v vrstnem redu nakupa.
    static func zaPosiljanje(_ vstopnice: [APITicket]) -> [APITicket] {
        Array(moje(vstopnice).dropFirst())
    }

    /// Izbrani prijatelji po vrstnem redu izbire (`ids`); neznani id-ji in podvojeni se preskocijo.
    static func prijateljiIzIdjev(_ ids: [Int], _ prijatelji: [FriendUser]) -> [FriendUser] {
        var poId: [Int: FriendUser] = [:]
        for f in prijatelji { poId[f.id] = f }
        var videni = Set<Int>()
        return ids.compactMap { id in
            guard videni.insert(id).inserted else { return nil }
            return poId[id]
        }
    }

    /// Prijatelj + vstopnica, ki jo dobi.
    struct Par: Equatable {
        let prijatelj: FriendUser
        let vstopnicaId: Int
    }

    /// Prvi izbrani dobi drugo vstopnico, drugi tretjo ... Prijatelji brez proste vstopnice (nad mejo) se ne uparijo.
    static func pari(prijatelji: [FriendUser], vstopnice: [APITicket]) -> [Par] {
        zip(prijatelji, zaPosiljanje(vstopnice)).map { Par(prijatelj: $0.0, vstopnicaId: $0.1.id) }
    }

    struct Neuspeh: Equatable {
        let par: Par
        /// Ze preveden (`userMessage`).
        let sporocilo: String
    }

    struct Izid: Equatable {
        var poslani: [Par] = []
        var neuspeli: [Neuspeh] = []
        /// `min_age` iz 400 `age_confirmation_required` (pokazi kljukico in ponovi); nil = te napake ni bilo.
        var zahtevaStarost: Int? = nil

        var jePopoln: Bool { neuspeli.isEmpty }
    }

    /// Napaka, ki bi pri vseh preostalih posiljanjih ponovila isto (brez povezave, potekla seja, navala, omejitev klicev):
    /// ostalih ne poskusamo, ampak jih oznacimo kot neposlane z istim sporocilom.
    static func prekineVse(_ napaka: Error) -> Bool {
        if napaka is URLError || napaka is CancellationError { return true }
        if let api = napaka as? APIError, case let .requestFailed(koda, _) = api {
            return koda == 401 || koda == 429 || koda == 503 || koda == -1
        }
        return false
    }

    /// Posilja ZAPOREDNO (ne vzporedno): za vsak par pokliče `posli`. Napaka enega para ne ustavi ostalih (vsak prijatelj ima svojo
    /// vstopnico), razen ce je `prekineVse`. Neuspeli pari ostanejo pri kupcu v Tickets in se lahko ponovijo.
    static func razdeli(_ pari: [Par], posli: (Par) async throws -> Void) async -> Izid {
        var izid = Izid()
        var i = 0
        while i < pari.count {
            let par = pari[i]
            i += 1
            do {
                try await posli(par)
                izid.poslani.append(par)
            } catch {
                if let n = PrenosStarosti.izNapake(error) { izid.zahtevaStarost = n }
                let sporocilo = error.userMessage
                izid.neuspeli.append(Neuspeh(par: par, sporocilo: sporocilo))
                if prekineVse(error) {
                    while i < pari.count {
                        izid.neuspeli.append(Neuspeh(par: pari[i], sporocilo: sporocilo))
                        i += 1
                    }
                }
            }
        }
        return izid
    }
}
