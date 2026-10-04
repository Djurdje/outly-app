import SwiftUI

/// List za "Mark as reserved": klub je gost poklical, mizo oznaci kot rezervirano po telefonu, da je prek Outly
/// nihce ne more kupiti. Placilo gre mimo Outly. POST /business/events/:id/tables/:tableId/hold.
/// Po uspehu klicatelj prevzame novo stanje iz odgovora (`onDone`).
@MainActor
struct VipHoldSheet: View {
    let eventId: Int
    let miza: VipBusinessTable
    let onDone: (BusinessEventVip) -> Void
    /// Napaka (npr. 409: mizo je medtem nekdo kupil) - klicatelj osvezi seznam, da ne ostane star.
    var onNapaka: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var guestName = ""
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    static let najvecImena = 60
    static let najvecOpombe = 200

    private var imeOcisceno: String { guestName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var jeVeljavno: Bool { !imeOcisceno.isEmpty && imeOcisceno.count <= Self.najvecImena }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mark as reserved")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        Text(verbatim: VipOznaka.miza(miza.label))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.vipZlata)
                    }
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Guest name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        OutlyTextField(placeholder: "Guest name", text: $guestName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        OutlyTextField(placeholder: "6 guests, arriving 23:00", text: $note)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    OutlyPrimaryButton(title: "Reserve", isLoading: isSending) {
                        Task { await rezerviraj() }
                    }
                    .disabled(!jeVeljavno || isSending)
                    .opacity(jeVeljavno ? 1 : 0.5)
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
        .onChange(of: guestName) { _, nova in
            if nova.count > Self.najvecImena { guestName = String(nova.prefix(Self.najvecImena)) }
        }
        .onChange(of: note) { _, nova in
            if nova.count > Self.najvecOpombe { note = String(nova.prefix(Self.najvecOpombe)) }
        }
    }

    private func rezerviraj() async {
        guard jeVeljavno else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        let opomba = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let novo = try await APIClient.shared.holdVipTable(
                eventId: eventId, tableId: miza.id,
                guestName: imeOcisceno, note: opomba.isEmpty ? nil : opomba,
                token: session.token)
            onDone(novo)
            dismiss()
        } catch {
            errorMessage = error.userMessage
            onNapaka()
        }
    }
}
