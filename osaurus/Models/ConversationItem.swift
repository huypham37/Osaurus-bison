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
  /// This is a synchronous fallback that just uses the user message
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

  /// Generate an intelligent title using the Foundation model
  /// Returns a short, descriptive title based on the conversation content
  static func generateSmartTitle(from messages: [(role: MessageRole, content: String)]) async -> String {
    guard let firstUserMessage = messages.first(where: { $0.role == .user }) else {
      return "New Chat"
    }

    let userMessage = firstUserMessage.content
    guard !userMessage.isEmpty else {
      return "New Chat"
    }

    // Try to use Foundation model if available
    if FoundationModelService.isDefaultModelAvailable() {
      do {
        let prompt = """
        Generate a short, concise title (2-5 words max) for a conversation that starts with this user message:

        "\(userMessage)"

        The title should capture the topic or intent, not just repeat the message. Be creative and descriptive.
        Examples:
        - "hello" → "Greeting"
        - "what's the weather like?" → "Weather Inquiry"
        - "how do I install Python?" → "Python Installation Help"

        Only output the title, nothing else.
        """

        let title = try await FoundationModelService.generateOneShot(
          prompt: prompt,
          temperature: 0.3,
          maxTokens: 20
        )

        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: """, with: "")
          .replacingOccurrences(of: """, with: "")

        // Validate the title isn't too long or empty
        if !cleanedTitle.isEmpty && cleanedTitle.count <= 50 {
          return cleanedTitle
        }
      } catch {
        // Fall through to fallback
      }
    }

    // Fallback: use the message itself (truncated)
    if userMessage.count > 50 {
      return String(userMessage.prefix(47)) + "..."
    } else {
      return userMessage
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
