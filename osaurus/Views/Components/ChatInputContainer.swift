//
//  ChatInputContainer.swift
//  osaurus
//
//  Created for attachment functionality
//

import SwiftUI

/// Container for the chat input field with glass morphism styling
struct ChatInputContainer: View {
  @Binding var text: String
  @Binding var measuredHeight: CGFloat
  @Binding var isFocused: Bool
  var onCommit: () -> Void
  var onFocusChange: ((Bool) -> Void)?
  var minHeight: CGFloat = 36
  var maxHeight: CGFloat = 120
  
  @Environment(\.theme) private var theme
  
  var body: some View {
    ZStack(alignment: .topLeading) {
      GlassInputFieldBridge(
        text: $text,
        measuredHeight: $measuredHeight,
        isFocused: isFocused,
        onCommit: onCommit,
        onFocusChange: onFocusChange,
        minHeight: minHeight,
        maxHeight: maxHeight
      )
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(
            theme.glassOpacityTertiary == 0.05
              ? theme.secondaryBackground.opacity(0.4) : theme.primaryBackground.opacity(0.4)
          )
          .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(.ultraThinMaterial)
          )
      )
      .overlay( RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(
            isFocused
              ? LinearGradient(
                colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
              : LinearGradient(
                colors: [theme.glassEdgeLight, theme.glassEdgeLight.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
            lineWidth: isFocused ? 1.5 : 0.5
          )
      )
      .shadow(
        color: isFocused ? Color.accentColor.opacity(0.2) : Color.clear,
        radius: isFocused ? 20 : 0
      )
      .animation(.easeInOut(duration: theme.animationDurationMedium), value: isFocused)

      // Placeholder text
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text("Type your message…")
          .font(.system(size: 15))
          .foregroundColor(theme.tertiaryText)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .allowsHitTesting(false)
      }
    }
  }
}

#if DEBUG
struct ChatInputContainer_Previews: PreviewProvider {
  static var previews: some View {
    ChatInputContainerPreview()
      .themedBackground()
      .padding()
      .frame(width: 600)
  }
  
  struct ChatInputContainerPreview: View {
    @State private var text = ""
    @State private var isFocused = false
    @State private var measuredHeight: CGFloat = 36
    
    var body: some View {
      ChatInputContainer(
        text: $text,
        measuredHeight: $measuredHeight,
        isFocused: $isFocused,
        onCommit: { print("Commit") },
        onFocusChange: { focused in isFocused = focused }
      )
      .frame(height: measuredHeight)
    }
  }
}
#endif
