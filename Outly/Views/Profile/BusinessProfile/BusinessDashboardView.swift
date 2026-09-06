import SwiftUI

private enum SalesRange: String, CaseIterable, Identifiable {
    case year = "By year"
    case month = "By month"
    case week = "By week"

    var id: String { rawValue }
}

private struct SalesPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

private struct PerformanceEvent: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let date: String
    let revenue: String
}

struct BusinessDashboardView: View {
    @State private var selectedRange: SalesRange = .year

    private let overviewCards: [BusinessStatCard] = [
        .init(title: "Total revenue", value: "$12,921"),
        .init(title: "Tickets sold", value: "1,321"),
        .init(title: "Withdrawable Balance", value: "$2,921"),
        .init(title: "Average Tickets per Event", value: "154")
    ]

    private let performanceEvents: [PerformanceEvent] = [
        .init(imageName: "cirkus_1", title: "Pump it up", date: "12 sep", revenue: "$1,200"),
        .init(imageName: "cirkus_2", title: "Redhedi", date: "11 sep", revenue: "$2,200"),
        .init(imageName: "cirkus_3", title: "Balkan blast", date: "1 sep", revenue: "$2,600"),
        .init(imageName: "k4", title: "Season closed", date: "28 jun", revenue: "$3,100"),
        .init(imageName: "logo", title: "Casolina", date: "20 jun", revenue: "$1,200")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                dashboardHeader
                statsGrid
                salesSection
                performanceSection
                activitySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.black.opacity(0.98))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var dashboardHeader: some View {
        VStack(spacing: 10) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)

            Text("Cirkus")
                .font(.title.bold())
        }
        .frame(maxWidth: .infinity)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(overviewCards) { card in
                StatCardView(card: card)
            }
        }
    }

    private var salesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sales")
                .font(.title2.bold())

            HStack(spacing: 10) {
                ForEach(SalesRange.allCases) { range in
                    Button {
                        selectedRange = range
                    } label: {
                        Text(range.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedRange == range ? .white : .white.opacity(0.8))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(selectedRange == range ? Color.blackColor : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blackColor.opacity(selectedRange == range ? 0 : 0.7), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            SalesChartView(points: salesPoints)
                .frame(height: 200)
                .padding(.top, 4)
        }
    }

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Event performance")
                    .font(.title2.bold())
                Spacer()
                Text("View all")
                    .foregroundStyle(Color.blackColor)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(spacing: 12) {
                ForEach(performanceEvents) { event in
                    PerformanceRow(event: event)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check activity")
                .font(.title2.bold())

            HStack(spacing: 12) {
                ActivityCard(title: "Clicks on profile", value: "89,419")
                ActivityCard(title: "Clicks on events", value: "21,204")
            }

            StaffActivityCard()
        }
    }

    private var salesPoints: [SalesPoint] {
        switch selectedRange {
        case .year:
            return [
                .init(label: "jan", value: 1500),
                .init(label: "feb", value: 1200),
                .init(label: "mar", value: 1400),
                .init(label: "apr", value: 3200),
                .init(label: "jun", value: 1800),
                .init(label: "jul", value: 1400),
                .init(label: "aug", value: 1700),
                .init(label: "sep", value: 3600),
                .init(label: "oct", value: 3200),
                .init(label: "nov", value: 3000),
                .init(label: "dec", value: 3300)
            ]
        case .month:
            return [
                .init(label: "w1", value: 900),
                .init(label: "w2", value: 1500),
                .init(label: "w3", value: 2100),
                .init(label: "w4", value: 1700)
            ]
        case .week:
            return [
                .init(label: "mon", value: 300),
                .init(label: "tue", value: 450),
                .init(label: "wed", value: 380),
                .init(label: "thu", value: 520),
                .init(label: "fri", value: 700),
                .init(label: "sat", value: 820),
                .init(label: "sun", value: 640)
            ]
        }
    }
}

private struct BusinessStatCard: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct StatCardView: View {
    let card: BusinessStatCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            Text(card.value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SalesChartView: View {
    let points: [SalesPoint]

    private let yAxisLabels: [String] = ["0$", "750$", "1500$", "3000$", "7000$"]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let maxValue = max(points.map(\.value).max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(yAxisLabels.reversed(), id: \.self) { label in
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(height: height / CGFloat(yAxisLabels.count - 1), alignment: .center)
                    }
                }

                ZStack(alignment: .bottomLeading) {
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * width
                            let y = height - (CGFloat(point.value / maxValue) * height)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blackColor, lineWidth: 2)

                    Path { path in
                        for (index, point) in points.enumerated() {
                            let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * width
                            let y = height - (CGFloat(point.value / maxValue) * height)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.addLine(to: CGPoint(x: 0, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.blackColor.opacity(0.4), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
    }
}

private struct PerformanceRow: View {
    let event: PerformanceEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(event.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                Text(event.date)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Text(event.revenue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.blackColor)
        }
    }
}

private struct ActivityCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct StaffActivityCard: View {
    private let staff: [(String, String, String)] = [
        ("G", "Gorisek", "1"),
        ("M", "Matic", "2"),
        ("J", "Janez", "3")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Staff activity")
                .font(.headline)
            ForEach(staff, id: \.1) { initial, name, value in
                HStack(spacing: 12) {
                    Text(initial)
                        .font(.headline)
                        .frame(width: 32, height: 32)
                        .background(Color.blackColor.opacity(0.8))
                        .clipShape(Circle())
                    Text(name)
                    Spacer()
                    Text(value)
                        .foregroundStyle(Color.blackColor)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
