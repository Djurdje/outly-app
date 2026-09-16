//
//  HelpCard.swift
//  Outly
//
//  Created by Luka Rakusa Djurdjevic on 8. 1. 26.
//

import SwiftUI

struct HelpCard: View {
    let topLine: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(topLine))
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Text(LocalizedStringKey(title))
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.blackColor.opacity(0.28), Color.gray.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}
