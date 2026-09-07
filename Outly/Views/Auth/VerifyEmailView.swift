//
//  VerifyEmailView.swift
//  Outly
//
//  Created by Luka Rakusa Djurdjevic on 11. 1. 26.
//

import SwiftUI

struct VerifyEmailView: View {
    @AppStorage("authStage") private var authStage: String = "verifyEmail"
    @AppStorage("pendingEmail") private var pendingEmail: String = ""

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

                Text("We sent a 6-digit code to:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Text(pendingEmail.isEmpty ? "—" : pendingEmail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .onChange(of: code) { _, newVal in
                        // samo številke, max 6
                        let filtered = newVal.filter { $0.isNumber }
                        if filtered != newVal { code = filtered }
                        if code.count > 6 { code = String(code.prefix(6)) }
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
                .disabled(isLoading || pendingEmail.isEmpty || code.count != 6)

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
        guard !pendingEmail.isEmpty, code.count == 6 else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await APIClient.shared.verifyEmail(email: pendingEmail, code: code)
            await MainActor.run {
                message = "Email verified. Please log in."
                authStage = "login"
            }
        } catch {
            await MainActor.run {
                message = error.localizedDescription
            }
        }
    }

    private func resend() async {
        message = nil
        guard !pendingEmail.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await APIClient.shared.resendVerification(email: pendingEmail)
            await MainActor.run {
                message = "Code sent again. Check your email."
            }
        } catch {
            await MainActor.run {
                message = error.localizedDescription
            }
        }
    }
}
