import SwiftUI
import UIKit
import UserNotifications

/// Obvestila: stanje sistemskega dovoljenja za potisna obvestila (APNs, outly-app#74), gumb za vklop in seznam,
/// kaj obvestila vsebujejo. Stikal po vrstah obvestil ni: strezniku ne povejo nic, zato bi bila lazna (trzenjskih
/// obvestil ni). Vrstni red dovoljenja: `.notDetermined` -> sistemski poziv (PushObvestila.zahtevajDovoljenje),
/// `.denied` -> nastavitve obvestil v iOS (iOS poziva ne pokaze drugic).
struct NotificationsView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// nil, dokler stanje ni prebrano (takrat se gumb ne kaze, da ne utripa).
    @State private var dovoljenje: UNAuthorizationStatus?
    @State private var zahtevaTece = false

    private var jeVklopljeno: Bool {
        guard let dovoljenje else { return false }
        return PushObvestila.jeOdobreno(dovoljenje)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {

                Text("Notifications")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                OutlySettingsCard("Push notifications") {
                    vrsticaStanja

                    if dovoljenje != nil && !jeVklopljeno {
                        OutlyPrimaryButton(title: "Turn on notifications", isLoading: zahtevaTece) {
                            vklopi()
                        }
                    }
                }

                OutlySettingsCard("What you'll get") {
                    vrsticaVsebine(ikona: "ticket", besedilo: Text("A ticket someone sent you"))
                    vrsticaVsebine(ikona: "calendar", besedilo: Text("New events from clubs you follow"))
                    vrsticaVsebine(ikona: "person.badge.plus", besedilo: Text("Invitations to a guest list"))
                    vrsticaVsebine(ikona: "wineglass", besedilo: Text("Table service requests, for club staff"))
                }

                Text("Sign-up and password codes always arrive by email.")
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
        .task { await osvezi() }
        // Vrnitev iz iOS nastavitev ali iz sistemskega poziva: stanje se je lahko spremenilo.
        .onChange(of: scenePhase) { _, faza in
            if faza == .active { Task { await osvezi() } }
        }
    }

    // MARK: - Vrstice

    private var vrsticaStanja: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: jeVklopljeno ? "bell.badge" : "bell.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                if dovoljenje == nil {
                    Text("Checking…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    (jeVklopljeno ? Text("Notifications are on") : Text("Notifications are off"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    pojasnilo
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pojasnilo: Text {
        if jeVklopljeno { return Text("You can change this any time in iOS Settings.") }
        if dovoljenje == .denied { return Text("Notifications are blocked in iOS Settings. Turn them on there to get updates.") }
        return Text("Allow Outly to send you notifications to get the updates below.")
    }

    private func vrsticaVsebine(ikona: String, besedilo: Text) -> some View {
        HStack(spacing: 14) {
            Image(systemName: ikona)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 24)
            besedilo
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    // MARK: - Dovoljenje

    private func osvezi() async {
        let nastavitve = await UNUserNotificationCenter.current().notificationSettings()
        dovoljenje = nastavitve.authorizationStatus
    }

    private func vklopi() {
        guard !zahtevaTece else { return }
        if dovoljenje == .denied {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
        zahtevaTece = true
        Task { @MainActor in
            await PushObvestila.deljen.zahtevajDovoljenje()
            await osvezi()
            zahtevaTece = false
        }
    }
}
