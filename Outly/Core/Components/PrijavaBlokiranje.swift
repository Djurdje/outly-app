import SwiftUI

// Prijava vsebine in blokiranje uporabnikov (outly-backend #189, Apple App Review 1.2).
// - ReportSheet: list z razlogi + neobvezno besedilo -> POST /reports.
// - UserSafetyMenu: meni »…« ob tujem uporabniku (Report, Block) za vrstice prijateljev, prosenj in iskanja.
// - .prijavaMeni(...): gumb »…« v vrstici zaslona (klub, dogodek) z dejanjem Report.
// Aplikacija ima o tujem uporabniku samo id, uporabnisko ime in sliko (invarianta I11), zato posebnega
// »profila drugega uporabnika« ni — uporabniki so vidni v vrsticah My friends in v iskanju.
// Modra ostane samo na glavnem gumbu (Send); Block je destruktiven.

// MARK: - List za prijavo

@MainActor
struct ReportSheet: View {
    let targetType: ReportTargetType
    let targetId: Int
    /// Ime cilja (uporabnik, klub, dogodek) — samo za prikaz pod naslovom.
    let targetName: String

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if sent {
                uspeh
            } else {
                obrazec
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .outlyOzadje()
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(sending)
    }

    // MARK: Deli

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Report")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                if !targetName.isEmpty {
                    Text(verbatim: targetName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(sending)
        }
        .padding(.top, 18)
    }

    private var obrazec: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Why are you reporting this?")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 2)

                    ForEach(ReportReason.allCases) { r in vrsticaRazloga(r) }

                    podrobnosti
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            if let errorText {
                Text(verbatim: errorText)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            OutlyPrimaryButton(title: "Send", isLoading: sending) {
                Task { await poslji() }
            }
            .disabled(reason == nil || sending)
            .opacity(reason == nil ? 0.4 : 1)
            .padding(.bottom, 16)
        }
    }

    private func vrsticaRazloga(_ r: ReportReason) -> some View {
        let izbran = reason == r
        return Button { reason = r } label: {
            HStack(spacing: 12) {
                Text(verbatim: r.label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: izbran ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(izbran ? .white : .white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(izbran ? 0.4 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(izbran ? .isSelected : [])
    }

    private var podrobnosti: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $details)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .tint(.outlyBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(height: 120)
                if details.isEmpty {
                    Text("Add details (optional)")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
            .onChange(of: details) { _, nova in
                // Backend steje kodne tocke, ne znakov.
                if nova.unicodeScalars.count > APIClient.prijavaPodrobnostiNajvec {
                    details = String(String.UnicodeScalarView(nova.unicodeScalars.prefix(APIClient.prijavaPodrobnostiNajvec)))
                }
            }
            Text(verbatim: "\(details.unicodeScalars.count)/\(APIClient.prijavaPodrobnostiNajvec)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.top, 6)
    }

    private var uspeh: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.85))
            Text("Thanks — we review reports within 24 hours.")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
            OutlyPrimaryButton(title: "Done") { dismiss() }
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Podatki

    private func poslji() async {
        guard let reason, !sending else { return }
        sending = true
        errorText = nil
        defer { sending = false }
        do {
            try await APIClient.shared.sendReport(token: session.token, targetType: targetType, targetId: targetId,
                                                  reason: reason, details: details)
            sent = true
        } catch {
            errorText = error.prijavaSporocilo
        }
    }
}

// MARK: - Meni »…« ob tujem uporabniku

/// Meni ob uporabniku (vrstica prijatelja, prosnje, zadetka iskanja): [dodatna dejanja], Report, Block.
/// Block ima potrditveno okno; po uspehu poklice `onBlocked` (starš osveži sezname — prijateljstvo in
/// prosnje so s strani streznika ze izginili).
@MainActor
struct UserSafetyMenu<Extra: View>: View {
    let user: FriendUser
    var onBlocked: () -> Void
    private let extra: Extra

    @EnvironmentObject private var session: SessionStore
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var blocking = false
    @State private var errorText: String?

    init(user: FriendUser, onBlocked: @escaping () -> Void, @ViewBuilder extra: () -> Extra) {
        self.user = user
        self.onBlocked = onBlocked
        self.extra = extra()
    }

    var body: some View {
        Menu {
            extra
            Button { showReport = true } label: {
                Label("Report", systemImage: "flag")
            }
            Button(role: .destructive) { confirmBlock = true } label: {
                Label("Block", systemImage: "nosign")
            }
        } label: {
            if blocking {
                ProgressView().tint(.white).frame(width: 36, height: 36)
            } else {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .disabled(blocking)
        .accessibilityLabel(Text("More options"))
        .sheet(isPresented: $showReport) {
            ReportSheet(targetType: .user, targetId: user.id, targetName: user.username)
                .environmentObject(session)
        }
        .confirmationDialog("Block \(user.username)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await blokiraj() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to find you or send you requests. They won't be notified.")
        }
        .alert("Couldn't block this user", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorText ?? "")
        }
    }

    private func blokiraj() async {
        guard !blocking else { return }
        blocking = true
        defer { blocking = false }
        do {
            try await APIClient.shared.blockUser(token: session.token, userId: user.id)
            onBlocked()
        } catch {
            errorText = error.prijavaSporocilo
        }
    }
}

extension UserSafetyMenu where Extra == EmptyView {
    init(user: FriendUser, onBlocked: @escaping () -> Void) {
        self.init(user: user, onBlocked: onBlocked, extra: { EmptyView() })
    }
}

// MARK: - Gumb »…« v vrstici zaslona (klub, dogodek)

private struct PrijavaMeniModifier: ViewModifier {
    let targetType: ReportTargetType
    let targetId: Int
    let targetName: String
    /// Lastna vsebina (moj klub, moj dogodek) se ne prijavlja.
    let skrij: Bool

    @EnvironmentObject private var session: SessionStore
    @State private var showReport = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if session.isLoggedIn && !skrij {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { showReport = true } label: {
                                Label("Report", systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel(Text("More options"))
                    }
                }
            }
            .sheet(isPresented: $showReport) {
                ReportSheet(targetType: targetType, targetId: targetId, targetName: targetName)
                    .environmentObject(session)
            }
    }
}

extension View {
    /// Doda v vrstico zaslona meni »…« z dejanjem Report (klub, dogodek). Prijavljeni uporabniki, ne za lastno vsebino.
    func prijavaMeni(targetType: ReportTargetType, targetId: Int, targetName: String, skrij: Bool = false) -> some View {
        modifier(PrijavaMeniModifier(targetType: targetType, targetId: targetId, targetName: targetName, skrij: skrij))
    }
}
