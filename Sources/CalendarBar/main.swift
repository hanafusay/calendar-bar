import AppKit
import CalendarCore
import CryptoKit
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
  enum Account {
    case loading
    case disconnected
    case connected(GoogleCredentials)
    case demo
  }
  private var account: Account = CommandLine.arguments.contains("--demo") ? .demo : .loading
  private var events: [CalendarEvent] = []
  private var client: GoogleCredentials?
  private var generation = 0
  private var refreshTask: Task<Void, Never>?
  private var login: GoogleLogin?
  private var message: String?
  private var settingsStatus: NSTextField?
  private var authButtons: [NSButton] = []
  private var updated: Date?
  private var statusItem: NSStatusItem!
  private var timer: Timer?
  private var settingsWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if case .demo = account {
      events = demoEvents()
      refresh()
    } else {
      render()
      let captured = generation
      Task {
        do {
          let stored = try await Task.detached { try CredentialStore.load() }.value
          guard generation == captured else { return }
          client = stored
          if let stored, stored.refreshToken != nil {
            account = .connected(stored)
          } else {
            account = .disconnected
          }
        } catch {
          guard generation == captured else { return }
          account = .disconnected
          message = "保存した認証情報を読み込めませんでした。Macのキーチェーンの許可を確認してください。"
        }
        refresh()
        updateSettings()
        if client == nil, settingsWindow == nil { showSettings() }
      }
    }
    if CommandLine.arguments.contains("--show-settings") { showSettings() }
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  @objc private func refresh() {
    if case .demo = account {
      updated = Date()
      render()
      return
    }
    guard case .connected(let credentials) = account, login == nil, refreshTask == nil else {
      render()
      return
    }
    let captured = generation
    refreshTask = Task { [weak self] in
      do {
        let result = try await GoogleCalendarAPI().events(credentials: credentials)
        guard let self, !Task.isCancelled, self.generation == captured else { return }
        self.events = result
        self.updated = Date()
        self.message = nil
      } catch {
        guard let self, !Task.isCancelled, self.generation == captured else { return }
        self.message =
          (error as? GoogleError)?.localizedDescription
          ?? GoogleError.requestFailed.localizedDescription
      }
      guard let self, self.generation == captured else { return }
      self.refreshTask = nil
      self.render()
      self.updateSettings()
    }
    render()
  }

  private func render() {
    let agenda = Agenda(events: events, now: Date())
    switch account {
    case .loading, .disconnected:
      statusItem.button?.title = "📅 Calendar Bar"
    case .connected, .demo:
      statusItem.button?.title = message == nil ? agenda.title : "📅 取得失敗"
    }
    statusItem.button?.setAccessibilityLabel(statusItem.button?.title ?? "Calendar Bar")
    let menu = NSMenu()
    switch account {
    case .loading, .disconnected:
      let item = NSMenuItem(
        title: "Google カレンダーへの接続を設定", action: #selector(showSettings), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    case .connected, .demo:
      for entry in agenda.entries {
        let row = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
        if entry.state == .completed {
          row.attributedTitle = NSAttributedString(
            string: entry.title, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        }
        let submenu = NSMenu()
        if let url = CalendarLinks.validated(entry.event.hangoutLink, meet: true) {
          addLink("Meet に参加", url: url, menu: submenu)
        }
        if let url = CalendarLinks.validated(entry.event.htmlLink, meet: false) {
          addLink("Google カレンダーで開く", url: url, menu: submenu)
        }
        if submenu.items.isEmpty {
          let item = NSMenuItem(title: "開けるリンクがありません", action: nil, keyEquivalent: "")
          submenu.addItem(item)
        }
        row.submenu = submenu
        menu.addItem(row)
      }
      if agenda.entries.isEmpty {
        menu.addItem(NSMenuItem(title: "今日の予定はありません", action: nil, keyEquivalent: ""))
      }
    }
    menu.addItem(.separator())
    if let message { menu.addItem(NSMenuItem(title: message, action: nil, keyEquivalent: "")) }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let stamp = updated.map { "更新 \(formatter.string(from: $0))（1分おき）" } ?? "未接続"
    menu.addItem(NSMenuItem(title: stamp, action: nil, keyEquivalent: ""))
    addAction("今すぐ更新", action: #selector(refresh), menu: menu)
    addAction("設定…", action: #selector(showSettings), menu: menu)
    menu.addItem(.separator())
    addAction("Calendar Bar を終了", action: #selector(quit), menu: menu)
    statusItem.menu = menu
  }

  private func addAction(_ title: String, action: Selector, menu: NSMenu) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
  }
  private func addLink(_ title: String, url: URL, menu: NSMenu) {
    let item = NSMenuItem(title: title, action: #selector(openLink(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = url
    menu.addItem(item)
  }
  @objc private func openLink(_ sender: NSMenuItem) {
    if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
  }
  @objc private func quit() { NSApp.terminate(nil) }

  @objc private func showSettings() {
    if let window = settingsWindow {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 340), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.title = "Calendar Bar"
    window.isReleasedWhenClosed = false
    let title = NSTextField(labelWithString: "Google カレンダー")
    title.font = .systemFont(ofSize: 20, weight: .semibold)
    let description = NSTextField(
      wrappingLabelWithString: "Google カレンダーの予定を直接取得し、メニューバーに表示します。Mac のカレンダーとの同期を待ちません。")
    let status = NSTextField(wrappingLabelWithString: "")
    settingsStatus = status
    updateSettings()
    let importButton = NSButton(title: "認証ファイルを選ぶ…", target: self, action: #selector(importClient))
    let connectButton = NSButton(title: "Google に接続", target: self, action: #selector(connect))
    let disconnectButton = NSButton(title: "接続解除", target: self, action: #selector(disconnect))
    authButtons = [importButton, connectButton, disconnectButton]
    updateSettings()
    let buttons = NSStackView(views: authButtons)
    buttons.spacing = 8
    status.textColor = .secondaryLabelColor
    let login = NSButton(
      checkboxWithTitle: "ログイン時に起動", target: self, action: #selector(toggleLogin(_:)))
    login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    let stack = NSStackView(views: [title, description, status, buttons, login])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
    ])
    settingsWindow = window
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func toggleLogin(_ sender: NSButton) {
    do {
      if sender.state == .on {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
      let alert = NSAlert()
      alert.messageText = "ログイン時の起動を変更できませんでした"
      alert.informativeText = "アプリをアプリケーションフォルダへ移し、システム設定のログイン項目を確認してください。"
      alert.runModal()
    }
  }
  private func updateSettings() {
    let loading: Bool
    if case .loading = account { loading = true } else { loading = false }
    authButtons.forEach { $0.isEnabled = !loading }
    if case .demo = account {
      settingsStatus?.stringValue = "デモ表示中。予定は架空のサンプルです。"
    } else if let message {
      settingsStatus?.stringValue = message
    } else if case .loading = account {
      settingsStatus?.stringValue = "保存した接続設定を読み込んでいます。Macにキーチェーンの確認が表示された場合は許可してください。"
    } else if login != nil {
      settingsStatus?.stringValue = "ブラウザでGoogleへの接続を完了してください。接続解除でキャンセルできます。"
    } else if case .connected = account {
      if let updated {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let count = Agenda(events: events, now: Date()).entries.count
        settingsStatus?.stringValue = "今日の予定\(count)件を取得しました。更新 \(formatter.string(from: updated))"
      } else {
        settingsStatus?.stringValue = "Google カレンダーから予定を取得しています。"
      }
    } else {
      settingsStatus?.stringValue =
        client == nil
        ? "自分のGoogle Cloudで作成したデスクトップアプリ用の認証JSONファイルを選び、Googleに接続してください。認証情報はMacのキーチェーンに保存します。"
        : "認証ファイルを設定しました。Googleに接続してください。"
    }
  }
  @objc private func importClient() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 65536 else { throw GoogleError.invalidCredentials }
      let credentials = try GoogleCredentials.importing(Data(contentsOf: url))
      try CredentialStore.save(credentials)
      clearTasks()
      client = credentials
      events = []
      updated = nil
      message = nil
      account = credentials.refreshToken == nil ? .disconnected : .connected(credentials)
      refresh()
    } catch { message = GoogleError.invalidCredentials.localizedDescription }
    updateSettings()
  }
  @objc private func connect() {
    guard login == nil else { return }
    guard let client else {
      message = "先に認証ファイルを選んでください。"
      updateSettings()
      return
    }
    clearTasks()
    account = .disconnected
    events = []
    updated = nil
    render()
    let captured = generation
    let login = GoogleLogin()
    self.login = login
    message = nil
    updateSettings()
    Task {
      do {
        let credentials = try await login.connect(client)
        guard generation == captured else { return }
        try CredentialStore.save(credentials)
        self.client = credentials
        account = .connected(credentials)
        message = nil
      } catch {
        guard generation == captured else { return }
        message =
          (error as? GoogleError)?.localizedDescription
          ?? GoogleError.requestFailed.localizedDescription
      }
      self.login = nil
      refresh()
      updateSettings()
    }
  }
  private func clearTasks() {
    generation += 1
    refreshTask?.cancel()
    refreshTask = nil
    login?.cancel()
    login = nil
  }
  @objc private func disconnect() {
    do { try CredentialStore.delete() } catch {
      message = "認証情報を削除できませんでした。"
      updateSettings()
      return
    }
    clearTasks()
    client = nil
    account = .disconnected
    events = []
    updated = nil
    message = nil
    render()
    updateSettings()
  }
  private func demoEvents() -> [CalendarEvent] {
    let day = Calendar.current.startOfDay(for: Date())
    let now = Date()
    let iso = ISO8601DateFormatter()
    let intervals = [
      (day.addingTimeInterval(3600), day.addingTimeInterval(5400), "チーム朝会"),
      (now.addingTimeInterval(-600), now.addingTimeInterval(1200), "製品レビュー"),
      (now.addingTimeInterval(2400), now.addingTimeInterval(4200), "開発相談"),
    ]
    let objects: [[String: Any]] = intervals.enumerated().map { index, value in
      [
        "id": "demo-\(index)", "summary": value.2, "start": ["dateTime": iso.string(from: value.0)],
        "end": ["dateTime": iso.string(from: value.1)],
        "htmlLink": "https://calendar.google.com/calendar/",
        "hangoutLink": "https://meet.google.com/",
      ]
    }
    return
      (try? JSONDecoder().decode(
        [CalendarEvent].self, from: JSONSerialization.data(withJSONObject: objects))) ?? []
  }
}
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--import-credentials") {
  guard arguments.indices.contains(index + 1) else {
    fputs("Credential file required.\n", stderr)
    exit(1)
  }
  do {
    let url = URL(fileURLWithPath: arguments[index + 1])
    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 65536 else {
      throw GoogleError.invalidCredentials
    }
    try CredentialStore.save(GoogleCredentials.importing(Data(contentsOf: url)))
  } catch {
    fputs("Credential import failed.\n", stderr)
    exit(1)
  }
}
if arguments.contains("--check-live") {
  Task {
    do {
      guard let credentials = try CredentialStore.load() else {
        throw GoogleError.invalidCredentials
      }
      let events = try await GoogleCalendarAPI().events(credentials: credentials)
      let agenda = Agenda(events: events, now: Date())
      print("Google Calendar API OK. Timed events: \(agenda.entries.count)")
      let canonical = agenda.entries.map { entry in
        [
          "id": entry.event.id, "summary": entry.event.summary ?? "(無題)",
          "start": entry.event.start?.dateTime ?? "", "end": entry.event.end?.dateTime ?? "",
          "meet": entry.event.hangoutLink ?? "", "calendar": entry.event.htmlLink ?? "",
        ]
      }
      let data = try JSONSerialization.data(
        withJSONObject: canonical, options: [.sortedKeys, .withoutEscapingSlashes])
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      print("Agenda SHA256: \(digest)")
      exit(0)
    } catch {
      let detail = (error as? GoogleError)?.localizedDescription
          ?? "System error: \((error as NSError).domain) \((error as NSError).code)"
        fputs("Google Calendar API check failed. \(detail)\n", stderr)
      exit(1)
    }
  }
  dispatchMain()
}
MainActor.assumeIsolated {
  let app = NSApplication.shared
  let controller = AppController()
  app.delegate = controller
  app.run()
}
