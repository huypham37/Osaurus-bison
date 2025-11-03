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
  
  var body: some View {
    VStack(spacing: 0) {
      // Header with New Chat button
      header
      
      Divider()
      
      // Conversation list
      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(store.conversations) { conversation in
            conversationRow(conversation)
          }
        }
        .padding(.vertical, 8)
      }
      
      Divider()
      
      // Footer with settings/info
      footer
    }
    .frame(width: 260)
    .background(Color(nsColor: .controlBackgroundColor))
  }
  
  // MARK: - Header
  
  private var header: some View {
    HStack {
      // Sidebar toggle button
      Button(action: onToggleSidebar) {
        Image(systemName: "sidebar.left")
          .font(.system(size: 14))
      }
      .buttonStyle(.borderless)
      .help("Hide Sidebar")
      
      Text("Conversations")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.secondary)
      
      Spacer()
      
      Button(action: onNewChat) {
        Image(systemName: "square.and.pencil")
          .font(.system(size: 14))
      }
      .buttonStyle(.borderless)
      .help("New Chat")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }
  
  // MARK: - Conversation Row
  
  private func conversationRow(_ conversation: ConversationItem) -> some View {
    let isSelected = store.currentConversationId == conversation.id
    let isHovered = hoveredId == conversation.id
    let isEditing = editingId == conversation.id
    
    return HStack(spacing: 8) {
      // Icon
      Image(systemName: "bubble.left")
        .font(.system(size: 12))
        .foregroundColor(isSelected ? .accentColor : .secondary)
        .frame(width: 16)
      
      // Title (editable)
      if isEditing {
        TextField("", text: $editingTitle, onCommit: {
          store.renameConversation(conversation.id, title: editingTitle)
          editingId = nil
        })
        .textFieldStyle(.plain)
        .font(.system(size: 12))
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text(conversation.title)
            .font(.system(size: 12))
            .foregroundColor(isSelected ? .primary : .secondary)
            .lineLimit(2)
          
          Text(relativeTime(conversation.updatedAt))
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.7))
        }
      }
      
      Spacer()
      
      // Delete button (show on hover)
      if isHovered && !isEditing {
        HStack(spacing: 4) {
          Button(action: {
            editingTitle = conversation.title
            editingId = conversation.id
          }) {
            Image(systemName: "pencil")
              .font(.system(size: 10))
          }
          .buttonStyle(.borderless)
          .help("Rename")
          
          Button(action: {
            store.deleteConversation(conversation.id)
          }) {
            Image(systemName: "trash")
              .font(.system(size: 10))
              .foregroundColor(.red)
          }
          .buttonStyle(.borderless)
          .help("Delete")
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
      
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
    .padding(.horizontal, 8)
  }
  
  // MARK: - Footer
  
  private var footer: some View {
    HStack {
      Text("\(store.conversations.count) chat\(store.conversations.count == 1 ? "" : "s")")
        .font(.system(size: 10))
        .foregroundColor(.secondary)
      
      Spacer()
      
      if store.conversations.count > 0 {
        Button(action: {
          if confirm("Delete all conversations?") {
            store.deleteAllConversations()
          }
        }) {
          Text("Clear All")
            .font(.system(size: 10))
            .foregroundColor(.red)
        }
        .buttonStyle(.borderless)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
  
  // MARK: - Helpers
  
  private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
  
  private func confirm(_ message: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    return alert.runModal() == .alertFirstButtonReturn
  }
}
