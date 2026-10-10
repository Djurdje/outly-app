import UIKit
import UserNotifications

/// Delegat za potisna obvestila (SwiftUI: `@UIApplicationDelegateAdaptor` v OutlyApp). Samo prestavi dogodke naprej:
/// zeton -> `PushObvestila`, dotik na obvestilo -> `PushUsmerjevalnik.postavi` (cilj prevzame MainTabView, ko je pripravljen).
final class OutlyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Delegat mora biti nastavljen ze ob zagonu: dotik na obvestilo na HLADNEM zagonu se dostavi takoj po tem.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushObvestila.deljen.pridobljenZeton(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushObvestila.deljen.registracijaNeuspela(error)
    }

    // MARK: - UNUserNotificationCenterDelegate
    // Zahteve protokola niso izolirane na glavno nit, zato nonisolated + skok na MainActor (kot pri QR skenerju).

    /// Obvestilo prispe, medtem ko je aplikacija odprta: banner + zvok, Home osvezi stevec na zvoncu.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        Task { @MainActor in
            NotificationCenter.default.post(name: .outlyPushPrispel, object: nil)
        }
    }

    /// Dotik na obvestilo (aplikacija je tekla, je v ozadju ali se zaganja). Neznan tip ali manjkajoc id: cilja ni, aplikacija se samo odpre.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let cilj = PushCilj(userInfo: response.notification.request.content.userInfo) {
            Task { @MainActor in
                PushUsmerjevalnik.deljen.postavi(cilj)
            }
        }
        completionHandler()
    }
}
