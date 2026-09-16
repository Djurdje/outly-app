import SwiftUI

/// Posiljanje vstopnice prijatelju (sheet iz TicketDetailView).
/// Prijatelj mora imeti Outly racun; vpisemo e-naslov njegovega racuna.
/// Po uspehu vstopnica izgine iz mojih (nov QR dobi prijatelj), zato zapremo tudi detajl.
@MainActor
struct TransferTicketView: View {
    let ticket: APITicket
    /// Poklicano po uspesnem prenosu (starsevski pogled zapre detajl vstopnice).
    var onTransferred: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var email = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var doneMessage: String?

    private var emailOk: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.contains("@") && e.contains(".") && e.count >= 6
    }

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
            .background(Color.black.ignoresSafeArea())
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
    }

    private var obrazec: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your friend's Outly email")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            OutlyTextField(placeholder: "friend@email.com", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

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
            .disabled(!emailOk || isSending)
            .opacity(emailOk ? 1 : 0.5)
            .padding(.top, 6)
        }
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

    private func posli() async {
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let r = try await APIClient.shared.transferTicket(
                token: session.token, ticketId: ticket.id,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            doneMessage = r.message
        } catch {
            errorMessage = error.userMessage
        }
    }
}
