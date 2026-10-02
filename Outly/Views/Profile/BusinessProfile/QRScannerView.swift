import SwiftUI
import UIKit
import AVFoundation

/// Skener QR za vrata, ki dela tudi brez povezave (backend issue #86).
///
/// 1. Vratar izbere dogodek. Javni kljuc in seznam vstopnic se prenesejo na telefon (in osvezujejo na ~2 min).
/// 2. Koda v2 se preveri LOKALNO (podpis Ed25519, dogodek, seznam, ze skenirano na tem telefonu): zeleno takoj,
///    sken gre v trajno vrsto, ki se poslje prek scan-batch takoj in periodicno. Streznik ostane razsodnik.
/// 3. Stara koda v1 se na telefonu ne da preveriti: s povezavo jo preveri obstojec POST /scan, brez nje je rumeno.
///
/// Vse odlocanje je v SkenSeja (testirano); ta zaslon samo kaze stanje: povezava, stevilo cakajocih, cas zadnjega prenosa seznama.
@MainActor
struct QRScannerView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var seja: SkenSeja
    @State private var omrezje = SkenOmrezje()

    @State private var zadnjaKoda = ""
    @State private var prikaz: SkenPrikaz?
    /// Ena koda naenkrat (ni prikazano; »Checking…« kaze seja samo ob spletnem preverjanju).
    @State private var obdelava = false
    @State private var dovoljenje: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var pokaziKonflikte = false
    /// Koda v1, ki jo vratar zeli spustiti sam: najprej potrdi (P4), sele nato gre v vrsto.
    @State private var zaPotrditev: String?

    /// `clubId`: klub, v katerem vratar dela (MyClubDetailView). Vrsta skenov je shranjena po klubu.
    init(clubId: Int? = nil) {
        _seja = StateObject(wrappedValue: SkenSeja(klubId: clubId ?? IzbraniKlub.id ?? 0, api: SkenApiZivi()))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if seja.dogodek == nil {
                izbiraDogodka
            } else {
                skener
            }
        }
        .navigationTitle(seja.dogodek?.title ?? String(localized: "Scan tickets"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !seja.konflikti.isEmpty {
                    Button { pokaziKonflikte = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("\(seja.konflikti.count)")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    }
                    .accessibilityLabel(Text("Conflicts"))
                }
                if seja.dogodek != nil {
                    Button { zamenjajDogodek() } label: { Image(systemName: "calendar") }
                        .accessibilityLabel(Text("Change event"))
                }
            }
        }
        .sheet(isPresented: $pokaziKonflikte) {
            SkenKonfliktiView(seja: seja)
        }
        .confirmationDialog("Let this guest in?", isPresented: Binding(get: { zaPotrditev != nil }, set: { if !$0 { zaPotrditev = nil } }),
                            titleVisibility: .visible) {
            Button("Let in") {
                if let qr = zaPotrditev {
                    prikaz = seja.spustiRocno(qr: qr)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                zaPotrditev = nil
            }
            Button("Cancel", role: .cancel) { zaPotrditev = nil }
        } message: {
            Text("This code could not be checked on the phone. The server checks it later; if it is not valid, it shows up under Conflicts.")
        }
        .task {
            if dovoljenje == .notDetermined {
                let ok = await AVCaptureDevice.requestAccess(for: .video)
                dovoljenje = ok ? .authorized : .denied
            }
        }
        .task { await zacniSejo() }
        .onChange(of: scenePhase) { _, faza in
            if faza == .active { seja.takojOsvezi() }
        }
        .onDisappear {
            omrezje.ustavi()
            seja.ustavi()
            // Zadnji poskus pred odhodom; kar ostane, je na disku in se poslje ob naslednjem odprtju skenerja.
            let s = seja
            Task { await s.poslji() }
        }
    }

    /// Poveze sejo z zetonom in uporabnikom, zazene tik (posiljanje, osvezevanje) in nalozi dogodke.
    private func zacniSejo() async {
        let store: SessionStore = session
        seja.zeton = { [weak store] in store?.token ?? "" }
        seja.uporabnikId = store.me?.id
        seja.zacni()
        let s = seja
        omrezje.zacni { gor in s.omrezjeSpremenjeno(gor: gor) }
        await seja.naloziDogodke()
    }

    private func zamenjajDogodek() {
        prikaz = nil
        zadnjaKoda = ""
        seja.zapriDogodek()
    }

    // MARK: - Izbira dogodka

    private var izbiraDogodka: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                stanjeVrstica(prikaziSeznam: false)

                Text("Choose an event")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.top, 6)
                Text("The ticket list is downloaded to this phone, so scanning keeps working without a connection.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))

                if seja.dogodkiNalaga && seja.dogodki.isEmpty {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 30)
                } else if let napaka = seja.dogodkiNapaka {
                    VStack(spacing: 10) {
                        Text(verbatim: napaka).foregroundColor(.red).font(.subheadline).multilineTextAlignment(.center)
                        Button("Try again") { Task { await seja.naloziDogodke() } }
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if seja.ponujeniDogodki.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.6))
                        Text("No events to scan")
                            .font(.headline).foregroundColor(.white)
                        Text("Published events of your club show up here.")
                            .font(.subheadline).foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    ForEach(seja.ponujeniDogodki) { d in
                        Button { Task { await seja.odpri(d) } } label: { vrsticaDogodka(d) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private func vrsticaDogodka(_ d: SkenDogodek) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: d.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                if let t = SkenCas.razcleni(d.startAt) {
                    Text(verbatim: t.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer()
            if d.lifecycle == "live" {
                Text("Live")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.green)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Skener

    private var skener: some View {
        ZStack {
            if dovoljenje == .authorized {
                KameraQR { koda in obravnavaj(koda) }
                    .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
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

            VStack(spacing: 10) {
                stanjeVrstica(prikaziSeznam: true)
                pripravaOpozorilo
                Spacer()
                if seja.preverjaNaStrezniku {
                    HStack(spacing: 10) { ProgressView().tint(.white); Text("Checking…").foregroundColor(.white) }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if let p = prikaz {
                    rezultatKartica(p)
                } else if dovoljenje == .authorized {
                    Text("Point the camera at the ticket's QR code")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    /// Vedno vidno: povezava, koliko skenov caka, cas zadnjega prenosa seznama (+ stevec vstopov).
    private func stanjeVrstica(prikaziSeznam: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(seja.povezava ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(LocalizedStringKey(seja.povezava ? "Online" : "Offline"))
                }
                if seja.cakajoce > 0 {
                    Text("\(seja.cakajoce) waiting").foregroundColor(.orange)
                } else {
                    Text("All sent").foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                if prikaziSeznam {
                    Text("\(seja.sprejeti) in").foregroundColor(.green)
                    Text("\(seja.zavrnjeni) refused").foregroundColor(.red)
                }
            }
            if prikaziSeznam {
                if let t = seja.zadnjiPrenos {
                    // M11: ce seznam ni od danes, je zraven datum (sicer »List updated 23:40« zjutraj izgleda svez).
                    Text("List updated \(SkenPrikaz.casPrenosa(t))")
                        .foregroundColor(seja.seznamStar ? .orange : .white.opacity(0.6))
                } else {
                    Text("List not downloaded").foregroundColor(.white.opacity(0.6))
                }
                if seja.seznamStar {
                    Text("The list could not be refreshed for a while. Tickets bought or refunded since then are not in it.")
                        .foregroundColor(.orange)
                }
            }
            if seja.dostopOdvzet {
                Text("You are no longer on this club's team. The downloaded lists were removed from this phone.")
                    .foregroundColor(.red)
            }
            if !seja.zapisOK {
                Text("Scans could not be saved on this phone. Free up storage space.")
                    .foregroundColor(.red)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var pripravaOpozorilo: some View {
        switch seja.priprava {
        case .nalaga:
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Downloading the ticket list…").foregroundColor(.white)
            }
            .font(.footnote.weight(.semibold))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .manjkaPodatkov(let sporocilo):
            VStack(alignment: .leading, spacing: 6) {
                Text("Offline check is not ready")
                    .font(.footnote.weight(.bold)).foregroundColor(.yellow)
                Text(verbatim: sporocilo)
                    .font(.footnote).foregroundColor(.white.opacity(0.8))
                Text("Until the list is downloaded, tickets can only be checked with a connection.")
                    .font(.footnote).foregroundColor(.white.opacity(0.8))
                Button("Try again") {
                    if let d = seja.dogodek { Task { await seja.odpri(d) } }
                }
                .font(.footnote.weight(.bold)).foregroundColor(.white)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        default:
            EmptyView()
        }
    }

    // MARK: - Rezultat

    private func rezultatKartica(_ p: SkenPrikaz) -> some View {
        let barva: Color = p.barva == .zeleno ? .green : (p.barva == .rdece ? .red : .yellow)
        let ikona = p.barva == .zeleno ? "checkmark.circle.fill" : (p.barva == .rdece ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: ikona)
                    .font(.system(size: 32))
                    .foregroundColor(barva)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: p.naslov)
                        .font(.headline).foregroundColor(.white)
                    if !p.podnaslov.isEmpty {
                        Text(verbatim: p.podnaslov)
                            .font(.subheadline).foregroundColor(.white.opacity(0.8))
                    }
                }
                Spacer()
                Button("Next") { naprej() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }

            if let o = p.opomba {
                Text(verbatim: o)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // VIP (backend 025): vratar/bar takoj vidi VIP, mizo in paket - tudi pri ze skenirani vstopnici.
            if let vip = p.vip {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)
                    Text(verbatim: vip)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.vipZlata)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Rumeno: aplikacija gosta ne spusti sama. Vratar odloci; sken gre v vrsto in ga streznik preveri naknadno.
            if p.ponudiVstop, let qr = p.qr {
                Button {
                    zaPotrditev = qr
                } label: {
                    Text("Let in")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(barva.opacity(0.25))
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func naprej() {
        prikaz = nil
        zadnjaKoda = ""
    }

    private func obravnavaj(_ koda: String) {
        // Ista koda ostane v kadru vec okvirjev zapored; odlocamo samo ob spremembi in ko ni odprtega rezultata.
        guard koda != zadnjaKoda, !obdelava, prikaz == nil else { return }
        zadnjaKoda = koda
        obdelava = true
        Task {
            defer { obdelava = false }
            let p = await seja.skeniraj(koda)
            prikaz = p
            let g = UINotificationFeedbackGenerator()
            switch p.barva {
            case .zeleno: g.notificationOccurred(.success)
            case .rdece: g.notificationOccurred(.error)
            case .rumeno: g.notificationOccurred(.warning)
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
