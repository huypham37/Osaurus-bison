//
//  AppDelegate.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
  static weak var shared: AppDelegate?
  let serverController = ServerController()
  private var statusItem: NSStatusItem?
  private var popover: NSPopover?
  private var cancellables: Set<AnyCancellable> = []
  let updater = UpdaterViewModel()

  private var activityDot: NSView?
  private var modelManagerWindow: NSWindow?
  private var chatWindow: NSWindow?  // Floating panel (quick access)
  private var mainChatWindow: NSWindow?  // Persistent main window
  private var panelInactivityTimer: Timer?  // Auto-destroy timer for floating panel
  private var pendingConversationId: UUID?  // Temp storage for conversation ID during expansion

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppDelegate.shared = self

    // Configure as menu bar app (hide Dock icon)
    NSApp.setActivationPolicy(.accessory)

    // App has launched

    // Set up observers for server state changes
    setupObservers()

    // Set up distributed control listeners (local-only management)
    setupControlNotifications()

    // Apply saved Start at Login preference on launch
    LoginItemService.shared.applyStartAtLogin(serverController.configuration.startAtLogin)

    // Create status bar item and attach click handler
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      if let image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Osaurus") {
        image.isTemplate = true
        button.image = image
      } else {
        button.title = "Osaurus"
      }
      button.toolTip = "Osaurus Server"
      button.target = self
      button.action = #selector(togglePopover(_:))

      // Add a small green blinking dot at the bottom-right of the status bar button
      let dot = NSView()
      dot.wantsLayer = true
      dot.translatesAutoresizingMaskIntoConstraints = false
      dot.isHidden = true
      button.addSubview(dot)
      NSLayoutConstraint.activate([
        dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
        dot.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
        dot.widthAnchor.constraint(equalToConstant: 7),
        dot.heightAnchor.constraint(equalToConstant: 7),
      ])
      if let layer = dot.layer {
        layer.backgroundColor = NSColor.systemGreen.cgColor
        layer.cornerRadius = 3.5
        layer.borderWidth = 1
        layer.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
      }
      activityDot = dot
    }
    statusItem = item
    updateStatusItemAndMenu()

    // Auto-start server on app launch
    Task { @MainActor in
      await serverController.startServer()
    }

    // Setup global hotkey for Chat overlay (configured)
    applyChatHotkey()
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      handleDeepLink(url)
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Quit immediately without confirmation; still shut down server gracefully if running
    guard serverController.isRunning else {
      return .terminateNow
    }

    // Delay termination briefly to allow async shutdown
    Task { @MainActor in
      await serverController.ensureShutdown()
      NSApp.reply(toApplicationShouldTerminate: true)
    }

    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    SharedConfigurationService.shared.remove()
  }

  // MARK: Status Item / Menu

  private func setupObservers() {
    cancellables.removeAll()
    serverController.$serverHealth
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateStatusItemAndMenu()
      }
      .store(in: &cancellables)
    serverController.$isRunning
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateStatusItemAndMenu()
      }
      .store(in: &cancellables)
    serverController.$configuration
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateStatusItemAndMenu()
      }
      .store(in: &cancellables)

    serverController.$activeRequestCount
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateStatusItemAndMenu()
      }
      .store(in: &cancellables)

    // Publish shared configuration on state/config/address changes
    Publishers.CombineLatest3(
      serverController.$serverHealth,
      serverController.$configuration,
      serverController.$localNetworkAddress
    )
    .receive(on: RunLoop.main)
    .sink { health, config, address in
      SharedConfigurationService.shared.update(
        health: health,
        configuration: config,
        localAddress: address
      )
    }
    .store(in: &cancellables)
  }

  private func updateStatusItemAndMenu() {
    guard let statusItem else { return }
    // Ensure no NSMenu is attached so button action is triggered
    statusItem.menu = nil
    if let button = statusItem.button {
      // Update symbol based on server activity
      let isActive = (serverController.serverHealth == .running) || serverController.isRestarting
      let desiredName = isActive ? "brain.fill" : "brain"
      var image = NSImage(systemSymbolName: desiredName, accessibilityDescription: "Osaurus")
      if image == nil && isActive {
        // Fallback if brain.fill is unavailable on this macOS version
        image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Osaurus")
      }
      if let image {
        image.isTemplate = true
        button.image = image
      }
      // Toggle green blinking dot overlay
      let isGenerating = serverController.activeRequestCount > 0
      if let dot = activityDot {
        if isGenerating {
          dot.isHidden = false
          if let layer = dot.layer, layer.animation(forKey: "blink") == nil {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.2
            anim.duration = 0.8
            anim.autoreverses = true
            anim.repeatCount = .infinity
            layer.add(anim, forKey: "blink")
          }
        } else {
          if let layer = dot.layer {
            layer.removeAnimation(forKey: "blink")
          }
          dot.isHidden = true
        }
      }
      var tooltip: String
      switch serverController.serverHealth {
      case .stopped:
        tooltip =
          serverController.isRestarting ? "Osaurus — Restarting…" : "Osaurus — Ready to start"
      case .starting:
        tooltip = "Osaurus — Starting…"
      case .restarting:
        tooltip = "Osaurus — Restarting…"
      case .running:
        tooltip = "Osaurus — Running on port \(serverController.port)"
      case .stopping:
        tooltip = "Osaurus — Stopping…"
      case .error(let message):
        tooltip = "Osaurus — Error: \(message)"
      }
      if serverController.activeRequestCount > 0 {
        tooltip += " — Generating…"
      }
      button.toolTip = tooltip
    }
  }

  // MARK: - Actions

  @objc private func togglePopover(_ sender: Any?) {
    if let popover, popover.isShown {
      popover.performClose(sender)
      return
    }
    showPopover()
  }

  // Expose a method to show the popover programmatically (e.g., for Cmd+,)
  func showPopover() {
    guard let statusButton = statusItem?.button else { return }
    if let popover, popover.isShown {
      // Already visible; bring app to front
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true

    let themeManager = ThemeManager.shared
    let contentView = ContentView()
      .environmentObject(serverController)
      .environment(\.theme, themeManager.currentTheme)
      .environmentObject(updater)

    popover.contentViewController = NSHostingController(rootView: contentView)
    self.popover = popover

    popover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
  }

}

// MARK: - Distributed Control (Local Only)
extension AppDelegate {
  fileprivate static let controlServeNotification = Notification.Name(
    "com.dinoki.osaurus.control.serve")
  fileprivate static let controlStopNotification = Notification.Name(
    "com.dinoki.osaurus.control.stop")
  fileprivate static let controlShowUINotification = Notification.Name(
    "com.dinoki.osaurus.control.ui")

  private func setupControlNotifications() {
    let center = DistributedNotificationCenter.default()
    center.addObserver(
      self,
      selector: #selector(handleServeCommand(_:)),
      name: Self.controlServeNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(handleStopCommand(_:)),
      name: Self.controlStopNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(handleShowUICommand(_:)),
      name: Self.controlShowUINotification,
      object: nil
    )
  }

  @objc private func handleServeCommand(_ note: Notification) {
    var desiredPort: Int? = nil
    var exposeFlag: Bool = false
    if let ui = note.userInfo {
      if let p = ui["port"] as? Int {
        desiredPort = p
      } else if let s = ui["port"] as? String, let p = Int(s) {
        desiredPort = p
      }
      if let e = ui["expose"] as? Bool {
        exposeFlag = e
      } else if let es = ui["expose"] as? String {
        let v = es.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        exposeFlag = (v == "1" || v == "true" || v == "yes" || v == "y")
      }
    }

    // Apply defaults if not provided
    let targetPort = desiredPort ?? (ServerConfigurationStore.load()?.port ?? 1337)
    guard (1..<65536).contains(targetPort) else { return }

    // Apply exposure policy based on request (default localhost-only)
    serverController.configuration.exposeToNetwork = exposeFlag
    serverController.port = targetPort
    serverController.saveConfiguration()

    Task { @MainActor in
      await serverController.startServer()
    }
  }

  @objc private func handleStopCommand(_ note: Notification) {
    Task { @MainActor in
      await serverController.stopServer()
    }
  }

  @objc private func handleShowUICommand(_ note: Notification) {
    Task { @MainActor in
      self.showPopover()
    }
  }
}

// MARK: Deep Link Handling
extension AppDelegate {
  func applyChatHotkey() {
    let cfg = ChatConfigurationStore.load()
    HotKeyManager.shared.register(hotkey: cfg.hotkey) { [weak self] in
      Task { @MainActor in
        self?.toggleChatOverlay()
      }
    }
  }
  fileprivate func handleDeepLink(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(), scheme == "huggingface" else { return }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
    let items = components.queryItems ?? []
    let modelId = items.first(where: { $0.name.lowercased() == "model" })?.value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let file = items.first(where: { $0.name.lowercased() == "file" })?.value?.trimmingCharacters(
      in: .whitespacesAndNewlines)

    guard let modelId, !modelId.isEmpty else {
      // No model id provided; ignore silently
      return
    }

    // Resolve to ensure it appears in the UI; enforce MLX-only via metadata
    Task { @MainActor in
      if await ModelManager.shared.resolveModelIfMLXCompatible(byRepoId: modelId) == nil {
        let alert = NSAlert()
        alert.messageText = "Unsupported model"
        alert.informativeText = "Osaurus only supports MLX-compatible Hugging Face repositories."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return
      }

      // Open Model Manager in its own window for deeplinks
      showModelManagerWindow(deeplinkModelId: modelId, file: file)
    }
  }
}

// MARK: - Chat Overlay Window
extension AppDelegate {
  private func setupChatHotKey() {}

  @MainActor private func toggleChatOverlay() {
    // Always close existing panel first (enforce single instance)
    if chatWindow != nil {
      closeChatOverlay()
    }
    // Always create fresh panel with empty chat session
    showChatOverlay()
  }

  @MainActor func showChatOverlay() {
    // Always create a fresh panel (no reuse)
    let themeManager = ThemeManager.shared
    let root = ChatView(displayMode: .floatingPanel)
      .environmentObject(serverController)
      .environment(\.theme, themeManager.currentTheme)

    let controller = NSHostingController(rootView: root)
    // Create already centered on the active screen to avoid any reposition jank
    // Start with compact size since chat is initially empty
    let defaultSize = NSSize(width: 720, height: 250)
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    let initialRect: NSRect
    if let s = screen {
      initialRect = centeredRect(size: defaultSize, on: s)
    } else {
      initialRect = NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height)
    }
    let win = NSPanel(
      contentRect: initialRect,
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    // Enable resizing and glass-style translucency
    win.styleMask.insert(.resizable)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hidesOnDeactivate = false
    win.isExcludedFromWindowsMenu = true
    win.standardWindowButton(.miniaturizeButton)?.isHidden = true
    win.standardWindowButton(.zoomButton)?.isHidden = true
    win.titleVisibility = .hidden
    win.titlebarAppearsTransparent = true
    win.isMovableByWindowBackground = true
    win.standardWindowButton(.closeButton)?.isHidden = true
    win.level = .modalPanel
    win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    win.contentViewController = controller
    win.delegate = self
    win.animationBehavior = .documentWindow  // Enable animations for SwiftUI content
    chatWindow = win
    // Pre-layout before showing to avoid initial jank
    controller.view.layoutSubtreeIfNeeded()
    NSApp.activate(ignoringOtherApps: true)
    chatWindow?.makeKeyAndOrderFront(nil)
    
    // Start 2-minute inactivity timer
    startPanelInactivityTimer()
    
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .chatOverlayActivated, object: nil)
    }
  }

  @MainActor func closeChatOverlay() {
    // Invalidate and clear inactivity timer
    panelInactivityTimer?.invalidate()
    panelInactivityTimer = nil
    
    // Close and destroy the panel
    chatWindow?.orderOut(nil)
    chatWindow = nil
  }
  
  // MARK: - Panel Inactivity Timer
  
  private func startPanelInactivityTimer() {
    // Invalidate any existing timer
    panelInactivityTimer?.invalidate()
    
    // Create 2-minute (120 seconds) timer
    panelInactivityTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: false) { [weak self] _ in
      Task { @MainActor in
        self?.closeChatOverlay()
      }
    }
  }
  
  func resetPanelInactivityTimer() {
    // Only reset if panel exists and timer is active
    guard chatWindow != nil, panelInactivityTimer != nil else { return }
    startPanelInactivityTimer()
  }
  
  // MARK: - Main Chat Window (Persistent)
  
  @MainActor func showMainChatWindow() {
    // If there's a pending conversation ID and window exists, close it first to recreate with conversation
    if let window = mainChatWindow, pendingConversationId != nil {
      saveMainWindowFrame()  // Save frame before closing
      window.close()
      mainChatWindow = nil
    }
    
    if let window = mainChatWindow {
      // Reuse existing window (no pending conversation)
      NSApp.activate(ignoringOtherApps: true)
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
      return
    }
    
    // Create new persistent window with optional conversation ID
    let themeManager = ThemeManager.shared
    let root = ChatView(displayMode: .mainWindow, initialConversationId: pendingConversationId)
      .environmentObject(serverController)
      .environment(\.theme, themeManager.currentTheme)
    
    let controller = NSHostingController(rootView: root)
    
    // Load saved frame or use default
    let savedFrame = loadMainWindowFrame()
    let defaultFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
    let initialFrame = savedFrame ?? defaultFrame
    
    let window = NSWindow(
      contentRect: initialFrame,
      styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    
    window.title = "Osaurus Chat"
    // Apple Liquid Glass title bar style - translucent title bar with vibrancy
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    
    // Add unified toolbar for modern macOS app look with Liquid Glass aesthetic
    let toolbar = NSToolbar()
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    
    window.contentViewController = controller
    window.delegate = self
    window.isReleasedWhenClosed = false
    
    if savedFrame == nil {
      window.center()
    }
    
    mainChatWindow = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
  
  @MainActor func expandPanelToWindow(conversationId: UUID) {
    guard let panel = chatWindow else {
      // Fallback: if panel doesn't exist, just show main window
      pendingConversationId = conversationId
      showMainChatWindow()
      pendingConversationId = nil
      return
    }
    
    // Store conversation ID temporarily
    pendingConversationId = conversationId
    
    // Stop inactivity timer since we're transitioning
    panelInactivityTimer?.invalidate()
    panelInactivityTimer = nil
    
    // Perform smooth morph animation from panel → main window
    morphPanelToMainWindow(panel: panel, conversationId: conversationId)
  }
  
  @MainActor private func morphPanelToMainWindow(panel: NSWindow, conversationId: UUID) {
    // 1. Get starting frame (current panel position/size)
    let startFrame = panel.frame
    
    // 2. Calculate target frame (centered main window)
    let targetSize = NSSize(width: 950, height: 580)
    let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
    let screenFrame = screen.visibleFrame
    let targetFrame = NSRect(
      x: screenFrame.midX - targetSize.width / 2,
      y: screenFrame.midY - targetSize.height / 2,
      width: targetSize.width,
      height: targetSize.height
    )
    
    // 3. Create the main window (but don't show it yet)
    let themeManager = ThemeManager.shared
    let root = ChatView(displayMode: .mainWindow, initialConversationId: conversationId)
      .environmentObject(serverController)
      .environment(\.theme, themeManager.currentTheme)
    
    let controller = NSHostingController(rootView: root)
    
    // 4. Create main window at the START frame (same as panel)
    let window = NSWindow(
      contentRect: startFrame,
      styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    
    window.title = "Osaurus Chat"
    // Apple Liquid Glass title bar style - translucent title bar with vibrancy
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    
    // Add toolbar with Liquid Glass aesthetic
    let toolbar = NSToolbar()
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    
    window.contentViewController = controller
    window.delegate = self
    window.isReleasedWhenClosed = false
    
    // 5. Start with main window semi-transparent (for cross-fade)
    window.alphaValue = 0.0
    
    // 6. Show main window at panel's position
    mainChatWindow = window
    window.makeKeyAndOrderFront(nil)
    
    // 7. Perform simultaneous animations
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.4 // 400ms animation
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      context.allowsImplicitAnimation = true
      
      // Animate main window: opacity + frame
      window.animator().alphaValue = 1.0
      window.animator().setFrame(targetFrame, display: true, animate: true)
      
      // Animate panel: fade out
      panel.animator().alphaValue = 0.0
      
    }, completionHandler: {
      // 8. Clean up: close and destroy the floating panel (on main actor)
      Task { @MainActor in
        panel.orderOut(nil)
        self.chatWindow = nil
        
        // 9. Ensure main window is fully opaque
        window.alphaValue = 1.0
        
        // 10. Clear temporary storage
        self.pendingConversationId = nil
        
        NSApp.activate(ignoringOtherApps: true)
      }
    })
  }
  
  // MARK: - Window Frame Persistence
  
  private func loadMainWindowFrame() -> NSRect? {
    guard let frameString = UserDefaults.standard.string(forKey: "MainChatWindowFrame") else {
      return nil
    }
    return NSRectFromString(frameString)
  }
  
  private func saveMainWindowFrame() {
    guard let window = mainChatWindow else { return }
    let frameString = NSStringFromRect(window.frame)
    UserDefaults.standard.set(frameString, forKey: "MainChatWindowFrame")
  }
}

// MARK: - Chat Overlay Helpers
extension AppDelegate {
  fileprivate func centerWindowOnActiveScreen(_ window: NSWindow) {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    guard let s = screen else {
      window.center()
      return
    }
    // Use visibleFrame to avoid menu bar and dock overlap
    let vf = s.visibleFrame
    let size = window.frame.size
    let x = vf.midX - size.width / 2
    let y = vf.midY - size.height / 2
    window.setFrameOrigin(NSPoint(x: x, y: y))
  }

  fileprivate func centeredRect(size: NSSize, on screen: NSScreen) -> NSRect {
    let vf = screen.visibleFrame
    let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
    return NSRect(origin: origin, size: size)
  }
}

extension Notification.Name {
  static let chatOverlayActivated = Notification.Name("chatOverlayActivated")
}

// MARK: Model Manager Window
extension AppDelegate {
  func showModelManagerWindow(deeplinkModelId: String? = nil, file: String? = nil) {
    NSLog(
      "[ModelManager] showModelManagerWindow called (modelId=%@, file=%@)",
      deeplinkModelId ?? "nil", file ?? "nil")
    let presentWindow: () -> Void = { [weak self] in
      guard let self = self else { return }

      let themeManager = ThemeManager.shared
      let root = ModelDownloadView(deeplinkModelId: deeplinkModelId, deeplinkFile: file)
        .environment(\.theme, themeManager.currentTheme)

      let hostingController = NSHostingController(rootView: root)

      if let window = self.modelManagerWindow {
        // Reuse existing window; just replace content and ensure visible/focused
        window.contentViewController = hostingController
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSLog("[ModelManager] Reused existing window and brought to front")
        return
      }

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      // Minimalistic appearance: hidden titlebar, still closable
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.isMovableByWindowBackground = true
      window.contentViewController = hostingController
      window.center()
      window.delegate = self
      window.isReleasedWhenClosed = false
      self.modelManagerWindow = window

      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
      NSLog("[ModelManager] Created new window and presented")
    }

    // If popover is open, close first, then present shortly after to avoid layout recursion
    if let pop = popover, pop.isShown {
      pop.performClose(nil)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        presentWindow()
      }
    } else {
      presentWindow()
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard let win = notification.object as? NSWindow else { return }
    
    if win == modelManagerWindow {
      modelManagerWindow = nil
    } else if win == mainChatWindow {
      // Save window frame before closing
      saveMainWindowFrame()
      mainChatWindow = nil
    }
  }
}
