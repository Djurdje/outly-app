import Foundation

/// Besedila in pravila prikaza guest liste (cisto, brez SwiftUI, da jih testi preverijo).
enum GuestListPrikaz {
    /// »Spots left: 3 of 5« (prosta mesta od vseh).
    static func mestaOpis(_ g: GuestList) -> String {
        String(localized: "Spots left: \(g.remaining) of \(g.spots)")
    }

    /// Gumb v listu za povabilo: »Invite 2 friends« (mnozina po jeziku), brez izbire »Invite friends«.
    static func gumbPovabi(izbranih: Int) -> String {
        izbranih <= 0 ? String(localized: "Invite friends") : String(localized: "Invite \(izbranih) friends")
    }

    /// Zakaj povabila ni mogoce (lista zaprta ali polna); nil = povabilo je mogoce.
    static func zakajNeVabi(_ g: GuestList) -> String? {
        if g.event.jeOdpovedan { return String(localized: "This event was cancelled.") }
        if !g.canInvite { return String(localized: "This guest list is closed.") }
        if g.remaining <= 0 { return String(localized: "All spots are taken. Remove a friend to free one up.") }
        return nil
    }

    /// »Checked in« / »Invited« za povabljenega.
    static func statusPovabljenega(_ i: GuestListInvited) -> String {
        i.jeVstopil ? String(localized: "Checked in") : String(localized: "Invited")
    }

    /// Vstopnica gostitelja med mojimi vstopnicami (GET /me/tickets) ali nil, ce je se ni (osvezitev, brez signala).
    static func gostiteljevaVstopnica(_ g: GuestList, med vstopnice: [APITicket]) -> APITicket? {
        guard let id = g.myTicketId else { return nil }
        return vstopnice.first { $0.id == id }
    }
}
