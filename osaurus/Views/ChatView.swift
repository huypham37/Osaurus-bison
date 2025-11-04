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
  private var currentTask: Task<Void, Never>?

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
          print("[ChatSession] Failed to fetch OpenCode models: \(error)")
        }
      }
    }

    modelOptions = opts
    // Set default selectedModel to Claude Sonnet 4.5 if available, otherwise first available
    selectedModel = opts.first
    
    // Check if OpenCode Claude Sonnet 4.5 becomes available
    Task {
      do {
        let models = try await opencode.getAvailableModels()
        await MainActor.run {
          // Find Claude Sonnet 4.5 and set as default
          for (provider, model, _) in models {
            let modelName = "\(provider):\(model)"
            if modelName.contains("claude-sonnet-4.5") {
              self.selectedModel = modelName
              print("[ChatSession] Set default model to: \(modelName)")
              break
            }
          }
        }
      } catch {
        print("[ChatSession] Failed to set default model: \(error)")
      }
    }
  }

  func sendCurrent() {
    guard !isStreaming else { return }
    let text = input
    input = ""
    send(text)
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

  func send(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    turns.append((.user, trimmed))
    streamResponse()
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
          let stream = try await svc.streamDeltas(prompt: prompt, parameters: params)
          for await delta in stream {
            if Task.isCancelled { break }
            if !delta.isEmpty {
              turns[idx].content += delta
              // Signal UI to autoscroll while streaming
              scrollTick &+= 1
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

  private var theme: ThemeProtocol {
    themeManager.currentTheme
  }
  
  let displayMode: ChatDisplayMode
  
  @StateObject private var session: ChatSession
  // Using AppKit-backed text view to handle Enter vs Shift+Enter
  @State private var focusTrigger: Int = 0
  @State private var isPinnedToBottom: Bool = true
  @State private var inputIsFocused: Bool = false
  @State private var hostWindow: NSWindow?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var currentConversationId: UUID?
  @State private var isExpandingToMainWindow: Bool = false  // Prevent double-expand
  @State private var isSendingMessage: Bool = false  // Prevent double-send from Enter+Button
  
  // Glow animation states
  @State private var testAnimationOpacity: Double = 0.3
  @State private var testAnimationScale: CGFloat = 1.0
  
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
      print("🔵 [MainWindow Init] Loaded conversation ID: \(conversationId) with \(initialMessages.count) messages")
      for (index, msg) in initialMessages.enumerated() {
        print("   Message \(index + 1): \(msg.role) - \(msg.content.prefix(50))...")
      }
    } else {
      initialMessages = []
      self._currentConversationId = State(initialValue: nil)
      print("🔵 [MainWindow Init] Starting with empty conversation")
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
          print("🔵 [MainWindow] Auto-streaming response for loaded conversation")
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
            modelPicker
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
      // Glass background with animated glow…
      GlassSurface(cornerRadius: 40)
//        .shadow(color: Color.blue.opacity(testAnimationOpacity * 0.6), radius: 20, x: 0, y: 0)
//        .shadow(color: Color.cyan.opacity(testAnimationOpacity * 0.4), radius: 15, x: 0, y: 0)
//        .allowsHitTesting(false)
        .onAppear {
          // Breathing glow animation - only affects the glass surface shadows
          withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            testAnimationOpacity = 1.0
            testAnimationScale = 1.05
          }
        }
      
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
    .frame(height: 80)
    .padding(.horizontal, 40)
  }
  
  private func handleMinimalEntrySend() {
    guard !session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard !isSendingMessage else {
      print("⚠️ [FloatingPanel] Already sending message, ignoring duplicate call")
      return
    }
    guard !isExpandingToMainWindow else { 
      print("⚠️ [FloatingPanel] Already expanding, ignoring send")
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
          print("⚠️ [FloatingPanel] Already expanding, skipping")
          return
        }
        isExpandingToMainWindow = true
        
        print("🟢 [FloatingPanel] Expanding immediately with user message: \(userMessage.prefix(50))")
        
        // Save conversation with just the user message (no assistant response yet)
        let conversationId = conversationStore.createConversation(messages: session.turns)
        print("🟢 [FloatingPanel] Created conversation ID: \(conversationId)")
        
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
              .frame(maxWidth: 1000)
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
              .frame(maxWidth: 1000)
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
          maxHeight: session.turns.isEmpty ? .infinity : .infinity,
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
      modelPicker
      
      Spacer()
      
      // Show "Expand" button only in floating panel mode when conversation exists
      if displayMode == .floatingPanel && !session.turns.isEmpty {
        Button(action: { 
          guard !isExpandingToMainWindow else {
            print("⚠️ [FloatingPanel] Already expanding, ignoring button click")
            return
          }
          isExpandingToMainWindow = true
          
          // Save conversation and pass ID to AppDelegate before expanding
          let conversationId = conversationStore.createConversation(messages: session.turns)
          print("🔵 [Expand Button] Created conversation with ID: \(conversationId)")
          print("🔵 [Expand Button] Total conversations in store: \(conversationStore.conversations.count)")
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

  private func displayModelName(_ raw: String?) -> String {
    guard let raw else { return "Model" }
    if raw.lowercased() == "foundation" { return "Foundation" }
    if let last = raw.split(separator: "/").last { return String(last) }
    return raw
  }
  
  // MARK: - Model Picker
  
  private var modelPicker: some View {
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
        
        // Border with gradient
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(
            LinearGradient(
              colors: [
                Color.white.opacity(0.06),
                Color.white.opacity(0.05)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 0.01
          )
      }
    )
    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
  }
  
  // MARK: - New Chat Button
  
  private var newChatButton: some View {
    Button(action: {
      createNewChat()
    }) {
      Image(systemName: "plus")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(theme.primaryText)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.borderless)
    .help("New Chat")
  }

  private func conversation(_ width: CGFloat) -> some View {
    ScrollViewReader { proxy in
      @State var hasInitialScroll = false
      ZStack(alignment: .bottomTrailing) {
        ScrollView {
          LazyVStack(spacing: 12) {
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
                } else {
                  Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 6) {
                  ZStack(alignment: .topTrailing) {
                    Group {
                      if turn.content.isEmpty && turn.role == .assistant && session.isStreaming {
                        HStack(spacing: 6) {
                          ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.accentColor))
                          Text("Thinking…")
                            .font(Typography.body(width))
                            .foregroundColor(theme.primaryText)
                        }
                        .padding(12)
                      } else {
                        MarkdownMessageView(text: turn.content, baseWidth: width)
                          .font(Typography.body(width))
                          .foregroundColor(theme.primaryText)
                          .padding(turn.role == .user ? 12 : 0)
                          .background(
                            turn.role == .user ? 
                              AnyView(RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.15))) : 
                              AnyView(Color.clear)
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
    HStack(alignment: .bottom, spacing: 12) {
      // Input field
      ZStack(alignment: .topLeading) {
        GlassInputFieldBridge(
          text: $session.input,
          isFocused: inputIsFocused,
          onCommit: { session.sendCurrent() },
          onFocusChange: { focused in inputIsFocused = focused }
        )
        .frame(minHeight: 48, maxHeight: 120)
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
              theme.glassOpacityTertiary == 0.05
                ? theme.secondaryBackground.opacity(0.4) : theme.primaryBackground.opacity(0.4)
            )
            .background(
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            )
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
              inputIsFocused
                ? LinearGradient(
                  colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
                : LinearGradient(
                  colors: [theme.glassEdgeLight, theme.glassEdgeLight.opacity(0.3)],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                ),
              lineWidth: inputIsFocused ? 1.5 : 0.5
            )
        )
        .shadow(
          color: inputIsFocused ? Color.accentColor.opacity(0.2) : Color.clear,
          radius: inputIsFocused ? 20 : 0
        )
        .animation(.easeInOut(duration: theme.animationDurationMedium), value: inputIsFocused)

        if session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text("Type your message…")
            .font(.system(size: 15))
            .foregroundColor(theme.tertiaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
        }
      }
      
      // Attachment button
      attachmentButton
      
      // Send/Stop button
      primaryActionButton
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
      // TODO: Implement file picker for attachments
      print("📎 Attachment button tapped - feature coming soon")
    }) {
      Image(systemName: "plus")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(theme.secondaryText)
        .frame(width: 36, height: 36)
        .background(Circle().fill(theme.secondaryBackground))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("Attach file (coming soon)")
  }

  private var sendButton: some View {
    Button(action: { session.sendCurrent() }) {
      HStack(spacing: 6) {
        Image(systemName: "paperplane.fill")
        Text("Send")
      }
      .font(.system(size: 14, weight: .medium))
      .foregroundColor(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(
        Capsule()
          .fill(Color.accentColor.opacity(0.9))
      )
      .shadow(
        color: Color.accentColor.opacity(0.3),
        radius: 8,
        x: 0,
        y: 2
      )
    }
    .buttonStyle(.plain)
    .disabled(
      session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || session.isStreaming
    )
    .opacity(
      session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || session.isStreaming ? 0.5 : 1
    )
    .animation(.easeInOut(duration: theme.animationDurationQuick), value: session.input)
    .keyboardShortcut(.return, modifiers: [.command])
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
      print("🟡 [MainWindow Save] Updating conversation ID: \(id)")
      conversationStore.updateConversation(id, messages: session.turns)
      print("🟡 [MainWindow Save] Total conversations in store: \(conversationStore.conversations.count)")
    } else {
      // Create new conversation
      print("🔴 [MainWindow Save] Creating NEW conversation (currentConversationId was nil!)")
      let newId = conversationStore.createConversation(messages: session.turns)
      currentConversationId = newId
      print("🔴 [MainWindow Save] Created with ID: \(newId), Total: \(conversationStore.conversations.count)")
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
        let hasCommand = event.modifierFlags.contains(.command)
        if hasShift {
          // Insert newline
          self.insertNewline(nil)
          return
        }
        if hasCommand || !hasCommand {
          // Command-Return or plain Return: commit
          commitHandler?()
          return
        }
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
