import SwiftUI

/// Urejevalnik tlorisa in VIP miz (organizator, issue outly-backend#175). Isti zaslon za razpored dogodka
/// (`VipVir.dogodek`) in za tloris kluba (`VipVir.klub`): bere in shranjuje prek `fetchVipLayout` / `saveVipLayout`.
///
/// Mreza celic (8...40), elementi (bar, oder, DJ ...) in mize (oznaka, oblika, sedezi, cena). Predmet se izbere z dotikom
/// (ali iz seznama), povleče na platnu (poravna se na celico) ali natančno premakne s stepperji. Cena je v evrih,
/// na strežnik gre v celih centih. Brez lastnega NavigationStack (naslov, Close in Save poda gostitelj: list z NavigationStack).
@MainActor
struct VipUrejevalnikView: View {
    let vir: VipVir
    /// Ze znan razpored (npr. po kopiji gostitelja); nil = naloži se s strežnika.
    let zacetno: VipLayout?
    var onSaved: (VipLayout) -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var stanje = VipUrStanje()
    @State private var izhodisce = VipUrStanje()
    @State private var paketi: [VipPackage] = []
    @State private var nalozeno = false
    @State private var napakaNalaganja: String?
    @State private var izbranId: UUID?
    @State private var sporocilo: String?
    @State private var shranjuje = false
    @State private var potrdiZavrzi = false

    private let ozadje = Color(white: 0.06)
    private let kartica = Color(white: 0.11)

    private var imaSpremembe: Bool { stanje != izhodisce }

    var body: some View {
        ZStack {
            ozadje.ignoresSafeArea()
            if nalozeno {
                vsebina
            } else if let napaka = napakaNalaganja {
                VStack(spacing: 12) {
                    Text(napaka)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await zacni() } }
                        .foregroundColor(.white)
                }
                .padding(24)
            } else {
                ProgressView().tint(.white)
            }
        }
        .navigationTitle(LocalizedStringKey("VIP layout"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    if imaSpremembe { potrdiZavrzi = true } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await shrani() }
                } label: {
                    Text(LocalizedStringKey(shranjuje ? "Saving..." : "Save"))
                }
                .disabled(!nalozeno || shranjuje || !imaSpremembe)
            }
        }
        .interactiveDismissDisabled(imaSpremembe)
        .confirmationDialog("Discard your changes?", isPresented: $potrdiZavrzi, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .preferredColorScheme(.dark)
        .task { await zacni() }
    }

    // MARK: - Vsebina

    private var vsebina: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VipUrPlatno(
                    stanje: stanje,
                    izbranId: izbranId,
                    onIzberi: { izbranId = $0 },
                    onPremakni: { id, dx, dy in stanje.premakni(id: id, dx: dx, dy: dy) }
                )

                Text("Drag items to move them. Tap an item to edit it.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))

                dodajMenu

                if let id = izbranId, stanje.predmeti.contains(where: { $0.id == id }) {
                    podrobnosti(id)
                }

                velikostKartica
                seznamKartica

                if let sporocilo {
                    Text(sporocilo)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var dodajMenu: some View {
        Menu {
            Button {
                dodaj(VipUrStanje.tipMize)
            } label: {
                Label("Table", systemImage: "circle.dashed")
            }
            Divider()
            ForEach(VipUrStanje.tipiElementov, id: \.self) { tip in
                Button {
                    dodaj(tip)
                } label: {
                    Text(LocalizedStringKey(Self.naziv(tip)))
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    /// Prevedeni naziv tipa predmeta (kljuc za `LocalizedStringKey`).
    static func naziv(_ tip: String) -> String {
        if tip == VipUrStanje.tipMize { return "Table" }
        if let n = VipOznaka.privzetNaziv(tip: tip) { return n }
        if tip == "label" { return "Label" }
        if tip == "wall" { return "Wall" }
        return "Item"
    }

    private func dodaj(_ tip: String) {
        sporocilo = nil
        if let id = stanje.dodaj(tip: tip) {
            izbranId = id
        } else {
            if tip == VipUrStanje.tipMize {
                sporocilo = String(localized: "A layout can have at most 60 tables.")
            } else {
                sporocilo = String(localized: "A layout can have at most 80 other items.")
            }
        }
    }

    // MARK: - Izbrani predmet

    /// Vez na eno polje predmeta po kljucu (ne po indeksu: predmet se lahko izbrise med izrisom).
    private func vez<T>(_ id: UUID, _ pot: WritableKeyPath<VipUrPredmet, T>, privzeto: T) -> Binding<T> {
        Binding(
            get: { stanje.predmeti.first(where: { $0.id == id })?[keyPath: pot] ?? privzeto },
            set: { v in
                if let i = stanje.predmeti.firstIndex(where: { $0.id == id }) { stanje.predmeti[i][keyPath: pot] = v }
            }
        )
    }

    private func podrobnosti(_ id: UUID) -> some View {
        let p = stanje.predmeti.first(where: { $0.id == id })
        let jeMiza = p?.jeMiza ?? false
        let px = p?.x ?? 0
        let py = p?.y ?? 0
        let pw = p?.w ?? 1
        let ph = p?.h ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedStringKey(Self.naziv(p?.tip ?? "")))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(role: .destructive) {
                    stanje.odstrani(id: id)
                    izbranId = nil
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 14, weight: .medium))
                }
            }

            TextField(LocalizedStringKey(jeMiza ? "Label (e.g. T1)" : "Label (optional)"), text: vez(id, \.oznaka, privzeto: ""))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            if jeMiza {
                Picker("Shape", selection: vez(id, \.oblika, privzeto: "round")) {
                    Text("Round").tag("round")
                    Text("Rectangle").tag("rect")
                }
                .pickerStyle(.segmented)

                Stepper(value: vez(id, \.sedezi, privzeto: 4), in: 1...20) {
                    HStack {
                        Text("Seats")
                        Spacer()
                        Text(verbatim: String(p?.sedezi ?? 0)).foregroundColor(.white.opacity(0.6))
                    }
                }

                HStack {
                    Text("Price (EUR)")
                    Spacer()
                    TextField("0", text: vez(id, \.cena, privzeto: ""))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            koraknik("Left", vrednost: px, vez: vez(id, \.x, privzeto: 0), obseg: 0...max(0, stanje.sirina - pw))
            koraknik("Top", vrednost: py, vez: vez(id, \.y, privzeto: 0), obseg: 0...max(0, stanje.visina - ph))
            koraknik("Width", vrednost: pw, vez: vez(id, \.w, privzeto: 1), obseg: 1...max(1, stanje.sirina - px))
            koraknik("Height", vrednost: ph, vez: vez(id, \.h, privzeto: 1), obseg: 1...max(1, stanje.visina - py))
        }
        .font(.system(size: 15))
        .foregroundColor(.white)
        .padding(14)
        .background(kartica)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func koraknik(_ naslov: LocalizedStringKey, vrednost: Int, vez: Binding<Int>, obseg: ClosedRange<Int>) -> some View {
        Stepper(value: vez, in: obseg) {
            HStack {
                Text(naslov)
                Spacer()
                Text(verbatim: String(vrednost)).foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Velikost mreze in seznam

    private var velikostKartica: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan size")
                .font(.system(size: 16, weight: .bold))
            Stepper(value: Binding(get: { stanje.sirina }, set: { stanje.sirina = $0; stanje.omeji() }),
                    in: VipUrStanje.mrezaMin...VipUrStanje.mrezaMax) {
                HStack {
                    Text("Columns")
                    Spacer()
                    Text(verbatim: String(stanje.sirina)).foregroundColor(.white.opacity(0.6))
                }
            }
            Stepper(value: Binding(get: { stanje.visina }, set: { stanje.visina = $0; stanje.omeji() }),
                    in: VipUrStanje.mrezaMin...VipUrStanje.mrezaMax) {
                HStack {
                    Text("Rows")
                    Spacer()
                    Text(verbatim: String(stanje.visina)).foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .font(.system(size: 15))
        .foregroundColor(.white)
        .padding(14)
        .background(kartica)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var seznamKartica: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Items")
                .font(.system(size: 16, weight: .bold))
                .padding(.bottom, 6)
            if stanje.predmeti.isEmpty {
                Text("Nothing here yet. Add tables and landmarks with the Add button.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            ForEach(stanje.predmeti) { p in
                Button {
                    izbranId = p.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.jeMiza ? "circle.dashed" : "square.dashed")
                            .foregroundColor(.white.opacity(0.6))
                        vrstica(p)
                        Spacer()
                        if p.id == izbranId {
                            Image(systemName: "checkmark").foregroundColor(.white)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundColor(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kartica)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func vrstica(_ p: VipUrPredmet) -> some View {
        if p.jeMiza {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: p.oznaka.isEmpty ? String(localized: "Table") : VipOznaka.miza(p.oznaka))
                    .font(.system(size: 15, weight: .medium))
                Text(verbatim: "\(p.sedezi) · \(Self.cena(p.cena))")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        } else if p.oznaka.isEmpty {
            Text(LocalizedStringKey(Self.naziv(p.tip)))
                .font(.system(size: 15, weight: .medium))
        } else {
            Text(verbatim: p.oznaka)
                .font(.system(size: 15, weight: .medium))
        }
    }

    /// Cena za prikaz (Denar.evri), ce je vneseno veljavno stevilo; sicer besedilo, kot je.
    private static func cena(_ besedilo: String) -> String {
        if let a = EventFormView.cents(from: besedilo), let centov = a { return Denar.evri(centov) }
        return besedilo
    }

    // MARK: - Podatki

    private func zacni() async {
        guard !nalozeno else { return }
        napakaNalaganja = nil
        if let z = zacetno {
            uporabi(z)
            return
        }
        do {
            let r = try await APIClient.shared.fetchVipLayout(vir: vir, token: session.token)
            uporabi(r)
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            napakaNalaganja = api.userMessage
        } catch {
            napakaNalaganja = error.userMessage
        }
    }

    private func uporabi(_ r: VipLayout) {
        let s = VipUrStanje(layout: r)
        stanje = s
        izhodisce = s
        paketi = r.packages
        nalozeno = true
    }

    private func shrani() async {
        sporocilo = nil
        let plan: [String: Any]
        let mize: [[String: Any]]
        switch stanje.preveri() {
        case .ok(let p, let m):
            plan = p
            mize = m
        case .napaka(let t):
            sporocilo = t
            return
        }
        shranjuje = true
        defer { shranjuje = false }
        do {
            let r = try await APIClient.shared.saveVipLayout(vir: vir, plan: plan, tables: mize, packages: paketi, token: session.token)
            onSaved(r)
            dismiss()
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            sporocilo = api.userMessage
        } catch {
            sporocilo = error.userMessage
        }
    }
}

// MARK: - Platno

/// Platno urejevalnika: temna mreza in predmeti. Celica = sirina platna / stevilo stolpcev; sirino prebere
/// en GeometryReader (nic se ne hrani v @State). Elementi so pod mizami.
private struct VipUrPlatno: View {
    let stanje: VipUrStanje
    let izbranId: UUID?
    let onIzberi: (UUID) -> Void
    let onPremakni: (UUID, Int, Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let celica = geo.size.width / CGFloat(max(1, stanje.sirina))
            ZStack(alignment: .topLeading) {
                Color(white: 0.08)
                mreza(celica: celica)
                ForEach(stanje.predmeti.filter { !$0.jeMiza }) { p in
                    predmet(p, celica: celica)
                }
                ForEach(stanje.predmeti.filter { $0.jeMiza }) { p in
                    predmet(p, celica: celica)
                }
            }
            .frame(width: geo.size.width, height: celica * CGFloat(stanje.visina), alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .aspectRatio(CGFloat(max(1, stanje.sirina)) / CGFloat(max(1, stanje.visina)), contentMode: .fit)
    }

    private func mreza(celica: CGFloat) -> some View {
        let sirina = celica * CGFloat(stanje.sirina)
        let visina = celica * CGFloat(stanje.visina)
        return Path { p in
            for i in 0...stanje.sirina {
                let x = CGFloat(i) * celica
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: visina))
            }
            for j in 0...stanje.visina {
                let y = CGFloat(j) * celica
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: sirina, y: y))
            }
        }
        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
    }

    private func predmet(_ p: VipUrPredmet, celica: CGFloat) -> some View {
        VipUrPredmetView(
            p: p,
            celica: celica,
            izbran: p.id == izbranId,
            onIzberi: { onIzberi(p.id) },
            onPremakni: { dx, dy in onPremakni(p.id, dx, dy) }
        )
    }
}

/// En predmet na platnu. Premik med vlecenjem je lokalen (`@GestureState`), v stanje urejevalnika gre
/// samo koncni premik v celih celicah, zato se med vlecenjem ne izrisuje cel zaslon.
private struct VipUrPredmetView: View {
    let p: VipUrPredmet
    let celica: CGFloat
    let izbran: Bool
    let onIzberi: () -> Void
    let onPremakni: (Int, Int) -> Void

    @GestureState private var premik: CGSize = .zero

    private var jeNapis: Bool { p.tip == "label" }
    private var jeStena: Bool { p.tip == "wall" }

    var body: some View {
        let sirina = CGFloat(p.w) * celica
        let visina = CGFloat(p.h) * celica
        let radij = min(8, celica * 0.4)
        return ZStack {
            if p.jeMiza {
                oblikaMize(radij: radij)
            } else if !jeNapis {
                RoundedRectangle(cornerRadius: radij, style: .continuous)
                    .fill(Color.white.opacity(jeStena ? 0.20 : 0.07))
                RoundedRectangle(cornerRadius: radij, style: .continuous)
                    .stroke(Color.white.opacity(izbran ? 0.9 : (jeStena ? 0 : 0.12)), lineWidth: izbran ? 2 : 1)
            } else if izbran {
                RoundedRectangle(cornerRadius: radij, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
            }
            napis
        }
        .frame(width: sirina, height: visina)
        .contentShape(Rectangle())
        .offset(x: CGFloat(p.x) * celica + premik.width, y: CGFloat(p.y) * celica + premik.height)
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($premik) { v, stanje, _ in stanje = v.translation }
                .onChanged { _ in if !izbran { onIzberi() } }
                .onEnded { v in
                    guard celica > 0 else { return }
                    let dx = Int((v.translation.width / celica).rounded())
                    let dy = Int((v.translation.height / celica).rounded())
                    if dx != 0 || dy != 0 { onPremakni(dx, dy) }
                }
        )
        .onTapGesture { onIzberi() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: p.jeMiza ? VipOznaka.miza(p.oznaka) : (p.oznaka.isEmpty ? p.tip : p.oznaka)))
        .accessibilityAddTraits(izbran ? .isSelected : [])
    }

    private func oblikaMize(radij: CGFloat) -> some View {
        let oblika: AnyShape = p.oblika == "rect" ? AnyShape(RoundedRectangle(cornerRadius: radij, style: .continuous)) : AnyShape(Ellipse())
        return ZStack {
            oblika.fill(Color(white: 0.14))
            oblika.stroke(Color.white.opacity(izbran ? 0.95 : 0.65), lineWidth: izbran ? 2.5 : 1.5)
        }
    }

    @ViewBuilder
    private var napis: some View {
        if p.jeMiza {
            urediNapis(Text(verbatim: p.oznaka), krepko: true)
        } else if !p.oznaka.isEmpty {
            urediNapis(Text(verbatim: p.oznaka), krepko: false)
        } else if let kljuc = VipOznaka.privzetNaziv(tip: p.tip) {
            urediNapis(Text(LocalizedStringKey(kljuc)), krepko: false)
        }
    }

    private func urediNapis(_ t: Text, krepko: Bool) -> some View {
        // Razbito na korake, da tipni preverjevalnik ne obupa (gnezdene ternarke + max/min).
        let velikost: CGFloat = krepko ? max(8, min(13, celica * 0.6)) : max(7, min(11, celica * 0.5))
        let teza: Font.Weight = krepko ? .bold : .medium
        return t.font(.system(size: velikost, weight: teza))
            .foregroundColor(.white.opacity(krepko ? 1 : 0.55))
            .multilineTextAlignment(.center)
            .lineLimit(krepko ? 1 : 2)
            .minimumScaleFactor(0.5)
            .padding(2)
    }
}
