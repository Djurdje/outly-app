import SwiftUI

struct AboutView: View {
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 12) {

                Text("About")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 6)

                NavigationLink { Text("About us page") } label: {
                    OutlyMenuRowButton(icon: "questionmark.circle", title: "About us")
                }
                .buttonStyle(.plain)

                NavigationLink { Text("Rate this app") } label: {
                    OutlyMenuRowButton(icon: "hand.thumbsup", title: "Rate this app")
                }
                .buttonStyle(.plain)

                NavigationLink { Text("Terms & condition") } label: {
                    OutlyMenuRowButton(icon: "doc.text", title: "Terms and condition")
                }
                .buttonStyle(.plain)

                NavigationLink { Text("Privacy") } label: {
                    OutlyMenuRowButton(icon: "doc.on.doc", title: "Privacy")
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
