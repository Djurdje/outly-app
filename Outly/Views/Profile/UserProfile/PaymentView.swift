import SwiftUI

struct PaymentView: View {
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                
                Text("Payment")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 6)
                
                
                BalanceCardView(balanceText: "Comming Soon") {
                    // TODO: Add balance action
                }
                
                Text("Payment methods")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.top, 6)
                
                NavigationLink(destination: MyClubsView()) {
                    OutlyMenuRowButton(icon: "rectangle.and.pencil.and.ellipsis", title: "Connect Stripe account")
                }
                    Divider()
                        .background(Color.gray.opacity(0.6))
                        .padding(.vertical, 6)
                    
                NavigationLink(destination: MyClubsView()) {
                    OutlyMenuRowButton(icon: "checkmark.circle", title: "Transactions")
                }
                    
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    struct BalanceCardView: View {
        let balanceText: String
        let onPlusTap: () -> Void
        
        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                
                
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.blackColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 165)
                
                VStack(spacing: 14) {
                    Text("Balance")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text(balanceText)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(50)
                .frame(maxWidth: .infinity)
                
                Button(action: onPlusTap) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(16)
            }
        }
    }

