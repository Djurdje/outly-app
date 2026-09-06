//
//  OutlyAvatarView.swift
//  Outly
//
//  Created by Luka Rakusa Djurdjevic on 11. 1. 26.
//

import SwiftUI

struct OutlyAvatarView: View {
    let avatarUrlString: String?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))

            if let s = avatarUrlString,
               !s.isEmpty,
               let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white.opacity(0.8))
                            .padding(size * 0.15)
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white.opacity(0.8))
                    .padding(size * 0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
