import SwiftUI

/// Moj racun -> Preferences: My preferences, Notifications, Language.
/// Isti slog kot MyAccountView (vrstice OutlyMenuRowButton, potisnjeno na obstojeci
/// NavigationStack — brez lastnega, da gumb nazaj ostane).
struct PreferencesView: View {
    @EnvironmentObject private var jezik: Jezik
    @EnvironmentObject private var session: SessionStore

    /// "Friends can see my plans" (users.share_plans_with_friends, migracija 016). Shranjeno na
    /// strezniku prek PATCH /me; lokalno stanje se ob napaki vrne na prejsnje.
    @State private var sharePlans = false
    @State private var sharePlansError: String?
    @State private var sharePlansSaving = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Preferences")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                VStack(spacing: 12) {
                    NavigationLink(destination: MyPreferencesView()) {
                        OutlyMenuRowButton(icon: "slider.horizontal.3", title: "My preferences")
                    }
                    NavigationLink(destination: NotificationsView()) {
                        OutlyMenuRowButton(icon: "bell", title: "Notifications")
                    }
                    NavigationLink(destination: LanguageView()) {
                        OutlyMenuRowButton(icon: "globe", title: "Language", value: jezik.ime)
                    }
                }

                Text("My preferences are used by “Use my preferences” in Filters.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                OutlySettingsCard("Friends") {
                    OutlySettingsToggleRow(title: "Friends can see my plans", isOn: $sharePlans)
                        .disabled(sharePlansSaving)
                }

                Text("When on, your friends see which events you have a ticket for under “Your friends' plans”. Only friends, never anyone else.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                if let sharePlansError {
                    Text(sharePlansError)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { sharePlans = session.me?.sharePlansWithFriends ?? false }
        .onChange(of: sharePlans) { _, nova in
            guard nova != (session.me?.sharePlansWithFriends ?? false) else { return }
            Task { await shraniSharePlans(nova) }
        }
    }

    private func shraniSharePlans(_ vrednost: Bool) async {
        sharePlansSaving = true
        sharePlansError = nil
        defer { sharePlansSaving = false }
        do {
            var u = APIClient.MeUpdate()
            u.sharePlansWithFriends = vrednost
            let me = try await APIClient.shared.updateMe(token: session.token, u)
            session.me = me
        } catch {
            sharePlansError = error.userMessage
            sharePlans = session.me?.sharePlansWithFriends ?? false
        }
    }
}
