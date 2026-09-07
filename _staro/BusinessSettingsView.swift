import SwiftUI

private struct SettingsRow: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
}

struct BusinessSettingsView: View {
    private let settings: [SettingsRow] = [
        .init(icon: "person.crop.circle", title: "Club info"),
        .init(icon: "lock.fill", title: "Password and security"),
        .init(icon: "arrow.triangle.2.circlepath", title: "Switch to personal account")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cirkus")
                            .font(.title3.bold())
                        Text("Edit your page")
                            .foregroundStyle(Color.blackColor)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }

                VStack(spacing: 12) {
                    ForEach(settings) { row in
                        HStack(spacing: 12) {
                            Image(systemName: row.icon)
                                .foregroundStyle(.white)
                                .frame(width: 24)
                            Text(row.title)
                                .font(.headline)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle")
                            .foregroundStyle(.white)
                            .frame(width: 24)
                        Text("Withdraw")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.opacity(0.98))
        .preferredColorScheme(.dark)
    }
}
