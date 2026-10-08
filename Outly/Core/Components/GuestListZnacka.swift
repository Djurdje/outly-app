import SwiftUI

/// Znacka »Guest list« (vstopnica gostitelja ali prijatelja, povabljenega na guest listo). Nevtralna (bela na temni podlagi):
/// zlata je samo za VIP, modra samo za glavni gumb. `kompakten` = manjsa (vrstice seznamov).
struct GuestListZnacka: View {
    var kompakten: Bool = false

    var body: some View {
        HStack(spacing: kompakten ? 3 : 4) {
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: kompakten ? 9 : 11, weight: .bold))
            Text("Guest list")
                .font(.system(size: kompakten ? 10 : 11, weight: .heavy))
                .tracking(0.4)
        }
        .foregroundColor(.white)
        .padding(.horizontal, kompakten ? 7 : 9)
        .padding(.vertical, kompakten ? 3 : 4)
        .background(Color.white.opacity(0.18))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}
