import Foundation

// Kaj vratar vidi po skenu: barva, naslov, podnaslov, VIP vrstica. Cisto besedilo (brez SwiftUI), da ga testi preverijo.

struct SkenPrikaz: Equatable {
    var barva: SkenSodba.Barva
    /// Ze preveden naslov (velike crke).
    var naslov: String
    var podnaslov: String = ""
    /// "VIP · Table T1 · paket" ali nil.
    var vip: String? = nil
    /// Pojasnilo pod naslovom (npr. "ni na seznamu"), ki ne sme zginiti.
    var opomba: String? = nil
    /// Rumeno: vratar sme gosta spustiti sam (sken gre v vrsto in ga streznik preveri naknadno).
    var ponudiVstop: Bool = false
    /// Surova koda, za gumb »Let in«.
    var qr: String? = nil

    /// Za zvok/haptiko.
    var uspesen: Bool { barva == .zeleno }

    static func cas(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    /// Iz lokalne odlocitve.
    static func iz(_ s: SkenSodba, qr: String) -> SkenPrikaz {
        let ime = s.vstopnica?.holderUsername ?? ""
        var vip: String? = nil
        if let v = s.vstopnica, v.isVip {
            vip = VipOznaka.vrstica(tableLabel: v.tableLabel, packageName: v.packageName)
        }
        switch s.razlog {
        case .veljavna:
            return SkenPrikaz(barva: .zeleno, naslov: String(localized: "WELCOME IN"), podnaslov: ime, vip: vip)
        case .veljavnaNiNaSeznamu:
            return SkenPrikaz(barva: .zeleno, naslov: String(localized: "WELCOME IN"),
                              opomba: String(localized: "Not on the list: bought after the last download. The server checks it when you are back online."))
        case .zeUporabljenaLokalno:
            let t = s.kdaj.map { cas($0) } ?? ""
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "ALREADY SCANNED"),
                              podnaslov: t.isEmpty ? String(localized: "Scanned on this phone.") : String(localized: "Scanned on this phone at \(t)."),
                              vip: vip)
        case .zeUporabljena:
            let t = s.kdaj.map { cas($0) } ?? ""
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "ALREADY SCANNED"),
                              podnaslov: t.isEmpty ? String(localized: "This ticket was already used.") : String(localized: "Already used at \(t)."),
                              vip: vip)
        case .prenesena:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "TICKET TRANSFERRED"),
                              podnaslov: String(localized: "This code is no longer valid: the ticket was sent to someone else."))
        case .vrnjena:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "REFUNDED"),
                              podnaslov: String(localized: "This ticket was refunded."))
        case .preklicana:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "CANCELLED"),
                              podnaslov: String(localized: "This ticket was cancelled."))
        case .napacenDogodek:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "WRONG EVENT"),
                              podnaslov: String(localized: "This ticket is for a different event."))
        case .neveljavna:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "INVALID CODE"),
                              podnaslov: String(localized: "This is not a valid Outly ticket."))
        case .staraKoda:
            return SkenPrikaz(barva: .rumeno, naslov: String(localized: "OLD CODE"),
                              podnaslov: String(localized: "This ticket has an old code. It can only be checked with a connection."),
                              ponudiVstop: true, qr: qr)
        case .manjkaPodatkov:
            return SkenPrikaz(barva: .rumeno, naslov: String(localized: "NO DATA YET"),
                              podnaslov: String(localized: "The ticket list is not downloaded yet. It can only be checked with a connection."),
                              ponudiVstop: true, qr: qr)
        }
    }

    /// Iz odgovora POST /business/tickets/scan (spletni sken: stara koda ali ni podatkov, a je povezava).
    static func iz(_ r: ScanResult) -> SkenPrikaz {
        var vip: String? = nil
        if let t = r.ticket, t.isVip {
            vip = VipOznaka.vrstica(tableLabel: t.tableLabel, packageName: t.packageName)
        }
        if r.result == "ok" {
            return SkenPrikaz(barva: .zeleno, naslov: String(localized: "WELCOME IN"), podnaslov: r.message, vip: vip)
        }
        let naslov: String
        switch r.result {
        case "already_used": naslov = String(localized: "ALREADY SCANNED")
        case "wrong_club": naslov = String(localized: "WRONG CLUB")
        case "unknown": naslov = String(localized: "UNKNOWN TICKET")
        case "unpaid": naslov = String(localized: "NOT PAID")
        default: naslov = String(localized: "REFUSED")
        }
        return SkenPrikaz(barva: .rdece, naslov: naslov, podnaslov: r.message, vip: vip)
    }

    /// Vratar je gosta spustil sam (stara koda brez povezave).
    static func spusceniRocno() -> SkenPrikaz {
        SkenPrikaz(barva: .zeleno, naslov: String(localized: "LET IN"),
                   opomba: String(localized: "Not checked yet. The server checks this ticket when you are back online."))
    }

    /// Zakaj streznik sken, ki je bil na telefonu zelen, ni potrdil.
    static func razlogKonflikta(_ result: String) -> String {
        switch result {
        case "already_used": return String(localized: "Already used: the server had this ticket scanned first.")
        case "transferred": return String(localized: "The ticket was transferred to someone else.")
        case "wrong_club": return String(localized: "The ticket is for another club.")
        case "unknown": return String(localized: "The server does not know this ticket.")
        case "unpaid": return String(localized: "The order is not paid.")
        case "refunded": return String(localized: "The ticket was refunded.")
        case "void": return String(localized: "The ticket was cancelled.")
        case "invalid": return String(localized: "The server rejected the code.")
        default: return String(localized: "The server did not confirm this entry.")
        }
    }
}
