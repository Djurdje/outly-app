import SwiftUI
import UIKit
import AVFoundation

/// Skener QR za vrata, ki dela tudi brez povezave (backend issue #86).
///
/// 1. Vratar NE izbira dogodka (8. 10. 2026): skener se odpre takoj. Aktivni so dogodki kluba od 12 h pred zacetkom do 6 h po koncu;
///    dogodek pove koda QR. Javni kljuc in seznami vstopnic aktivnih dogodkov se prenesejo na telefon (in osvezujejo na ~2 min).
///    Brez aktivnega dogodka zaslon pove, kdaj se odpre naslednji.
/// 2. Koda v2 se preveri LOKALNO (podpis Ed25519, dogodek, seznam, ze skenirano na tem telefonu): zeleno takoj,
///    sken gre v trajno vrsto, ki se poslje prek scan-batch takoj in periodicno. Streznik ostane razsodnik.
/// 3. Stara koda v1 se na telefonu ne da preveriti: s povezavo jo preveri obstojec POST /scan, brez nje je rumeno.
///
/// Vse odlocanje je v SkenSeja (testirano); ta zaslon samo kaze stanje: povezava, stevilo cakajocih, cas zadnjega prenosa seznama.
/// Na vratih (varnostni pregled 5. 10. 2026): zaslon med odprtim skenerjem ne ugasne, svetilka za temne prostore, kamera se po
/// prekinitvi (klic, Control Center, reset medijskih storitev, vrnitev v ospredje) zazene znova, ista koda je po »Next« 3 s zadrzana.
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
    /// Po »Next« se ista koda (gost je se v kadru) 3 s ne prebere znova.
    @State private var zadrzek = SkenZadrzek()
    @State private var svetilka = false
    private static let imaSvetilko = AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    /// Povecanje = kamera naj se zazene znova, ce ne tece (vrnitev v ospredje).
    @State private var zagonKamere = 0

    /// `clubId`: klub, v katerem vratar dela (MyClubDetailView). Vrsta skenov je shranjena po klubu.
    init(clubId: Int? = nil) {
        _seja = StateObject(wrappedValue: SkenSeja(klubId: clubId ?? IzbraniKlub.id ?? 0, api: SkenApiZivi()))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if seja.aktivni.isEmpty {
                brezDogodka
            } else {
                skener
            }
        }
        .navigationTitle(naslovZaslona)
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
                if !seja.aktivni.isEmpty && dovoljenje == .authorized && Self.imaSvetilko {
                    Button { svetilka.toggle() } label: {
                        Image(systemName: svetilka ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundColor(svetilka ? .yellow : .white)
                    }
                    .accessibilityLabel(Text("Flashlight"))
                }
                if !seja.aktivni.isEmpty {
                    // Dosegljivo tudi med skeniranjem: klub je dogodek objavil ali prestavil, telefon pa ima star seznam dogodkov.
                    Button { Task { await seja.naloziDogodke() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(seja.dogodkiNalaga)
                        .accessibilityLabel(Text("Reload events"))
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
        .onChange(of: seja.aktivni.isEmpty) { _, prazen in
            // Okno zadnjega dogodka se je zaprlo: skener izgine, zato ne ostane odprt rezultat, zadrzek ali prizgana svetilka.
            if prazen {
                prikaz = nil
                zadnjaKoda = ""
                zadrzek.pocisti()
                svetilka = false
            }
        }
        .onAppear {
            // Vratar telefona med vecerom ne dotika: zaslon ne sme ugasniti (velja samo, dokler je skener odprt).
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onChange(of: scenePhase) { _, faza in
            if faza == .active {
                seja.takojOsvezi()
                UIApplication.shared.isIdleTimerDisabled = true
                zagonKamere += 1
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            svetilka = false
            omrezje.ustavi()
            seja.ustavi()
            // Zadnji poskus pred odhodom; kar ostane, je na disku in se poslje ob naslednjem odprtju skenerja.
            let s = seja
            Task { await s.poslji() }
        }
    }

    /// En aktivni dogodek: njegov naslov; vec: »2 events« (naslovi so v statusni vrstici); nobenega: »Scan tickets«.
    private var naslovZaslona: String {
        switch seja.aktivni.count {
        case 0: return String(localized: "Scan tickets")
        case 1: return seja.aktivni[0].title
        case let n: return String(localized: "\(n) events")
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

    // MARK: - Brez aktivnega dogodka

    private var brezDogodka: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                stanjeVrstica(prikaziSeznam: false)

                if seja.dostopOdvzet {
                    EmptyView()   // razlog pove statusna vrstica
                } else if !seja.dogodkiNalozeni {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 30)
                } else if let napaka = seja.dogodkiNapaka {
                    VStack(spacing: 10) {
                        Text(verbatim: napaka).foregroundColor(.red).font(.subheadline).multilineTextAlignment(.center)
                        gumbPonovnoNalozi
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.6))
                        Text("No event right now")
                            .font(.headline).foregroundColor(.white)
                        Text("Scanning opens \(Int(SkenOkno.predZacetkom / 3600)) hours before the event starts.")
                            .font(.subheadline).foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        if let n = seja.naslednji, let od = SkenOkno.odprtoOd(n) {
                            Text(verbatim: String(localized: "Next: \(n.title) · scanning from \(SkenPrikaz.casPrenosa(od))"))
                                .font(.subheadline.weight(.semibold)).foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                        if let t = seja.dogodkiPosodobljeni {
                            Text("Events updated \(SkenPrikaz.casPrenosa(t))")
                                .font(.footnote).foregroundColor(.white.opacity(0.5))
                        }
                        gumbPonovnoNalozi.padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private var gumbPonovnoNalozi: some View {
        Button {
            Task { await seja.naloziDogodke() }
        } label: {
            HStack(spacing: 8) {
                if seja.dogodkiNalaga { ProgressView().tint(.white) }
                Text("Reload events")
            }
            .foregroundColor(.white)
        }
        .disabled(seja.dogodkiNalaga)
    }

    // MARK: - Skener

    private var skener: some View {
        ZStack {
            if dovoljenje == .authorized {
                KameraQR(svetilka: svetilka, zagon: zagonKamere) { koda in obravnavaj(koda) }
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
            if prikaziSeznam && seja.aktivni.count > 1 {
                ForEach(seja.aktivni) { d in
                    Text(verbatim: d.title).lineLimit(1)
                }
            }
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
            if seja.uraNapacna {
                // Okno skeniranja se racuna po uri telefona: pri napacni uri je »NOT TODAY'S EVENT« lahko napacen.
                Text("The time on this phone is wrong — check date and time settings.")
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
                    Task { await seja.naloziDogodke() }
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

            // Guest lista (backend 8. 10. 2026): vratar vidi, da gre za gosta z liste (in cigav je).
            if let gl = p.guestList {
                HStack(spacing: 10) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)
                    Text(verbatim: gl)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white)
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
        // Gost, ki je ze noter, je lahko se v kadru: njegove kode 3 s ne beremo znova (sicer rdece »ALREADY SCANNED«).
        zadrzek.zadrzi(zadnjaKoda)
        prikaz = nil
        zadnjaKoda = ""
    }

    private func obravnavaj(_ koda: String) {
        // Ista koda ostane v kadru vec okvirjev zapored; odlocamo samo ob spremembi in ko ni odprtega rezultata.
        guard koda != zadnjaKoda, !obdelava, prikaz == nil, !zadrzek.ignoriraj(koda) else { return }
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
/// `svetilka`: vklop/izklop svetilke. `zagon`: ob spremembi se seja zazene znova, ce ne tece (vrnitev v ospredje).
struct KameraQR: UIViewControllerRepresentable {
    var svetilka: Bool = false
    var zagon: Int = 0
    let onCode: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> KameraQRController {
        let c = KameraQRController()
        c.onCode = onCode
        c.zadnjiZagon = zagon
        c.nastaviSvetilko(svetilka)
        return c
    }

    func updateUIViewController(_ uiViewController: KameraQRController, context: Context) {
        uiViewController.onCode = onCode
        uiViewController.nastaviSvetilko(svetilka)
        if uiViewController.zadnjiZagon != zagon {
            uiViewController.zadnjiZagon = zagon
            uiViewController.zazeni()
        }
    }
}

final class KameraQRController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (@MainActor (String) -> Void)?
    var zadnjiZagon = 0
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var naprava: AVCaptureDevice?
    /// Zagon, ustavitev in svetilka zaporedno na eni vrsti (startRunning blokira; ne na glavni niti).
    private let vrsta = DispatchQueue(label: "si.outly.skener.kamera")
    /// Zaslon je viden, zato naj seja tece: po prekinitvi ali napaki jo zazenemo znova.
    private var najTece = false
    private var svetilka = false
    /// Zaporedne napake seje (ponovni zagon najvec 3-krat, da se ob trajni napaki ne vrtimo; ponastavi se ob uspesnem nadaljevanju).
    private var napakeZapored = 0
    private var opazovalci: [NSObjectProtocol] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        naprava = device

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
        najTece = true
        napakeZapored = 0
        opazuj()
        zazeni()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        najTece = false
        prenehajOpazovati()
        vrsta.async { [session, naprava] in
            KameraQRController.uporabiSvetilko(false, naprava)
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Zazene sejo, ce je zaslon viden in seja ne tece, in znova nastavi svetilko (po prekinitvi je ugasnjena).
    func zazeni() {
        guard najTece else { return }
        let vklop = svetilka
        vrsta.async { [session, naprava] in
            if !session.isRunning { session.startRunning() }
            KameraQRController.uporabiSvetilko(vklop, naprava)
        }
    }

    func nastaviSvetilko(_ vklop: Bool) {
        guard vklop != svetilka else { return }
        svetilka = vklop
        guard najTece else { return }   // ob naslednjem zagonu
        vrsta.async { [naprava] in KameraQRController.uporabiSvetilko(vklop, naprava) }
    }

    /// Svetilka dela samo, ko seja tece; napako (npr. pregreta naprava) tiho spregledamo.
    nonisolated private static func uporabiSvetilko(_ vklop: Bool, _ naprava: AVCaptureDevice?) {
        guard let d = naprava, d.hasTorch else { return }
        if vklop && !d.isTorchAvailable { return }
        let nacin: AVCaptureDevice.TorchMode = vklop ? .on : .off
        guard d.torchMode != nacin else { return }
        do {
            try d.lockForConfiguration()
            d.torchMode = nacin
            d.unlockForConfiguration()
        } catch {}
    }

    // MARK: Prekinitve

    /// Klic, Control Center, druga aplikacija s kamero: seja se ustavi (wasInterrupted) in praviloma sama nadaljuje
    /// (interruptionEnded). Za vsak primer jo ob koncu prekinitve, po napaki seje in po resetu medijskih storitev zazenemo sami.
    private func opazuj() {
        guard opazovalci.isEmpty else { return }
        let nc = NotificationCenter.default
        opazovalci.append(nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.napakeZapored = 0
                self?.zazeni()
            }
        })
        opazovalci.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.poNapaki() }
        })
        opazovalci.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.poNapaki() }
        })
    }

    private func prenehajOpazovati() {
        for o in opazovalci { NotificationCenter.default.removeObserver(o) }
        opazovalci.removeAll()
    }

    /// Napaka seje (tudi AVError.mediaServicesWereReset): po kratkem premoru znova zazeni, najvec 3-krat zapored.
    private func poNapaki() {
        guard najTece, napakeZapored < 3 else { return }
        napakeZapored += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.zazeni()
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
