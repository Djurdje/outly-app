import SwiftUI

/// Obvestila / vabila v ekipo kluba (Figma 370:942 "My clubs inv"): kartica z
/// logotipom kluba, "X has sent you an invitation to work as a Manager", razlaga
/// in gumba Reject / Accept. Po sprejemu se vrne na My clubs, ki pokaze cestitko
/// (onJoined). Vabila: GET /me/invites, POST /me/invites/:id/accept|decline.
@MainActor
struct ClubInvitesView: View {
    @Binding var invites: [MyInvite]
    /// Klice se z imenom kluba po uspesnem sprejemu.
    var onJoined: (String) -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var busyId: Int?
    @State private var errorText: String?

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("Notifications")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    if isLoading && invites.isEmpty {
                        HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 40)
                    } else if invites.isEmpty {
                        prazno
                    } else {
                        ForEach(invites) { v in
                            kartica(v)
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
            // Samostojna naloga: SwiftUI sicer prekine osvezitev ob spremembi stanja (glej HomeView).
            .refreshable { await Task { await load() }.value }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Kartica vabila (Figma 370:1011–1048)

    private func kartica(_ v: MyInvite) -> some View {
        VStack(spacing: 18) {
            logo(v.clubLogoUrl)
                .padding(.top, 10)

            VStack(spacing: 10) {
                (Text("\(v.clubName) has sent you an invitation to work as a ")
                    + Text(v.roleLabel).fontWeight(.bold))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                (Text("By accepting, you will become a ")
                    + Text(v.clubName).fontWeight(.bold)
                    + Text(" employee. With this role you will get access to \(v.roleDescription)."))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                if let who = v.invitedByUsername, !who.isEmpty {
                    Text("Invited by \(who)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 22)

            HStack(spacing: 14) {
                gumb("Reject", barva: Color(red: 1, green: 76/255, blue: 76/255), busy: busyId == v.id) {
                    Task { await decline(v) }
                }
                gumb("Accept", barva: Color(red: 52/255, green: 168/255, blue: 83/255), busy: busyId == v.id) {
                    Task { await accept(v) }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 25/255, green: 25/255, blue: 25/255), .black],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func gumb(_ naslov: String, barva: Color, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(LocalizedStringKey(naslov))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(barva))
        }
        .buttonStyle(.plain)
        .disabled(busyId != nil)
    }

    private func logo(_ url: String) -> some View {
        Group {
            if !url.isEmpty, let u = URL(string: url) {
                Color.clear
                    .overlay(
                        AsyncImage(url: u) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color.white.opacity(0.1))
                        }
                    )
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.outlyBlue.opacity(0.2))
                    .overlay(Image(systemName: "building.2").font(.system(size: 28)).foregroundColor(.outlyBlue))
            }
        }
        .frame(width: 95, height: 95)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var prazno: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.35))
            Text("No new notifications")
                .font(.headline)
                .foregroundColor(.white)
            Text("Invitations from clubs to join their team\nwill show up here.")
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    // MARK: - Podatki

    private func load() async {
        guard session.isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            invites = try await APIClient.shared.fetchMyInvites(token: session.token)
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }

    private func accept(_ v: MyInvite) async {
        errorText = nil
        busyId = v.id
        defer { busyId = nil }
        do {
            let r = try await APIClient.shared.acceptInvite(token: session.token, inviteId: v.id)
            invites = []
            await session.refreshMe()
            onJoined(r.club.name)
            dismiss()
        } catch {
            errorText = error.userMessage
            // Vabilo morda ni vec veljavno — osvezimo seznam.
            await load()
        }
    }

    private func decline(_ v: MyInvite) async {
        errorText = nil
        busyId = v.id
        defer { busyId = nil }
        do {
            invites = try await APIClient.shared.declineInvite(token: session.token, inviteId: v.id)
            await session.refreshMe()
        } catch {
            errorText = error.userMessage
            await load()
        }
    }
}
