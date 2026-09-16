import SwiftUI

struct AboutRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(LocalizedStringKey(title))
            Spacer()
        }
        .padding()
        .background(Color("CardBackground"))
        .cornerRadius(12)
    }
}
