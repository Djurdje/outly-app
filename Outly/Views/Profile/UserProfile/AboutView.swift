import SwiftUI
import StoreKit

/// O aplikaciji. Pogoji uporabe in politika zasebnosti morata biti dostopna IZ aplikacije
/// (Apple 5.1.1, ZVOP-2) — prej sta vrstici vodili na prazen zaslon z besedilom "Privacy".
/// "About us" in "Rate this app" sta bila prazna zaslona; "Rate" zdaj odpre App Store
/// oceno, "About us" kratek opis s kontaktom podjetja.
struct AboutView: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 12) {

                Text("About")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 6)

                NavigationLink { AboutUsView() } label: {
                    OutlyMenuRowButton(icon: "questionmark.circle", title: "About us")
                }
                .buttonStyle(.plain)

                Button { requestReview() } label: {
                    OutlyMenuRowButton(icon: "hand.thumbsup", title: "Rate this app")
                }
                .buttonStyle(.plain)

                Link(destination: LegalLinks.terms) {
                    OutlyMenuRowButton(icon: "doc.text", title: "Terms of Service")
                }
                .buttonStyle(.plain)

                Link(destination: LegalLinks.privacy) {
                    OutlyMenuRowButton(icon: "doc.on.doc", title: "Privacy Policy")
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutUsView: View {
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 14) {
                Text("About Outly")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 6)

                Text("Outly helps you find where to go tonight: clubs, events and tickets.")
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Text("NEXT DIMENSIONS, družba za marketing, d.o.o.\nTrebče 81, 3256 Bistrica ob Sotli, Slovenia")
                    .font(.footnote)
                    .foregroundColor(.gray)

                Link("luka@outly.si", destination: URL(string: "mailto:luka@outly.si")!)
                    .font(.footnote)
                    .foregroundColor(.outlyBlue)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
