import SwiftUI

/// Vstopnice uporabnika. Prodaja vstopnic v aplikaciji se ne obstaja (pride s Stripe
/// Connect, migracija 002), zato backend nima poti za seznam vstopnic. Do takrat
/// zaslon posteno pokaze prazno stanje — prej je kazal pet izmisljenih vstopnic.
struct TicketsView: View {
    var body: some View {
        Screen {
            VStack(spacing: 22) {
                Text("Tickets")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                Spacer()

                Image(systemName: "ticket")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.outlyBlue)

                Text("No tickets yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Tickets you buy through Outly\nwill show up here.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Spacer()
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
        .background(Color.outlyBlue)
        .cornerRadius(12)
    }
}
