//
//  ModelPickerView.swift
//  osaurus
//
//  Created by Claude Code on 11/5/25.
//

import SwiftUI

struct ModelPickerView: View {
  @ObservedObject var session: ChatSession
  @Environment(\.theme) private var theme
  @State private var isHovered: Bool = false

  var body: some View {
    HStack(spacing: 10) {
      // Model icon - using a gradient circle with SF Symbol (Apple liquid glass style)
      ZStack {
        Circle()
          .fill(
            LinearGradient(
              colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 24, height: 24)
          .overlay(
            Circle()
              .fill(
                RadialGradient(
                  colors: [Color.white.opacity(0.3), Color.clear],
                  center: .topLeading,
                  startRadius: 0,
                  endRadius: 16
                )
              )
          )

        Image(systemName: "apple.intelligence")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.white)
      }
//      .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 1.5)

      // Model name and picker - animate with scale and opacity
      if isHovered || session.modelOptions.count == 1 {
        if session.modelOptions.count > 1 {
          Menu {
            ForEach(session.modelOptions, id: \.self) { name in
              Button(action: {
                session.selectedModel = name
              }) {
                HStack {
                  Text(displayModelName(name))
                    .font(.system(size: 13))
                  Spacer()
                  if session.selectedModel == name {
                    Image(systemName: "checkmark")
                      .font(.system(size: 12, weight: .semibold))
                      .foregroundColor(.accentColor)
                  }
                }
              }
            }
          } label: {
            Text(session.selectedModel.map(displayModelName) ?? "Select Model")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(theme.primaryText)
              .lineLimit(1)
          }
          .menuStyle(.borderlessButton)
          .buttonStyle(.plain)
          .help("Select model")
          .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
        } else if let selected = session.selectedModel {
          Text(displayModelName(selected))
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(theme.primaryText)
            .lineLimit(1)
            .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background {
        RoundedRectangle(
          cornerRadius: isHovered || session.modelOptions.count == 1 ? 12 : 16,
          style: .continuous
        )
        .fill(.ultraThinMaterial)
        .frame(height: 32)
        .animation(.spring(response: 1.0, dampingFraction: 0.7), value: isHovered)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    .contentShape(Rectangle())
    .onHover { hovering in
        withAnimation(.spring(response: 1.0, dampingFraction: 0.7)) {
        isHovered = hovering
      }
    }
  }

  private func displayModelName(_ raw: String?) -> String {
    guard let raw else { return "Model" }
    if raw.lowercased() == "foundation" { return "Foundation" }
    if let last = raw.split(separator: "/").last { return String(last) }
    return raw
  }
}
