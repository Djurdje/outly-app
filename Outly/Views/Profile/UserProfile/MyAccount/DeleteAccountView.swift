import SwiftUI

/// Figma: "my acc delete" (558:1943). Applova zahteva 5.1.1(v): brisanje racuna v aplikaciji.
/// Backend (DELETE /me) zahteva geslo; ce ima uporabnik narocila, jih anonimizira
/// (racunovodske listine ostanejo, osebni podatki ne).
@MainActor
struct DeleteAccountView: View {
    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "main"
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var message: String?
    @State private var isLoading = false
    @State private var showConfirm = false
    @State private var googleVodja = GoogleSejaVodja()
    @State private var appleVodja = AppleVodja()

    /// `apple` | `google` za racun brez gesla; nil = racun z e-posto in geslom (nespremenjeno).
    private var ponudnik: String? {
        DruzabnaPrijavaLogika.ponudnik(zahtevki: DruzabnaPrijavaLogika.zahtevki(izZetona: session.token))
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Delete account")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("This action is permanent. It will remove your account, liked events and personal data. Tickets you have already bought stay valid, but they will no longer be linked to you and cannot be recovered in the app.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                if let ponudnik {
                    // Racun iz Googla/Appla gesla nima: pred izbrisom se znova prijavi pri ponudniku (backend zahteva svezo prijavo).
                    Text(ponudnik == "apple" ? "Confirm with your Apple account to continue." : "Confirm with your Google account to continue.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.top, 6)
                } else {
                    Text("Enter your password to confirm.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    OutlySecureField(placeholder: "password", text: $password)
                        .textContentType(.password)
                }

                if let message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showConfirm = true
                } label: {
                    HStack(spacing: 10) {
                        if isLoading { ProgressView().tint(.white) }
                        Text(LocalizedStringKey(isLoading ? "Deleting..." : (ponudnik == "apple" ? "Confirm with Apple" : ponudnik != nil ? "Confirm with Google" : "Delete Account")))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(isLoading || (ponudnik == nil && password.isEmpty))
                .opacity(ponudnik == nil && password.isEmpty ? 0.6 : 1)

                Button("Cancel") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)

                Spacer()
            }
            .padding(24)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .alert("Are you sure you want to delete your account?", isPresented: $showConfirm) {
            Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We're sorry to see you go! This is permanent: your account and personal data will be removed, and tickets you bought will no longer be linked to you.")
        }
    }

    private func deleteAccount() async {
        message = nil
        let ponudnik = self.ponudnik
        if ponudnik == nil {
            guard !password.isEmpty else { message = String(localized: "Enter your password to continue."); return }
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let ponudnik {
                // Nova prijava pri ponudniku = nov zeton s svezim `amr` (oauth); z NJIM DELETE /me. Preklic = nic.
                let nova: SupabaseSession?
                // Applov `authorizationCode` iz iste ponovne prijave (backend Issue #427: preklic Applovih zetonov). Samo v tej
                // lokalni spremenljivki do klica DELETE /me; ne shranjuje se nikamor. Google: nil (brez polja).
                var appleKoda: String? = nil
                if ponudnik == "apple" {
                    let apple = try await appleVodja.prijava()
                    nova = apple?.seja
                    appleKoda = apple?.koda
                } else {
                    nova = try await googleVodja.prijava()
                }
                guard let nova else { return }
                // Druga seja (izbira drugega Google racuna / Apple ID) NE sme izbrisati tujega racuna: isti `sub`, sicer nic.
                guard DruzabnaPrijavaLogika.istiUporabnik(zeton: session.token, zeton: nova.accessToken) else {
                    let tuj = nova.accessToken
                    Task { try? await SupabaseAuth.shared.signOut(token: tuj) }   // nova seja ne ostane osirotela
                    message = String(localized: "This is a different account than the one you are signed in with.")
                    return
                }
                let stari = session.token
                session.setSession(token: nova.accessToken, refreshToken: nova.refreshToken)
                guard session.isLoggedIn else { return }
                // Stara seja (osvezevalni zeton) ne ostane osirotela; napaka ne ustavi izbrisa.
                Task { try? await SupabaseAuth.shared.signOut(token: stari) }
                try await APIClient.shared.deleteAccountReauth(token: session.token, appleKoda: appleKoda)
            } else {
                try await APIClient.shared.deleteAccount(token: session.token, password: password)
            }
            // Racun ne obstaja vec: zeton izbrisi in vrni na prijavo. Brez DELETE /me/devices: streznik je naprave pobrisal sam
            // (kaskada), z zetonom izbrisanega racuna pa bi requireAuth racun ustvaril znova.
            session.logout(brezNaprave: true)
            authStage = "login"
        } catch let api as APIError {
            if case let .requestFailed(code, raw) = api, code == 401 {
                if DruzabnaPrijavaLogika.jeReauthPotreben(raw) {
                    // Seja je veljavna (NI odjava): prijava pri ponudniku je prestara ali je bila osvezena; poskusi znova.
                    message = String(localized: "Sign in again with Google or Apple, then retry deleting the account.")
                    return
                }
                // Racun brez gesla: 401 brez reauth_required ni »napacno geslo«.
                if ponudnik != nil {
                    message = String(localized: "Something went wrong. Please try again.")
                    return
                }
                // 401 tu pomeni napacno geslo (streznik vrne "Invalid credentials"), NE potekle seje.
                message = String(localized: "Wrong password.")
                return
            }
            message = api.userMessage
        } catch {
            message = error.userMessage
        }
    }
}
