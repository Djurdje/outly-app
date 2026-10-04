import SwiftUI
import SafariServices

/// Stripova placilna stran, ki jo odpira `.fullScreenCover(item:)`. `Identifiable`, da je vsako odprtje nov zaslon.
struct StripeStran: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

/// SFSafariViewController v SwiftUI (SafariServices je sistemski framework, ne paket). Kartica se vnasa na Stripovi strani,
/// aplikacija je nikoli ne vidi (PCI DSS). Ko uporabnik tapne Done, poklice `onKonec`; zaslon, ki je Safari odprl, zapre
/// `.fullScreenCover` (binding `item` postane nil) in njegov `onDismiss` osvezi narocilo.
struct StripeSafariView: UIViewControllerRepresentable {
    let url: URL
    var onKonec: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onKonec: onKonec) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .done
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onKonec: () -> Void
        init(onKonec: @escaping () -> Void) { self.onKonec = onKonec }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onKonec()
        }
    }
}

/// Obvestilo pod nakupnim obrazcem, ko Stripe se ni potrdil placila (webhook zakasni nekaj sekund ali uporabnik se ni placal):
/// kratko sporocilo in gumb za ponovno branje. Gumb je nevtralen (modra samo na glavnem gumbu).
struct PlaciloSeVeriKartica: View {
    let preverjanje: Bool
    let onPreveri: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NapotekKartica(besedilo: String(localized: "Checking your payment … your tickets will show up in Profile → Tickets in a few seconds."))

            Button {
                onPreveri()
            } label: {
                Group {
                    if preverjanje {
                        ProgressView().tint(.white)
                    } else {
                        Text("Check again")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(preverjanje)
        }
    }
}
