import SwiftUI

private struct BusinessEvent: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let date: String
    let status: String
    let statusColor: Color
}

struct BusinessEventsView: View {
    private let events: [BusinessEvent] = [
        .init(imageName: "cirkus_1", title: "Henny", date: "7. July 2025", status: "Upcoming", statusColor: .green),
        .init(imageName: "cirkus_2", title: "Aca Lukas", date: "7. August 2025", status: "Ended", statusColor: .red),
        .init(imageName: "cirkus_3", title: "Crni Cerak", date: "7. September 2024", status: "Ended", statusColor: .red),
        .init(imageName: "k4", title: "Inas", date: "7. November 2024", status: "Ended", statusColor: .red),
        .init(imageName: "logo", title: "Milica Pavlovic", date: "7. December 2024", status: "Ended", statusColor: .red)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Events")
                        .font(.title.bold())
                    Spacer()
                    Button("Add event") {}
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blackColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 14) {
                    ForEach(events) { event in
                        BusinessEventRow(event: event)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.black.opacity(0.98))
        .preferredColorScheme(.dark)
    }
}

private struct BusinessEventRow: View {
    let event: BusinessEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(event.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)
                Text(event.date)
                    .font(.subheadline.weight(.semibold))
                Text(event.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(event.statusColor)
            }

            Spacer()

            Button("View details") {}
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.blackColor)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
