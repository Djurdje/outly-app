import SwiftUI

/// Moj racun -> Preferences: My preferences, Notifications, Language.
/// Isti slog kot MyAccountView (vrstice OutlyMenuRowButton, potisnjeno na obstojeci
/// NavigationStack — brez lastnega, da gumb nazaj ostane).
struct PreferencesView: View {
    @EnvironmentObject private var jezik: Jezik

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
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}
