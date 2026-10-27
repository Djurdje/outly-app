import SwiftUI
import CoreImage.CIFilterBuiltins

/// Koda QR iz niza, brez zunanjih knjiznic (CoreImage). Vsebina je podpisan
/// zapis vstopnice iz backenda; aplikacija je ne sestavlja sama.
struct QRCodeView: View {
    let content: String
    var size: CGFloat = 220
    /// Ze preveden opis stanja vstopnice (npr. `APITicket.statusLabel`) za bralnik zaslona; nil = stanje ni znano.
    var stanje: String? = nil

    var body: some View {
        Group {
            if let img = Self.slika(content) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle().fill(Color.white.opacity(0.1))
                    .overlay(Text("QR").foregroundColor(.white.opacity(0.5)))
            }
        }
        .frame(width: size, height: size)
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ticket QR code"))
        .accessibilityValue(Text(verbatim: stanje ?? ""))
    }

    private static func slika(_ s: String) -> UIImage? {
        guard let data = s.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
