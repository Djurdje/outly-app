//
//  VerifyEmailView.swift
//  Outly
//
//  Created by Luka Rakusa Djurdjevic on 11. 1. 26.
//

import SwiftUI

/// Potrditev e-naslova s kodo (6–10 stevk, dolzina je nastavljena v Supabase) iz Supabasovega maila (predloga
/// "Confirm signup" vsebuje kodo {{ .Token }} in povezavo). Uspesna potrditev
/// vrne sejo -> uporabnik je takoj prijavljen. Ce je e-naslov potrdil prek
/// povezave na outly.si, gre na prijavo z gumbom spodaj.
///
/// Povezava iz maila porabi isto enkratno potrditev kot koda (koda potem vrne otp_expired, nov mail se za
/// potrjen racun ne poslje). Zato aplikacija, dokler ima geslo v pomnilniku (CakajocaPotrditev), TIHO poskusi
/// prijavo: ob vrnitvi v aplikacijo (scenePhase .active; ne ob prvem prikazu, ker je racun takrat zagotovo se nepotrjen), ob neveljavni kodi in ob »Resend code«.
/// Prijava uspe samo, ce je racun potrjen; vse napake so tihe.
@MainActor
struct VerifyEmailView: View {
    @AppStorage("authStage") private var authStage: String = "verifyEmail"
    @AppStorage("pendingEmail") private var pendingEmail: String = ""
    @AppStorage("loginNotice") private var loginNotice: String = ""
    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var code: String = ""
    @State private var message: String?
    /// Zeleno (uspeh, npr. »Code sent again«) ali rdece (napaka).
    @State private var messageIsSuccess = false
    /// Siv pojasnilo pod sporocilom (npr. »ce je e-naslov ze potrjen, nove kode ne dobis«).
    @State private var hint: String?
    @State private var isLoading = false
    /// Zastavica proti vzporednima tihima prijavama (vrnitev v aplikacijo + gumb hkrati).
    @State private var tihaPrijavaTece = false
    /// Zadnja tiha prijava ob vrnitvi v aplikacijo: ne pogosteje kot na 10 s (Supabase omejuje prijave na IP).
    @State private var zadnjaTihaPrijava: Date = .distantPast

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer().frame(height: 30)

                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 250)
                    .padding(.top, 10)

                Text("Verify your email")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.outlyBlue)

                Text("We sent a verification code to:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Text(pendingEmail.isEmpty ? "—" : pendingEmail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                TextField("code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .onChange(of: code) { _, newVal in
                        // samo stevilke, najvec 10 (Supabase OTP je lahko 6–10 stevk)
                        let filtered = newVal.filter { $0.isNumber }
                        if filtered != newVal { code = filtered }
                        if code.count > 10 { code = String(code.prefix(10)) }
                    }

                if let message = message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(messageIsSuccess ? .green : .red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }

                if let hint = hint {
                    Text(hint)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }

                Button {
                    Task { await verify() }
                } label: {
                    HStack(spacing: 10) {
                        if isLoading { ProgressView().tint(.white) }
                        Text(LocalizedStringKey(isLoading ? "Verifying..." : "Verify"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.outlyBlue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isLoading || pendingEmail.isEmpty || code.count < 6)

                Button {
                    Task { await resend() }
                } label: {
                    Text("Resend code")
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.top, 6)
                }
                .buttonStyle(.plain)
                .disabled(isLoading || pendingEmail.isEmpty)

                Button {
                    // E-naslov potrjen prek povezave v mailu -> prijava.
                    CakajocaPotrditev.shared.pocisti()
                    authStage = "login"
                } label: {
                    Text("Already confirmed? Sign in")
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)

                Button {
                    // nazaj na register
                    CakajocaPotrditev.shared.pocisti()
                    pendingEmail = ""
                    authStage = "register"
                } label: {
                    Text("Change email")
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        // Ob vrnitvi v aplikacijo (npr. po kliku na povezavo v mailu).
        .onChange(of: scenePhase) { _, nova in
            guard nova == .active, Date().timeIntervalSince(zadnjaTihaPrijava) > 10 else { return }
            zadnjaTihaPrijava = Date()
            Task { _ = await poskusiTihoPrijavo() }
        }
    }

    /// Tiha prijava z geslom iz pomnilnika. Vrne true, ce je uporabnik prijavljen (zaslon se zamenja).
    /// Brez gesla za ta e-naslov, med drugo tiho prijavo, ali ob kakrsnikoli napaki (tudi
    /// email_not_confirmed) ne naredi nic vidnega. Ne ponavlja se sama.
    private func poskusiTihoPrijavo() async -> Bool {
        let naslov = pendingEmail
        guard !naslov.isEmpty, !tihaPrijavaTece,
              let geslo = CakajocaPotrditev.shared.geslo(za: naslov) else { return false }
        tihaPrijavaTece = true
        defer { tihaPrijavaTece = false }

        do {
            let seja = try await SupabaseAuth.shared.signIn(email: naslov, password: geslo)
            session.setSession(token: seja.accessToken, refreshToken: seja.refreshToken)
            guard session.isLoggedIn else { return false }
            // Isto kot LoginView po uspehu: GET /me (SessionLoadingView) ustvari racun / pokaze onboarding.
            CakajocaPotrditev.shared.pocisti()
            pendingEmail = ""
            authStage = "main"
            return true
        } catch {
            return false
        }
    }

    private func verify() async {
        message = nil
        messageIsSuccess = false
        hint = nil
        guard !pendingEmail.isEmpty, (6...10).contains(code.count) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let seja = try await SupabaseAuth.shared.verify(email: pendingEmail, code: code, type: "signup")
            await MainActor.run {
                session.setSession(token: seja.accessToken, refreshToken: seja.refreshToken)
                CakajocaPotrditev.shared.pocisti()
                pendingEmail = ""
                if session.isLoggedIn {
                    // Prijavljen; GET /me (SessionLoadingView) ustvari racun na backendu.
                    authStage = "main"
                } else {
                    // Zaslon se zamenja, zato obvestilo pokaze LoginView (loginNotice).
                    loginNotice = String(localized: "Email verified. Log in with your email and password.")
                    authStage = "login"
                }
            }
        } catch {
            let neveljavnaKoda = ["otp_expired", "otp_disabled"].contains((error as? SupabaseAuthError)?.code ?? "")
            // Povezava v mailu je kodo ze porabila -> ce je racun potrjen, nas tiha prijava spusti naprej.
            if neveljavnaKoda, await poskusiTihoPrijavo() { return }
            // Z geslom v pomnilniku je tiha prijava pravkar povedala, da racun NI potrjen -> koda je res napacna.
            let geslaNi = CakajocaPotrditev.shared.geslo(za: pendingEmail) == nil
            await MainActor.run {
                if neveljavnaKoda && geslaNi {
                    // Brez gesla (aplikacija je bila vmes zaprta) ne moremo vedeti, ali je racun ze potrjen.
                    message = String(localized: "This code is wrong or no longer works. If you already confirmed your email with the link, tap “Already confirmed? Sign in” below.")
                } else {
                    message = error.userMessage
                }
            }
        }
    }

    private func resend() async {
        message = nil
        messageIsSuccess = false
        hint = nil
        guard !pendingEmail.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        // Za ze potrjen racun Supabase maila ne poslje (a vrne 200) -> najprej poskusi tiho prijavo.
        if await poskusiTihoPrijavo() { return }
        // Brez gesla v pomnilniku ne vemo, ali je racun ze potrjen: dodaj pojasnilo.
        let geslaNi = CakajocaPotrditev.shared.geslo(za: pendingEmail) == nil

        do {
            try await SupabaseAuth.shared.resend(email: pendingEmail, type: "signup")
            await MainActor.run {
                messageIsSuccess = true
                message = String(localized: "Code sent again. Check your email.")
                if geslaNi {
                    hint = String(localized: "If your email is already confirmed, no new code is sent. Tap “Already confirmed? Sign in” below.")
                }
            }
        } catch {
            await MainActor.run {
                message = error.userMessage
            }
        }
    }
}
