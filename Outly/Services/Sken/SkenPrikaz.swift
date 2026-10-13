import Foundation

// Kaj vratar vidi po skenu: barva, naslov, podnaslov, VIP vrstica. Cisto besedilo (brez SwiftUI), da ga testi preverijo.

struct SkenPrikaz: Equatable {
    var barva: SkenSodba.Barva
    /// Ze preveden naslov (velike crke).
    var naslov: String
    var podnaslov: String = ""
    /// "VIP · Table T1 · paket" ali nil.
    var vip: String? = nil
    /// "Guest list · @host" ali nil (backend 8. 10. 2026): vstopnica gostitelja ali povabljenega prijatelja.
    var guestList: String? = nil
    /// Pojasnilo pod naslovom (npr. "ni na seznamu"), ki ne sme zginiti.
    var opomba: String? = nil
    /// Rumeno: vratar sme gosta spustiti sam (sken gre v vrsto in ga streznik preveri naknadno).
    var ponudiVstop: Bool = false
    /// Surova koda, za gumb »Let in«.
    var qr: String? = nil

    /// »Guest list · @host« (brez gostitelja samo »Guest list«); nil, ce vstopnica ni z guest liste.
    static func guestListOznaka(isGuestList: Bool, host: String?) -> String? {
        guard isGuestList else { return nil }
        if let host, !host.isEmpty { return String(localized: "Guest list · @\(host)") }
        return String(localized: "Guest list")
    }

    /// Za zvok/haptiko.
    var uspesen: Bool { barva == .zeleno }

    static func cas(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    /// Cas prenosa seznama: samo ura, ce je danes, sicer datum in ura (M11).
    static func casPrenosa(_ d: Date, zdaj: Date = Date(), koledar: Calendar = .current) -> String {
        if koledar.isDate(d, inSameDayAs: zdaj) { return cas(d) }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    /// Iz lokalne odlocitve.
    static func iz(_ s: SkenSodba, qr: String) -> SkenPrikaz {
        let ime = s.vstopnica?.holderUsername ?? ""
        var vip: String? = nil
        if let v = s.vstopnica, v.isVip {
            vip = VipOznaka.vrstica(tableLabel: v.tableLabel, packageName: v.packageName)
        }
        let gl = s.vstopnica.flatMap { guestListOznaka(isGuestList: $0.isGuestList, host: $0.guestListHostUsername) }
        switch s.razlog {
        case .veljavna:
            return SkenPrikaz(barva: .zeleno, naslov: String(localized: "WELCOME IN"), podnaslov: ime, vip: vip, guestList: gl)
        case .veljavnaNiNaSeznamu:
            return SkenPrikaz(barva: .zeleno, naslov: String(localized: "WELCOME IN"),
                              opomba: String(localized: "Not on the list: bought after the last download. The server checks it when you are back online."))
        case .zeUporabljenaLokalno:
            let t = s.kdaj.map { cas($0) } ?? ""
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "ALREADY SCANNED"),
                              podnaslov: t.isEmpty ? String(localized: "Scanned on this phone.") : String(localized: "Scanned on this phone at \(t)."),
                              vip: vip, guestList: gl)
        case .zeUporabljena:
            let t = s.kdaj.map { cas($0) } ?? ""
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "ALREADY SCANNED"),
                              podnaslov: t.isEmpty ? String(localized: "This ticket was already used.") : String(localized: "Already used at \(t)."),
                              vip: vip, guestList: gl)
        case .prenesena:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "TICKET TRANSFERRED"),
                              podnaslov: String(localized: "This code is no longer valid: the ticket was sent to someone else."))
        case .vrnjena:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "REFUNDED"),
                              podnaslov: String(localized: "This ticket was refunded."))
        case .preklicana:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "CANCELLED"),
                              podnaslov: String(localized: "This ticket was cancelled."))
        case .neplacana:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "NOT PAID"),
                              podnaslov: String(localized: "The order for this ticket is not paid."))
        case .placiloVSporu:
            return placiloVSporu(vip: vip, guestList: gl)
        case .napacenDogodek:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "WRONG EVENT"),
                              podnaslov: String(localized: "This ticket is for a different event."))
        case .nijeZaDanes:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "NOT TODAY'S EVENT"),
                              podnaslov: String(localized: "This ticket is not for today's event."))
        case .neveljavna:
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "INVALID CODE"),
                              podnaslov: String(localized: "This is not a valid Outly ticket."))
        case .staraKoda:
            return SkenPrikaz(barva: .rumeno, naslov: String(localized: "OLD CODE"),
                              podnaslov: String(localized: "This ticket has an old code. It can only be checked with a connection."),
                              ponudiVstop: true, qr: qr)
        case .manjkaPodatkov:
            return SkenPrikaz(barva: .rumeno, naslov: String(localized: "NO DATA YET"),
                              podnaslov: String(localized: "The scanner key is not downloaded yet. This ticket can only be checked with a connection."))
        case .kljucNeujema:
            return SkenPrikaz(barva: .rumeno, naslov: String(localized: "KEY OUTDATED"),
                              podnaslov: String(localized: "The scanner key is out of date. Connect to the internet to update it."))
        }
    }

    /// Iz odgovora POST /business/tickets/scan (spletni sken: stara koda ali ni podatkov, a je povezava).
    static func iz(_ r: ScanResult) -> SkenPrikaz {
        var vip: String? = nil
        if let t = r.ticket, t.isVip {
            vip = VipOznaka.vrstica(tableLabel: t.tableLabel, packageName: t.packageName)
        }
        let gl = r.ticket.flatMap { guestListOznaka(isGuestList: $0.isGuestList, host: $0.guestListHostUsername) }
        if r.result == "ok" {
            return SkenPrikaz(barva: .zeleno, naslov: String(localized: "WELCOME IN"), podnaslov: r.message, vip: vip, guestList: gl)
        }
        if r.result == "event_cancelled" { return odpovedanDogodek(vip: vip, guestList: gl) }
        // Namenoma NE uporabimo `r.message`: strezniku besedilo (angleski stavek, enak za vse odjemalce) zavrzemo in pokazemo
        // svoj prevedeni prikaz, da vratar jasno vidi, kaj storiti (gosta napotiti k vodji kluba).
        if r.result == "payment_disputed" { return placiloVSporu(vip: vip, guestList: gl) }
        let naslov: String
        switch r.result {
        case "already_used": naslov = String(localized: "ALREADY SCANNED")
        case "wrong_club": naslov = String(localized: "WRONG CLUB")
        case "unknown": naslov = String(localized: "UNKNOWN TICKET")
        case "unpaid": naslov = String(localized: "NOT PAID")
        case "not_today": naslov = String(localized: "NOT TODAY'S EVENT")
        default: naslov = String(localized: "REFUSED")
        }
        return SkenPrikaz(barva: .rdece, naslov: naslov, podnaslov: r.message, vip: vip, guestList: gl)
    }

    /// Dokoncen odgovor streznika na sken, ki je bil na telefonu zelen (K2: z povezavo odloci streznik).
    /// `sodba` je lokalna sodba (za VIP in ime imetnika pri `ok`).
    static func iz(streznik rezultat: String, usedAt: String?, sodba: SkenSodba) -> SkenPrikaz {
        if rezultat == "ok" { return iz(sodba, qr: "") }
        let t = SkenCas.razcleni(usedAt).map { cas($0) } ?? ""
        switch rezultat {
        case "already_used":
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "ALREADY SCANNED"),
                              podnaslov: t.isEmpty ? String(localized: "This ticket was already used.") : String(localized: "Already used at \(t)."))
        case "transferred": return iz(SkenSodba(razlog: .prenesena, serial: sodba.serial), qr: "")
        case "refunded": return iz(SkenSodba(razlog: .vrnjena, serial: sodba.serial), qr: "")
        case "void": return iz(SkenSodba(razlog: .preklicana, serial: sodba.serial), qr: "")
        case "unpaid": return iz(SkenSodba(razlog: .neplacana, serial: sodba.serial), qr: "")
        // Streznik (okno -12 h ... +6 h, backend #170): dogodek ni danes. Isti prikaz kot lokalni razlog.
        case "not_today": return iz(SkenSodba(razlog: .nijeZaDanes, serial: sodba.serial), qr: "")
        case "event_cancelled": return odpovedanDogodek(vip: nil)
        case "payment_disputed": return placiloVSporu(vip: nil)
        case "wrong_club":
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "WRONG CLUB"), podnaslov: String(localized: "This ticket is for another club."))
        case "unknown":
            return SkenPrikaz(barva: .rdece, naslov: String(localized: "UNKNOWN TICKET"), podnaslov: String(localized: "The server does not know this ticket."))
        default:
            return iz(SkenSodba(razlog: .neveljavna, serial: sodba.serial), qr: "")
        }
    }

    /// Dogodek je odpovedan (backend od 5. 10. 2026, I21): vstopnica ostane placana, a na vratih ne velja vec.
    /// Telefon brez povezave odpovedi ne pozna (seznam nima statusa dogodka), zato pride samo od streznika.
    static func odpovedanDogodek(vip: String?, guestList: String? = nil) -> SkenPrikaz {
        SkenPrikaz(barva: .rdece, naslov: String(localized: "EVENT CANCELLED"),
                   podnaslov: String(localized: "This event was cancelled."), vip: vip, guestList: guestList)
    }

    /// Placilo vstopnice je v sporu pri banki (backend 13. 10. 2026, #232): vstopnica ne velja, gosta napoti k vodji kluba.
    /// Rdece (nikoli rumeno, brez gumba »Let in«): vratar tega gosta ne sme spustiti sam.
    static func placiloVSporu(vip: String?, guestList: String? = nil) -> SkenPrikaz {
        SkenPrikaz(barva: .rdece, naslov: String(localized: "PAYMENT DISPUTED"),
                   podnaslov: String(localized: "Ticket not valid. Send the guest to the club manager."), vip: vip, guestList: guestList)
    }

    /// Streznik je povedal, da uporabnik ni vec v ekipi kluba (404 »Club not found.« / 403 »Forbidden.«).
    static func brezDostopa() -> SkenPrikaz {
        SkenPrikaz(barva: .rdece, naslov: String(localized: "NO ACCESS"),
                   podnaslov: String(localized: "You are no longer on this club's team. Nobody is let in from this phone."))
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
        case "event_cancelled": return String(localized: "This event was cancelled.")
        case "not_today": return String(localized: "This ticket is not for today's event.")
        case "payment_disputed": return String(localized: "The payment is disputed: this guest was let in, but the ticket is not valid.")
        case "invalid": return String(localized: "The server rejected the code.")
        default: return String(localized: "The server did not confirm this entry.")
        }
    }
}
