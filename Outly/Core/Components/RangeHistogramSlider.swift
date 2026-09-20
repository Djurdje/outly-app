import SwiftUI

/// Drsnik z dvema rocajema (od-do) in histogramom nad progo (Filtri: Distance, Age range,
/// Entry price). Visina stolpca = stevilo dogodkov v tistem intervalu: vec dogodkov = visji
/// stolpec, brez dogodkov = brez stolpca. Stolpci znotraj izbranega razpona so modri,
/// zunaj zatemnjeni. Histogram ni okrasen: `counts` pripravi klicatelj iz zivih dogodkov
/// (glej `Histogram.prestej`), zato se ob spremembi drugih filtrov posodobi.
struct OutlyRangeHistogramSlider: View {
    /// Stevilo dogodkov po intervalih (levo -> desno cez `range`). Prazno = brez histograma.
    let counts: [Int]
    let range: ClosedRange<Double>
    var step: Double = 1
    @Binding var lower: Double
    @Binding var upper: Double
    /// Napis pod rocajem (npr. "5 km", "18", "5 €").
    let label: (Double) -> String

    // Izracunane, ne shranjene: zasebna shranjena lastnost bi naredila memberwise init zaseben.
    private var thumbSize: CGFloat { 16 }
    private var histogramHeight: CGFloat { 72 }
    private var trackHeight: CGFloat { 28 }
    private var labelHeight: CGFloat { 18 }

    private var span: Double { max(range.upperBound - range.lowerBound, 0.000_001) }

    var body: some View {
        GeometryReader { geo in
            // Rocaja se premikata po "uporabni" sirini (brez polovice rocaja na vsaki strani),
            // histogram in napisi so poravnani z isto sirino.
            let usable = max(geo.size.width - thumbSize, 1)
            let xLower = polozaj(lower, usable: usable)
            let xUpper = polozaj(upper, usable: usable)

            VStack(spacing: 0) {
                histogram
                    .frame(width: usable, height: histogramHeight)
                    .padding(.horizontal, thumbSize / 2)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: usable, height: 2)
                        .padding(.horizontal, thumbSize / 2)

                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: max(xUpper - xLower, 0), height: 2)
                        .offset(x: thumbSize / 2 + xLower)

                    rocaj(x: xLower, usable: usable, jeSpodnji: true)
                    rocaj(x: xUpper, usable: usable, jeSpodnji: false)
                }
                .frame(width: geo.size.width, height: trackHeight)
                .coordinateSpace(name: "outlyRange")

                napisi(xLower: xLower, xUpper: xUpper, usable: usable)
                    .frame(width: geo.size.width, height: labelHeight)
            }
        }
        .frame(height: histogramHeight + trackHeight + labelHeight)
    }

    // MARK: - Deli

    private var histogram: some View {
        let maxCount = counts.max() ?? 0
        let n = max(counts.count, 1)
        let binWidth = span / Double(n)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(counts.enumerated()), id: \.offset) { i, c in
                let od = range.lowerBound + Double(i) * binWidth
                let doV = od + binWidth
                let vRazponu = doV >= lower && od <= upper
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(vRazponu ? Color.outlyBlue : Color.white.opacity(0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: maxCount > 0 && c > 0 ? max(4, histogramHeight * CGFloat(c) / CGFloat(maxCount)) : 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func rocaj(x: CGFloat, usable: CGFloat, jeSpodnji: Bool) -> some View {
        Circle()
            .fill(Color.outlyBlue)
            .frame(width: thumbSize, height: thumbSize)
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .offset(x: x + thumbSize / 2 - 22)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("outlyRange"))
                    .onChanged { g in
                        let nova = vrednost(zaX: g.location.x - thumbSize / 2, usable: usable)
                        if jeSpodnji { lower = min(nova, upper) } else { upper = max(nova, lower) }
                    }
            )
            .accessibilityLabel(Text(jeSpodnji ? "From" : "To"))
            .accessibilityValue(Text(verbatim: label(jeSpodnji ? lower : upper)))
    }

    /// Napisa pod rocajema; ce sta preblizu, en skupen napis "od – do" na sredini.
    private func napisi(xLower: CGFloat, xUpper: CGFloat, usable: CGFloat) -> some View {
        let sredinaL = thumbSize / 2 + xLower
        let sredinaU = thumbSize / 2 + xUpper
        let sirina = usable + thumbSize
        return ZStack(alignment: .topLeading) {
            if sredinaU - sredinaL < 64 {
                Text(verbatim: "\(label(lower)) – \(label(upper))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize()
                    .position(x: min(max((sredinaL + sredinaU) / 2, 40), sirina - 40), y: labelHeight / 2)
            } else {
                Text(verbatim: label(lower))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize()
                    .position(x: min(max(sredinaL, 18), sirina - 18), y: labelHeight / 2)
                Text(verbatim: label(upper))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize()
                    .position(x: min(max(sredinaU, 18), sirina - 18), y: labelHeight / 2)
            }
        }
    }

    // MARK: - Pretvorbe

    private func polozaj(_ v: Double, usable: CGFloat) -> CGFloat {
        let t = (min(max(v, range.lowerBound), range.upperBound) - range.lowerBound) / span
        return CGFloat(t) * usable
    }

    private func vrednost(zaX x: CGFloat, usable: CGFloat) -> Double {
        let t = Double(min(max(x, 0), usable) / usable)
        let surova = range.lowerBound + t * span
        let zaokrozena = (surova / step).rounded() * step
        return min(max(zaokrozena, range.lowerBound), range.upperBound)
    }
}

/// Stetje vrednosti po enakih intervalih za histogram.
enum Histogram {
    /// `values` razdeli v `bins` enakih intervalov cez `range`; vrednosti zunaj razpona se
    /// ne stejejo (zgornja meja spada v zadnji interval).
    static func prestej(_ values: [Double], range: ClosedRange<Double>, bins: Int) -> [Int] {
        guard bins > 0, range.upperBound > range.lowerBound else { return [] }
        var counts = Array(repeating: 0, count: bins)
        let span = range.upperBound - range.lowerBound
        for v in values where range.contains(v) {
            let i = min(Int((v - range.lowerBound) / span * Double(bins)), bins - 1)
            counts[i] += 1
        }
        return counts
    }
}
