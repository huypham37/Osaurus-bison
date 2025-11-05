//
//  ConversationItem.swift
//  osaurus
//
//  Conversation management for sidebar
//

import Foundation

/// Represents a saved conversation
struct ConversationItem: Identifiable, Codable {
  let id: UUID
  var title: String
  var messages: [(role: MessageRole, content: String)]
  var createdAt: Date
  var updatedAt: Date
  
  init(
    id: UUID = UUID(),
    title: String = "New Chat",
    messages: [(role: MessageRole, content: String)] = [],
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.messages = messages
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
  
  /// Auto-generate title from first user message (max 50 chars)
  mutating func generateTitle() {
    if let firstUserMessage = messages.first(where: { $0.role == .user }) {
      let content = firstUserMessage.content
      if content.count > 50 {
        self.title = String(content.prefix(47)) + "..."
      } else {
        self.title = content.isEmpty ? "New Chat" : content
      }
    } else {
      self.title = "New Chat"
    }
  }
  
  // MARK: - Codable Conformance
  
  enum CodingKeys: String, CodingKey {
    case id, title, messages, createdAt, updatedAt
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    
    // Decode messages
    let messagesData = try container.decode([MessageData].self, forKey: .messages)
    messages = messagesData.map { ($0.role, $0.content) }
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(updatedAt, forKey: .updatedAt)
    
    // Encode messages
    let messagesData = messages.map { MessageData(role: $0.role, content: $0.content) }
    try container.encode(messagesData, forKey: .messages)
  }
  
  private struct MessageData: Codable {
    let role: MessageRole
    let content: String
  }
}
