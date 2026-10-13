import Foundation

/// Demo klubi (outly-backend#243, odlocitev 13. 10. 2026): izmisljeni klubi za predstavitev, ki so oznaceni `is_demo` in
/// vstopnic ne prodajajo. Streznik je merodajen: `POST /events/:id/orders` in `POST /events/:id/tables/:tableId/orders` za demo
/// vrneta 409 `{"error":"demo_club","message":"This is a demo club. Tickets can't be bought."}`; izjema je vloga `admin`
/// (`Me.isAdmin`), ki jo streznik spusti. Aplikacija samo skrije nakup, da kupec ne pride do 409.
///
/// Demo se ugotovi iz `isDemo`, NE iz `payment_mode`: `unavailable` je lahko tudi `seller_incomplete` / `stripe_not_ready`,
/// odgovor pa je za vse enak (admin vidi `unavailable`, a nakup uspe).
enum DemoKlub {
    /// Besedilo namesto gumba za nakup (isti angleski niz kot na spletu in v odgovoru streznika).
    static var sporocilo: String { String(localized: "This is a demo club. Tickets can't be bought.") }

    /// Namesto gumba za nakup pokazi `sporocilo`: demo klub in uporabnik ni admin.
    static func brezNakupa(isDemo: Bool, jeAdmin: Bool) -> Bool {
        isDemo && !jeAdmin
    }

    /// Prodaja je za tega uporabnika nedosegljiva (gumb skrit / onemogocen). Demo: samo ne-admin (adminu gumb ostane, ne glede
    /// na `payment_mode`, ker streznik admina spusti); sicer odloca `payment_mode` kot doslej.
    static func prodajaNedosegljiva(isDemo: Bool, jeAdmin: Bool, nacin: NacinPlacila) -> Bool {
        if isDemo { return !jeAdmin }
        return nacin.prodajaNedosegljiva
    }
}

extension Me {
    /// Vloga `admin` (GET /me `role`); strezniku je dovoljeno vse, kar je dovoljeno vlogi (tudi nakup pri demo klubu).
    var isAdmin: Bool { role == "admin" }
}

extension Error {
    /// 409 `demo_club`: dogodek je demo kluba, narocilo NI nastalo (brez stranskih ucinkov). Ni povezano s tlorisom (miza je prosta)
    /// in ni nerazresen izid kljuca (`nakupniIzid` = `.navadna`).
    var jeDemoKlub: Bool {
        guard let api = self as? APIError, case .requestFailed(let code, let raw) = api, code == 409 else { return false }
        return raw.lowercased().contains("demo_club")
    }
}
