//
//  ConversationSidebarView.swift
//  osaurus
//
//  Sidebar for managing conversations (like Claude Desktop)
//

import SwiftUI

struct ConversationSidebarView: View {
  @ObservedObject var store: ConversationStore
  @Environment(\.theme) private var theme

  var onSelectConversation: (UUID) -> Void
  var onNewChat: () -> Void
  var onToggleSidebar: () -> Void

  @State private var hoveredId: UUID?
  @State private var editingId: UUID?
  @State private var editingTitle: String = ""
  @State private var showSettings: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      // App branding
      appBranding
        .padding(.top, 16)
        .padding(.bottom, 12)

      // New Thread button
      newThreadButton
        .padding(.horizontal, 12)
        .padding(.bottom, 12)

      // Conversation list
      ScrollView {
        LazyVStack(spacing: 6) {
          ForEach(store.conversations) { conversation in
            conversationRow(conversation)
          }
        }
        .padding(.vertical, 8)
      }

      Spacer()

      // Settings button at bottom
      settingsButton
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
    .frame(width: 260)
    .background(Color(nsColor: .controlBackgroundColor))
  }
  
  // MARK: - App Branding

  private var appBranding: some View {
    HStack(spacing: 8) {
      Image(systemName: "brain")
        .font(.system(size: 20, weight: .medium))
        .foregroundColor(.primary)

      Text("osaurus")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.primary)

      Spacer()
    }
    .padding(.horizontal, 16)
  }

  // MARK: - New Thread Button

  private var newThreadButton: some View {
    Button(action: onNewChat) {
      HStack {
        Text("New Thread")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)

        Spacer()
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 14)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(nsColor: .controlBackgroundColor))
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
  }
  
  // MARK: - Conversation Row
  
  private func conversationRow(_ conversation: ConversationItem) -> some View {
    let isSelected = store.currentConversationId == conversation.id
    let isHovered = hoveredId == conversation.id
    let isEditing = editingId == conversation.id

    return HStack(spacing: 10) {
      // Title (editable)
      if isEditing {
        TextField("", text: $editingTitle, onCommit: {
          store.renameConversation(conversation.id, title: editingTitle)
          editingId = nil
        })
        .textFieldStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
      } else {
        Text(conversation.title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))
          .lineLimit(1)
          .truncationMode(.tail)
      }

      Spacer()

      // Action buttons (show on hover)
      if isHovered && !isEditing {
        HStack(spacing: 6) {
          Button(action: {
            editingTitle = conversation.title
            editingId = conversation.id
          }) {
            Image(systemName: "pencil")
              .font(.system(size: 11, weight: .medium))
              .foregroundColor(.secondary)
          }
          .buttonStyle(.borderless)
          .help("Rename")

          Button(action: {
            store.deleteConversation(conversation.id)
          }) {
            Image(systemName: "trash")
              .font(.system(size: 11, weight: .medium))
              .foregroundColor(.red.opacity(0.8))
          }
          .buttonStyle(.borderless)
          .help("Delete")
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.gray.opacity(0.08) : Color.clear))
    )
    .contentShape(Rectangle())
    .onTapGesture {
      if !isEditing {
        onSelectConversation(conversation.id)
      }
    }
    .onHover { hovering in
      hoveredId = hovering ? conversation.id : nil
    }
    .padding(.horizontal, 12)
  }
  
  // MARK: - Settings Button

  private var settingsButton: some View {
    Button(action: {
      showSettings.toggle()
    }) {
      HStack(spacing: 8) {
        Image(systemName: "gearshape")
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.secondary)

        Text("Settings")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)

        Spacer()
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 14)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.gray.opacity(0.08))
      )
    }
    .buttonStyle(.plain)
    .popover(isPresented: $showSettings, arrowEdge: .trailing) {
      settingsPopover
    }
  }

  private var settingsPopover: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Conversation Settings")
        .font(.system(size: 13, weight: .semibold))
        .padding(.bottom, 4)

      if store.conversations.count > 0 {
        Button(action: {
          if confirm("Delete all conversations?") {
            store.deleteAllConversations()
            showSettings = false
          }
        }) {
          HStack {
            Image(systemName: "trash")
              .foregroundColor(.red)
            Text("Clear All Conversations")
              .foregroundColor(.red)
          }
        }
        .buttonStyle(.borderless)
      }

      Divider()

      Text("\(store.conversations.count) conversation\(store.conversations.count == 1 ? "" : "s")")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
    .padding(16)
    .frame(width: 220)
  }
  
  // MARK: - Helpers

  private func confirm(_ message: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    return alert.runModal() == .alertFirstButtonReturn
  }
}
