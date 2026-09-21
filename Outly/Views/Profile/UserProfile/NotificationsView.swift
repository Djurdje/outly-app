import SwiftUI

/// Obvestila — po Figmi "notification" (113:955): skupine s stikali.
/// Potisnih obvestil (APNs) se ni; izbire se shranijo na napravi (@AppStorage) in bodo
/// veljale, ko pridejo potisna obvestila. To uporabniku povemo v opombi spodaj.
struct NotificationsView: View {
    @AppStorage("notif.eventReminders")   private var eventReminders = true
    @AppStorage("notif.newEventsInCity")  private var newEventsInCity = true
    @AppStorage("notif.ticketPurchase")   private var ticketPurchase = true
    @AppStorage("notif.ticketReminders")  private var ticketReminders = true
    @AppStorage("notif.specialOffers")    private var specialOffers = false
    @AppStorage("notif.appUpdates")       private var appUpdates = true
    @AppStorage("notif.securityAlerts")   private var securityAlerts = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {

                Text("Notifications")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                OutlySettingsCard("Event updates") {
                    OutlySettingsToggleRow(title: "Event reminders", isOn: $eventReminders)
                    OutlySettingsToggleRow(title: "New events in my city", isOn: $newEventsInCity)
                }

                OutlySettingsCard("Tickets") {
                    OutlySettingsToggleRow(title: "Ticket purchase confirmation", isOn: $ticketPurchase)
                    OutlySettingsToggleRow(title: "Ticket reminders", isOn: $ticketReminders)
                }

                OutlySettingsCard("Special offers") {
                    OutlySettingsToggleRow(title: "Offers from clubs", isOn: $specialOffers)
                }

                OutlySettingsCard("App & account") {
                    OutlySettingsToggleRow(title: "App updates & announcements", isOn: $appUpdates)
                    OutlySettingsToggleRow(title: "Security alerts", isOn: $securityAlerts)
                }

                Text("Push notifications are coming soon — your choices are saved. Sign-up and password codes always arrive by email.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}
