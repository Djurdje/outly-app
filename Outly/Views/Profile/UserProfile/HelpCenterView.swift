import SwiftUI

/// Pomoc: iskanje po clankih, seznam clankov (vsak vodi na HelpArticleView)
/// in stik. Vsebina je v aplikaciji (brez backenda), opisuje dejanske tokove Outlyja.
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

                    Text(search.isEmpty ? "Popular articles" : "Results")
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
                        VStack(spacing: 12) {
                            ForEach(filtered) { a in
                                NavigationLink { HelpArticleView(article: a) } label: {
                                    HelpCard(topLine: a.topic, title: a.title)
                                }
                                .buttonStyle(.plain)
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

struct HelpArticle: Identifiable {
    let id: String
    let topic: String
    let title: String
    let body: String

    static let all: [HelpArticle] = [
        HelpArticle(
            id: "account",
            topic: "Getting started  >  Account",
            title: "Creating an account",
            body: """
            Tap Sign up, enter your username, email and a password. We send a 6-digit code to your email — type it in to confirm your address.

            Then complete your profile: date of birth, country and the music you like. Your date of birth is used only to check age limits on events.

            You must be at least 15 to use Outly.
            """
        ),
        HelpArticle(
            id: "password",
            topic: "Login & Passwords  >  Reset",
            title: "Reset your password",
            body: """
            On the login screen tap Forgot password and enter your email. We send you a code; enter it together with a new password.

            If you are logged in, go to My Account > Password and security to change your password. This logs you out on all other devices.
            """
        ),
        HelpArticle(
            id: "buy",
            topic: "Tickets  >  Buying",
            title: "How to buy a ticket",
            body: """
            Open an event and tap the price bar under the poster. Choose how many tickets you want and confirm.

            Your tickets appear under Profile > Tickets right away. Each ticket has its own QR code.

            Events marked 18+ require a date of birth in your profile.
            """
        ),
        HelpArticle(
            id: "door",
            topic: "Tickets  >  At the door",
            title: "Using your ticket at the door",
            body: """
            Open Profile > Tickets and tap the ticket. Show the QR code to the staff at the entrance — they scan it with Outly.

            A ticket can be scanned only once. Screenshots work, but keep your brightness up so the code is readable.
            """
        ),
        HelpArticle(
            id: "transfer",
            topic: "Tickets  >  Friends",
            title: "Send a ticket to a friend",
            body: """
            Bought tickets for the whole group? Open a ticket and tap Send to a friend, then enter your friend's Outly email.

            The ticket moves to their account with a new QR code — your old code stops working. Your friend needs an Outly account with a confirmed email and must meet the event's age limit.

            Tickets can be sent until the event starts.
            """
        ),
        HelpArticle(
            id: "refund",
            topic: "Refunds and cancellations",
            title: "Refunds and cancelled events",
            body: """
            Tickets are sold by the club; Outly is the marketplace. Because a ticket is for a specific date, there is no 14-day right of withdrawal after purchase.

            If the club cancels an event, you are entitled to a refund from the club, to your original payment method.

            For anything else, contact the club or write to luka@outly.si with your ticket number.
            """
        ),
        HelpArticle(
            id: "age",
            topic: "Events  >  Age limits",
            title: "Age limits",
            body: """
            You must be 15 or older to use Outly. Some events are 18+ — this is shown on the event and you need a date of birth in your profile to buy tickets for them.

            The club may ask for an ID at the door.
            """
        ),
        HelpArticle(
            id: "club",
            topic: "Clubs  >  List your club",
            title: "Add your club to Outly",
            body: """
            Go to My Account > Request for creator and fill in the short form. We review requests by hand — you can follow the status on the same screen.

            Once approved, your profile switches to the business view: Dashboard, Events, Scan tickets and Settings.
            """
        ),
        HelpArticle(
            id: "delete",
            topic: "Account  >  Delete",
            title: "Delete your account",
            body: """
            Go to My Account > Delete account. Your personal data is removed; records of past purchases are kept anonymised, as required for accounting.

            Valid tickets on a deleted account cannot be recovered, so use them or send them to a friend first.
            """
        ),
    ]
}
