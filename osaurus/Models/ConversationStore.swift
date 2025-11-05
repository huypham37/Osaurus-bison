//
//  ConversationStore.swift
//  osaurus
//
//  Manages conversation persistence and state
//

import Foundation
import Combine

class ConversationStore: ObservableObject {
  @Published var conversations: [ConversationItem] = []
  @Published var currentConversationId: UUID?
  
  private let saveKey = "SavedConversations"
  private let currentConversationKey = "CurrentConversationId"
  
  static let shared = ConversationStore()
  
  private init() {
    loadConversations()
    loadCurrentConversationId()
  }
  
  // MARK: - Current Conversation
  
  var currentConversation: ConversationItem? {
    get {
      guard let id = currentConversationId else { return nil }
      return conversations.first(where: { $0.id == id })
    }
  }
  
  func setCurrentConversation(_ id: UUID?) {
    currentConversationId = id
    saveCurrentConversationId()
  }
  
  // MARK: - CRUD Operations
  
  /// Create a new conversation
  func createConversation(title: String = "New Chat", messages: [(role: MessageRole, content: String)] = []) -> UUID {
    var conversation = ConversationItem(title: title, messages: messages)
    if !messages.isEmpty {
      conversation.generateTitle()
    }
    conversations.insert(conversation, at: 0) // Add to top
    currentConversationId = conversation.id
    saveConversations()
    saveCurrentConversationId()
    return conversation.id
  }
  
  /// Update an existing conversation
  func updateConversation(_ id: UUID, messages: [(role: MessageRole, content: String)]) {
    guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
    conversations[index].messages = messages
    conversations[index].updatedAt = Date()
    conversations[index].generateTitle()
    saveConversations()
  }
  
  /// Delete a conversation
  func deleteConversation(_ id: UUID) {
    conversations.removeAll(where: { $0.id == id })
    if currentConversationId == id {
      currentConversationId = conversations.first?.id
      saveCurrentConversationId()
    }
    saveConversations()
  }
  
  /// Delete all conversations
  func deleteAllConversations() {
    conversations.removeAll()
    currentConversationId = nil
    saveConversations()
    saveCurrentConversationId()
  }
  
  /// Rename a conversation
  func renameConversation(_ id: UUID, title: String) {
    guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
    conversations[index].title = title
    saveConversations()
  }
  
  // MARK: - Persistence
  
  private func saveConversations() {
    do {
      let data = try JSONEncoder().encode(conversations)
      UserDefaults.standard.set(data, forKey: saveKey)
    } catch {
      print("Failed to save conversations: \(error)")
    }
  }
  
  private func loadConversations() {
    guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
    do {
      conversations = try JSONDecoder().decode([ConversationItem].self, from: data)
    } catch {
      print("Failed to load conversations: \(error)")
      conversations = []
    }
  }
  
  private func saveCurrentConversationId() {
    if let id = currentConversationId {
      UserDefaults.standard.set(id.uuidString, forKey: currentConversationKey)
    } else {
      UserDefaults.standard.removeObject(forKey: currentConversationKey)
    }
  }
  
  private func loadCurrentConversationId() {
    guard let uuidString = UserDefaults.standard.string(forKey: currentConversationKey),
          let uuid = UUID(uuidString: uuidString) else { return }
    currentConversationId = uuid
  }
}
