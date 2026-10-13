import SwiftUI

/// Kam vodi gumb »Take me there« v clanku pomoci. Samo zasloni, ki jih Help Center (potisnjen v NavigationStack
/// Profila) doseze brez dodatnega stanja: nobenega zavihka (MainTabView drzi izbiro zavihka privatno in jo pri
/// preklopu spremlja animacija prehoda — ne posegamo vanjo, CLAUDE.md pravilo 5) in nobenega poslovnega zaslona
/// (Dashboard, skener, ekipa rabijo izbran klub in vlogo). Vsi cilji berejo samo `SessionStore`, `Jezik` in
/// `UserPreferences`, ki so v okolju korena (OutlyApp).
enum HelpDestination: Hashable {
    case tickets
    case friends
    case notifications
    case personalInfo
    case passwordSecurity
    case preferences
    case payment
    case deleteAccount
    case requestForCreator
    case myClubs

    @ViewBuilder
    var view: some View {
        switch self {
        case .tickets: TicketsView()
        case .friends: MyFriendsView()
        case .notifications: NotificationsView()
        case .personalInfo: PersonalInfoView()
        case .passwordSecurity: PasswordSecurityView()
        case .preferences: PreferencesView()
        case .payment: PaymentView()
        case .deleteAccount: DeleteAccountView()
        case .requestForCreator: ReguestForCreatorView()
        case .myClubs: MyClubsView()
        }
    }
}

/// En clanek pomoci. Vsebina je v aplikaciji (brez backenda) in opisuje dejanske zaslone Outlyja: imena
/// gumbov in zaslonov morajo ustrezati napisom v aplikaciji (Localizable.xcstrings).
struct HelpArticle: Identifiable {
    /// Stabilen kljuc v anglescini (isti se poslje backendu pri odzivu `POST /help/feedback`) — NE prevajaj.
    let id: String
    /// Skupina v vodicu (naslov nad karticami); clanki iste skupine so v `all` skupaj.
    let group: String
    let topic: String
    let title: String
    /// En stavek: cemu clanek sluzi.
    let summary: String
    /// Kje zacnes (npr. Profile > Tickets); prazno, ce ni ene poti.
    let path: [String]
    /// Ostevilceni koraki: en korak = en ukrep.
    let steps: [String]
    /// »Good to know«: pravila, omejitve, nasveti (pravno obcutljive stavke dobesedno).
    let notes: [String]
    /// »Take me there«; nil = gumba ni.
    let destination: HelpDestination?
    /// `id`-ji sorodnih clankov (2–3, vsi morajo obstajati v `all`).
    let related: [String]

    /// Iskanje po naslovu, temi, povzetku, korakih in opombah (`query` je ze male crke in brez presledkov na robu).
    func matches(_ query: String) -> Bool {
        if title.lowercased().contains(query) || topic.lowercased().contains(query) || summary.lowercased().contains(query) {
            return true
        }
        return steps.contains { $0.lowercased().contains(query) } || notes.contains { $0.lowercased().contains(query) }
    }

    /// Racunana lastnost (ne `static let`): Jezik preklopi jezik brez ponovnega zagona, clanki morajo slediti.
    /// Vsebina je po skupinah v HelpArticleContent.swift (en velik literal bi upocasnil pregled tipov).
    static var all: [HelpArticle] {
        gettingStarted + discover + eventsAndClubs + tickets + friendsAndNotifications + account + forClubs
    }
}

/// Odziv »Was this article helpful?« shranjen na napravi (id clanka -> ali je bil v pomoc), da se ob ponovnem
/// odprtju clanka vidi, kaj si izbral. Streznik dobi odziv posebej (`APIClient.sendHelpFeedback`).
enum HelpFeedback {
    private static let key = "helpFeedback"

    static func vote(for articleId: String) -> Bool? {
        let all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        return all[articleId] as? Bool
    }

    static func save(_ helpful: Bool, for articleId: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[articleId] = helpful
        UserDefaults.standard.set(all, forKey: key)
    }
}
