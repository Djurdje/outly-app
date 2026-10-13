import SwiftUI

/// Pomoc: iskanje po clankih, vodic "How to use Outly" (clanki po skupinah, vsak vodi na HelpArticleView)
/// in stik. Vsebina je v aplikaciji (brez backenda), opisuje dejanske zaslone in gumbe Outlyja:
/// imena v besedilu morajo ustrezati napisom v aplikaciji (Localizable.xcstrings).
struct HelpCenterView: View {
    @State private var search = ""

    private var filtered: [HelpArticle] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return HelpArticle.all }
        return HelpArticle.all.filter {
            $0.title.lowercased().contains(q)
                || $0.topic.lowercased().contains(q)
                || $0.body.lowercased().contains(q)
        }
    }

    /// Clanki po skupinah, v vrstnem redu prve pojavitve v `HelpArticle.all` (iskanje filtrira cez vse skupine).
    private var groups: [HelpGroup] {
        var result: [HelpGroup] = []
        for a in filtered {
            if let i = result.firstIndex(where: { $0.name == a.group }) {
                result[i].articles.append(a)
            } else {
                result.append(HelpGroup(name: a.group, articles: [a]))
            }
        }
        return result
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("Help Center")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)

                    Text("Hi, how can we help?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .center)

                    SearchBar(text: $search, placeholder: "Search help")

                    Text(LocalizedStringKey(search.isEmpty ? "How to use Outly" : "Results"))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    if filtered.isEmpty {
                        Text("Nothing found. Try another word or contact us below.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.vertical, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(groups) { g in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(g.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.gray)
                                        .padding(.leading, 4)

                                    VStack(spacing: 12) {
                                        ForEach(g.articles) { a in
                                            NavigationLink { HelpArticleView(article: a) } label: {
                                                HelpCard(topLine: a.topic, title: a.title)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text("Still need help?")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.top, 12)

                    Link(destination: URL(string: "mailto:luka@outly.si?subject=Outly%20support")!) {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope")
                                .foregroundColor(.outlyBlue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Contact us")
                                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                                Text("luka@outly.si — we usually reply within a day.")
                                    .font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundColor(.gray)
                        }
                        .padding(14)
                        .background(Color.outlyBlue.opacity(0.12))
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// En clanek pomoci: naslov, tema, odstavki (locitev z prazno vrstico).
struct HelpArticleView: View {
    let article: HelpArticle

    private var paragraphs: [String] {
        article.body.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(article.topic)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 6)

                    Text(article.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                        Text(p)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Skupina clankov v Help Centru (naslov skupine + clanki pod njim).
private struct HelpGroup: Identifiable {
    let name: String
    var articles: [HelpArticle]
    var id: String { name }
}

struct HelpArticle: Identifiable {
    let id: String
    /// Skupina v vodicu (naslov nad karticami); clanki iste skupine so v `all` skupaj.
    let group: String
    let topic: String
    let title: String
    let body: String

    /// Racunana lastnost (ne `static let`): Jezik preklopi jezik brez ponovnega zagona, clanki morajo slediti.
    static var all: [HelpArticle] { [
        HelpArticle(
            id: "account",
            group: String(localized: "Getting started"),
            topic: String(localized: "Getting started  >  Account"),
            title: String(localized: "Creating an account"),
            body: String(localized: """
            Tap Sign up, enter your username, email and a password. We send a code (6–10 digits) to your email — type it in to confirm your address.

            Then complete your profile: date of birth, country and the music you like. Your date of birth is used only to check age limits on events.

            You must be at least 15 to use Outly.
            """)
        ),
        HelpArticle(
            id: "tabs",
            group: String(localized: "Getting started"),
            topic: String(localized: "Getting started  >  Navigation"),
            title: String(localized: "Finding your way around"),
            body: String(localized: """
            The bar at the bottom has four tabs: Home, Search, Map and Profile.

            On Home, tap your picture (top left) to open your Profile and the bell (top right) for notifications. Tap Where to? to search, or the sliders icon next to it to open Filters. Pull down to refresh.

            Everything you can do in Outly is explained in the articles below — use the search field on this screen to jump to one.
            """)
        ),
        HelpArticle(
            id: "home",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Home"),
            title: String(localized: "What you see on Home"),
            body: String(localized: """
            Home is a feed of what is on. Depending on what is available you will see Suggestions (clubs that match your genres), Tonight or This week, Interested events, Last week's biggest hits, In your area, Friends plans, Big events coming up, This weekend and Discover your genre. Tap any card to open it.

            In your area: tap a club to open it. If you allowed your location, the first tap shows how far away the club is and the second tap opens it.

            Discover your genre lists music genres; tap one to see its upcoming events. Tap See all events at the bottom of Home for a list of every upcoming event.
            """)
        ),
        HelpArticle(
            id: "search",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Search"),
            title: String(localized: "Search for clubs and events"),
            body: String(localized: """
            Open the Search tab, or tap Where to? on Home. Type at least 2 characters; results are split into Clubs and Events. Tap a result to open it.

            Before you type, Search shows Browse by genre — tap a genre to see its events — and a list of clubs.
            """)
        ),
        HelpArticle(
            id: "filters",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Filters"),
            title: String(localized: "Filter by city, genre, distance, age and price"),
            body: String(localized: """
            On Home tap the sliders icon next to Where to?. Choose a City, tick Music genres and move the sliders for Distance, Age range and Entry price. Tap Apply filters.

            A blue dot on the icon means filters are on. Tap Reset to clear them.

            Turn on Use my preferences to fill in the filters from Profile > My Account > Preferences > My preferences.
            """)
        ),
        HelpArticle(
            id: "map",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Map"),
            title: String(localized: "Find clubs on the map"),
            body: String(localized: """
            Open the Map tab. Every club on Outly is a pin, and you see yourself too if you allowed your location. Tap a pin to see the club's name and city, then tap the info button (i) next to it to open the club page.
            """)
        ),
        HelpArticle(
            id: "interested",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Interested events"),
            title: String(localized: "Mark an event with I'm in"),
            body: String(localized: """
            Open an event and tap I'm in next to its title. The button changes to Interested; tap it again to take it back. Once you have a ticket it shows Going.

            Events you are interested in appear on Home under Interested events. Tap See all to open the full list, split into Coming up and Already happened.
            """)
        ),
        HelpArticle(
            id: "event-page",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Events  >  Event page"),
            title: String(localized: "Everything on an event page"),
            body: String(localized: """
            Open an event from Home, Search, a club page or the Map. At the top is the poster with the ticket price. Below it are the club (tap it to open the club page), the date and time, the address with a small map (tap it for directions), Bar prices, the description (ABOUT) and who is selling the tickets.

            If friends are going or interested, you see them under the title. To report an event, tap the … menu at the top right and choose Report.
            """)
        ),
        HelpArticle(
            id: "club-page",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Clubs  >  Club page"),
            title: String(localized: "Club pages and Follow"),
            body: String(localized: """
            A club page has photos, the city, music genres and minimum age, then Popular and Coming Soon events, a map with the address, Contact (email, phone, Instagram, website) and a description. Tap an event to open it.

            Tap Follow to follow a club — you get a notification when it posts a new event (allow notifications when Outly asks, or turn them on under Preferences). Tap Following to stop. To report a club, tap the … menu at the top right and choose Report.
            """)
        ),
        HelpArticle(
            id: "bar-prices",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Events  >  Bar prices"),
            title: String(localized: "See bar prices"),
            body: String(localized: """
            On an event page tap Bar prices to open the club's drink list, grouped by category. Prices are set by the club and may change.

            If it says Not added yet, the club has not shared its prices.
            """)
        ),
        HelpArticle(
            id: "vip-book",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Events  >  VIP tables"),
            title: String(localized: "Reserve a VIP table"),
            body: String(localized: """
            On an event page scroll to VIP & TABLES and tap Reserve a VIP table. If the club has published a table layout you see the floor plan; if not, call the club on the number shown under the card.

            Tap a free table, choose your bottle if the club offers packages (it is included in the table price) and tap Reserve table. If you pay through Stripe, the table is held for you until you finish paying.

            Afterwards you can send tickets to your friends: choose them from the list and tap Send to friends, or tap Skip — tickets you don't send stay under Tickets.

            Like tickets, a VIP table for a dated event cannot be returned after purchase. The seller is the club; Outly is the intermediary.
            """)
        ),
        HelpArticle(
            id: "age",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Events  >  Age limits"),
            title: String(localized: "Age limits"),
            body: String(localized: """
            You must be 15 or older to use Outly. Some events are 18+ — this is shown on the event and you need a date of birth in your profile to buy tickets for them.

            The club may ask for an ID at the door.
            """)
        ),
        HelpArticle(
            id: "buy",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  Buying"),
            title: String(localized: "How to buy a ticket"),
            body: String(localized: """
            Open an event and tap the price on the poster. Choose how many tickets you want with the minus and plus buttons, then tap Pay (it shows the total), or Get ticket if the event is free. If the club takes payments through Stripe, a secure Stripe page opens for the payment and brings you back to Outly.

            Your tickets appear under Profile > Tickets as soon as the payment goes through. Each ticket has its own QR code.

            If the poster says at the door, you pay at the club; if it says sold by the club, the button opens the club's own ticket page.

            Events marked 18+ require a date of birth in your profile.
            """)
        ),
        HelpArticle(
            id: "my-tickets",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  Your tickets"),
            title: String(localized: "Where to find your tickets"),
            body: String(localized: """
            Open Profile > Tickets. Upcoming tickets are on top and Past below; tickets that were already scanned move to Used tickets. Tap a ticket to open it with its QR code. A VIP table is one group — tap it to open its tickets.

            Tickets someone sent you and guest list tickets are here too.

            No signal? Tickets keeps the last list it downloaded, so you can still open your QR code at the door.
            """)
        ),
        HelpArticle(
            id: "door",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  At the door"),
            title: String(localized: "Using your ticket at the door"),
            body: String(localized: """
            Open Profile > Tickets and tap the ticket. Show the QR code to the staff at the entrance — they scan it with Outly.

            A ticket can be scanned only once. Screenshots work, but keep your brightness up so the code is readable.
            """)
        ),
        HelpArticle(
            id: "transfer",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  Friends"),
            title: String(localized: "Send a ticket to a friend"),
            body: String(localized: """
            Bought tickets for the whole group? Open a ticket and tap Send to a friend. Choose a friend from your list, or tap Send by email instead and enter their email, then tap Send ticket and confirm.

            The ticket moves to their account with a new QR code — your old code stops working. Your friend needs an Outly account with a confirmed email and must meet the event's age limit. (Where the screen says we'll email them the ticket, a friend without an account can get it by email too.) For events with an age limit you confirm that your friend is old enough.

            Tickets can be sent until the event starts. Guest list tickets can't be sent.

            If the event is cancelled, the refund goes to the original buyer, not to the person you send the ticket to.
            """)
        ),
        HelpArticle(
            id: "guest-list",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  Guest lists"),
            title: String(localized: "Guest lists: invite your friends"),
            body: String(localized: """
            A guest list is set up by Outly for an event, with you as the host and a set number of spots. It appears under Profile > Tickets > Guest lists, and you get your own ticket with a QR code under Tickets.

            Open the guest list and tap Invite friends, choose friends from your list and confirm. Each friend gets their own ticket with their own QR code and can arrive separately. To free a spot, tap the x next to a friend before they have entered — their ticket stops working.

            If a friend adds you to their guest list, you get a notification and the ticket appears under Tickets as Invited by @name.
            """)
        ),
        HelpArticle(
            id: "refund",
            group: String(localized: "Tickets"),
            topic: String(localized: "Refunds and cancellations"),
            title: String(localized: "Refunds and cancelled events"),
            body: String(localized: """
            Tickets are sold by the club; Outly is the marketplace. Because a ticket is for a specific date, there is no 14-day right of withdrawal after purchase.

            If the club cancels an event, you are entitled to a refund from the club, to your original payment method.

            For anything else, contact the club or write to luka@outly.si with your ticket number.
            """)
        ),
        HelpArticle(
            id: "friends-add",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Friends  >  Add friends"),
            title: String(localized: "Add friends and answer requests"),
            body: String(localized: """
            Open Profile > My Friends and tap Add friends. Search by username (at least 2 letters) and tap Add next to a person. Requested means the request is waiting; tap it to cancel.

            Requests you receive appear at the top of My Friends under Friend requests (and in the bell on Home). Tap Accept or Decline. To remove a friend, open the … menu next to them and choose Remove friend.
            """)
        ),
        HelpArticle(
            id: "friends-plans",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Friends  >  Friends plans"),
            title: String(localized: "See where your friends are going"),
            body: String(localized: """
            On Home, Friends plans shows your friends as circles: a blue ring means they have a ticket, a white ring means they are interested. Tap View to see their events, then Join them to buy a ticket for the same event or View event to open it. Tap Invite more to share Outly with someone who isn't on it yet.

            Your friends can see your plans too. To switch that off, go to Profile > My Account > Preferences and turn off Friends can see my plans.
            """)
        ),
        HelpArticle(
            id: "bell",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Notifications  >  Bell"),
            title: String(localized: "The bell on Home"),
            body: String(localized: """
            Tap the bell at the top right of Home to see what is new: invitations to join a club team, friend requests, a ticket a friend sent you, guest list invitations, new events from clubs you follow and, for club staff, VIP tables ready to serve. Tap an item to open it. A number on the bell means something is waiting.
            """)
        ),
        HelpArticle(
            id: "push",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Notifications  >  Push"),
            title: String(localized: "Turn on push notifications"),
            body: String(localized: """
            Go to Profile > My Account > Preferences > Notifications and tap Turn on notifications. You get a notification for a ticket someone sent you, new events from clubs you follow, an invitation to a guest list and, for club staff, table service requests.

            If you said no earlier, turn them on in iOS Settings. Sign-up and password codes always arrive by email.
            """)
        ),
        HelpArticle(
            id: "report-block",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Safety  >  Report and block"),
            title: String(localized: "Report or block"),
            body: String(localized: """
            To report an event or a club, tap the … menu at the top right of its page and choose Report. Pick a reason and tap Send. We review reports within 24 hours.

            To report or block a person, open the … menu next to their name (in My Friends or when you search for friends) and choose Report or Block. People you block can't find you or send you requests, and they are not notified. You can undo it under Profile > My Account > Blocked users with Unblock; the friendship does not come back.
            """)
        ),
        HelpArticle(
            id: "password",
            group: String(localized: "Account"),
            topic: String(localized: "Login & Passwords  >  Reset"),
            title: String(localized: "Reset your password"),
            body: String(localized: """
            On the login screen tap Forgot password and enter your email. We send you a code; enter it together with a new password.

            If you are logged in, go to My Account > Password and security to change your password. This logs you out on all other devices.
            """)
        ),
        HelpArticle(
            id: "security",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Security"),
            title: String(localized: "Change your password or sign out everywhere"),
            body: String(localized: """
            Go to Profile > My Account > Password and security. Under Login tap Edit, enter your current password and the new one twice, then tap Done. Other devices are signed out; this one stays signed in.

            Under Sessions tap Sign out and confirm to sign out of all devices, including this one. To log out of this device only, tap Log out at the bottom of Profile.
            """)
        ),
        HelpArticle(
            id: "profile",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Profile"),
            title: String(localized: "Edit your profile"),
            body: String(localized: """
            Go to Profile > My Account > Personal info. Tap the picture with the + to add or change your profile photo. Each card — Username, Phone number, Date of birth and Country — has an Edit button. Your username needs 3–20 characters: letters, numbers and underscore.

            Your email can't be changed in the app; to change it, write to luka@outly.si.
            """)
        ),
        HelpArticle(
            id: "preferences",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Preferences"),
            title: String(localized: "Preferences, language and notifications"),
            body: String(localized: """
            Go to Profile > My Account > Preferences. My preferences saves your favourite music genres, maximum distance, age range and ticket price range on this phone; switch on Use my preferences in Filters to apply them.

            Language switches the app between English and Slovenščina straight away. Notifications is where you turn on push notifications. Friends can see my plans decides whether your friends see which events you are going to.
            """)
        ),
        HelpArticle(
            id: "payment",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Payment"),
            title: String(localized: "How payments work"),
            body: String(localized: """
            Tickets are paid at checkout. Payments are processed by Stripe; Outly never sees or stores your card details, and the app does not hold a balance.

            You can read this any time under Profile > Payment. For refunds see Refunds and cancelled events.
            """)
        ),
        HelpArticle(
            id: "delete",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Delete"),
            title: String(localized: "Delete your account"),
            body: String(localized: """
            Go to My Account > Delete account. Your personal data is removed; records of past purchases are kept anonymised, as required for accounting.

            Valid tickets on a deleted account cannot be recovered, so use them or send them to a friend first.
            """)
        ),
        HelpArticle(
            id: "club",
            group: String(localized: "For clubs"),
            topic: String(localized: "Clubs  >  List your club"),
            title: String(localized: "Add your club to Outly"),
            body: String(localized: """
            Go to My Account > Request for creator and fill in the short form. We review requests by hand — you can follow the status on the same screen.

            Once approved, your profile switches to the business view: Edit your page, Dashboard, Events, My team and Settings (if it does not, log out and log in again). Scanning tickets is under Profile > My Clubs — see Scan tickets at the door.

            Owners can switch between the club and the personal profile: Settings > Switch to personal account, and back with My Account > Switch to club account.
            """)
        ),
        HelpArticle(
            id: "club-setup",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Club page"),
            title: String(localized: "Set up your club page"),
            body: String(localized: """
            The first time you open the club profile you see Set up your club: add a logo, the name, address and city, minimum age and music genres, then tap Create club. If you organize events without your own venue, switch on I organize events without my own venue — there is then no address or map pin and you choose the venue for each event.

            Later tap Edit your page, then Club info (also under Settings) to change details: Club name, Phone number, Website, Instagram, Email, About club, Address, City, Minimum age, Music genres, Slideshow (up to 3 photos), Club video and Bar prices. Under Bar prices tap Add item, enter a name and price (category is optional) and tap Save.

            Seller details (company name, registered office, registration number, tax number) and VAT status are shown to buyers before payment. Only the club owner can change them.
            """)
        ),
        HelpArticle(
            id: "club-events",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Events"),
            title: String(localized: "Create and edit events"),
            body: String(localized: """
            Open Events and tap Add event (managers: Profile > My Clubs > your club > Create event). Fill in Title and Description, When (Starts, and Has end time if the event has an end), Who (Minimum age and music genres) and Tickets: Price in EUR (leave it empty if tickets are not sold on Outly, 0 means free entry), Capacity and an optional external ticket link. Choose a poster, switch on Published (visible to everyone) and tap Save.

            Tap an event in the list to edit it. To remove one, tap Cancel or delete event. If tickets were already sold, the event is cancelled instead of deleted, so buyers keep proof of purchase.

            Past events can get an Event video that guests see on your club page — only your three most popular past events qualify.
            """)
        ),
        HelpArticle(
            id: "club-dashboard",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Dashboard"),
            title: String(localized: "Read your dashboard"),
            body: String(localized: """
            Open Dashboard. Sales shows revenue for a period — choose By year, By month or By week. Below are Total revenue, Tickets sold, Outly fee and Your payout (after fee and refunds).

            Check activity shows clicks on your profile and events and your Followers; Staff activity shows what your team scanned; Event performance lists your events — tap one for Door check-in and VIP reservations, or View all for the full list. While payments are in test mode, a TEST label shows and no money moves.
            """)
        ),
        HelpArticle(
            id: "club-scanner",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Scanner"),
            title: String(localized: "Scan tickets at the door"),
            body: String(localized: """
            Owners, managers and door staff scan with the camera: open Profile > My Clubs, tap your club, then Scan ticket (owners first switch to their personal profile: Settings > Switch to personal account). The scanner opens straight away — you don't pick an event. It covers the club's events from 12 hours before the start until 6 hours after the end. Point the camera at the guest's QR code.

            Green WELCOME IN lets the guest in. Red means no (for example ALREADY SCANNED, REFUNDED, CANCELLED, NOT PAID or INVALID CODE). A gold bar marks a VIP table, a white bar a guest list guest. Tap Next for the following guest.

            Yellow means the phone can't check the ticket by itself. If you decide to let the guest in, tap Let in; the server checks later and anything wrong appears under Conflicts (triangle, top right). Use the flashlight button in dark rooms.

            The scanner also works without signal: it downloads the ticket list and sends scans when you are back online. Until the list is downloaded, tickets can only be checked with a connection. You can also check guests in by hand: Dashboard > event > Check in.
            """)
        ),
        HelpArticle(
            id: "club-team",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Team"),
            title: String(localized: "Invite your team"),
            body: String(localized: """
            Open My team (managers: Profile > My Clubs > your club > Team). Tap Invite member, enter their Outly email, choose a role and tap Send invite. They need an Outly account with that email; the invitation reaches them in the app and they join when they accept.

            Roles: Manager — events, sales, club page and door staff; only the owner can add managers. Door staff — scans tickets at the door, nothing else. Bartender — sees VIP tables to serve and marks them delivered, with no guest details.

            To remove someone, or to cancel a pending invitation, tap the x next to the name. A removed person loses access to the club tools right away.
            """)
        ),
        HelpArticle(
            id: "club-invite",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Invitations"),
            title: String(localized: "Accept an invitation to a club team"),
            body: String(localized: """
            When a club invites you to its team, you see it in the bell on Home and in Profile > My Clubs (bell, top right). Open the invitation and tap Accept to join or Reject to decline. The club then shows under My Clubs, with the tools for your role.

            To leave a team, open the club under My Clubs and tap Leave the team. The club can invite you again.
            """)
        ),
        HelpArticle(
            id: "club-vip",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  VIP tables"),
            title: String(localized: "Set up VIP tables and phone reservations"),
            body: String(localized: """
            If the app says Set up VIP tables at outly.si/app, the floor plan and prices are set up there. Organizers without their own venue can also do it in the app: open the event, go to VIP tables and choose Use the venue's layout, Own layout for this event or No VIP tables; Edit tables and layout lets you add tables, drag them into place and set seats and price. Save the event first.

            To take a reservation by phone: Dashboard > event > VIP reservations, tap Mark as reserved on a free table, enter the Guest name and a Note, and tap Reserve. Tap Release to free the table again. Only owners and managers can do this.
            """)
        ),
        HelpArticle(
            id: "club-service",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Table service"),
            title: String(localized: "Serve VIP tables"),
            body: String(localized: """
            Owners, managers and bartenders open Profile > My Clubs > your club > Table service (owners switch to their personal profile first). When door staff scan a VIP ticket, the table appears in the list with its package and the time it was scanned. The list refreshes by itself; pull down to refresh it yourself. Choose the event at the top if there is more than one.

            Tap Delivered once the table has been served. Tapped by mistake? Tap Undo. Staff also get a notification when a table is ready to serve.
            """)
        ),
    ] }
}
