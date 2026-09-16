import SwiftUI

/// "Request for creator": prosnja za poslovni racun. Do septembra 2026 je gumb odpiral
/// outly.si/Creator.html (prijave so sle v Supabase, ki ga backend ne vidi). Zdaj gre
/// prosnja na POST /creator-applications; admin jo odobri v panelu in uporabnik dobi
/// vlogo business + prazen klub. Pogled najprej pokaze stanje ze oddanih prosenj.
@MainActor
struct ReguestForCreatorView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var applications: [CreatorApplication] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var pending: CreatorApplication? { applications.first { $0.status == "new" } }
    private var approved: CreatorApplication? { applications.first { $0.status == "approved" } }
    private var lastRejected: CreatorApplication? { applications.first { $0.status == "rejected" } }

    var body: some View {
        // Ta pogled se POTISNE na obstojeci NavigationStack (ProfileView/MyAccountView);
        // gnezden NavigationStack bi skril gumb nazaj in zlomil navigacijo.
        Group {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {

                    Text("Request a Business Account")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Partner with Outly and reach more nightlife lovers")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Join our platform and promote your club, bar, or event to thousands of tourists and locals. With a business account, you can publish events, sell tickets directly through the app, and connect with your audience in real time.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.70))
                            .lineSpacing(3)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Who can apply?")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            BulletRow(text: "Nightclubs")
                            BulletRow(text: "Bars with live music")
                            BulletRow(text: "Event organizers & promoters")
                            BulletRow(text: "Festivals and special nightlife events")
                        }
                        .foregroundColor(.white.opacity(0.70))
                    }

                    statusCard

                    if let loadError {
                        Text(loadError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarBackButtonHidden(false) // sistemski back
        }
        .preferredColorScheme(.dark)
        // onAppear (ne samo task): po vrnitvi z obrazca se stanje znova prebere.
        .onAppear { Task { await load() } }
    }

    // MARK: - Stanje prosnje

    @ViewBuilder
    private var statusCard: some View {
        if isLoading && applications.isEmpty {
            HStack { ProgressView().tint(.white); Text("Checking your application…").foregroundColor(.white.opacity(0.7)) }
                .font(.system(size: 14))
        } else if session.me?.role == "business" || approved != nil {
            OutlyInfoCardButton(
                icon: "checkmark.seal",
                title: "Approved",
                value: approved?.businessName ?? "Business account",
                description: session.me?.role == "business"
                    ? "Your business account is active. Manage your club and events from your profile."
                    : "Your application was approved. Log out and log in again to switch to your business account.",
                actionTitle: ""
            ) {}
        } else if let pending {
            OutlyInfoCardButton(
                icon: "clock",
                title: "Application sent",
                value: pending.businessName,
                description: "We are reviewing your application. You will get an email when it is approved.",
                actionTitle: ""
            ) {}
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let lastRejected {
                    Group {
                        if lastRejected.decisionNote.isEmpty {
                            Text("Your previous application for \"\(lastRejected.businessName)\" was not approved. You can apply again.")
                        } else {
                            Text("Your previous application for \"\(lastRejected.businessName)\" was not approved: \(lastRejected.decisionNote) You can apply again.")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                }
                NavigationLink {
                    CreatorApplicationFormView()
                } label: {
                    OutlyInfoCardButton(
                        icon: "doc.text",
                        title: "Application form",
                        value: "Fill your application form",
                        description: "Tell us about your venue. We usually reply within a few days.",
                        actionTitle: ""
                    ) {}
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        guard session.isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            applications = try await APIClient.shared.fetchMyCreatorApplications(token: session.token)
            loadError = nil
        } catch {
            loadError = error.userMessage
        }
    }
}

private struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("–")
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 1)

            Text(LocalizedStringKey(text))
                .font(.system(size: 14, weight: .regular))
        }
    }
}

// MARK: - Obrazec

/// Polja iz Creator.html (spletna stran) oziroma zaslona "Reguest for ba" v Figmi.
/// E-naslova ne vprasamo: streznik ga vzame iz zetona.
@MainActor
struct CreatorApplicationFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var form = CreatorApplicationForm()
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false

    private var canSend: Bool {
        form.businessName.trimmingCharacters(in: .whitespaces).count >= 2 &&
        form.contactName.trimmingCharacters(in: .whitespaces).count >= 2 && !isSending
    }

    var body: some View {
        Group {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {

                    Text("Application form")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    section("Business") {
                        OutlyTextField(placeholder: "Legal business name *", text: $form.businessName)
                        OutlyTextField(placeholder: "Business type (club, bar, promoter…)", text: $form.businessType)
                        OutlyTextField(placeholder: "Business address", text: $form.businessAddress)
                        OutlyTextField(placeholder: "City", text: $form.city)
                        OutlyTextField(placeholder: "Business licence / registration ID", text: $form.licenceId)
                    }

                    section("Contact person") {
                        OutlyTextField(placeholder: "Full name *", text: $form.contactName)
                        OutlyTextField(placeholder: "Role / position", text: $form.contactRole)
                        OutlyTextField(placeholder: "Phone number, e.g. +386 41 123 456", text: $form.phone)
                            .keyboardType(.phonePad)
                        Text("We will reply to \(session.me?.email ?? String(localized: "your account email")).")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    section("Anything else?") {
                        OutlyTextField(placeholder: "Message (optional)", text: $form.message)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    OutlyPrimaryButton(title: "Submit Application", isLoading: isSending) {
                        Task { await submit() }
                    }
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.5)

                    Text("By submitting you agree to our Terms and Privacy Policy. Your data is used only to review this application.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarBackButtonHidden(false)
        }
        .preferredColorScheme(.dark)
        .alert("Application sent", isPresented: $sent) {
            Button("OK") { dismiss() }
        } message: {
            Text("Thanks! We will review it and email you when it is approved.")
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            content()
        }
    }

    private func submit() async {
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            try await APIClient.shared.submitCreatorApplication(token: session.token, form: form)
            sent = true
        } catch {
            errorMessage = error.userMessage
        }
    }
}
