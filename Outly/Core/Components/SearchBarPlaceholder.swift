//
//  SearchBarPlaceholder.swift
//  Outly
//
//  Created by Ivo Peterka on 4. 1. 26.
//

import SwiftUI

struct SearchBarPlaceholder: View {
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            Text("Where to?")
                .foregroundColor(.gray)
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}
