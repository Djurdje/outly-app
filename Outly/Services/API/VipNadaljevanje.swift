import Foundation

/// Vrnitev na placilo VIP mize po zaprtju nakupnega lista (outly-app#59).
///
/// Miza s `pending` narocilom je v backendu ZASEDENA (`VIP_ZASEDENA_STANJA`), zato je ob ponovnem odprtju lista v tlorisu `available == false`
/// in je kupec ne more izbrati, cetudi bi backend ponovitev z ISTIM `Idempotency-Key` sprejel (isto narocilo, isti `checkout_url`).
/// List zato, ko ima nerazresen poskus (`NakupniKljucShramba.odprtaVsebina`) za mizo, ki ni vec prosta, prebere moja narocila
/// (GET /me/orders) in tu razvrsti, kaj se je z narocilom zgodilo. Mizo predizbere SAMO, ce na njej caka moje narocilo:
/// tuje zasedene mize ne izberemo nikoli, kljuc pa je ze po zasnovi vezan na (dogodek, miza, paket) in ga druga miza ne dobi.
///
/// Cisti tip brez UI-ja (testabilen). Stanja `.vObdelavi` in `.poteklo` kljuca NE pozabita (ponovitev ga razresi na strezniku:
/// placano -> 201, preklicano -> 409 `order_not_active` -> nov kljuc; enak vzorec kot pri vstopnicah, backend#203).
enum VipNadaljevanje: Equatable {
    /// Moje narocilo mize caka na placilo (`pending`, seja se velja): predizbira mize in gumb »Continue to payment« (isti kljuc).
    case nadaljuj
    /// Moje narocilo je placano in ima vstopnice: pokazi uspesni zaslon (kupec je placal, pa uspeha ni videl).
    case placano
    /// Kupec je placal, banka denarja se ni potrdila (`payment_processing`): sporocilo, brez novega placila.
    case vObdelavi
    /// Stripova seja je potekla, narocilo je se `pending` (miza se sprosti po pospravljanju): sporocilo, brez povezave.
    case poteklo
    /// Na tej mizi ni mojega aktivnega narocila (preklicano/neplacano ali mizo je zasedel nekdo drug): kljuc se zavrze, miza ostane »Booked«.
    case ni
    /// Ni gotovo (placano brez vstopnic, ki se niso zapisane): nic ne spremenimo, ostane napotek »Check Profile -> Tickets«.
    case nejasno

    /// Razvrstitev in (pri `.placano`) narocilo za uspesni zaslon.
    struct Izid {
        let stanje: VipNadaljevanje
        let narocilo: APIOrder?
    }

    /// Stanja narocila, v katerih backend mizo drzi zasedeno (`VIP_ZASEDENA_STANJA`).
    private static let zasedenaStanja: Set<String> = ["pending", "paid", "partially_refunded"]

    /// Razvrsti narocila (GET /me/orders) za mizo `mizaId` dogodka `dogodekId`. Backend dovoli kvecjemu eno zasedeno narocilo na
    /// (dogodek, miza) (unikatni indeks), zato je izbira prvega zadetka enolicna.
    static func razvrsti(narocila: [APIOrder], dogodekId: Int, mizaId: Int) -> Izid {
        let zadetek = narocila.first {
            $0.eventId == dogodekId && $0.tableId == mizaId && zasedenaStanja.contains($0.status)
        }
        guard let n = zadetek else { return Izid(stanje: .ni, narocilo: nil) }
        if n.status == "pending" {
            if n.paymentProcessing { return Izid(stanje: .vObdelavi, narocilo: nil) }
            if n.checkoutExpired { return Izid(stanje: .poteklo, narocilo: nil) }
            return Izid(stanje: .nadaljuj, narocilo: nil)
        }
        // paid | partially_refunded: uspeh samo z vstopnicami (webhook jih zapise skupaj s placilom; prazen seznam = prehodno).
        if n.tickets.isEmpty { return Izid(stanje: .nejasno, narocilo: nil) }
        return Izid(stanje: .placano, narocilo: n)
    }

    /// Odgovor za obstojeci uspesni zaslon iz placanega narocila (`mode` "test" ohrani oznako TEST pri testnih narocilih).
    static func odgovor(_ narocilo: APIOrder) -> PurchaseResponse {
        PurchaseResponse(mode: narocilo.isTest ? "test" : "stripe", order: narocilo, tickets: narocilo.tickets, checkoutUrl: nil)
    }

    /// Ali sme list pri odprtju ostati na izbrani mizi, ki ni vec prosta: samo, ce je njena nerazresena vsebina enaka
    /// (isti dogodek in miza) in je kljuc se zivo. Uporablja se tudi pri osvezitvi tlorisa (`naloziVip`).
    static func jeMojaMiza(odprta: NakupniKljuc.Vsebina?, dogodekId: Int, mizaId: Int) -> Bool {
        guard let o = odprta else { return false }
        return o.dogodekId == dogodekId && o.mizaId == mizaId
    }
}
