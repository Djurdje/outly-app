import SwiftUI

struct MyClubsView: View {
    var body: some View {
        Screen {
            VStack(spacing: 22) {

                Text("My clubs")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                Spacer()

                Text("You are currently not working\nfor any club")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)

                Text("check the notification\nsection for invitations")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct Screen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .background(Color.black.ignoresSafeArea())
    }
}
