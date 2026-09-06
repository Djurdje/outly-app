import SwiftUI

struct HelpCenterView: View {
    @State private var search = ""

    var body: some View {
        Screen {
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

                SearchBar(text: $search)

                Text("Popular articles")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 6)

                VStack(spacing: 12) {
                    HelpCard(topLine: "Getting started  > Creating an account", title: "Creating an account")
                    HelpCard(topLine: "Login & Passwords  > Log in", title: "Reset password")
                    HelpCard(topLine: "Tickets  > Buying tickets", title: "How to purchase a ticket")
                    HelpCard(topLine: "Refunds and cancellations  > Request a refund", title: "How to request a refund")
                    HelpCard(topLine: "You did not find an answer?", title: "Contact us")
                }

                Text("Topics")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TopicsView: View {
    var body: some View {
        Screen {
            VStack(spacing: 14) {
                Text("Topics")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                TopicsCard(title: "Getting Started", items: [
                    "How to create an account",
                    "How to log in for the first time",
                    "Connecting your Google or Apple account"
                ])

                TopicsCard(title: "Login & Passwords", items: [
                    "Resetting your password",
                    "Two-factor authentication (2FA)",
                    "Troubleshooting login issues"
                ])

                TopicsCard(title: "Account Settings", items: [
                    "How to change your email address",
                    "How to delete your account",
                    "Changing the app language"
                ])

                TopicsCard(title: "Tickets", items: [
                    "How to buy ticket",
                    "How to use ticket",
                    "How to refund ticket"
                ])

                TopicsCard(title: "Payment", items: [
                    "How to update payment method",
                    "How to delete card",
                    "How to add money"
                ])

                TopicsCard(title: "Technical Issues", items: [
                    "Notification problems",
                    "Connection errors",
                    "Syncing issues"
                ])

                TopicsCard(title: "Contact Support", items: [
                    "Support email address",
                    "Live chat"
                ])

                Spacer(minLength: 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TopicsCard: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)

            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color("blackColor").opacity(0.25), Color.gray.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}
