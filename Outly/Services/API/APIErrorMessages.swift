import Foundation

/// Prevod napak streznika v sporocila za uporabnika.
/// Pravilo: uporabnik nikoli ne vidi surovega besedila streznika ali stevilke napake.
extension Error {
    var userMessage: String {
        if let api = self as? APIError { return api.userMessage }
        if let sb = self as? SupabaseAuthError { return sb.userMessage }
        if let url = self as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return String(localized: "No internet connection. Check your network and try again.")
            case .timedOut:
                return String(localized: "The server took too long to respond. Please try again.")
            default:
                return String(localized: "Connection problem. Please try again.")
            }
        }
        return String(localized: "Something went wrong. Please try again.")
    }
}

extension APIError {
    var userMessage: String {
        switch self {
        case .invalidURL, .decodingFailed:
            return String(localized: "Unexpected response from the server. Please try again later.")
        case .requestFailed(let code, let raw):
            return APIError.translate(code: code, raw: raw)
        }
    }

    /// Znana sporocila backenda (index.js) -> razumljiva sporocila.
    private static func translate(code: Int, raw: String) -> String {
        let t = raw.lowercased()

        // Najprej po vsebini, ker je ista koda (400) uporabljena za vec razlicnih stvari.
        if t.contains("invalid or expired code")        { return String(localized: "The code is wrong or has expired. Request a new one.") }
        if t.contains("too many attempts")              { return String(localized: "Too many wrong attempts. Request a new code.") }
        if t.contains("code must be 6 digits")          { return String(localized: "Enter the code from the email.") }
        if t.contains("password too short")             { return String(localized: "Password must be at least 8 characters.") }
        if t.contains("email not verified")             { return String(localized: "Your email is not verified yet.") }
        if t.contains("locked")                         { return String(localized: "Too many failed logins. Try again in 15 minutes.") }
        if t.contains("invalid credentials")            { return String(localized: "Wrong email or password.") }
        if t.contains("username too short")             { return String(localized: "Username must be at least 3 characters.") }
        if t.contains("username too long")              { return String(localized: "Username can have at most 20 characters.") }
        if t.contains("username invalid")               { return String(localized: "Username can contain only letters, numbers and underscore.") }
        if t.contains("username already in use")        { return String(localized: "That username is already taken.") }
        if t.contains("phone must be")                  { return String(localized: "Enter the phone number with country code, e.g. +386 41 123 456.") }
        if t.contains("phone number already in use")    { return String(localized: "That phone number is already used by another account.") }
        if t.contains("new password must be different")   { return String(localized: "New password must be different from the current one.") }
        if t.contains("club name is required")          { return String(localized: "Enter the club name.") }
        if t.contains("lat and lng")                    { return String(localized: "Location could not be saved. Try again.") }
        if t.contains("invalid club data")              { return String(localized: "Some club data is out of range. Check the values and try again.") }
        if t.contains("invalid value type")             { return String(localized: "Please check what you entered and try again.") }
        if t.contains("refresh token")                  { return String(localized: "Your session has expired. Please log in again.") }
        if t.contains("invalid token") || t.contains("missing token") { return String(localized: "Your session has expired. Please log in again.") }
        if t.contains("auth service unavailable")       { return String(localized: "Sign-in service is temporarily unavailable. Please try again.") }
        if t.contains("identity provider")              { return String(localized: "Please sign out and sign in again, then retry.") }
        if t.contains("could not delete the account")   { return String(localized: "Could not delete the account right now. Please try again.") }
        if t.contains("at least 15 years")              { return String(localized: "You must be at least 15 years old to use Outly.") }
        if t.contains("title is required")              { return String(localized: "Enter a title.") }
        if t.contains("startat must be")                { return String(localized: "Enter a valid start date.") }
        if t.contains("endat must be")                  { return String(localized: "Enter a valid end date.") }
        if t.contains("ticketpricecents")               { return String(localized: "Enter the price as a number, e.g. 12.50.") }
        if t.contains("minage must be")                 { return String(localized: "Minimum age must be between 0 and 99.") }
        if t.contains("status must be")                 { return String(localized: "Invalid event status.") }
        if t.contains("own club")                       { return String(localized: "You can only manage events of your own club.") }
        if t.contains("club not found")                 { return String(localized: "Your club is not set up yet.") }
        if t.contains("event not found")                { return String(localized: "This event no longer exists.") }
        if t.contains("sold tickets and was cancelled") { return String(localized: "Tickets were already sold, so the event was cancelled instead of deleted.") }
        if t.contains("dateofbirth") || t.contains("date of birth") {
            if t.contains("future")     { return String(localized: "Date of birth cannot be in the future.") }
            if t.contains("plausible")  { return String(localized: "That date of birth does not look right.") }
            return String(localized: "Enter a valid date of birth.")
        }
        if t.contains("country must be")                { return String(localized: "Choose your country.") }
        if t.contains("unknown_genres")                 { return String(localized: "One of the selected genres is not available. Reload and try again.") }
        if t.contains("genres must be")                 { return String(localized: "Select at least one genre.") }
        if t.contains("nothing to update")              { return String(localized: "Nothing to save.") }
        if t.contains("password required")              { return String(localized: "Enter your password to continue.") }
        // Prosnja za poslovni racun (POST /creator-applications)
        if t.contains("already pending")                { return String(localized: "You already have an application waiting for review.") }
        if t.contains("businessname is required")       { return String(localized: "Enter the business name (at least 2 characters).") }
        if t.contains("contactname is required")        { return String(localized: "Enter the contact person's name.") }
        if t.contains("phone must contain")             { return String(localized: "Enter a valid phone number, e.g. +386 41 123 456.") }
        if t.contains("invalid application data")       { return String(localized: "Please check what you entered and try again.") }
        // Prenos vstopnice (POST /tickets/:id/transfer)
        if t.contains("valid email is required")        { return String(localized: "Enter your friend's email address.") }
        if t.contains("no outly account with this email") { return String(localized: "No Outly account with this email. Ask your friend to sign up first.") }
        if t.contains("already hold this ticket")       { return String(localized: "That is your own email.") }
        if t.contains("not verified yet")               { return String(localized: "Your friend's account is not verified yet.") }
        if t.contains("must add a date of birth")       { return String(localized: "Your friend must add a date of birth in the app before receiving this ticket.") }
        if t.contains("friend must be at least")        { return String(localized: "Your friend is too young for this event.") }
        if t.contains("already used")                   { return String(localized: "This ticket was already used.") }
        if t.contains("ticket not found")               { return String(localized: "This ticket is not available anymore.") }
        if t.contains("no longer valid")                { return String(localized: "This ticket is no longer valid.") }
        // Ekipa in vabila (migracija 013)
        if t.contains("already_invited") || t.contains("pending invitation") { return String(localized: "This person already has a pending invitation from your club.") }
        if t.contains("already in the team") || t.contains("already_member") || t.contains("already in a club team") || t.contains("another club's team") {
            return t.contains("you are") ? String(localized: "You are already in a club team. Leave it first.") : String(localized: "This person is already in a club team.")
        }
        if t.contains("is_owner") || t.contains("owns the club") || t.contains("owns another club") || t.contains("own a club and") {
            return t.contains("you own") ? String(localized: "You own a club, so you can't join another team.") : String(localized: "This person owns a club and can't join a team.")
        }
        if t.contains("only the club owner can")        { return String(localized: "Only the club owner can do that.") }
        if t.contains("invitation not found")           { return String(localized: "This invitation is no longer available.") }
        if t.contains("not in a club team")             { return String(localized: "You are not in a club team.") }
        // Vstopnice
        if t.contains("quantity must be")               { return String(localized: "Choose between 1 and 10 tickets.") }
        // VIP mize (POST /events/:id/tables/:tableId/orders)
        if t.contains("already booked")                 { return String(localized: "This table is already booked.") }
        if t.contains("price has changed")              { return String(localized: "The table price has changed. Check the new price and try again.") }
        if t.contains("choose a bottle package") || t.contains("package does not belong") { return String(localized: "Choose a bottle for your table.") }
        if t.contains("table not found")                { return String(localized: "This table is not available anymore.") }
        if t.contains("not on sale")                    { return String(localized: "This event is not on sale.") }
        if t.contains("no tickets on outly")            { return String(localized: "Tickets for this event are not sold on Outly.") }
        if t.contains("already started")                { return String(localized: "This event has already started.") }
        if t.contains("already ended")                  { return String(localized: "This event has already ended.") }
        if t.contains("have not opened")                { return String(localized: "Ticket sales have not opened yet.") }
        if t.contains("sales are closed")               { return String(localized: "Ticket sales are closed.") }
        if t.contains("tickets left") || t.contains("not enough tickets") { return String(localized: "Not enough tickets left.") }
        if t.contains("add your date of birth")         { return String(localized: "Add your date of birth in Personal info to buy tickets.") }
        if t.contains("you must be at least")           { return raw }
        if t.contains("payments are not available")     { return String(localized: "Payments are not available yet.") }
        if t.contains("club_has_orders")                { return String(localized: "Your club has sold tickets. Transfer club ownership before deleting your account.") }
        if t.contains("already exists") || t.contains("already registered") {
            return String(localized: "An account with this email or username already exists.")
        }

        switch code {
        case 400: return String(localized: "Please check what you entered and try again.")
        case 401: return String(localized: "Wrong password or your session has expired.")
        case 403: return String(localized: "You do not have permission to do that.")
        case 404: return String(localized: "Not found.")
        case 409: return String(localized: "This is already in use.")
        case 429: return String(localized: "Too many attempts. Please wait a while and try again.")
        case 500...599: return String(localized: "The server is having trouble. Please try again later.")
        case -1: return String(localized: "No response from the server. Check your connection.")
        default: return String(localized: "Something went wrong. Please try again.")
        }
    }
}

// MARK: - Naval pri nakupu (503)

/// Backend (semafor nakupov, outly-backend #111) ob navali odgovori 503 + `Retry-After: 5`, ko nakup
/// ne dobi mesta v vrsti ali baza ne pride do povezave. Velja SAMO za nakupna zaslona (vstopnice, VIP
/// mize): drugje ostane 503 splosno sporocilo (`userMessage`). Nakupa se NE ponavlja samodejno: uporabnik
/// pritisne znova, in ker nakup nosi `Idempotency-Key` (NakupniKljuc, outly-backend #112), je to varno.
enum NavalNakupa {
    /// Kako dolgo je gumb za nakup onemogocen po 503. `Retry-After` iz glave `send()` ne vrne, zato
    /// privzeta vrednost backenda (5 s).
    static let premorNanosekund: UInt64 = 5_000_000_000
}

extension Error {
    /// 503 pri nakupu, ki ga je sprozila naval. Pozitivno ujemanje telesa (backend #111: semafor
    /// "Too many purchases at once.", "Server busy.", "Service temporarily unavailable."); vse drugo
    /// (HTML ob izpadu Renderja, "Payments are not available", "Auth service unavailable") ostane
    /// pri `userMessage`.
    var jeNavalNakupa: Bool {
        guard let api = self as? APIError, case .requestFailed(let code, let raw) = api, code == 503 else { return false }
        let t = raw.lowercased()
        return t.contains("too many purchases") || t.contains("server busy") || t.contains("service temporarily unavailable")
    }

    /// Vsak 503 pri nakupu: gumb je kratek cas onemogocen (nakupa se ne ponavlja samodejno).
    var jeNakup503: Bool {
        guard let api = self as? APIError, case .requestFailed(let code, _) = api else { return false }
        return code == 503
    }

    /// Sporocilo za nakupna zaslona: izidi, ki jih doloca idempotentni kljuc (NakupniKljuc), naval -> posebno
    /// sporocilo, sicer enako kot `userMessage`. Kljucni izidi so PRED `userMessage`, ker bi ga `translate`
    /// ("already used") sicer pomotoma prevedel kot »This ticket was already used.« (ali 409 kot »already booked«).
    var nakupUserMessage: String {
        switch nakupniIzid {
        case .kljucZavrzen:
            return String(localized: "Something changed, please try again.")
        case .vObdelavi:
            return String(localized: "Your previous attempt is still being processed. Please try again in a moment.")
        case .narociloNeaktivno:
            return String(localized: "Your previous order is no longer active. Tap again to buy anew.")
        case .nejasen:
            return String(localized: "Your purchase may have gone through — tap the button again to check (you won't be charged twice).")
        case .navadna:
            break
        }
        if jeNavalNakupa {
            return String(localized: "Lots of people are buying right now. Please try again in a few seconds.")
        }
        return userMessage
    }
}
