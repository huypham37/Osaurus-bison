//
//  ChatView.swift
//  osaurus
//
//  Created by Terence on 10/26/25.
//

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

// MARK: - Display Mode
enum ChatDisplayMode {
  case floatingPanel  // Quick access panel (Cmd+Shift+;)
  case mainWindow     // Persistent main window (menu bar button)
}

@MainActor
final class ChatSession: ObservableObject {
  @Published var turns: [(role: MessageRole, content: String)] = []
  @Published var isStreaming: Bool = false
  @Published var input: String = ""
  @Published var selectedModel: String? = nil
  @Published var modelOptions: [String] = []
  @Published var scrollTick: Int = 0
  @Published var attachments: [Attachment] = []
  private var currentTask: Task<Void, Never>?
  private var currentAttachments: [Attachment] = []
    

  init(initialConversation: [(role: MessageRole, content: String)] = []) {
    // Set initial conversation if provided
    self.turns = initialConversation
    
    // Build options list (foundation first if available)
    var opts: [String] = []
    if FoundationModelService.isDefaultModelAvailable() {
      opts.append("foundation")
    }
    let mlx = MLXService.getAvailableModels()
    opts.append(contentsOf: mlx)

    // Add OpenCode models if available (fetch dynamically)
    let opencode = OpenCodeProxyService()
    if opencode.isAvailable() {
      Task {
        do {
          let models = try await opencode.getAvailableModels()
          await MainActor.run {
            // Add provider:model format to options
            for (provider, model, _) in models {
              let modelName = "\(provider):\(model)"
              if !self.modelOptions.contains(modelName) {
                self.modelOptions.append(modelName)
              }
            }
          }
        } catch {
        }
      }
    }

    modelOptions = opts

    // Set default selectedModel to foundation if available, otherwise first available
    if FoundationModelService.isDefaultModelAvailable() {
      selectedModel = "foundation"
    } else {
      selectedModel = opts.first
    }
  }

  func sendCurrent() {
    guard !isStreaming else { return }
    let text = input
    let currentAttachments = attachments
    input = ""
    attachments = []  // Clear attachments after capturing
    send(text, attachments: currentAttachments)
  }

  func stop() {
    currentTask?.cancel()
    currentTask = nil
  }

  func reset() {
    stop()
    turns.removeAll()
    input = ""
  }

  func send(_ text: String, attachments: [Attachment] = []) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    
    
    // Allow sending if there's text OR attachments
    guard !trimmed.isEmpty || !attachments.isEmpty else {
      return
    }
    
    // For now, store attachment info in the content string
    // TODO: Refactor to store multimodal content properly
    var content = trimmed
    if !attachments.isEmpty {
      let attachmentInfo = attachments.map { "📎 \($0.fileName)" }.joined(separator: "\n")
      content = content.isEmpty ? attachmentInfo : "\(content)\n\(attachmentInfo)"
    }
    
    turns.append((.user, content))
    
    // Store attachments temporarily for the streaming call
    currentAttachments = attachments
    streamResponse()
    // Note: Don't clear currentAttachments here - it will be cleared after Task starts
  }
  
  // Stream response for existing conversation (don't add user message again)
  func streamResponse() {
    guard !turns.isEmpty else { return }
    
    var messages = turns.map { Message(role: $0.role, content: $0.content) }
    let chatCfg = ChatConfigurationStore.load()
    let sys = chatCfg.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !sys.isEmpty {
      messages.insert(Message(role: .system, content: sys), at: 0)
    }
    let prompt = PromptBuilder.buildPrompt(from: messages)

    currentTask = Task { @MainActor in
      // Capture attachments at the start of Task, then clear
      let capturedAttachments = currentAttachments
      currentAttachments = []
      
      isStreaming = true
      ServerController.signalGenerationStart()
      defer {
        isStreaming = false
        ServerController.signalGenerationEnd()
      }

      let services: [ModelService] = [
        FoundationModelService(),
        MLXService.shared,
        OpenCodeProxyService()
      ]
      let installed = MLXService.getAvailableModels()
      switch ModelServiceRouter.resolve(
        requestedModel: selectedModel,
        installedModels: installed,
        services: services
      ) {
      case .none:
        turns.append((.assistant, "No model available. Open Model Manager to download one."))
        return
      case .service(let svc, _):
        turns.append((.assistant, ""))
        let idx = turns.count - 1
        let params = GenerationParameters(temperature: 0.7, maxTokens: 1024)
        do {
          // Check if we're using OpenCode with attachments (multimodal)
          let stream: AsyncStream<String>
          if let openCodeService = svc as? OpenCodeProxyService,
             !capturedAttachments.isEmpty {
            stream = try await openCodeService.streamDeltasWithAttachments(
              prompt: prompt,
              parameters: params,
              attachments: capturedAttachments
            )
          } else {
            // Standard text-only streaming
            stream = try await svc.streamDeltas(prompt: prompt, parameters: params)
          }
          
          var deltaCount = 0
          var totalChars = 0
          
          for await delta in stream {
            if Task.isCancelled {
              break
            }
            if !delta.isEmpty {
              deltaCount += 1
              totalChars += delta.count
              turns[idx].content += delta
              // Signal UI to autoscroll while streaming
              scrollTick &+= 1
              
              // Log every 10th delta or first/last
              if deltaCount == 1 {
              } else if deltaCount % 10 == 0 {
              }
            }
          }
          
        } catch {
          turns[idx].content = "Error: \(error.localizedDescription)"
        }
      }
    }
  }
}

struct ChatView: View {
  @EnvironmentObject var server: ServerController
  @StateObject private var themeManager = ThemeManager.shared
  @StateObject private var conversationStore = ConversationStore.shared
  @State private var isExpanded = false

  private var theme: ThemeProtocol {
    themeManager.currentTheme
  }
  
  let displayMode: ChatDisplayMode
  
  @StateObject private var session: ChatSession
  // Using AppKit-backed text view to handle Enter vs Shift+Enter
  @State private var focusTrigger: Int = 0
  @State private var isPinnedToBottom: Bool = true
  @State private var inputIsFocused: Bool = false
  @State private var inputHeight: CGFloat = 36
  @State private var hostWindow: NSWindow?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var currentConversationId: UUID?
  @State private var isExpandingToMainWindow: Bool = false  // Prevent double-expand
  @State private var isSendingMessage: Bool = false  // Prevent double-send from Enter+Button
  
  init(
    displayMode: ChatDisplayMode,
    initialConversationId: UUID? = nil
  ) {
    self.displayMode = displayMode
    
    // Load conversation from store if ID is provided, otherwise start empty
    let initialMessages: [(role: MessageRole, content: String)]
    if let conversationId = initialConversationId,
       let conversation = ConversationStore.shared.conversations.first(where: { $0.id == conversationId }) {
      initialMessages = conversation.messages
      self._currentConversationId = State(initialValue: conversationId)
    } else {
      initialMessages = []
      self._currentConversationId = State(initialValue: nil)
    }
    
    self._session = StateObject(wrappedValue: ChatSession(initialConversation: initialMessages))
  }

  var body: some View {
    mainContentView
      .modifier(ChatViewModifiers(
        displayMode: displayMode,
        hostWindow: $hostWindow,
        focusTrigger: $focusTrigger,
        isPinnedToBottom: $isPinnedToBottom,
        session: session,
        inputIsFocused: inputIsFocused,
        onResizeWindow: resizeWindowForContent,
        onSaveConversation: saveCurrentConversation
      ))
      .onAppear {
        // Auto-send if main window loaded with a user message that needs a response
        if displayMode == .mainWindow,
           let lastMessage = session.turns.last,
           lastMessage.role == .user {
          // Stream response without re-adding the user message
          Task { @MainActor in
            // Give UI a moment to render
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            session.streamResponse()
          }
        }
      }
  }

  // MARK: - Main Content View
  
  private var mainContentView: some View {
    Group {
      if displayMode == .mainWindow {
        mainWindowWithSidebar
      } else {
        floatingPanelView
      }
    }
  }
  
  private var mainWindowWithSidebar: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      // Sidebar column
      sidebarView
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
    } detail: {
      // Detail column (chat content)
      chatContent
        .toolbar {
          ToolbarItem(placement: .navigation) {
            ModelPickerView(session: session)
          }

          ToolbarItem(placement: .automatic) {
            Spacer()
          }

          ToolbarItem(placement: .automatic) {
            newChatButton
          }
        }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(
      minWidth: 800,
      idealWidth: 950,
      maxWidth: .infinity,
      minHeight: session.turns.isEmpty ? 180 : 450,
      idealHeight: session.turns.isEmpty ? 220 : 580,
      maxHeight: .infinity
    )
  }
  
  private var floatingPanelView: some View {
    Group {
      if session.turns.isEmpty {
        // Beautiful minimal entry UI
        minimalEntryView
      } else {
        // Full chat content after first message
        chatContent
      }
    }
    .frame(
      minWidth: session.turns.isEmpty ? 500 : 700,
      idealWidth: session.turns.isEmpty ? 600 : 900,
      maxWidth: .infinity,
      minHeight: session.turns.isEmpty ? 140 : 525,
      idealHeight: session.turns.isEmpty ? 140 : 700,
      maxHeight: .infinity
    )
  }
  
  private var sidebarView: some View {
    ConversationSidebarView(
      store: conversationStore,
      onSelectConversation: { id in
        loadConversation(id)
      },
      onNewChat: {
        createNewChat()
      },
      onToggleSidebar: {
        withAnimation {
          columnVisibility = columnVisibility == .all ? .detailOnly : .all
        }
      }
    )
  }
  
  // MARK: - Minimal Entry View (Floating Panel Empty State)
  
  private var minimalEntryView: some View {
    ZStack {
      // Glass background
      GlassSurface(cornerRadius: 40)
      
      HStack(spacing: 12) {
        // Plus icon
        Image(systemName: "plus")
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.white.opacity(0.7))
        
        // Input field
        TextField("Your question here", text: $session.input, onCommit: {
          handleMinimalEntrySend()
        })
        .textFieldStyle(.plain)
        .font(.system(size: 16, weight: .regular))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        
        // Send button (circular white button with arrow)
        Button(action: {
          handleMinimalEntrySend()
        }) {
          ZStack {
            Circle()
              .fill(Color.white)
              .frame(width: 44, height: 44)
              .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            
            Image(systemName: "arrow.right")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.black)
          }
        }
        .buttonStyle(.plain)
        .help("Send message")
        .disabled(session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 18)
    }
    .frame(height: 60) // Adjust this value to control initial input field height
    .padding(.horizontal, 40)
    
  }
  
  private func handleMinimalEntrySend() {
    guard !session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard !isSendingMessage else {
      return
    }
    guard !isExpandingToMainWindow else { 
      return 
    }
    
    isSendingMessage = true
    
    // For floating panel: save message and expand immediately without streaming
    if displayMode == .floatingPanel {
      // Save the user input before clearing it
      let userMessage = session.input.trimmingCharacters(in: .whitespacesAndNewlines)
      session.input = ""
      
      // Add user message to session (don't call sendCurrent - we'll send in main window)
      session.turns.append((.user, userMessage))
      
      Task { @MainActor in
        guard !isExpandingToMainWindow else {
          return
        }
        isExpandingToMainWindow = true
        
        
        // Save conversation with just the user message (no assistant response yet)
        let conversationId = conversationStore.createConversation(messages: session.turns)
        
        // Trigger immediate morph animation to main window
        // Main window will load this conversation and automatically start streaming
        AppDelegate.shared?.expandPanelToWindow(conversationId: conversationId)
        
        // Reset flags after expansion
        try? await Task.sleep(nanoseconds: 500_000_000)
        isSendingMessage = false
        isExpandingToMainWindow = false
      }
    } else {
      // In main window, just send normally
      session.sendCurrent()
      isSendingMessage = false
    }
  }
  
  // MARK: - Chat Content
  
  private var chatContent: some View {
    GeometryReader { proxy in
      let containerWidth = proxy.size.width
      ZStack(alignment: .bottomTrailing) {
        // Conditional background based on display mode
        if displayMode == .floatingPanel {
          // Glass effect for floating panel
          GlassSurface(cornerRadius: 28)
            .allowsHitTesting(false)
        } else {
          // Solid background for main window (desktop app style)
          Color.clear
            .allowsHitTesting(false)
        }

        VStack(spacing: 10) {
          // Only show header for floating panel, main window uses toolbar
          if displayMode == .floatingPanel {
            header(containerWidth)
              .padding(.horizontal, 20)
              .frame(maxWidth: .infinity)
          }
          
          if hasAnyModel {
            if !session.turns.isEmpty {
              conversation(containerWidth)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
              // Add flexible spacer when empty to center the input
              Spacer()
            }
            
            // Input bar at the bottom with integrated send button
            inputBarWithButton(containerWidth)
              .padding(.horizontal, 20)
              .frame(maxWidth: .infinity)
          } else {
            emptyState
              .padding(.horizontal, 20)
          }
        }
        .animation(.easeInOut(duration: 0.25), value: session.turns.isEmpty)
        .padding(.vertical, 20)
        .frame(
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: .top
        )
      }
    }
  }
  
  private func resizeWindowForContent(isEmpty: Bool) {
    guard let window = hostWindow else { return }

    let targetHeight: CGFloat = isEmpty ? 250 : 700
    let currentFrame = window.frame

    // Calculate center point of current window
    let currentCenterY = currentFrame.origin.y + (currentFrame.height / 2)
    let currentCenterX = currentFrame.origin.x + (currentFrame.width / 2)

    // Keep window centered at the same point
    let newFrame = NSRect(
      x: currentCenterX - (currentFrame.width / 2),
      y: currentCenterY - (targetHeight / 2),
      width: currentFrame.width,
      height: targetHeight
    )

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.3
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      window.animator().setFrame(newFrame, display: true)
    })
  }

  private func header(_ width: CGFloat) -> some View {
    HStack(spacing: 12) {
      // Model picker in title bar area
      ModelPickerView(session: session)

      Spacer()

      // Show "Expand" button only in floating panel mode when conversation exists
      if displayMode == .floatingPanel && !session.turns.isEmpty {
        Button(action: {
          guard !isExpandingToMainWindow else {
            return
          }
          isExpandingToMainWindow = true

          // Save conversation and pass ID to AppDelegate before expanding
          let conversationId = conversationStore.createConversation(messages: session.turns)
          AppDelegate.shared?.expandPanelToWindow(conversationId: conversationId)
        }) {
          HStack(spacing: 4) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
            Text("Expand")
          }
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          Capsule()
            .fill(Color.accentColor.opacity(0.1))
            .overlay(
              Capsule()
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        )
        .help("Expand to main window")
      }
    }
  }

  // MARK: - New Chat Button
  
  private var newChatButton: some View {
    Button(action: {
      createNewChat()
    }) {
      ZStack {
        Circle()
          .fill(theme.secondaryBackground.opacity(0.5))
          .frame(width: 28, height: 28)
        
        Image(systemName: "plus")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(theme.primaryText)
      }
    }
    .buttonStyle(.borderless)
    .help("New Chat")
  }

  private func conversation(_ width: CGFloat) -> some View {
    ScrollViewReader { proxy in
      @State var hasInitialScroll = false
      ZStack(alignment: .bottomTrailing) {
        ScrollView {
          LazyVStack(spacing: 24) {
            ForEach(Array(session.turns.enumerated()), id: \.offset) { item in
              let turn = item.element
              HStack(alignment: .top, spacing: 12) {
                // Avatar
                if turn.role == .user {
                  Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .overlay(
                      Text("Y")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    )

                }
                VStack(alignment: .leading, spacing: 6) {
                  ZStack(alignment: .topTrailing) {
                    Group {
                      if turn.content.isEmpty && turn.role == .assistant && session.isStreaming {
                        ThinkingAnimationView()
                        .padding(12)
                        .background(
                          GlassMessageBubble(role: .assistant, isStreaming: true)
                        )
                      } else {
                        MarkdownMessageView(text: turn.content, baseWidth: width)
                          .font(Typography.body(width))
                          .foregroundColor(theme.primaryText)
                          .padding(12)
                          .background(
                            GlassMessageBubble(role: turn.role, isStreaming: false)
                          )
                          .transition(.opacity.combined(with: .scale(scale: 0.95)))
                      }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if turn.role == .assistant && !turn.content.isEmpty {
                      HoverButton(action: { copyToPasteboard(turn.content) }) {
                        Image(systemName: "doc.on.doc")
                          .font(.system(size: 12))
                          .foregroundColor(theme.tertiaryText)
                      }
                      .padding(8)
                      .offset(x: 8, y: -8)
                    }
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 0)
              }
              .frame(maxWidth: 1000)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.horizontal, 20)
            }
            Color.clear
              .frame(height: 1)
              .id("BOTTOM")
              .onAppear { isPinnedToBottom = true }
              .onDisappear { isPinnedToBottom = false }
          }
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.visible, axes: .vertical)
        .onAppear {
          // Make scrollbar subtle after a brief delay to ensure view is loaded
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
              findAndStyleScrollViews(in: window.contentView)
            }
          }
        }

        if !isPinnedToBottom && !session.turns.isEmpty {
          Button(action: {
            withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) }
            isPinnedToBottom = true
          }) {
            HStack(spacing: 4) {
              Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(Color.accentColor)
                .background(
                  Circle()
                    .fill(theme.primaryBackground.opacity(0.9))
                    .frame(width: 20, height: 20)
                )
            }
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
          }
          .buttonStyle(.plain)
          .transition(.opacity.combined(with: .scale))
          .padding(16)
        }
      }
      .onChange(of: session.turns.count) { _, _ in
        if hasInitialScroll {
          if isPinnedToBottom { withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) } }
        } else {
          proxy.scrollTo("BOTTOM", anchor: .bottom)
          hasInitialScroll = true
        }
      }
      .onChange(of: session.scrollTick) { _, _ in
        if isPinnedToBottom { withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) } }
      }
      .onReceive(NotificationCenter.default.publisher(for: .chatOverlayActivated)) { _ in
        proxy.scrollTo("BOTTOM", anchor: .bottom)
        hasInitialScroll = true
        isPinnedToBottom = true
      }
    }
  }

  private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func inputBarWithButton(_ width: CGFloat) -> some View {
    VStack(spacing: 0) {
      // Attachments container (shown only when there are attachments)
      if !session.attachments.isEmpty {
        AttachmentsContainer(
          attachments: session.attachments,
          onRemove: { attachment in
            withAnimation(.easeInOut(duration: 0.2)) {
              session.attachments.removeAll { $0.id == attachment.id }
            }
          }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
      }
      
      HStack(alignment: .bottom, spacing: 12) {
        // Input field
        ChatInputContainer(
          text: $session.input,
          measuredHeight: $inputHeight,
          isFocused: $inputIsFocused,
          onCommit: { session.sendCurrent() },
          onFocusChange: { focused in inputIsFocused = focused }
        )
        .frame(height: inputHeight)
        .animation(.easeInOut(duration: 0.2), value: inputHeight)
        
        // Attachment button
        attachmentButton
        
        // Send/Stop button
        primaryActionButton
      }
    }
  }

  private var primaryActionButton: some View {
    Group {
      if session.isStreaming {
        // Stop button - circular
        Button(action: { session.stop() }) {
          Image(systemName: "stop.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.red.opacity(0.9)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 2)
        .help("Stop response")
      } else {
        // Send button - circular with arrow.up
        Button(action: { session.sendCurrent() }) {
          Image(systemName: "arrow.up")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.accentColor.opacity(0.9)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        .shadow(
          color: session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
            ? Color.clear 
            : Color.accentColor.opacity(0.3),
          radius: 8,
          x: 0,
          y: 2
        )
        .animation(.easeInOut(duration: theme.animationDurationQuick), value: session.input)
        .keyboardShortcut(.return, modifiers: [.command])
        .help("Send message")
      }
    }
  }
  
  // Attachment button
  private var attachmentButton: some View {
    Button(action: {
      Task {
        do {
          if let attachment = try await AttachmentService.pickImage() {
            withAnimation(.easeInOut(duration: 0.2)) {
              session.attachments.append(attachment)
            }
          }
        } catch let error as AttachmentError {
          // Show error to user
          // TODO: Show user-facing error alert
        } catch {
        }
      }
    }) {
      Image(systemName: "paperclip")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(theme.secondaryText)
        .frame(width: 36, height: 36)
        .background(Circle().fill(theme.secondaryBackground))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("Attach image (.jpg, .png, .webp, max 5MB)")
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Text("No local models found")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(theme.primaryText)
      Text("Download an MLX model or use the Foundation model if available.")
        .font(.system(size: 12))
        .foregroundColor(theme.secondaryText)
      HStack(spacing: 8) {
        Button("Open Model Manager") {
          AppDelegate.shared?.showModelManagerWindow()
        }
        if FoundationModelService.isDefaultModelAvailable() {
          Button("Use Foundation") {
            session.selectedModel = "foundation"
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private var hasAnyModel: Bool {
    FoundationModelService.isDefaultModelAvailable() || !MLXService.getAvailableModels().isEmpty
  }
  
  // MARK: - Conversation Management
  
  /// Load a conversation from the store
  private func loadConversation(_ id: UUID) {
    guard let conversation = conversationStore.conversations.first(where: { $0.id == id }) else { return }
    
    // Save current conversation before switching (if in main window and has content)
    if displayMode == .mainWindow && !session.turns.isEmpty {
      saveCurrentConversation()
    }
    
    // Load the selected conversation
    session.turns = conversation.messages
    currentConversationId = id
    conversationStore.setCurrentConversation(id)
    
    // Reset scroll
    isPinnedToBottom = true
  }
  
  /// Create a new chat
  private func createNewChat() {
    // Save current conversation if it has content
    if displayMode == .mainWindow && !session.turns.isEmpty {
      saveCurrentConversation()
    }
    
    // Create new conversation
    let newId = conversationStore.createConversation()
    currentConversationId = newId
    
    // Reset session
    session.reset()
    isPinnedToBottom = true
  }
  
  /// Save the current conversation to the store
  private func saveCurrentConversation() {
    guard displayMode == .mainWindow else { return }
    guard !session.turns.isEmpty else { return }
    
    if let id = currentConversationId {
      // Update existing conversation
      conversationStore.updateConversation(id, messages: session.turns)
    } else {
      // Create new conversation
      let newId = conversationStore.createConversation(messages: session.turns)
      currentConversationId = newId
    }
  }
}

// MARK: - Chat View Modifiers

struct ChatViewModifiers: ViewModifier {
  let displayMode: ChatDisplayMode
  @Binding var hostWindow: NSWindow?
  @Binding var focusTrigger: Int
  @Binding var isPinnedToBottom: Bool
  @ObservedObject var session: ChatSession
  let inputIsFocused: Bool
  let onResizeWindow: (Bool) -> Void
  let onSaveConversation: () -> Void
  
  func body(content: Content) -> some View {
    content
      .animation(.easeInOut(duration: 0.3), value: session.turns.isEmpty)
      .background(WindowAccessor(window: $hostWindow))
      .overlay(alignment: .topTrailing) {
        closeButton
      }
      .onExitCommand { 
        AppDelegate.shared?.closeChatOverlay() 
      }
      .onReceive(NotificationCenter.default.publisher(for: .chatOverlayActivated)) { _ in
        focusTrigger &+= 1
        isPinnedToBottom = true
      }
      .onChange(of: session.turns.isEmpty) { oldValue, newValue in
        // Only resize for floating panel, not main window
        if displayMode == .floatingPanel {
           onResizeWindow(newValue)
        }
      }
      .onChange(of: session.input) { oldValue, newValue in
        handleInputChange()
      }
      .onChange(of: session.turns.count) { oldValue, newValue in
        handleTurnsCountChange(oldCount: oldValue, newCount: newValue)
      }
      .onChange(of: inputIsFocused) { oldValue, newValue in
        handleFocusChange(newValue)
      }
      .onChange(of: session.isStreaming) { oldValue, newValue in
        handleStreamingChange(oldValue: oldValue, newValue: newValue)
      }
  }
  
  private var closeButton: some View {
    HoveringIcon(systemName: "xmark", help: "Close") {
      AppDelegate.shared?.closeChatOverlay()
    }
    .padding(20)
  }
  
  private func handleInputChange() {
    if displayMode == .floatingPanel {
      AppDelegate.shared?.resetPanelInactivityTimer()
    }
  }
  
  private func handleTurnsCountChange(oldCount: Int, newCount: Int) {
    if displayMode == .floatingPanel {
      AppDelegate.shared?.resetPanelInactivityTimer()
    }
    
    // Auto-save when messages change in main window (but not during streaming or initial load)
    // Only save if count increased from a non-zero value (meaning new messages were added after init)
    if displayMode == .mainWindow && newCount > oldCount && oldCount > 0 && !session.isStreaming {
      onSaveConversation()
    }
  }
  
  private func handleFocusChange(_ focused: Bool) {
    if displayMode == .floatingPanel && focused {
      AppDelegate.shared?.resetPanelInactivityTimer()
    }
  }
  
  private func handleStreamingChange(oldValue: Bool, newValue: Bool) {
    if displayMode == .mainWindow && !newValue && oldValue && !session.turns.isEmpty {
      onSaveConversation()
    }
  }
}

// MARK: - AppKit-backed Multiline Text View with Enter to send
struct MultilineTextView: NSViewRepresentable {
  @Binding var text: String
  @Binding var focusTrigger: Int
  var onCommit: () -> Void
  var onFocusChange: ((Bool) -> Void)? = nil

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true

    let tv = CommitInterceptTextView()
    tv.delegate = context.coordinator
    tv.isRichText = false
    tv.isAutomaticQuoteSubstitutionEnabled = false
    tv.isAutomaticDashSubstitutionEnabled = false
    tv.font = NSFont.systemFont(ofSize: 15)
    tv.backgroundColor = .clear
    tv.textColor = NSColor.labelColor
    tv.string = text
    tv.commitHandler = onCommit
    tv.minSize = NSSize(width: 0, height: 40)
    tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 120)
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false
    tv.textContainerInset = NSSize(width: 6, height: 6)
    tv.textContainer?.containerSize = NSSize(
      width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    tv.textContainer?.widthTracksTextView = true

    scroll.documentView = tv
    return scroll
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    if let tv = nsView.documentView as? CommitInterceptTextView {
      if tv.string != text { tv.string = text }
      tv.commitHandler = onCommit
      tv.focusHandler = onFocusChange
      if context.coordinator.lastFocusTrigger != focusTrigger {
        context.coordinator.lastFocusTrigger = focusTrigger
        // Try focusing immediately, then again on the next runloop to handle first-show timing
        nsView.window?.makeFirstResponder(tv)
        DispatchQueue.main.async {
          nsView.window?.makeFirstResponder(tv)
        }
      }
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MultilineTextView
    var lastFocusTrigger: Int = 0
    init(_ parent: MultilineTextView) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let tv = notification.object as? NSTextView else { return }
      parent.text = tv.string
    }

    func textDidBeginEditing(_ notification: Notification) {
      parent.onFocusChange?(true)
    }

    func textDidEndEditing(_ notification: Notification) {
      parent.onFocusChange?(false)
    }
  }

  final class CommitInterceptTextView: NSTextView {
    var commitHandler: (() -> Void)?
    var focusHandler: ((Bool) -> Void)?
    override func keyDown(with event: NSEvent) {
      let isReturn = (event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter)
      if isReturn {
        let hasShift = event.modifierFlags.contains(.shift)
        if hasShift {
          // Insert newline
          self.insertNewline(nil)
          return
        }
        // Command-Return or plain Return: commit
        commitHandler?()
        return
      }
      super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
      let r = super.becomeFirstResponder()
      if r { focusHandler?(true) }
      return r
    }

    override func resignFirstResponder() -> Bool {
      let r = super.resignFirstResponder()
      if r { focusHandler?(false) }
      return r
    }
  }
}

// MARK: - Hover Button Component
struct HoverButton<Content: View>: View {
  let action: () -> Void
  let content: () -> Content
  @State private var isHovered: Bool = false
  @Environment(\.theme) private var theme

  init(action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
    self.action = action
    self.content = content
  }

  var body: some View {
    Button(action: action) {
      content()
        .padding(6)
        .background(
          Circle()
            .fill(theme.secondaryBackground.opacity(isHovered ? 0.9 : 0.7))
            .overlay(
              Circle()
                .strokeBorder(theme.glassEdgeLight, lineWidth: 0.5)
            )
        )
        .shadow(
          color: Color.black.opacity(0.1),
          radius: 4,
          x: 0,
          y: 2
        )
    }
    .buttonStyle(.plain)
    .opacity(isHovered ? 1 : 0)
    .animation(.easeInOut(duration: 0.15), value: isHovered)
    .onHover { hovering in
      isHovered = hovering
    }
    .help("Copy message")
  }
}

// MARK: - Hovering Icon Button
struct HoveringIcon: View {
  let systemName: String
  let help: String
  let action: () -> Void
  @State private var isHovered: Bool = false
  @Environment(\.theme) private var theme

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(theme.secondaryText)
        .padding(6)
    }
    .buttonStyle(.plain)
    .opacity(isHovered ? 1 : 0)
    .animation(.easeInOut(duration: 0.15), value: isHovered)
    .onHover { hovering in
      isHovered = hovering
    }
    .help(help)
  }
}

// MARK: - ScrollView Styling Helper
func findAndStyleScrollViews(in view: NSView?) {
  guard let view = view else { return }
  
  if let scrollView = view as? NSScrollView {
    scrollView.scrollerStyle = .overlay
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    
    if let scroller = scrollView.verticalScroller {
      scroller.alphaValue = 0.4
      scroller.knobStyle = .light
    }
  }
  
  for subview in view.subviews {
    findAndStyleScrollViews(in: subview)
  }
}

// MARK: - GIF Image View
struct GIFImageView: NSViewRepresentable {
  let gifName: String
  let size: CGSize

  func makeNSView(context: Context) -> NSImageView {
    let imageView = NSImageView()
    imageView.imageScaling = .scaleProportionallyDown
    imageView.imageAlignment = .alignCenter
    imageView.animates = true
    imageView.frame = NSRect(origin: .zero, size: size)

    // Try to load GIF from Resources folder
    if let path = Bundle.main.path(forResource: gifName, ofType: "gif"),
       let image = NSImage(contentsOfFile: path) {
      imageView.image = image
    }

    return imageView
  }

  func updateNSView(_ nsView: NSImageView, context: Context) {
    nsView.frame.size = size
  }
}

// MARK: - Thinking Animation
struct ThinkingAnimationView: View {
  var body: some View {
    HStack {
      GIFImageView(gifName: "thinking-animation", size: CGSize(width: 24, height: 24))
        .frame(width: 24, height: 24)
    }
    .frame(minWidth: 60, minHeight: 24)
  }
}

// MARK: - Window Accessor Helper
struct WindowAccessor: NSViewRepresentable {
  @Binding var window: NSWindow?

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      self.window = view.window
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    if window == nil {
      DispatchQueue.main.async {
        self.window = nsView.window
      }
    }
  }
}
