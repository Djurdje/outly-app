import SwiftUI

struct ReguestForCreatorView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Ta pogled se POTISNE na obstojeci NavigationStack (ProfileView/MyAccountView);
        // gnezden NavigationStack bi skril gumb nazaj in zlomil navigacijo.
        Group {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {

                    Text("Request a Business Account")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Partner with Outly and reach more nightlife lovers")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Join our platform and promote your club, bar, or event to thousands of tourists and locals. With a business account, you can publish events, sell tickets directly through the app, and connect with your audience in real time.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.70))
                            .lineSpacing(3)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Who can apply?")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            BulletRow(text: "Nightclubs")
                            BulletRow(text: "Bars with live music")
                            BulletRow(text: "Event organizers & promoters")
                            BulletRow(text: "Festivals and special nightlife events")
                        }
                        .foregroundColor(.white.opacity(0.70))
                    }

                    // Obrazec za ustvarjalce je na spletni strani (Creator.html); prijave
                    // gredo v tabelo creator_applications in na luka@/fedja@outly.si.
                    Link(destination: LegalLinks.creatorForm) {
                        OutlyInfoCardButton(
                            icon: "doc.text",
                            title: "Application form",
                            value: "Fill your application form",
                            description: "Opens outly.si in your browser.",
                            actionTitle: ""
                        ) {}
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarBackButtonHidden(false) // sistemski back
        }
        .preferredColorScheme(.dark)
    }
}

private struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("–")
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 14, weight: .regular))
        }
    }
}
