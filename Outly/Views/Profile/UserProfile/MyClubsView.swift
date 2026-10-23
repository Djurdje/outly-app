import SwiftUI

/// "My clubs" po Figmi (370:735 prazno, 382:805 s klubom, 370:849 z vabilom,
/// 370:1303 po sprejemu): SEZNAM klubov, katerih ekipe je uporabnik clan — vsak
/// klub svoja kartica (logo, ime, vloga, "View"). Od backend migracije 018 (21. 9.)
/// je oseba lahko v vec ekipah: seznam pride iz GET /me `clubs`; "View" nastavi
/// IzbraniKlub (glava X-Outly-Club), da vsi klici veljajo za izbrani klub. Zaposlitev je popolnoma locena
/// od osebnega profila (ProfileView): vse klubske funkcije (Dashboard, Scan
/// tickets, Events, Team, Edit page) so tu, znotraj izbranega kluba, ne globalno.
/// Desno zgoraj je zvonec z znacko: tam uporabnik prejme vabilo v ekipo in ga
/// sprejme ali zavrne (ClubInvitesView).
/// Podatki: GET /me (club_id, club_role, pending_invites), GET /business/clubs/me,
/// GET /me/invites. Martin, 13. 9. 2026 (seznam kartic: 20. 9. 2026).
@MainActor
struct MyClubsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var club: APIClub?
    @State private var invites: [MyInvite] = []
    @State private var isLoading = false
    @State private var errorText: String?
    /// Po sprejemu vabila: "Congratulations, you have become a X employee." (Figma 370:1303).
    @State private var justJoined: String?

    private var me: Me? { session.me }
    private var pendingCount: Int { max(invites.count, me?.pendingInvites ?? 0) }

    /// Klub + vloga za vsako clanstvo. Od backend migracije 018 jih je lahko vec (GET /me `clubs`);
    /// star backend seznama nima -> eno clanstvo iz club_id/club_role kot prej.
    private struct Membership: Identifiable {
        let clubId: Int
        let ime: String
        let logoUrl: String
        let role: String
        var id: Int { clubId }
    }
    private var memberships: [Membership] {
        if let me, !me.clubs.isEmpty {
            return me.clubs.map { Membership(clubId: $0.clubId, ime: $0.clubName, logoUrl: $0.clubLogoUrl, role: $0.role) }
        }
        guard let role = me?.clubRole, let id = me?.clubId else { return [] }
        return [Membership(clubId: id, ime: club?.name ?? "", logoUrl: club?.logoUrl ?? "", role: role)]
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("My clubs")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    if isLoading && club == nil && invites.isEmpty && me?.clubRole == nil {
                        HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 40)
                    } else {
                        if let justJoined {
                            cestitka(justJoined)
                        }

                        if !memberships.isEmpty {
                            VStack(spacing: 12) {
                                ForEach(memberships) { m in
                                    klubVrstica(m)
                                }
                            }
                        } else {
                            if let first = invites.first {
                                vabiloNamig(first)
                            }
                            prazno
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
            // Samostojna naloga: SwiftUI sicer prekine osvezitev ob spremembi stanja (glej HomeView).
            .refreshable { await Task { await load() }.value }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ClubInvitesView(invites: $invites) { clubName in
                        justJoined = clubName
                        Task { await load() }
                    }
                } label: {
                    zvonec
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Deli

    /// Zvonec z rdeco znacko (Figma 370:1093–1095).
    private var zvonec: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Circle().fill(Color(red: 1, green: 0.30, blue: 0.30)))
                    .offset(x: 3, y: -2)
            }
        }
        .accessibilityLabel(pendingCount > 0 ? String(localized: "\(pendingCount) invitations") : String(localized: "Notifications"))
    }

    /// Kartica kluba (Figma 382:805): logo, ime, vloga, desno "View". Ena na clanstvo.
    private func klubVrstica(_ m: Membership) -> some View {
        NavigationLink {
            MyClubDetailView(clubId: m.clubId, ime: m.ime, logoUrl: m.logoUrl, role: m.role)
        } label: {
            HStack(spacing: 14) {
                logo(m.logoUrl, size: 56, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(m.ime.isEmpty ? String(localized: "Your club") : m.ime)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(roleLabel(m.role))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Text("View")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.outlyBlue)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    /// Namig nad praznim stanjem (Figma 370:931–940): "X has sent you an invitation — Open it".
    private func vabiloNamig(_ v: MyInvite) -> some View {
        NavigationLink {
            ClubInvitesView(invites: $invites) { clubName in
                justJoined = clubName
                Task { await load() }
            }
        } label: {
            HStack(spacing: 12) {
                logo(v.clubLogoUrl, size: 40, radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(v.clubName) has sent you an invitation")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text("Open it")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.outlyBlue)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    /// Prazno stanje (Figma 370:846–847).
    private var prazno: some View {
        VStack(spacing: 14) {
            Text("You are currently not working\nfor any club")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("tap the bell above\nto see invitations")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.bottom, 10)
    }

    /// Kartica po sprejemu (Figma 370:1377): zapre jo X.
    private func cestitka(_ clubName: String) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                logo(club?.logoUrl, size: 72, radius: 12)
                Text("Congratulations, you have become a \(clubName) employee.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 25/255, green: 25/255, blue: 25/255), .black],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            Button {
                withAnimation(.easeOut(duration: 0.2)) { justJoined = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private func logo(_ url: String?, size: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let url, !url.isEmpty, let u = URL(string: url) {
                Color.clear
                    .overlay(
                        OutlyAsyncImage(url: u) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color.white.opacity(0.1))
                        }
                    )
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.outlyBlue.opacity(0.2))
                    .overlay(Image(systemName: "building.2").foregroundColor(.outlyBlue))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "owner": return String(localized: "Owner")
        case "manager": return String(localized: "Manager")
        case "bartender": return String(localized: "Bartender")
        default: return String(localized: "Door staff")
        }
    }

    // MARK: - Podatki

    private func load() async {
        guard session.isLoggedIn else { return }
        // Seznam: noben klub ni izbran (glava X-Outly-Club se ne poslje).
        IzbraniKlub.id = nil
        isLoading = true
        defer { isLoading = false }
        errorText = nil
        await session.refreshMe()
        do {
            if session.me?.clubId != nil {
                club = try await APIClient.shared.fetchMyBusinessClub(token: session.token)
            } else {
                club = nil
            }
            invites = try await APIClient.shared.fetchMyInvites(token: session.token)
        } catch let api as APIError {
            // 404 = klub se ni ustvarjen; to ni napaka za uporabnika.
            if case let .requestFailed(code, _) = api, code == 404 { return }
            errorText = opisNapake(api)
        } catch {
            errorText = opisNapake(error)
        }
    }

    /// Brez povezave (K1): seznam klubov pride iz shranjenega Me, zato ni napaka, ampak opomba; skener deluje naprej.
    private func opisNapake(_ e: Error) -> String {
        e.jeIzpadPovezave ? String(localized: "No connection. Showing your saved clubs; the scanner still works.") : e.userMessage
    }
}

/// Klub, v katerem delam (Figma 382:897 "My clubs profile club"): glava kluba,
/// vrstice Create event / View events / Scan ticket in spodaj izstop iz ekipe.
/// Vratar vidi samo skener, natakar samo Table service (streznik ostalo zavrne s 403).
@MainActor
struct MyClubDetailView: View {
    let clubId: Int
    /// Ime in logo iz seznama (GET /me clubs), da glava ni prazna, dokler se klub nalaga.
    let ime: String
    let logoUrl: String
    let role: String

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    /// Poln klub (GET /business/clubs/me z glavo X-Outly-Club za ta klub).
    @State private var club: APIClub?
    @State private var showCreate = false
    @State private var showLeave = false
    @State private var errorText: String?

    private var canManage: Bool { role == "owner" || role == "manager" }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {

                    HStack(spacing: 16) {
                        logo
                        VStack(alignment: .leading, spacing: 4) {
                            Text(club?.name ?? (ime.isEmpty ? String(localized: "Your club") : ime))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            if let c = club, !c.city.isEmpty {
                                Text(c.city)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Text(roleLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.outlyBlue)
                        }
                        Spacer()
                    }
                    .padding(.top, 6)

                    VStack(spacing: 10) {
                        if canManage {
                            NavigationLink {
                                EditBusinessPageView(clubId: clubId)
                            } label: {
                                OutlyMenuRowButton(icon: "pencil", title: "Edit your page")
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                BusinessDashboardView(clubId: clubId, clubName: club?.name ?? (ime.isEmpty ? nil : ime), clubLogoUrl: (club?.logoUrl ?? "").isEmpty ? logoUrl : (club?.logoUrl ?? ""))
                            } label: {
                                OutlyMenuRowButton(icon: "chart.bar", title: "Dashboard")
                            }
                            .buttonStyle(.plain)

                            Button { showCreate = true } label: {
                                OutlyMenuRowButton(icon: "plus.circle", title: "Create event")
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                BusinessEventsView(clubId: clubId, clubName: club?.name ?? ime)
                            } label: {
                                OutlyMenuRowButton(icon: "calendar", title: "View events")
                            }
                            .buttonStyle(.plain)

                            // Kdo je rezerviral katero VIP mizo (owner, manager; vratar rezervacije vidi v seznamu vstopnic dogodka).
                            NavigationLink {
                                RezervacijeDogodkiView(smeSprostiti: canManage)
                            } label: {
                                OutlyMenuRowButton(icon: "table.furniture", title: "Reservations")
                            }
                            .buttonStyle(.plain)

                            // Ekipo (migracija 009) ureja lastnik in manager, isto kot canManage.
                            NavigationLink {
                                TeamView(clubName: club?.name)
                            } label: {
                                OutlyMenuRowButton(icon: "person.2", title: "Team")
                            }
                            .buttonStyle(.plain)
                        }

                        // Skener: owner, manager, doorman (natakar ga ne vidi).
                        if role != "bartender" {
                            NavigationLink {
                                QRScannerView(clubId: clubId)
                            } label: {
                                OutlyMenuRowButton(icon: "qrcode.viewfinder", title: "Scan ticket")
                            }
                            .buttonStyle(.plain)
                        }

                        // Strezba VIP miz: owner, manager, bartender (vratar je ne vidi).
                        if TableServiceView.smeVideti(role: role) {
                            NavigationLink {
                                TableServiceView(clubId: clubId, clubName: club?.name ?? ime)
                            } label: {
                                OutlyMenuRowButton(icon: "wineglass", title: "Table service")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let errorText {
                        Text(errorText).font(.system(size: 13)).foregroundColor(.red)
                    }

                    Spacer(minLength: 60)

                    if role != "owner" {
                        Button { showLeave = true } label: {
                            Text("Leave the team")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.red.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(Color.red.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("Leave the team?", isPresented: $showLeave, titleVisibility: .visible) {
                            Button("Leave team", role: .destructive) { Task { await leave() } }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("You lose access to the club tools. The club can invite you again.")
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Od tu naprej (Dashboard, Events, Team, Edit page ...) vsi klici veljajo za TA klub.
            IzbraniKlub.id = clubId
            club = try? await APIClient.shared.fetchMyBusinessClub(token: session.token)
        }
        .sheet(isPresented: $showCreate) {
            EventFormView(clubId: clubId, existing: nil) { _ in }
                .environmentObject(session)
        }
    }

    private var roleLabel: String {
        switch role {
        case "owner": return String(localized: "Owner")
        case "manager": return String(localized: "Manager")
        case "bartender": return String(localized: "Bartender")
        default: return String(localized: "Door staff")
        }
    }

    private var logo: some View {
        Group {
            if let s = club?.logoUrl ?? (logoUrl.isEmpty ? nil : logoUrl), !s.isEmpty, let u = URL(string: s) {
                Color.clear
                    .overlay(
                        OutlyAsyncImage(url: u) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color.white.opacity(0.1))
                        }
                    )
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.outlyBlue.opacity(0.2))
                    .overlay(Image(systemName: "building.2").font(.system(size: 26)).foregroundColor(.outlyBlue))
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func leave() async {
        do {
            try await APIClient.shared.leaveTeam(token: session.token)
            await session.refreshMe()
            dismiss()
        } catch {
            errorText = error.userMessage
        }
    }
}

struct Screen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .outlyOzadje()
    }
}
