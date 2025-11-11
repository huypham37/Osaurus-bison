//
//  ConversationTitleService.swift
//  osaurus
//
//  Service for automatically generating conversation titles using Foundation model
//

import Foundation

@MainActor
final class ConversationTitleService {
  static let shared = ConversationTitleService()

  private init() {}

  /// Generate a concise title for a conversation based on the first user message
  /// Uses the Foundation model to create a short, descriptive title
  func generateTitle(for firstUserMessage: String) async -> String? {
    guard FoundationModelService.isDefaultModelAvailable() else {
      return nil
    }

    // Create a prompt asking the model to generate a short title
    let prompt = """
    Generate a very short, concise title (3-5 words maximum) for a conversation that starts with this question:

    "\(firstUserMessage)"

    Only respond with the title itself, nothing else. No quotes, no punctuation at the end.
    """

    do {
      let title = try await FoundationModelService.generateOneShot(
        prompt: prompt,
        temperature: 0.3, // Low temperature for more consistent titles
        maxTokens: 20 // Keep it short
      )

      // Clean up the title - remove quotes, trim whitespace, limit length
      let cleanTitle = title
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'""''"))
        .trimmingCharacters(in: .whitespacesAndNewlines)

      // Ensure title isn't too long
      if cleanTitle.count > 50 {
        return String(cleanTitle.prefix(47)) + "..."
      }

      return cleanTitle.isEmpty ? nil : cleanTitle
    } catch {
      return nil
    }
  }

  /// Automatically rename a conversation after the first assistant response
  /// Should be called when a conversation gets its first complete exchange (user + assistant)
  func autoRenameConversation(
    conversationId: UUID,
    firstUserMessage: String,
    store: ConversationStore
  ) async {
    guard let generatedTitle = await generateTitle(for: firstUserMessage) else {
      return
    }

    // Update the conversation with the generated title
    await MainActor.run {
      store.renameConversation(conversationId, title: generatedTitle)
    }
  }
}
