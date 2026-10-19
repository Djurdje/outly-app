import SwiftUI

/// Figma: "complete acc" (424:1355). V Figmi je to modalno okno cez domaci zaslon;
/// tu je samostojen zaslon na temnem ozadju, ker se domaci zaslon pred dokoncanjem
/// racuna sploh ne nalozi. Vsebina kartice je enaka Figmi.
///
/// Poslje PATCH /me { phone?, dateOfBirth, country } in nadaljuje na izbiro zanrov.
@MainActor
struct CompleteAccountView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var countryCode: String = Locale.current.region?.identifier ?? "SI"
    @State private var dialCode: String = ""
    @State private var phoneNumber: String = ""
    @State private var birthDate: Date = CompleteAccountView.defaultBirthDate
    @State private var message: String?
    @State private var isLoading = false
    @State private var goToGenres = false

    private static var defaultBirthDate: Date {
        StarostRacuna.gregorijanski().date(byAdding: .year, value: -20, to: Date()) ?? Date()
    }

    /// Najstarejsi/najmlajsi dovoljeni datum: 120 let nazaj do danes - 18 let (koledarsko, StarostRacuna; Martin 19. 10. 2026,
    /// prej 15). Ze vpisan datum (racun 15-17 let, vpisan pred 19. 10.) ostane izbirljiv, ker ga backend sprejme (ni sprememba).
    private var dateRange: ClosedRange<Date> {
        StarostRacuna.obsegIzbirnika(obstojec: session.me?.dateOfBirth.flatMap(Self.parse))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.outlyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 40)

                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 48)
                            .padding(.bottom, 30)

                        card
                            .padding(.horizontal, 28)

                        Spacer(minLength: 60)
                    }
                }
            }
            .navigationDestination(isPresented: $goToGenres) {
                SelectGenresView()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: prefill)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Complete your account")
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(.white)

            // --- telefon (neobvezen) ---
            VStack(alignment: .leading, spacing: 6) {
                Text("Phone number (optional)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.outlyMuted)
                HStack(spacing: 10) {
                    Menu {
                        ForEach(DialCodes.all, id: \.iso) { c in
                            Button("\(c.flag) \(c.name) \(c.dial)") {
                                dialCode = c.dial
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(DialCodes.flag(forDial: dialCode) ?? "🌐")
                            Text(dialCode.isEmpty ? "+" : dialCode)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black.opacity(0.7))
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.black.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Color.white.opacity(0.95))
                        .cornerRadius(8)
                    }

                    OutlyTextField(placeholder: "41 123 456", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
            }

            // --- datum rojstva ---
            VStack(alignment: .leading, spacing: 6) {
                Text("Date of birth")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.outlyMuted)
                DatePicker("", selection: $birthDate, in: dateRange, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .environment(\.colorScheme, .light)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(8)
            }

            // --- drzava ---
            VStack(alignment: .leading, spacing: 6) {
                Text("Country")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.outlyMuted)
                Menu {
                    ForEach(Countries.all, id: \.code) { c in
                        Button(c.name) { selectCountry(c.code) }
                    }
                } label: {
                    HStack {
                        Text(Countries.name(for: countryCode) ?? String(localized: "Country"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.75))
                        Spacer()
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.black.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(8)
                }
            }

            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
            }

            OutlyPrimaryButton(title: isLoading ? "Saving..." : "Continue", isLoading: isLoading) {
                Task { await save() }
            }
            .disabled(isLoading)
            .padding(.top, 10)
        }
        .padding(22)
        .background(Color.outlyCard)
        .cornerRadius(12)
    }

    // MARK: - logika

    private func prefill() {
        guard let me = session.me else { return }
        if let c = me.country, !c.isEmpty { countryCode = c }
        if dialCode.isEmpty { dialCode = DialCodes.dial(forISO: countryCode) ?? "+386" }
        if let p = me.phone, !p.isEmpty {
            // "+38641123456" -> klicna koda + preostanek
            if let d = DialCodes.all.first(where: { p.hasPrefix($0.dial) }) {
                dialCode = d.dial
                phoneNumber = String(p.dropFirst(d.dial.count))
            } else {
                phoneNumber = p
            }
        }
        if let dob = me.dateOfBirth, let d = Self.parse(dob) { birthDate = d }
    }

    private func selectCountry(_ code: String) {
        countryCode = code
        if phoneNumber.isEmpty, let d = DialCodes.dial(forISO: code) { dialCode = d }
    }

    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        // Lokalni casovni pas, enako kot DatePicker in prikaz — sicer je zahodno od GMT dan prej.
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func save() async {
        message = nil

        // Najnizja starost racuna 18 let (Martin 19. 10. 2026; backend #301, po ljubljanskem koledarju). Datum, ki je ze v racunu,
        // ni sprememba: backend ga sprejme, zato ga tudi tu ne zavrnemo (obstojec racun 15-17 let).
        let izbran = Self.format(birthDate)
        guard StarostRacuna.smeShraniti(izbran: izbran, shranjen: session.me?.dateOfBirth,
                                        danes: StarostRacuna.dan(Date())) else {
            message = String(localized: "You must be at least 18 years old to use Outly.")
            return
        }
        guard Countries.name(for: countryCode) != nil else {
            message = String(localized: "Choose your country.")
            return
        }

        var update = APIClient.MeUpdate()
        update.dateOfBirth = izbran
        update.country = countryCode

        let digits = phoneNumber.filter { $0.isNumber }
        if !digits.isEmpty {
            let dial = dialCode.filter { $0.isNumber }
            guard !dial.isEmpty else {
                message = String(localized: "Choose the country code for your phone number.")
                return
            }
            update.phone = .some("+" + dial + digits)
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let me = try await APIClient.shared.updateMe(token: session.token, update)
            session.me = me
            goToGenres = true
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 {
                session.logout()
                return
            }
            message = api.userMessage
        } catch {
            message = error.userMessage
        }
    }
}

// MARK: - Seznami

/// Drzave po ISO 3166-1 alpha-2, imena iz sistema (lokalizirana). Backend zahteva 2 crki.
enum Countries {
    struct Country { let code: String; let name: String }

    static let all: [Country] = {
        let codes = Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        let named = codes.compactMap { code -> Country? in
            guard let n = Locale.current.localizedString(forRegionCode: code) else { return nil }
            return Country(code: code, name: n)
        }
        return named.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static func name(for code: String) -> String? {
        all.first { $0.code == code }?.name
    }
}

/// Klicne kode. Ni popoln seznam sveta — uporabnik lahko kodo vpise tudi rocno
/// (izbere najblizjo, stevilko pa vpise s celotno kodo). Backend preveri E.164.
enum DialCodes {
    struct Entry { let iso: String; let name: String; let dial: String; let flag: String }

    static let all: [Entry] = [
        Entry(iso: "SI", name: "Slovenia",        dial: "+386", flag: "🇸🇮"),
        Entry(iso: "HR", name: "Croatia",         dial: "+385", flag: "🇭🇷"),
        Entry(iso: "AT", name: "Austria",         dial: "+43",  flag: "🇦🇹"),
        Entry(iso: "IT", name: "Italy",           dial: "+39",  flag: "🇮🇹"),
        Entry(iso: "HU", name: "Hungary",         dial: "+36",  flag: "🇭🇺"),
        Entry(iso: "DE", name: "Germany",         dial: "+49",  flag: "🇩🇪"),
        Entry(iso: "CH", name: "Switzerland",     dial: "+41",  flag: "🇨🇭"),
        Entry(iso: "BA", name: "Bosnia and Herzegovina", dial: "+387", flag: "🇧🇦"),
        Entry(iso: "RS", name: "Serbia",          dial: "+381", flag: "🇷🇸"),
        Entry(iso: "ME", name: "Montenegro",      dial: "+382", flag: "🇲🇪"),
        Entry(iso: "MK", name: "North Macedonia", dial: "+389", flag: "🇲🇰"),
        Entry(iso: "XK", name: "Kosovo",          dial: "+383", flag: "🇽🇰"),
        Entry(iso: "AL", name: "Albania",         dial: "+355", flag: "🇦🇱"),
        Entry(iso: "SK", name: "Slovakia",        dial: "+421", flag: "🇸🇰"),
        Entry(iso: "CZ", name: "Czechia",         dial: "+420", flag: "🇨🇿"),
        Entry(iso: "PL", name: "Poland",          dial: "+48",  flag: "🇵🇱"),
        Entry(iso: "FR", name: "France",          dial: "+33",  flag: "🇫🇷"),
        Entry(iso: "ES", name: "Spain",           dial: "+34",  flag: "🇪🇸"),
        Entry(iso: "PT", name: "Portugal",        dial: "+351", flag: "🇵🇹"),
        Entry(iso: "NL", name: "Netherlands",     dial: "+31",  flag: "🇳🇱"),
        Entry(iso: "BE", name: "Belgium",         dial: "+32",  flag: "🇧🇪"),
        Entry(iso: "GB", name: "United Kingdom",  dial: "+44",  flag: "🇬🇧"),
        Entry(iso: "IE", name: "Ireland",         dial: "+353", flag: "🇮🇪"),
        Entry(iso: "DK", name: "Denmark",         dial: "+45",  flag: "🇩🇰"),
        Entry(iso: "SE", name: "Sweden",          dial: "+46",  flag: "🇸🇪"),
        Entry(iso: "NO", name: "Norway",          dial: "+47",  flag: "🇳🇴"),
        Entry(iso: "FI", name: "Finland",         dial: "+358", flag: "🇫🇮"),
        Entry(iso: "GR", name: "Greece",          dial: "+30",  flag: "🇬🇷"),
        Entry(iso: "RO", name: "Romania",         dial: "+40",  flag: "🇷🇴"),
        Entry(iso: "BG", name: "Bulgaria",        dial: "+359", flag: "🇧🇬"),
        Entry(iso: "UA", name: "Ukraine",         dial: "+380", flag: "🇺🇦"),
        Entry(iso: "TR", name: "Türkiye",         dial: "+90",  flag: "🇹🇷"),
        Entry(iso: "US", name: "United States",   dial: "+1",   flag: "🇺🇸"),
        Entry(iso: "CA", name: "Canada",          dial: "+1",   flag: "🇨🇦"),
        Entry(iso: "AU", name: "Australia",       dial: "+61",  flag: "🇦🇺"),
    ]

    static func dial(forISO iso: String) -> String? { all.first { $0.iso == iso }?.dial }
    static func flag(forDial dial: String) -> String? { all.first { $0.dial == dial }?.flag }
}
