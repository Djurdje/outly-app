import SwiftUI

struct TicketRow: View {
    let imageName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 70, height: 70)
                .clipped()
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text("View details")
                    .font(.subheadline)
                    .foregroundColor(Color("blackColor"))
            }

            Spacer()
        }
        .padding(14)
        .background(Color.gray.opacity(0.14))
        .cornerRadius(16)
    }
}
