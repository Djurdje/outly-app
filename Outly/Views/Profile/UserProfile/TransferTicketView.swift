import SwiftUI

/// Posiljanje vstopnice prijatelju (sheet iz TicketDetailView).
/// Od 20. 9. (Martin): najprej izbira prijatelja iz seznama (GET /me/friends, prenos po
/// user_id); vpis e-naslova ostane kot druga pot (za nekoga, ki se ni prijatelj).
/// Po uspehu vstopnica izgine iz mojih (nov QR dobi prijatelj), zato zapremo tudi detajl.
@MainActor
struct TransferTicketView: View {
    let ticket: APITicket
    /// Poklicano po uspesnem prenosu (starsevski pogled zapre detajl vstopnice).
    var onTransferred: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var friends: [FriendUser] = []
    @State private var friendsLoading = true
    @State private var selected: FriendUser?
    /// true = vpis e-naslova (tudi ce ima uporabnik prijatelje).
    @State private var byEmail = false
    @State private var email = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var doneMessage: String?

    private var emailOk: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.contains("@") && e.contains(".") && e.count >= 6
    }

    /// Prikaz e-naslova: uporabnik ga je izbral ali pa nima prijateljev.
    private var kazeEmail: Bool { byEmail || (!friendsLoading && friends.isEmpty) }
    private var lahkoPoslje: Bool { kazeEmail ? emailOk : selected != nil }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Send to a friend")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ticket.eventTitle)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(ticket.clubName) · \(ticket.publicRef)")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    if let doneMessage {
                        uspeh(doneMessage)
                    } else {
                        obrazec
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .outlyOzadje()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                        if doneMessage != nil { onTransferred() }
                    } label: {
                        Text(LocalizedStringKey(doneMessage == nil ? "Cancel" : "Done"))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSending)
        .task { await loadFriends() }
    }

    private var obrazec: some View {
        VStack(alignment: .leading, spacing: 16) {
            if friendsLoading {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                    .frame(height: 52)
            } else if kazeEmail {
                Text("Your friend's Outly email")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                OutlyTextField(placeholder: "friend@email.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !friends.isEmpty {
                    preklop("Choose from my friends instead") { byEmail = false }
                }
            } else {
                Text("Choose a friend")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                VStack(spacing: 8) {
                    ForEach(friends) { f in
                        Button { selected = (selected?.id == f.id) ? nil : f } label: {
                            HStack(spacing: 12) {
                                OutlyAvatarView(avatarUrlString: f.avatarUrl, size: 40)
                                Text(f.username)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: selected?.id == f.id ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(selected?.id == f.id ? .outlyBlue : .white.opacity(0.35))
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(selected?.id == f.id ? 0.12 : 0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(selected?.id == f.id ? Color.outlyBlue : Color.clear, lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                preklop("Send by email instead") { byEmail = true; selected = nil }
            }

            Group {
                if ticket.minAge > 0 {
                    Text("The ticket moves to your friend's account with a new QR code. Your copy stops working. Your friend needs an Outly account and must be \(ticket.minAge)+.")
                } else {
                    Text("The ticket moves to your friend's account with a new QR code. Your copy stops working. Your friend needs an Outly account.")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.5))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }

            OutlyPrimaryButton(title: "Send ticket", isLoading: isSending) {
                Task { await posli() }
            }
            .disabled(!lahkoPoslje || isSending)
            .opacity(lahkoPoslje ? 1 : 0.5)
            .padding(.top, 6)
        }
    }

    private func preklop(_ naslov: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(naslov))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.outlyBlue)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private func uspeh(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.outlyBlue)
            Text(msg)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("It will show up under Tickets in their app.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
            OutlyPrimaryButton(title: "Done") {
                dismiss()
                onTransferred()
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    private func loadFriends() async {
        friendsLoading = true
        defer { friendsLoading = false }
        // Napaka pri nalaganju prijateljev ni ovira: pade se nazaj na vpis e-naslova.
        if let r = try? await APIClient.shared.fetchMyFriends(token: session.token) {
            friends = r.friends
        }
    }

    private func posli() async {
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let r: TransferResponse
            if !kazeEmail, let f = selected {
                r = try await APIClient.shared.transferTicket(token: session.token, ticketId: ticket.id, userId: f.id)
            } else {
                r = try await APIClient.shared.transferTicket(
                    token: session.token, ticketId: ticket.id,
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            doneMessage = r.message
        } catch {
            errorMessage = error.userMessage
        }
    }
}
