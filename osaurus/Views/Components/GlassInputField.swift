//
//  GlassInputField.swift
//  osaurus
//
//  AppKit-based auto-sizing text input with NSTextView
//  Bridges AppKit NSTextView to SwiftUI with height measurement
//

import SwiftUI

// MARK: - Custom scroll view with constrained intrinsic size
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
  @Binding var measuredHeight: CGFloat
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
    textView.textContainerInset = NSSize(width: 12, height: 8)
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
      // Measure and update height
      context.coordinator.remeasure(textView: textView, scrollView: nsView)
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
      guard let textView = notification.object as? NSTextView,
            let scrollView = textView.enclosingScrollView as? ConstrainedHeightScrollView else { return }
      parent.text = textView.string
      remeasure(textView: textView, scrollView: scrollView)
    }
    
    func remeasure(textView: NSTextView, scrollView: ConstrainedHeightScrollView) {
      guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer else { return }
      
      // Ensure layout is up to date
      layoutManager.ensureLayout(for: textContainer)
      
      // Calculate content height
      let usedRect = layoutManager.usedRect(for: textContainer)
      let contentHeight = usedRect.height + textView.textContainerInset.height * 2
      
      // Clamp between min and max
      let clampedHeight = max(parent.minHeight, min(parent.maxHeight, contentHeight))
      
      // Update SwiftUI binding on main thread
      DispatchQueue.main.async {
        self.parent.measuredHeight = clampedHeight
      }
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
