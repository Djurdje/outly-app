import Foundation

/// Podatki prodajalca (kluba) pred nakupom in na potrdilu (outly-backend#94 / #101; ZVPot-1 18/1-2, 130/1-1).
/// Prodajalec je klub `events.club_id` (pri gostovanem dogodku organizator, ne prizorisce); Outly je posrednik. Izjema: uradni
/// profil Outly (`isPlatform`, backend I50) - prodaja NEXT DIMENSIONS sama, brez posrednika.
/// Backend ga vrne v `seller` pri GET /events/:id, GET /events/:id/vip in GET /clubs/:id (ne v seznamih).
/// Star backend objekta nima -> `seller == nil` in zaslon se obnasa kot doslej.
/// Vsa polja imajo privzeto vrednost (trdo pravilo 2): manjkajoc ali napacen kljuc ne podre dekodiranja.
struct Seller: Codable, Equatable {
    /// `legal_name`, ce prazen ime kluba.
    var name: String
    /// Sedez; lahko "".
    var address: String
    var registrationNumber: String
    var taxNumber: String
    /// true = zavezanec za DDV, false = ni zavezanec, nil = ni vpisano.
    var vatPayer: Bool?
    var phone: String
    var email: String
    /// Backend: firma, sedez, maticna, davcna, DDV status in (telefon ali e-naslov) so izpolnjeni.
    var complete: Bool
    /// Prodajalec je platforma sama (uradni profil Outly, NEXT DIMENSIONS; backend I50, PR #302): polje `is_platform: true` pride
    /// SAMO takrat, pri navadnem klubu ga ni (-> false). Takrat Outly NI posrednik in zaslon tega ne sme pisati.
    var isPlatform: Bool

    enum CodingKeys: String, CodingKey {
        case name, address, phone, email, complete
        case registrationNumber = "registration_number"
        case taxNumber = "tax_number"
        case vatPayer = "vat_payer"
        case isPlatform = "is_platform"
    }

    init(name: String = "", address: String = "", registrationNumber: String = "", taxNumber: String = "",
         vatPayer: Bool? = nil, phone: String = "", email: String = "", complete: Bool = false, isPlatform: Bool = false) {
        self.name = name
        self.address = address
        self.registrationNumber = registrationNumber
        self.taxNumber = taxNumber
        self.vatPayer = vatPayer
        self.phone = phone
        self.email = email
        self.complete = complete
        self.isPlatform = isPlatform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name               = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        address            = (try? c.decodeIfPresent(String.self, forKey: .address)) ?? ""
        registrationNumber = (try? c.decodeIfPresent(String.self, forKey: .registrationNumber)) ?? ""
        taxNumber          = (try? c.decodeIfPresent(String.self, forKey: .taxNumber)) ?? ""
        vatPayer           = (try? c.decodeIfPresent(Bool.self, forKey: .vatPayer)) ?? nil
        phone              = (try? c.decodeIfPresent(String.self, forKey: .phone)) ?? ""
        email              = (try? c.decodeIfPresent(String.self, forKey: .email)) ?? ""
        complete           = (try? c.decodeIfPresent(Bool.self, forKey: .complete)) ?? false
        isPlatform         = (try? c.decodeIfPresent(Bool.self, forKey: .isPlatform)) ?? false
    }

    // MARK: - Besedila za prikaz

    /// Vrstica DDV pod skupnim zneskom (#101): izbira po `vat_payer`; brez prodajalca (star backend) kot `nil`.
    /// Ne pise »Prices include VAT« brezpogojno, ker klub morda ni zavezanec za DDV.
    static func ddvBesedilo(_ seller: Seller?) -> String {
        switch seller?.vatPayer {
        case true?:
            return String(localized: "Prices include VAT")
        case false?:
            return String(localized: "The seller is not a VAT payer")
        default:
            return String(localized: "VAT according to the seller's VAT status")
        }
    }

    /// »Reg. no. X · Tax no. Y« (kar ni prazno); "" ce nobene ni.
    var registracijaVrstica: String {
        var deli: [String] = []
        let reg = registrationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let dav = taxNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reg.isEmpty { deli.append(String(localized: "Reg. no. \(reg)")) }
        if !dav.isEmpty { deli.append(String(localized: "Tax no. \(dav)")) }
        return deli.joined(separator: " · ")
    }

    /// Telefon in e-naslov (kar ni prazno), locena s pikico; "" ce nobenega ni.
    var stikVrstica: String {
        [phone, email]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Ime za vrstico »Sold by …« (prazno ime = vrstice ne kazemo).
    var imeProdajalca: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}
