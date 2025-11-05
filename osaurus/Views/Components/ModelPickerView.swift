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

        Image(systemName: "sparkles")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.white)
      }
      .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 1.5)

      // Model name and picker
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
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("Select model")
      } else if let selected = session.selectedModel {
        HStack(spacing: 6) {
          Text(displayModelName(selected))
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(theme.primaryText)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(
      ZStack {
        // Liquid glass effect base
        RoundedRectangle(cornerRadius: 12)
          .fill(.ultraThinMaterial)

        // Subtle gradient overlay for depth
        RoundedRectangle(cornerRadius: 12)
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.08),
                Color.white.opacity(0.02)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )

//        // Border with gradient
//        RoundedRectangle(cornerRadius: 12)
//          .strokeBorder(
//            LinearGradient(
//              colors: [
//                Color.white.opacity(0.06),
//                Color.white.opacity(0.05)
//              ],
//              startPoint: .topLeading,
//              endPoint: .bottomTrailing
//            ),
//            lineWidth: 0.01
//          )
      }
    )
    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
  }

  private func displayModelName(_ raw: String?) -> String {
    guard let raw else { return "Model" }
    if raw.lowercased() == "foundation" { return "Foundation" }
    if let last = raw.split(separator: "/").last { return String(last) }
    return raw
  }
}
