//
//  CardSwiftUIView.swift
//  FocusProblem
//
//  Simple SwiftUI card used via UIHostingConfiguration.
//  Focus detected via @Environment(\.isFocused), auto-propagated from the UIKit cell.
//

import SwiftUI

struct CardSwiftUIView: View {
    let title: String

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            Text("Subtitle")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(isFocused ? Color.blue : Color.white.opacity(0.15)))
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
