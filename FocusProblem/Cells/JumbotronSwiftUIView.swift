import SwiftUI
import Foundation

struct JumbotronSwiftUIView: View {
    let title: String
    let description: String

    @Environment(\.isFocused) private var envIsFocused
    
    var body: some View {
        let _ = {
            print("🐛 [FocusProblem] JumbotronSwiftUIView body evaluated — title: \(title), @Environment isFocused: \(envIsFocused)")
        }()
        VStack(alignment: .leading, spacing: 20) {
            // Image placeholder
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.4))
                .frame(height: 300)
                .overlay(
                    Image(systemName: "headphones")
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.6))
                )
            
            // Title
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            
            // Buttons row
            HStack(spacing: 20) {
                FocusableButton(label: "Play", icon: "play.fill", color: .blue)
                    .id("Play")
                FocusableButton(label: "Favorite", icon: "heart.fill", color: .pink)
                    .id("Favorite")
                FocusableButton(label: "Info", icon: "info.circle.fill", color: .gray)
                    .id("Info")
            }
            .focusSection()

            // Description
            Text(description)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Focusable Button

private struct FocusableButton: View {
    let label: String
    let icon: String
    let color: Color

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            print("[\(label)] tapped")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.headline)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(minWidth: 160)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? color : color.opacity(0.3))
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .foregroundStyle(.white)
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .onChange(of: isFocused) { _, newValue in
            print("🐛 [FocusProblem] FocusableButton '\(label)' isFocused → \(newValue)")
        }
    }
}

#Preview {
    JumbotronSwiftUIView(
        title: "My Podcast",
        description: "Podcast description with multiple lines of text to test rendering."
    )
    .padding()
    .background(Color.black)
}
