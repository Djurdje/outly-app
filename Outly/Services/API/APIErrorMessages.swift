import Foundation

/// Prevod napak streznika v sporocila za uporabnika.
/// Pravilo: uporabnik nikoli ne vidi surovega besedila streznika ali stevilke napake.
extension Error {
    var userMessage: String {
        if let api = self as? APIError { return api.userMessage }
        if let url = self as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "No internet connection. Check your network and try again."
            case .timedOut:
                return "The server took too long to respond. Please try again."
            default:
                return "Connection problem. Please try again."
            }
        }
        return "Something went wrong. Please try again."
    }
}

extension APIError {
    var userMessage: String {
        switch self {
        case .invalidURL, .decodingFailed:
            return "Unexpected response from the server. Please try again later."
        case .requestFailed(let code, let raw):
            return APIError.translate(code: code, raw: raw)
        }
    }

    /// Znana sporocila backenda (index.js) -> razumljiva sporocila.
    private static func translate(code: Int, raw: String) -> String {
        let t = raw.lowercased()

        // Najprej po vsebini, ker je ista koda (400) uporabljena za vec razlicnih stvari.
        if t.contains("invalid or expired code")        { return "The code is wrong or has expired. Request a new one." }
        if t.contains("too many attempts")              { return "Too many wrong attempts. Request a new code." }
        if t.contains("code must be 6 digits")          { return "Enter the 6-digit code from the email." }
        if t.contains("password too short")             { return "Password must be at least 8 characters." }
        if t.contains("email not verified")             { return "Your email is not verified yet." }
        if t.contains("locked")                         { return "Too many failed logins. Try again in 15 minutes." }
        if t.contains("invalid credentials")            { return "Wrong email or password." }
        if t.contains("username too short")             { return "Username must be at least 3 characters." }
        if t.contains("username too long")              { return "Username can have at most 20 characters." }
        if t.contains("username invalid")               { return "Username can contain only letters, numbers and underscore." }
        if t.contains("username already in use")        { return "That username is already taken." }
        if t.contains("phone must be")                  { return "Enter the phone number with country code, e.g. +386 41 123 456." }
        if t.contains("phone number already in use")    { return "That phone number is already used by another account." }
        if t.contains("new password must be different")   { return "New password must be different from the current one." }
        if t.contains("club name is required")          { return "Enter the club name." }
        if t.contains("lat and lng")                    { return "Location could not be saved. Try again." }
        if t.contains("invalid club data")              { return "Some club data is out of range. Check the values and try again." }
        if t.contains("invalid value type")             { return "Please check what you entered and try again." }
        if t.contains("refresh token")                  { return "Your session has expired. Please log in again." }
        if t.contains("invalid token") || t.contains("missing token") { return "Your session has expired. Please log in again." }
        if t.contains("at least 15 years")              { return "You must be at least 15 years old to use Outly." }
        if t.contains("title is required")              { return "Enter a title." }
        if t.contains("startat must be")                { return "Enter a valid start date." }
        if t.contains("endat must be")                  { return "Enter a valid end date." }
        if t.contains("ticketpricecents")               { return "Enter the price as a number, e.g. 12.50." }
        if t.contains("minage must be")                 { return "Minimum age must be between 0 and 99." }
        if t.contains("status must be")                 { return "Invalid event status." }
        if t.contains("own club")                       { return "You can only manage events of your own club." }
        if t.contains("club not found")                 { return "Your club is not set up yet." }
        if t.contains("event not found")                { return "This event no longer exists." }
        if t.contains("sold tickets and was cancelled") { return "Tickets were already sold, so the event was cancelled instead of deleted." }
        if t.contains("dateofbirth") || t.contains("date of birth") {
            if t.contains("future")     { return "Date of birth cannot be in the future." }
            if t.contains("plausible")  { return "That date of birth does not look right." }
            return "Enter a valid date of birth."
        }
        if t.contains("country must be")                { return "Choose your country." }
        if t.contains("unknown_genres")                 { return "One of the selected genres is not available. Reload and try again." }
        if t.contains("genres must be")                 { return "Select at least one genre." }
        if t.contains("nothing to update")              { return "Nothing to save." }
        if t.contains("password required")              { return "Enter your password to continue." }
        // Prosnja za poslovni racun (POST /creator-applications)
        if t.contains("already pending")                { return "You already have an application waiting for review." }
        if t.contains("businessname is required")       { return "Enter the business name (at least 2 characters)." }
        if t.contains("contactname is required")        { return "Enter the contact person's name." }
        if t.contains("phone must contain")             { return "Enter a valid phone number, e.g. +386 41 123 456." }
        if t.contains("invalid application data")       { return "Please check what you entered and try again." }
        // Prenos vstopnice (POST /tickets/:id/transfer)
        if t.contains("valid email is required")        { return "Enter your friend's email address." }
        if t.contains("no outly account with this email") { return "No Outly account with this email. Ask your friend to sign up first." }
        if t.contains("already hold this ticket")       { return "That is your own email." }
        if t.contains("not verified yet")               { return "Your friend's account is not verified yet." }
        if t.contains("must add a date of birth")       { return "Your friend must add a date of birth in the app before receiving this ticket." }
        if t.contains("friend must be at least")        { return "Your friend is too young for this event." }
        if t.contains("already used")                   { return "This ticket was already used." }
        if t.contains("ticket not found")               { return "This ticket is not available anymore." }
        if t.contains("no longer valid")                { return "This ticket is no longer valid." }
        // Vstopnice
        if t.contains("quantity must be")               { return "Choose between 1 and 10 tickets." }
        if t.contains("not on sale")                    { return "This event is not on sale." }
        if t.contains("no tickets on outly")            { return "Tickets for this event are not sold on Outly." }
        if t.contains("already started")                { return "This event has already started." }
        if t.contains("have not opened")                { return "Ticket sales have not opened yet." }
        if t.contains("sales are closed")               { return "Ticket sales are closed." }
        if t.contains("tickets left") || t.contains("not enough tickets") { return "Not enough tickets left." }
        if t.contains("add your date of birth")         { return "Add your date of birth in Personal info to buy tickets." }
        if t.contains("you must be at least")           { return raw }
        if t.contains("payments are not available")     { return "Payments are not available yet." }
        if t.contains("club_has_orders")                { return "Your club has sold tickets. Transfer club ownership before deleting your account." }
        if t.contains("already exists") || t.contains("already registered") {
            return "An account with this email or username already exists."
        }

        switch code {
        case 400: return "Please check what you entered and try again."
        case 401: return "Wrong password or your session has expired."
        case 403: return "You do not have permission to do that."
        case 404: return "Not found."
        case 409: return "This is already in use."
        case 429: return "Too many attempts. Please wait a while and try again."
        case 500...599: return "The server is having trouble. Please try again later."
        case -1: return "No response from the server. Check your connection."
        default: return "Something went wrong. Please try again."
        }
    }
}
