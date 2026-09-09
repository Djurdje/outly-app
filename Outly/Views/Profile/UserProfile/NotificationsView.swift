import SwiftUI

/// Obvestila: potisnih obvestil (APNs) se ni, zato zaslon pokaze, kaj uporabnik
/// dobiva po e-posti, in prazno stanje za obvestila v aplikaciji.
/// Ko pridejo APNs, tu pride seznam iz backenda.
struct NotificationsView: View {
    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("Notifications")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(spacing: 12) {
                        Image(systemName: "bell")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundColor(.outlyBlue)
                        Text("No notifications yet")
                            .font(.title3).fontWeight(.semibold).foregroundColor(.white)
                        Text("Updates about your tickets and events\nwill show up here.")
                            .font(.footnote).foregroundColor(.gray).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .padding(.bottom, 20)

                    Text("What we email you")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))

                    vrstica(icon: "checkmark.seal", title: "Account", text: "Confirmation code at sign-up and password reset codes.")

                    Text("Coming soon")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 6)

                    vrstica(icon: "ticket", title: "Tickets", text: "A ticket sent to you by a friend, cancelled events and refunds.")
                    vrstica(icon: "building.2", title: "Creators", text: "The decision on your request to list a club.")
                    vrstica(icon: "bell.badge", title: "Tonight", text: "Push notifications about events near you.")

                    Text("You can always check your tickets under Profile > Tickets.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 6)

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func vrstica(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.outlyBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                Text(text).font(.caption).foregroundColor(.gray).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.gray.opacity(0.14))
        .cornerRadius(16)
    }
}
