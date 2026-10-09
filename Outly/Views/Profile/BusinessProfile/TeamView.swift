import SwiftUI

/// Ekipa kluba: lastnik + managerji + vratarji + natakarji (GET /business/team) + cakajoca vabila.
/// Lastnik vabi in odstranjuje vse; manager samo vratarje. Vratar tega zaslona ne vidi.
/// Od 13. 9. (migracija 013) dodajanje poslje VABILO: clan nastane, ko ga
/// povabljeni sprejme v aplikaciji (My clubs -> zvonec). Povabljeni mora ze imeti Outly racun.
@MainActor
struct TeamView: View {
    let clubName: String?

    @EnvironmentObject private var session: SessionStore

    @State private var myRole = ""
    @State private var members: [TeamMember] = []
    @State private var invites: [TeamInvite] = []
    @State private var cancelling: TeamInvite?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showAdd = false
    @State private var removing: TeamMember?
    @State private var busyUserId: Int?

    private var canAddManagers: Bool { myRole == "owner" || myRole == "admin" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Team")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    if let clubName, !clubName.isEmpty {
                        Text(clubName)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.top, 6)

                if isLoading && members.isEmpty {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                        .padding(.top, 40)
                } else if let errorText, members.isEmpty {
                    VStack(spacing: 10) {
                        Text(errorText).foregroundColor(.red).font(.subheadline)
                        Button("Try again") { Task { await load() } }
                            .foregroundColor(.outlyBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                } else {
                    VStack(spacing: 10) {
                        ForEach(members) { m in
                            vrstica(m)
                        }
                    }

                    if !invites.isEmpty {
                        Text("Waiting for reply")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 4)
                        VStack(spacing: 10) {
                            ForEach(invites) { v in
                                vabiloVrstica(v)
                            }
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    OutlyPrimaryButton(title: "Invite member") { showAdd = true }
                        .padding(.top, 6)

                    razlaga
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            AddTeamMemberView(canAddManagers: canAddManagers) { r in
                myRole = r.myRole
                members = r.members
                invites = r.invites
            }
            .environmentObject(session)
        }
        .confirmationDialog(
            removing.map { (m) -> LocalizedStringKey in "Remove \(m.username) from the team?" } ?? "",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let m = removing { Task { await remove(m) } }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("They lose access to the club tools right away.")
        }
        .confirmationDialog(
            cancelling.map { (v) -> LocalizedStringKey in "Cancel the invitation for \(v.username.isEmpty ? v.email : v.username)?" } ?? "",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible
        ) {
            Button("Cancel invitation", role: .destructive) {
                if let v = cancelling { Task { await cancel(v) } }
            }
            Button("Keep it", role: .cancel) { cancelling = nil }
        }
    }

    // MARK: - Vrstica cakajocega vabila

    private func canCancel(_ v: TeamInvite) -> Bool {
        if canAddManagers { return true }
        return v.role == "doorman" || v.role == "bartender"
    }

    private func vabiloVrstica(_ v: TeamInvite) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.06))
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(v.username.isEmpty ? v.email : v.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                Text("Invited as \(v.roleLabel.lowercased()) · waiting")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if canCancel(v) {
                Button {
                    cancelling = v
                } label: {
                    Group {
                        if busyUserId == -v.id {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(busyUserId != nil)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    // MARK: - Vrstica clana

    private func canRemove(_ m: TeamMember) -> Bool {
        if m.role == "owner" { return false }
        if canAddManagers { return true }
        return m.role == "doorman" || m.role == "bartender"
    }

    private func vrstica(_ m: TeamMember) -> some View {
        HStack(spacing: 12) {
            avatar(m)

            VStack(alignment: .leading, spacing: 3) {
                Text(m.username.isEmpty ? m.email : m.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(m.email)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            pill(m)

            if canRemove(m) {
                Button {
                    removing = m
                } label: {
                    Group {
                        if busyUserId == m.userId {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(busyUserId != nil)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func avatar(_ m: TeamMember) -> some View {
        let initial = String((m.username.isEmpty ? m.email : m.username).prefix(1)).uppercased()
        return ZStack {
            Circle().fill(m.role == "owner" ? Color.outlyBlue.opacity(0.25) : Color.white.opacity(0.1))
            if let s = m.avatarUrl, !s.isEmpty, let url = URL(string: s) {
                OutlyAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Text(initial).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                }
            } else {
                Text(initial).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func pill(_ m: TeamMember) -> some View {
        HStack(spacing: 5) {
            Image(systemName: m.roleIcon)
                .font(.system(size: 10, weight: .semibold))
            Text(m.roleLabel)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(m.role == "owner" ? .outlyBlue : .white.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(m.role == "owner" ? Color.outlyBlue.opacity(0.15) : Color.white.opacity(0.08)))
    }

    private var razlaga: some View {
        VStack(alignment: .leading, spacing: 10) {
            vloga(icon: "person.text.rectangle", title: "Manager",
                  text: "Events, sales, club page and door staff. Can't add other managers.")
            vloga(icon: "qrcode.viewfinder", title: "Door staff",
                  text: "Scans tickets at the door. Nothing else.")
            vloga(icon: "wineglass", title: "Bartender",
                  text: "Sees VIP tables to serve and marks them delivered. No guest details.")
        }
        .padding(.top, 10)
    }

    private func vloga(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.outlyBlue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(text).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Podatki

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await APIClient.shared.fetchTeam(token: session.token)
            myRole = r.myRole
            members = r.members
            invites = r.invites
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }

    private func remove(_ m: TeamMember) async {
        removing = nil
        busyUserId = m.userId
        defer { busyUserId = nil }
        do {
            let r = try await APIClient.shared.removeTeamMember(token: session.token, userId: m.userId)
            myRole = r.myRole
            members = r.members
            invites = r.invites
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }

    private func cancel(_ v: TeamInvite) async {
        cancelling = nil
        busyUserId = -v.id
        defer { busyUserId = nil }
        do {
            let r = try await APIClient.shared.cancelTeamInvite(token: session.token, inviteId: v.id)
            myRole = r.myRole
            members = r.members
            invites = r.invites
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }
}

// MARK: - Dodajanje clana

/// Sheet: e-naslov Outly racuna + vloga -> poslje VABILO. Manager lahko povabi samo vratarja.
@MainActor
struct AddTeamMemberView: View {
    let canAddManagers: Bool
    var onAdded: (TeamResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var email = ""
    @State private var role = "doorman"
    @State private var isSending = false
    @State private var errorMessage: String?

    private var emailOk: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.contains("@") && e.contains(".") && e.count >= 6
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Invite to team")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Their Outly email")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        OutlyTextField(placeholder: "name@email.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("They need an Outly account with this email. They get the invitation in the app (Profile → My clubs) and join once they accept.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Role")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        if canAddManagers {
                            izbira(value: "manager", icon: "person.text.rectangle", title: "Manager",
                                   text: "Events, sales, club page and door staff.")
                        }
                        izbira(value: "doorman", icon: "qrcode.viewfinder", title: "Door staff",
                               text: "Scans tickets at the door.")
                        izbira(value: "bartender", icon: "wineglass", title: "Bartender",
                               text: "Serves VIP tables and marks them delivered.")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    OutlyPrimaryButton(title: "Send invite", isLoading: isSending) {
                        Task { await dodaj() }
                    }
                    .disabled(!emailOk || isSending)
                    .opacity(emailOk ? 1 : 0.5)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .outlyOzadje()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSending)
    }

    private func izbira(value: String, icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        let on = role == value
        return Button {
            role = value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(on ? .outlyBlue : .white.opacity(0.7))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    Text(text).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(on ? .outlyBlue : .white.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(on ? 0.1 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(on ? Color.outlyBlue.opacity(0.7) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func dodaj() async {
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let r = try await APIClient.shared.addTeamMember(
                token: session.token,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role)
            onAdded(r)
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }
}
