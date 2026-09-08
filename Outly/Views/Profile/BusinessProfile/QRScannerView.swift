import SwiftUI
import UIKit
import AVFoundation

/// Skener QR za vrata (AVFoundation, brez zunanjih knjiznic). Vsak prebran QR gre na
/// POST /business/tickets/scan; streznik preveri podpis in stanje. Ista koda se
/// ne poslje dvakrat zapored, dokler je v kadru (sicer bi vsak okvir sprozil klic).
@MainActor
struct QRScannerView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var zadnjaKoda = ""
    @State private var rezultat: ScanResult?
    @State private var isChecking = false
    @State private var dovoljenje: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var stevec = (ok: 0, zavrnjeno: 0)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if dovoljenje == .authorized {
                KameraQR { koda in obravnavaj(koda) }
                    .ignoresSafeArea()
                okvir
            } else if dovoljenje == .notDetermined {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("Asking for camera access…").foregroundColor(.white.opacity(0.7))
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 40)).foregroundColor(.outlyBlue)
                    Text("Camera access is off")
                        .font(.headline).foregroundColor(.white)
                    Text("Allow the camera in Settings → Outly to scan tickets at the door.")
                        .font(.subheadline).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .foregroundColor(.outlyBlue)
                }
                .padding(30)
            }

            VStack {
                Spacer()
                rezultatKartica
            }
            .padding(18)
        }
        .navigationTitle("Scan tickets")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task {
            if dovoljenje == .notDetermined {
                let ok = await AVCaptureDevice.requestAccess(for: .video)
                dovoljenje = ok ? .authorized : .denied
            }
        }
    }

    private var okvir: some View {
        VStack {
            Text("Point the camera at the ticket's QR code")
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding(.top, 20)
            Spacer()
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 240, height: 240)
            Spacer()
            HStack(spacing: 18) {
                Text("\(stevec.ok) in").foregroundColor(.green)
                Text("\(stevec.zavrnjeno) refused").foregroundColor(.red)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(.bottom, 120)
        }
    }

    @ViewBuilder
    private var rezultatKartica: some View {
        if isChecking {
            HStack(spacing: 10) { ProgressView().tint(.white); Text("Checking…").foregroundColor(.white) }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let r = rezultat {
            let ok = r.result == "ok"
            HStack(spacing: 12) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 32))
                    .foregroundColor(ok ? .green : .red)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ok ? "WELCOME IN" : naslovNapake(r.result))
                        .font(.headline).foregroundColor(.white)
                    Text(r.message).font(.subheadline).foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Button("Next") { rezultat = nil; zadnjaKoda = "" }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(14)
            .background((ok ? Color.green : Color.red).opacity(0.25))
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func naslovNapake(_ r: String) -> String {
        switch r {
        case "already_used": return "ALREADY SCANNED"
        case "wrong_club": return "WRONG CLUB"
        case "unknown": return "UNKNOWN TICKET"
        case "unpaid": return "NOT PAID"
        default: return "REFUSED"
        }
    }

    private func obravnavaj(_ koda: String) {
        // Ista koda ostane v kadru vec okvirjev zapored; klicemo samo ob spremembi in ko ni odprtega rezultata.
        guard koda != zadnjaKoda, !isChecking, rezultat == nil else { return }
        zadnjaKoda = koda
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let r = try await APIClient.shared.scanTicket(token: session.token, qr: koda)
                rezultat = r
                if r.result == "ok" { stevec.ok += 1 } else { stevec.zavrnjeno += 1 }
                let g = UINotificationFeedbackGenerator()
                g.notificationOccurred(r.result == "ok" ? .success : .error)
            } catch {
                rezultat = ScanResult(result: "error", message: error.userMessage, usedAt: nil)
            }
        }
    }
}

// MARK: - AVFoundation most

/// Kamera + branje QR. Vrne surovo vsebino kode; odlocanje je v strezniku.
struct KameraQR: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> KameraQRController {
        let c = KameraQRController()
        c.onCode = onCode
        return c
    }

    func updateUIViewController(_ uiViewController: KameraQRController, context: Context) {}
}

final class KameraQRController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (@MainActor (String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            // startRunning blokira; ne na glavni niti.
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
        }
    }

    // Zahteva protokola ni izolirana na glavno nit (UIViewController je @MainActor),
    // zato nonisolated + skok na MainActor za klic nazaj v SwiftUI.
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr, let s = obj.stringValue, !s.isEmpty else { return }
        Task { @MainActor in self.onCode?(s) }
    }
}
