import SwiftUI

struct HorizontalClubsScrollAPI: View {
    let clubs: [APIClub]
    let variant: ClubCardVariant

    init(clubs: [APIClub], variant: ClubCardVariant) {
        self.clubs = clubs
        self.variant = variant
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(clubs) { club in
                    ClubCard(
                        club: club,
                        variant: variant
                    )
                }
            }
            .padding(.vertical, 4)

        }
    }
}
