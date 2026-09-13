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
struct VerifyEmailView: View {
    @AppStorage("authStage") private var authStage: String = "verifyEmail"
    @AppStorage("pendingEmail") private var pendingEmail: String = ""
    @AppStorage("loginNotice") private var loginNotice: String = ""
    @EnvironmentObject private var session: SessionStore

    @State private var code: String = ""
    @State private var message: String?
    @State private var isLoading = false

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
                        .foregroundColor(message.lowercased().contains("verified") ? .green : .red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }

                Button {
                    Task { await verify() }
                } label: {
                    HStack(spacing: 10) {
                        if isLoading { ProgressView().tint(.white) }
                        Text(isLoading ? "Verifying..." : "Verify")
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
                    authStage = "login"
                } label: {
                    Text("Already confirmed? Sign in")
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)

                Button {
                    // nazaj na register
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
    }

    private func verify() async {
        message = nil
        guard !pendingEmail.isEmpty, (6...10).contains(code.count) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let seja = try await SupabaseAuth.shared.verify(email: pendingEmail, code: code, type: "signup")
            await MainActor.run {
                session.setSession(token: seja.accessToken, refreshToken: seja.refreshToken)
                pendingEmail = ""
                if session.isLoggedIn {
                    // Prijavljen; GET /me (SessionLoadingView) ustvari racun na backendu.
                    authStage = "main"
                } else {
                    // Zaslon se zamenja, zato obvestilo pokaze LoginView (loginNotice).
                    loginNotice = "Email verified. Log in with your email and password."
                    authStage = "login"
                }
            }
        } catch {
            await MainActor.run {
                message = error.userMessage
            }
        }
    }

    private func resend() async {
        message = nil
        guard !pendingEmail.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await SupabaseAuth.shared.resend(email: pendingEmail, type: "signup")
            await MainActor.run {
                message = "Code sent again. Check your email."
            }
        } catch {
            await MainActor.run {
                message = error.userMessage
            }
        }
    }
}
