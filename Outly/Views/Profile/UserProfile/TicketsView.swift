import SwiftUI

struct TicketsView: View {
    @State private var search = ""

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 14) {

                HStack {
                    Text("Tickets")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Spacer()

                    SearchBar(text: $search)
                        .frame(maxWidth: 140)
                }
                .padding(.top, 6)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        TicketRow(imageName: "cirkus_1", title: "Henny", subtitle: "7. July - Pure")
                        TicketRow(imageName: "cirkus_2", title: "Aca Lukas", subtitle: "7. August - Pure")
                        TicketRow(imageName: "cirkus_3", title: "Crni Cerak", subtitle: "7. Septembr - Pure")
                        TicketRow(imageName: "k4", title: "Inas", subtitle: "7. November - Pure")
                        TicketRow(imageName: "logo", title: "Milica Pavlovic", subtitle: "7. December - Pure")
                    }
                    .padding(.top, 10)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white)

            TextField(placeholder, text: $text)
                .foregroundColor(.white)
            
        }
        .padding(12)
        .background(Color.blackColor)
        .cornerRadius(12)
    }
}
