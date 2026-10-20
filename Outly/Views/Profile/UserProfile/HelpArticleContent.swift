// Vsebina clankov pomoci, po skupinah; vsak clanek je svoj stavek (r.append), ker bi en velik literal vseh clankov
// bistveno podaljsal pregled tipov (izmerjeno: < 15 ms na izraz). Model: HelpArticle.swift.
// Vsak niz ima slovenski prevod v Localizable.xcstrings; pravno obcutljive stavke so dobesedno iz prejsnjih besedil (PR #94).
// Imena gumbov in zaslonov morajo ustrezati napisom v aplikaciji.

import Foundation

extension HelpArticle {
    static var gettingStarted: [HelpArticle] {
        var r: [HelpArticle] = []
        r.append(HelpArticle(
            id: "account",
            group: String(localized: "Getting started"),
            topic: String(localized: "Getting started  >  Account"),
            title: String(localized: "Creating an account"),
            summary: String(localized: "Create your Outly account with your email and confirm it with a code."),
            path: [],
            steps: [
                String(localized: "Tap Sign up."),
                String(localized: "Enter your username, email and a password."),
                String(localized: "Type in the code (6–10 digits) we send to your email to confirm your address."),
                String(localized: "Complete your profile: date of birth, country and the music you like."),
            ],
            notes: [
                String(localized: "Your date of birth is used only to check age limits on events."),
                String(localized: "You must be at least 18 to create an Outly account. You can browse events without an account."),
            ],
            destination: nil,
            related: ["age", "profile", "password"]
        ))
        r.append(HelpArticle(
            id: "tabs",
            group: String(localized: "Getting started"),
            topic: String(localized: "Getting started  >  Navigation"),
            title: String(localized: "Finding your way around"),
            summary: String(localized: "The bar at the bottom has four tabs, and Home has a few shortcuts."),
            path: [],
            steps: [
                String(localized: "Use the bar at the bottom: Home, Search, Map and Profile."),
                String(localized: "On Home, tap your picture (top left) to open your Profile."),
                String(localized: "Tap the bell (top right) to see notifications."),
                String(localized: "Tap Where to? to search, or the sliders icon next to it to open Filters."),
                String(localized: "Pull down to refresh."),
            ],
            notes: [
                String(localized: "Everything you can do in Outly is explained in the Help Center — use its search field to jump to an article."),
            ],
            destination: nil,
            related: ["home", "search", "filters"]
        ))
        return r
    }
}

extension HelpArticle {
    static var discover: [HelpArticle] {
        var r: [HelpArticle] = []
        r.append(HelpArticle(
            id: "home",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Home"),
            title: String(localized: "What you see on Home"),
            summary: String(localized: "Home is a feed of what is on, shown in sections."),
            path: [],
            steps: [
                String(localized: "Scroll down to browse the sections."),
                String(localized: "Tap any card to open it."),
                String(localized: "Under In your area, tap a club to open it."),
                String(localized: "Under Discover your genre, tap a genre to see its upcoming events."),
                String(localized: "Tap See all events at the bottom of Home to see every upcoming event."),
            ],
            notes: [
                String(localized: "Depending on what is available you will see Suggestions (clubs that match your genres), Tonight or This week, Interested events, Last week's biggest hits, In your area, Friends plans, Big events coming up, This weekend and Discover your genre."),
                String(localized: "If you allowed your location, the first tap on a club under In your area shows how far away it is and the second tap opens it."),
            ],
            destination: nil,
            related: ["tabs", "filters", "interested"]
        ))
        r.append(HelpArticle(
            id: "search",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Search"),
            title: String(localized: "Search for clubs and events"),
            summary: String(localized: "Find clubs and events by name."),
            path: [
                String(localized: "Search"),
            ],
            steps: [
                String(localized: "Open the Search tab, or tap Where to? on Home."),
                String(localized: "Type at least 2 characters."),
                String(localized: "Look through the results, split into Clubs and Events."),
                String(localized: "Tap a result to open it."),
            ],
            notes: [
                String(localized: "Before you type, Search shows Browse by genre — tap a genre to see its events — and a list of clubs."),
            ],
            destination: nil,
            related: ["filters", "home", "map"]
        ))
        r.append(HelpArticle(
            id: "filters",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Filters"),
            title: String(localized: "Filter by city, genre, distance, age and price"),
            summary: String(localized: "Narrow down events by city, music genre, distance, age and price."),
            path: [
                String(localized: "Home"),
                String(localized: "Filters"),
            ],
            steps: [
                String(localized: "Tap the sliders icon next to Where to?."),
                String(localized: "Choose a City and tick Music genres."),
                String(localized: "Move the sliders for Distance, Age range and Entry price."),
                String(localized: "Tap Apply filters."),
            ],
            notes: [
                String(localized: "A blue dot on the icon means filters are on. Tap Reset to clear them."),
                String(localized: "Turn on Use my preferences to fill in the filters from Profile > My Account > Preferences > My preferences."),
            ],
            destination: nil,
            related: ["search", "preferences", "home"]
        ))
        r.append(HelpArticle(
            id: "map",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Map"),
            title: String(localized: "Find clubs on the map"),
            summary: String(localized: "See every club on a map and open its page."),
            path: [
                String(localized: "Map"),
            ],
            steps: [
                String(localized: "Open the Map tab."),
                String(localized: "Tap a pin to see the club's name and city."),
                String(localized: "Tap the info button (i) next to it to open the club page."),
            ],
            notes: [
                String(localized: "Every club on Outly is a pin. You see yourself too if you allowed your location."),
            ],
            destination: nil,
            related: ["club-page", "search", "home"]
        ))
        r.append(HelpArticle(
            id: "interested",
            group: String(localized: "Discover"),
            topic: String(localized: "Discover  >  Interested events"),
            title: String(localized: "Mark an event with I'm in"),
            summary: String(localized: "Mark events you like, so you find them again on Home."),
            path: [],
            steps: [
                String(localized: "Open an event."),
                String(localized: "Tap I'm in next to its title. The button changes to Interested."),
                String(localized: "Tap it again to take it back."),
            ],
            notes: [
                String(localized: "Once you have a ticket it shows Going."),
                String(localized: "Events you are interested in appear on Home under Interested events. Tap See all to open the full list, split into Coming up and Already happened."),
            ],
            destination: nil,
            related: ["home", "buy", "friends-plans"]
        ))
        return r
    }
}

extension HelpArticle {
    static var eventsAndClubs: [HelpArticle] {
        var r: [HelpArticle] = []
        r.append(HelpArticle(
            id: "event-page",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Events  >  Event page"),
            title: String(localized: "Everything on an event page"),
            summary: String(localized: "A quick tour of what you can see and tap on an event."),
            path: [],
            steps: [
                String(localized: "Open an event from Home, Search, a club page or the Map."),
                String(localized: "Check the poster at the top: it shows the ticket price."),
                String(localized: "Below it find the club, the date and time, and the address with a small map."),
                String(localized: "Tap the club to open its page, or the small map for directions."),
                String(localized: "Tap Bar prices to see drinks, and read the description under ABOUT."),
            ],
            notes: [
                String(localized: "The event page also shows who is selling the tickets."),
                String(localized: "If friends are going or interested, you see them under the title."),
                String(localized: "To report an event, tap the … menu at the top right and choose Report."),
            ],
            destination: nil,
            related: ["buy", "bar-prices", "club-page"]
        ))
        r.append(HelpArticle(
            id: "club-page",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Clubs  >  Club page"),
            title: String(localized: "Club pages and Follow"),
            summary: String(localized: "See a club's events and details, and follow it to hear about new events."),
            path: [],
            steps: [
                String(localized: "Open a club from Search, the Map or an event."),
                String(localized: "Scroll through its events, the map with the address and Contact."),
                String(localized: "Tap an event to open it."),
                String(localized: "Tap Follow to get a notification when the club posts a new event."),
                String(localized: "Tap Following to stop."),
            ],
            notes: [
                String(localized: "A club page has photos, the city, music genres and minimum age, then Popular and Coming Soon events, a map with the address, Contact (email, phone, Instagram, website) and a description."),
                String(localized: "Allow notifications when Outly asks, or turn them on under Preferences."),
                String(localized: "To report a club, tap the … menu at the top right and choose Report."),
            ],
            destination: nil,
            related: ["map", "push", "report-block"]
        ))
        r.append(HelpArticle(
            id: "bar-prices",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Events  >  Bar prices"),
            title: String(localized: "See bar prices"),
            summary: String(localized: "Look up the club's drink prices before you go."),
            path: [],
            steps: [
                String(localized: "Open an event."),
                String(localized: "Tap Bar prices."),
                String(localized: "Browse the club's drink list, grouped by category."),
            ],
            notes: [
                String(localized: "Prices are set by the club and may change."),
                String(localized: "If it says Not added yet, the club has not shared its prices."),
            ],
            destination: nil,
            related: ["event-page", "club-page", "buy"]
        ))
        r.append(HelpArticle(
            id: "vip-book",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Events  >  VIP tables"),
            title: String(localized: "Reserve a VIP table"),
            summary: String(localized: "Reserve a table at an event that offers VIP tables."),
            path: [],
            steps: [
                String(localized: "On an event page, scroll to VIP & TABLES."),
                String(localized: "Tap Reserve a VIP table."),
                String(localized: "Tap a free table."),
                String(localized: "Choose your bottle, if the club offers packages."),
                String(localized: "Tap Reserve table."),
                String(localized: "To send tickets to friends, choose them from the list and tap Send to friends, or tap Skip."),
            ],
            notes: [
                String(localized: "If the club has published a table layout you see the floor plan; if not, call the club on the number shown under the card."),
                String(localized: "The bottle is included in the table price."),
                String(localized: "If you pay through Stripe, the table is held for you until you finish paying."),
                String(localized: "Tickets you don't send stay under Tickets."),
                String(localized: "Like tickets, a VIP table for a dated event cannot be returned after purchase. The seller is the club or event organiser; for Outly's own events the seller is the operator of Outly."),
            ],
            destination: nil,
            related: ["buy", "transfer", "refund"]
        ))
        r.append(HelpArticle(
            id: "age",
            group: String(localized: "Events & clubs"),
            topic: String(localized: "Events  >  Age limits"),
            title: String(localized: "Age limits"),
            summary: String(localized: "An Outly account is for people aged 18 and over, and some events have a higher age limit."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Account"),
                String(localized: "Personal info"),
            ],
            steps: [
                String(localized: "Find the Date of birth card."),
                String(localized: "Tap Edit and enter your date of birth."),
            ],
            notes: [
                String(localized: "You must be 18 or older to create an Outly account. Some events have a higher age limit — this is shown on the event and you need a date of birth in your profile to buy tickets for them."),
                String(localized: "The club may ask for an ID at the door."),
            ],
            destination: .personalInfo,
            related: ["account", "profile", "buy"]
        ))
        return r
    }
}

extension HelpArticle {
    static var tickets: [HelpArticle] {
        var r: [HelpArticle] = []
        r.append(HelpArticle(
            id: "buy",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  Buying"),
            title: String(localized: "How to buy a ticket"),
            summary: String(localized: "Buy tickets for an event and find them under Tickets."),
            path: [],
            steps: [
                String(localized: "Open an event and tap the price on the poster."),
                String(localized: "Choose how many tickets you want with the minus and plus buttons."),
                String(localized: "Tap Pay (it shows the total), or Get ticket if the event is free."),
                String(localized: "If a secure Stripe page opens, pay there. It brings you back to Outly."),
                String(localized: "Open Profile > Tickets to see your tickets."),
            ],
            notes: [
                String(localized: "Your tickets appear under Profile > Tickets as soon as the payment goes through. Each ticket has its own QR code."),
                String(localized: "If the poster says at the door, you pay at the club; if it says sold by the club, the button opens the club's own ticket page."),
                String(localized: "Events marked 18+ require a date of birth in your profile."),
            ],
            destination: nil,
            related: ["my-tickets", "transfer", "refund"]
        ))
        r.append(HelpArticle(
            id: "my-tickets",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  Your tickets"),
            title: String(localized: "Where to find your tickets"),
            summary: String(localized: "All your tickets are in one place, each with its own QR code."),
            path: [
                String(localized: "Profile"),
                String(localized: "Tickets"),
            ],
            steps: [
                String(localized: "Look for upcoming tickets on top and Past below."),
                String(localized: "Tap a ticket to open it with its QR code."),
                String(localized: "For a VIP table, tap the group to open its tickets."),
            ],
            notes: [
                String(localized: "Tickets that were already scanned move to Used tickets."),
                String(localized: "Tickets someone sent you and guest list tickets are here too."),
                String(localized: "No signal? Tickets keeps the last list it downloaded, so you can still open your QR code at the door."),
            ],
            destination: .tickets,
            related: ["door", "transfer", "guest-list"]
        ))
        r.append(HelpArticle(
            id: "door",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  At the door"),
            title: String(localized: "Using your ticket at the door"),
            summary: String(localized: "Show your QR code at the entrance and the staff scan it."),
            path: [
                String(localized: "Profile"),
                String(localized: "Tickets"),
            ],
            steps: [
                String(localized: "Tap the ticket."),
                String(localized: "Show the QR code to the staff at the entrance. They scan it with Outly."),
            ],
            notes: [
                String(localized: "A ticket can be scanned only once."),
                String(localized: "Screenshots work, but keep your brightness up so the code is readable."),
            ],
            destination: .tickets,
            related: ["my-tickets", "buy", "transfer"]
        ))
        r.append(HelpArticle(
            id: "transfer",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  Friends"),
            title: String(localized: "Send a ticket to a friend"),
            summary: String(localized: "Give a ticket to a friend. It moves to their account with a new QR code."),
            path: [
                String(localized: "Profile"),
                String(localized: "Tickets"),
            ],
            steps: [
                String(localized: "Open the ticket you want to send."),
                String(localized: "Tap Send to a friend."),
                String(localized: "Choose a friend from your list, or tap Send by email instead and enter their email."),
                String(localized: "Tap Send ticket and confirm."),
            ],
            notes: [
                String(localized: "The ticket moves to their account with a new QR code — your old code stops working."),
                String(localized: "Your friend needs an Outly account with a confirmed email and must meet the event's age limit. (Where the screen says we'll email them the ticket, a friend without an account can get it by email too.) For events with an age limit you confirm that your friend is old enough."),
                String(localized: "Tickets can be sent until the event starts. Guest list tickets can't be sent."),
                String(localized: "If the event is cancelled, the refund goes to the original buyer, not to the person you send the ticket to."),
            ],
            destination: .tickets,
            related: ["my-tickets", "refund", "guest-list"]
        ))
        r.append(HelpArticle(
            id: "guest-list",
            group: String(localized: "Tickets"),
            topic: String(localized: "Tickets  >  Guest lists"),
            title: String(localized: "Guest lists: invite your friends"),
            summary: String(localized: "Invite friends to an event from your own guest list."),
            path: [
                String(localized: "Profile"),
                String(localized: "Tickets"),
                String(localized: "Guest lists"),
            ],
            steps: [
                String(localized: "Open the guest list."),
                String(localized: "Tap Invite friends."),
                String(localized: "Choose friends from your list and confirm."),
                String(localized: "To free a spot, tap the x next to a friend before they have entered."),
            ],
            notes: [
                String(localized: "A guest list is set up by Outly for an event, with you as the host and a set number of spots. You get your own ticket with a QR code under Tickets."),
                String(localized: "Each friend gets their own ticket with their own QR code and can arrive separately."),
                String(localized: "When you free a spot, that friend's ticket stops working."),
                String(localized: "If a friend adds you to their guest list, you get a notification and the ticket appears under Tickets as Invited by @name."),
            ],
            destination: .tickets,
            related: ["my-tickets", "transfer", "friends-add"]
        ))
        r.append(HelpArticle(
            id: "refund",
            group: String(localized: "Tickets"),
            topic: String(localized: "Refunds and cancellations"),
            title: String(localized: "Refunds and cancelled events"),
            summary: String(localized: "How refunds work for tickets and cancelled events."),
            path: [],
            steps: [],
            notes: [
                String(localized: "Tickets are sold by the club or event organiser, with Outly as the intermediary; for Outly's own events the seller is the operator of Outly. Because a ticket is for a specific date, there is no 14-day right of withdrawal after purchase."),
                String(localized: "If an event is cancelled, you are entitled to a refund from the seller, to your original payment method."),
                String(localized: "For anything else, contact the seller or write to luka@outly.si with your ticket number."),
            ],
            destination: nil,
            related: ["buy", "transfer", "my-tickets"]
        ))
        return r
    }
}

extension HelpArticle {
    static var friendsAndNotifications: [HelpArticle] {
        var r: [HelpArticle] = []
        r.append(HelpArticle(
            id: "friends-add",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Friends  >  Add friends"),
            title: String(localized: "Add friends and answer requests"),
            summary: String(localized: "Find people by username, send requests and answer the ones you receive."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Friends"),
            ],
            steps: [
                String(localized: "Tap Add friends."),
                String(localized: "Search by username (at least 2 letters)."),
                String(localized: "Tap Add next to a person."),
                String(localized: "To answer a request, find it under Friend requests at the top and tap Accept or Decline."),
                String(localized: "To remove a friend, open the … menu next to them and choose Remove friend."),
            ],
            notes: [
                String(localized: "Requested means the request is waiting; tap it to cancel."),
                String(localized: "Requests you receive also appear in the bell on Home."),
            ],
            destination: .friends,
            related: ["friends-plans", "report-block", "bell"]
        ))
        r.append(HelpArticle(
            id: "friends-plans",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Friends  >  Friends plans"),
            title: String(localized: "See where your friends are going"),
            summary: String(localized: "See which events your friends are going to or are interested in."),
            path: [
                String(localized: "Home"),
                String(localized: "Friends plans"),
            ],
            steps: [
                String(localized: "On Home, find Friends plans."),
                String(localized: "Tap View to see a friend's events."),
                String(localized: "Tap Join them to buy a ticket for the same event, or View event to open it."),
                String(localized: "Tap Invite more to share Outly with someone who isn't on it yet."),
            ],
            notes: [
                String(localized: "Friends are shown as circles: a blue ring means they have a ticket, a white ring means they are interested."),
                String(localized: "Your friends can see your plans too. To switch that off, go to Profile > My Account > Preferences and turn off Friends can see my plans."),
            ],
            destination: nil,
            related: ["friends-add", "preferences", "interested"]
        ))
        r.append(HelpArticle(
            id: "bell",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Notifications  >  Bell"),
            title: String(localized: "The bell on Home"),
            summary: String(localized: "The bell shows what is new for you."),
            path: [
                String(localized: "Home"),
            ],
            steps: [
                String(localized: "Tap the bell at the top right of Home."),
                String(localized: "Tap an item to open it."),
            ],
            notes: [
                String(localized: "You see invitations to join a club team, friend requests, a ticket a friend sent you, guest list invitations, new events from clubs you follow and, for club staff, VIP tables ready to serve."),
                String(localized: "A number on the bell means something is waiting."),
            ],
            destination: nil,
            related: ["friends-add", "club-invite", "push"]
        ))
        r.append(HelpArticle(
            id: "push",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Notifications  >  Push"),
            title: String(localized: "Turn on push notifications"),
            summary: String(localized: "Get a push notification when something needs your attention."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Account"),
                String(localized: "Preferences"),
                String(localized: "Notifications"),
            ],
            steps: [
                String(localized: "Open Notifications under Preferences."),
                String(localized: "Tap Turn on notifications."),
            ],
            notes: [
                String(localized: "You get a notification for a ticket someone sent you, new events from clubs you follow, an invitation to a guest list and, for club staff, table service requests."),
                String(localized: "If you said no earlier, turn them on in iOS Settings."),
                String(localized: "Sign-up and password codes always arrive by email."),
            ],
            destination: .notifications,
            related: ["bell", "club-page", "preferences"]
        ))
        r.append(HelpArticle(
            id: "report-block",
            group: String(localized: "Friends & notifications"),
            topic: String(localized: "Safety  >  Report and block"),
            title: String(localized: "Report or block"),
            summary: String(localized: "Report an event, a club or a person, or block someone."),
            path: [],
            steps: [
                String(localized: "To report an event or a club, tap the … menu at the top right of its page and choose Report."),
                String(localized: "Pick a reason and tap Send."),
                String(localized: "To report or block a person, open the … menu next to their name."),
                String(localized: "Choose Report or Block."),
            ],
            notes: [
                String(localized: "You find the person's … menu in My Friends and when you search for friends."),
                String(localized: "We review reports within 24 hours."),
                String(localized: "People you block can't find you or send you requests, and they are not notified."),
                String(localized: "You can undo a block under Profile > My Account > Blocked users with Unblock; the friendship does not come back."),
            ],
            destination: nil,
            related: ["friends-add", "club-page", "event-page"]
        ))
        return r
    }
}

extension HelpArticle {
    static var account: [HelpArticle] {
        var r: [HelpArticle] = []
        r.append(HelpArticle(
            id: "password",
            group: String(localized: "Account"),
            topic: String(localized: "Login & Passwords  >  Reset"),
            title: String(localized: "Reset your password"),
            summary: String(localized: "Get back into your account with a code we send to your email."),
            path: [],
            steps: [
                String(localized: "On the login screen, tap Forgot password."),
                String(localized: "Enter your email."),
                String(localized: "Enter the code we send you, together with a new password."),
            ],
            notes: [
                String(localized: "If you are logged in, go to My Account > Password and security to change your password. This logs you out on all other devices."),
            ],
            destination: nil,
            related: ["security", "account", "profile"]
        ))
        r.append(HelpArticle(
            id: "security",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Security"),
            title: String(localized: "Change your password or sign out everywhere"),
            summary: String(localized: "Change your password, or sign out of all your devices."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Account"),
                String(localized: "Password and security"),
            ],
            steps: [
                String(localized: "Under Login, tap Edit."),
                String(localized: "Enter your current password and the new one twice."),
                String(localized: "Tap Done."),
                String(localized: "To sign out of all devices, tap Sign out under Sessions and confirm."),
            ],
            notes: [
                String(localized: "When you change your password, other devices are signed out; this one stays signed in."),
                String(localized: "Sign out under Sessions signs you out of all devices, including this one."),
                String(localized: "To log out of this device only, tap Log out at the bottom of Profile."),
            ],
            destination: .passwordSecurity,
            related: ["password", "profile", "delete"]
        ))
        r.append(HelpArticle(
            id: "profile",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Profile"),
            title: String(localized: "Edit your profile"),
            summary: String(localized: "Change your photo, username, phone number, date of birth and country."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Account"),
                String(localized: "Personal info"),
            ],
            steps: [
                String(localized: "Tap the picture with the + to add or change your profile photo."),
                String(localized: "On a card — Username, Phone number, Date of birth or Country — tap Edit."),
            ],
            notes: [
                String(localized: "Your username needs 3–20 characters: letters, numbers and underscore."),
                String(localized: "Your email can't be changed in the app; to change it, write to luka@outly.si."),
            ],
            destination: .personalInfo,
            related: ["account", "age", "security"]
        ))
        r.append(HelpArticle(
            id: "preferences",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Preferences"),
            title: String(localized: "Preferences, language and notifications"),
            summary: String(localized: "Set your favourites, the app language, notifications and who sees your plans."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Account"),
                String(localized: "Preferences"),
            ],
            steps: [
                String(localized: "Tap My preferences to save your favourite music genres, maximum distance, age range and ticket price range."),
                String(localized: "Tap Language to switch between English and Slovenščina."),
                String(localized: "Tap Notifications to turn on push notifications."),
                String(localized: "Turn Friends can see my plans on or off."),
            ],
            notes: [
                String(localized: "My preferences are saved on this phone. Switch on Use my preferences in Filters to apply them."),
                String(localized: "The language switches straight away."),
                String(localized: "Friends can see my plans decides whether your friends see which events you are going to."),
            ],
            destination: .preferences,
            related: ["filters", "push", "friends-plans"]
        ))
        r.append(HelpArticle(
            id: "payment",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Payment"),
            title: String(localized: "How payments work"),
            summary: String(localized: "Tickets are paid at checkout, through Stripe."),
            path: [
                String(localized: "Profile"),
                String(localized: "Payment"),
            ],
            steps: [],
            notes: [
                String(localized: "Tickets are paid at checkout."),
                String(localized: "Payments are processed by Stripe; Outly never sees or stores your card details, and the app does not hold a balance."),
                String(localized: "You can read this any time under Profile > Payment."),
            ],
            destination: .payment,
            related: ["buy", "refund", "my-tickets"]
        ))
        r.append(HelpArticle(
            id: "delete",
            group: String(localized: "Account"),
            topic: String(localized: "Account  >  Delete"),
            title: String(localized: "Delete your account"),
            summary: String(localized: "Permanently delete your account and personal data."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Account"),
                String(localized: "Delete account"),
            ],
            steps: [
                String(localized: "Enter your password to confirm."),
                String(localized: "Tap Delete Account and confirm."),
            ],
            notes: [
                String(localized: "Your personal data is removed; records of past purchases are kept anonymised, as required for accounting."),
                String(localized: "Valid tickets on a deleted account cannot be recovered, so use them or send them to a friend first."),
            ],
            destination: .deleteAccount,
            related: ["security", "my-tickets", "transfer"]
        ))
        return r
    }
}

extension HelpArticle {
    static var forClubs: [HelpArticle] {
        var r: [HelpArticle] = []
        r.append(HelpArticle(
            id: "club",
            group: String(localized: "For clubs"),
            topic: String(localized: "Clubs  >  List your club"),
            title: String(localized: "Add your club to Outly"),
            summary: String(localized: "Apply for a club account and, once approved, manage your club in Outly."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Account"),
                String(localized: "Request for creator"),
            ],
            steps: [
                String(localized: "Fill in the short form."),
                String(localized: "Follow the status of your request on the same screen."),
                String(localized: "Once approved, your profile switches to the business view. If it does not, log out and log in again."),
            ],
            notes: [
                String(localized: "We review requests by hand."),
                String(localized: "The business view has Edit your page, Dashboard, Events, My team and Settings."),
                String(localized: "Scanning tickets is under Profile > My Clubs — see Scan tickets at the door."),
                String(localized: "Owners can switch between the club and the personal profile: Settings > Switch to personal account, and back with My Account > Switch to club account."),
            ],
            destination: .requestForCreator,
            related: ["club-setup", "club-scanner", "club-team"]
        ))
        r.append(HelpArticle(
            id: "club-setup",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Club page"),
            title: String(localized: "Set up your club page"),
            summary: String(localized: "Add your logo and details so guests can find your club."),
            path: [
                String(localized: "Edit your page"),
                String(localized: "Club info"),
            ],
            steps: [
                String(localized: "In Set up your club, add a logo, the name, address and city, minimum age and music genres."),
                String(localized: "Tap Create club."),
                String(localized: "Later, tap Edit your page, then Club info, to change details."),
                String(localized: "Under Bar prices, tap Add item."),
                String(localized: "Enter a name and price (category is optional) and tap Save."),
            ],
            notes: [
                String(localized: "You see Set up your club the first time you open the club profile."),
                String(localized: "If you organize events without your own venue, switch on I organize events without my own venue — there is then no address or map pin and you choose the venue for each event."),
                String(localized: "Club info (also under Settings) covers: Club name, Phone number, Website, Instagram, Email, About club, Address, City, Minimum age, Music genres, Slideshow (up to 3 photos), Club video and Bar prices."),
                String(localized: "Seller details (company name, registered office, registration number, tax number) and VAT status are shown to buyers before payment. Only the club owner can change them."),
            ],
            destination: nil,
            related: ["club", "club-events", "club-dashboard"]
        ))
        r.append(HelpArticle(
            id: "club-events",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Events"),
            title: String(localized: "Create and edit events"),
            summary: String(localized: "Publish an event with tickets, and change or cancel it later."),
            path: [
                String(localized: "Events"),
            ],
            steps: [
                String(localized: "Open Events and tap Add event (managers: Profile > My Clubs > your club > Create event)."),
                String(localized: "Fill in Title and Description."),
                String(localized: "Under When, set Starts, and Has end time if the event has an end."),
                String(localized: "Under Who, set Minimum age and music genres."),
                String(localized: "Under Tickets, set Price in EUR, Capacity and an optional external ticket link."),
                String(localized: "Choose a poster, switch on Published (visible to everyone) and tap Save."),
            ],
            notes: [
                String(localized: "Leave Price empty if tickets are not sold on Outly; 0 means free entry."),
                String(localized: "Tap an event in the list to edit it. To remove one, tap Cancel or delete event."),
                String(localized: "If tickets were already sold, the event is cancelled instead of deleted, so buyers keep proof of purchase."),
                String(localized: "Past events can get an Event video that guests see on your club page — only your three most popular past events qualify."),
            ],
            destination: nil,
            related: ["club-setup", "club-dashboard", "club-vip"]
        ))
        r.append(HelpArticle(
            id: "club-dashboard",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Dashboard"),
            title: String(localized: "Read your dashboard"),
            summary: String(localized: "See your sales, payout, followers and how each event is doing."),
            path: [
                String(localized: "Dashboard"),
            ],
            steps: [
                String(localized: "Under Sales, choose By year, By month or By week."),
                String(localized: "Read Total revenue, Tickets sold, Outly fee and Your payout below."),
                String(localized: "Open Check activity for clicks on your profile and events, and your Followers."),
                String(localized: "Under Event performance, tap an event for Door check-in and VIP reservations, or tap View all."),
            ],
            notes: [
                String(localized: "Sales shows revenue for the period you choose. Your payout is what is left after fee and refunds."),
                String(localized: "Staff activity shows what your team scanned."),
                String(localized: "While payments are in test mode, a TEST label shows and no money moves."),
            ],
            destination: nil,
            related: ["club-events", "club-scanner", "club-team"]
        ))
        r.append(HelpArticle(
            id: "club-scanner",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Scanner"),
            title: String(localized: "Scan tickets at the door"),
            summary: String(localized: "Scan guests' QR codes with the camera and let them in."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Clubs"),
            ],
            steps: [
                String(localized: "Tap your club, then Scan ticket."),
                String(localized: "Point the camera at the guest's QR code."),
                String(localized: "Green WELCOME IN means you let the guest in."),
                String(localized: "Red means no. Do not let the guest in."),
                String(localized: "Tap Next for the following guest."),
            ],
            notes: [
                String(localized: "Owners, managers and door staff scan with the camera. Owners first switch to their personal profile: Settings > Switch to personal account."),
                String(localized: "The scanner opens straight away — you don't pick an event. It covers the club's events from 12 hours before the start until 6 hours after the end."),
                String(localized: "Red is for example ALREADY SCANNED, REFUNDED, CANCELLED, NOT PAID or INVALID CODE. A gold bar marks a VIP table, a white bar a guest list guest."),
                String(localized: "Yellow means the phone can't check the ticket by itself. If you decide to let the guest in, tap Let in; the server checks later and anything wrong appears under Conflicts (triangle, top right)."),
                String(localized: "Use the flashlight button in dark rooms."),
                String(localized: "The scanner also works without signal: it downloads the ticket list and sends scans when you are back online. Until the list is downloaded, tickets can only be checked with a connection."),
                String(localized: "You can also check guests in by hand: Dashboard > event > Check in."),
            ],
            destination: .myClubs,
            related: ["club-team", "club-dashboard", "door"]
        ))
        r.append(HelpArticle(
            id: "club-team",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Team"),
            title: String(localized: "Invite your team"),
            summary: String(localized: "Invite people to your club's team and choose what each can do."),
            path: [
                String(localized: "My team"),
            ],
            steps: [
                String(localized: "Open My team (managers: Profile > My Clubs > your club > Team)."),
                String(localized: "Tap Invite member."),
                String(localized: "Enter their Outly email and choose a role."),
                String(localized: "Tap Send invite."),
                String(localized: "To remove someone, or cancel a pending invitation, tap the x next to the name."),
            ],
            notes: [
                String(localized: "They need an Outly account with that email; the invitation reaches them in the app and they join when they accept."),
                String(localized: "Manager — events, sales, club page and door staff; only the owner can add managers."),
                String(localized: "Door staff — scans tickets at the door, nothing else."),
                String(localized: "Bartender — sees VIP tables to serve and marks them delivered, with no guest details."),
                String(localized: "A removed person loses access to the club tools right away."),
            ],
            destination: nil,
            related: ["club-invite", "club-scanner", "club-service"]
        ))
        r.append(HelpArticle(
            id: "club-invite",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Invitations"),
            title: String(localized: "Accept an invitation to a club team"),
            summary: String(localized: "Join a club's team by accepting its invitation."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Clubs"),
            ],
            steps: [
                String(localized: "Find the invitation in the bell on Home, or in My Clubs (bell, top right)."),
                String(localized: "Open the invitation."),
                String(localized: "Tap Accept to join, or Reject to decline."),
            ],
            notes: [
                String(localized: "The club then shows under My Clubs, with the tools for your role."),
                String(localized: "To leave a team, open the club under My Clubs and tap Leave the team. The club can invite you again."),
            ],
            destination: .myClubs,
            related: ["club-team", "bell", "club-scanner"]
        ))
        r.append(HelpArticle(
            id: "club-vip",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  VIP tables"),
            title: String(localized: "Set up VIP tables and phone reservations"),
            summary: String(localized: "Set up VIP tables for an event, and take reservations by phone."),
            path: [],
            steps: [
                String(localized: "Open the event and go to VIP tables."),
                String(localized: "Choose Use the venue's layout, Own layout for this event or No VIP tables."),
                String(localized: "Tap Edit tables and layout to add tables, drag them into place and set seats and price."),
                String(localized: "To take a phone reservation, go to Dashboard > event > VIP reservations."),
                String(localized: "On a free table, tap Mark as reserved."),
                String(localized: "Enter the Guest name and a Note, and tap Reserve."),
                String(localized: "To free the table again, tap Release."),
            ],
            notes: [
                String(localized: "If the app says Set up VIP tables at outly.si/app, the floor plan and prices are set up there. Organizers without their own venue can also do it in the app."),
                String(localized: "Save the event first."),
                String(localized: "Only owners and managers can take phone reservations."),
            ],
            destination: nil,
            related: ["club-events", "club-service", "vip-book"]
        ))
        r.append(HelpArticle(
            id: "club-service",
            group: String(localized: "For clubs"),
            topic: String(localized: "For clubs  >  Table service"),
            title: String(localized: "Serve VIP tables"),
            summary: String(localized: "See which VIP tables have arrived and mark them as served."),
            path: [
                String(localized: "Profile"),
                String(localized: "My Clubs"),
            ],
            steps: [
                String(localized: "Tap your club, then Table service."),
                String(localized: "Choose the event at the top, if there is more than one."),
                String(localized: "Find the table in the list once door staff have scanned its VIP ticket."),
                String(localized: "Tap Delivered once the table has been served."),
                String(localized: "Tapped by mistake? Tap Undo."),
            ],
            notes: [
                String(localized: "Owners, managers and bartenders can serve tables. Owners switch to their personal profile first."),
                String(localized: "Each table shows its package and the time it was scanned."),
                String(localized: "The list refreshes by itself; pull down to refresh it yourself."),
                String(localized: "Staff also get a notification when a table is ready to serve."),
            ],
            destination: .myClubs,
            related: ["club-team", "club-scanner", "club-vip"]
        ))
        return r
    }
}
