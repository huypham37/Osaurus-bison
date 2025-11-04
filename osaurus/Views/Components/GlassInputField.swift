//
//  GlassInputField.swift
//  osaurus
//
//  Glass-effect input field with backdrop blur and accent glow
//

import SwiftUI

struct GlassInputField: View {
  @Binding var text: String
  @FocusState private var isFocused: Bool
  var placeholder: String = "Message…"
  var onCommit: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var glowAnimation: Bool = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      // Glass background
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(glassBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 0.5)
        )
        .shadow(
          color: isFocused ? Color.accentColor.opacity(0.3) : Color.clear,
          radius: isFocused ? 20 : 0,
          x: 0,
          y: 0
        )

      // Placeholder
      if text.isEmpty {
        Text(placeholder)
          .font(.system(size: 15))
          .foregroundColor(Color.secondary.opacity(0.8))
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .allowsHitTesting(false)
      }

      // Text Editor
      TextEditor(text: $text)
        .font(.system(size: 15))
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .focused($isFocused)
        .onSubmit {
          onCommit()
        }
    }
    .animation(.easeInOut(duration: 0.3), value: isFocused)
    .onAppear {
      withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
        glowAnimation = true
      }
    }
  }

  private var glassBackground: some ShapeStyle {
    LinearGradient(
      colors: [
        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.1),
        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.08),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var borderColor: some ShapeStyle {
    if isFocused {
      return LinearGradient(
        colors: [
          Color.accentColor.opacity(0.8),
          Color.accentColor.opacity(0.4),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    } else {
      return LinearGradient(
        colors: [
          Color.white.opacity(0.2),
          Color.white.opacity(0.1),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }
}

// Custom scroll view with constrained intrinsic size
class ConstrainedHeightScrollView: NSScrollView {
  var minHeight: CGFloat = 36
  var maxHeight: CGFloat = 120
  
  override var intrinsicContentSize: NSSize {
    guard let textView = documentView as? NSTextView else {
      return NSSize(width: NSView.noIntrinsicMetric, height: minHeight)
    }
    
    // Calculate actual content height
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    let contentHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
    let totalHeight = contentHeight + textView.textContainerInset.height * 2
    
    // Clamp between min and max
    let constrainedHeight = max(minHeight, min(maxHeight, totalHeight))
    return NSSize(width: NSView.noIntrinsicMetric, height: constrainedHeight)
  }
}

// SwiftUI wrapper for the custom text view
struct GlassInputFieldBridge: NSViewRepresentable {
  @Binding var text: String
  var isFocused: Bool
  var onCommit: () -> Void
  var onFocusChange: ((Bool) -> Void)?
  var minHeight: CGFloat = 36
  var maxHeight: CGFloat = 120

  func makeNSView(context: Context) -> ConstrainedHeightScrollView {
    let scrollView = ConstrainedHeightScrollView()
    scrollView.minHeight = minHeight
    scrollView.maxHeight = maxHeight
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder

    let textView = NSTextView()
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.font = NSFont.systemFont(ofSize: 15)
    textView.backgroundColor = .clear
    textView.textColor = NSColor.labelColor
    textView.string = text
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.drawsBackground = false
    
    // Remove extra padding from text container
    textView.textContainer?.lineFragmentPadding = 0
    
    // Set paragraph style to minimize spacing
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 0
    paragraphStyle.paragraphSpacing = 0
    paragraphStyle.paragraphSpacingBefore = 0
    textView.defaultParagraphStyle = paragraphStyle
    textView.typingAttributes[.paragraphStyle] = paragraphStyle

    scrollView.documentView = textView

    return scrollView
  }

  func updateNSView(_ nsView: ConstrainedHeightScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView else { return }

    if textView.string != text {
      textView.string = text
      // Invalidate intrinsic size when text changes
      nsView.invalidateIntrinsicContentSize()
    }

    if isFocused && nsView.window?.firstResponder != textView {
      DispatchQueue.main.async {
        nsView.window?.makeFirstResponder(textView)
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: GlassInputFieldBridge

    init(_ parent: GlassInputFieldBridge) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        if !NSEvent.modifierFlags.contains(.shift) {
          parent.onCommit()
          return true
        }
      }
      return false
    }

    func textDidBeginEditing(_ notification: Notification) {
      parent.onFocusChange?(true)
    }

    func textDidEndEditing(_ notification: Notification) {
      parent.onFocusChange?(false)
    }
  }
}
