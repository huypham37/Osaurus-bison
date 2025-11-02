//
//  CodeBlockView.swift
//  osaurus
//

import AppKit
import SwiftUI

struct CodeBlockView: View {
  let code: String
  let language: String?
  let baseWidth: CGFloat
  @State private var copied = false
  @StateObject private var themeManager = ThemeManager.shared

  var body: some View {
    VStack(spacing: 0) {
      // Header with language and copy button
      HStack {
        if let language, !language.isEmpty {
          Text(language.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isDark ? Color(hex: "9ca3af") : Color(hex: "6b7280"))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        
        Spacer()
        
        Button(action: copy) {
          HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 11))
            if copied {
              Text("Copied!")
                .font(.system(size: 10, weight: .medium))
            }
          }
          .foregroundColor(copied ? (isDark ? Color(hex: "50fa7b") : Color(hex: "10b981")) : (isDark ? Color(hex: "9ca3af") : Color(hex: "6b7280")))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
          .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Copy code")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(isDark ? Color(hex: "282a36") : Color(hex: "f6f8fa"))
      
      Divider()
        .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
      
      // Code content with syntax highlighting
      ScrollView(.horizontal, showsIndicators: true) {
        SyntaxHighlighter.highlight(
          code,
          language: language,
          baseWidth: baseWidth,
          isDark: isDark
        )
        .textSelection(.enabled)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(codeBackground)
    }
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.12), lineWidth: 1)
    )
    .shadow(
      color: isDark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
      radius: 8,
      x: 0,
      y: 2
    )
  }

  private var isDark: Bool {
    NSApp.effectiveAppearance.name == .darkAqua
  }
  
  private var codeBackground: Color {
    themeManager.currentTheme.codeBlockBackground
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code, forType: .string)
    copied = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { copied = false }
  }
}
