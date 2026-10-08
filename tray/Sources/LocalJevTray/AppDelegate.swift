import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  let store = SettingsStore()
  let server = ServerController()

  private var statusItem: NSStatusItem!
  private var statusMenuItem: NSMenuItem!
  private var addressMenuItem: NSMenuItem!
  private var startStopMenuItem: NSMenuItem!
  private var settingsWindowController: SettingsWindowController!
  private var logWindowController: LogWindowController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    settingsWindowController = SettingsWindowController(store: store, server: server)
    logWindowController = LogWindowController(server: server)
    server.onStateChange = { [weak self] _ in self?.refreshStatusPresentation() }
    buildStatusItem()
    refreshStatusPresentation()
    if store.settings.startOnLaunch {
      server.start(settings: store.settings)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    server.stopSync()
  }

  // MARK: - Status item

  private func buildStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    let menu = NSMenu()
    menu.autoenablesItems = false

    statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    statusMenuItem.isEnabled = false
    menu.addItem(statusMenuItem)

    addressMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    addressMenuItem.isEnabled = false
    menu.addItem(addressMenuItem)

    menu.addItem(.separator())

    startStopMenuItem = NSMenuItem(
      title: "Start Server",
      action: #selector(toggleServer),
      keyEquivalent: ""
    )
    menu.addItem(startStopMenuItem)

    menu.addItem(.separator())

    let logItem = NSMenuItem(
      title: "Logs...",
      action: #selector(openLogs),
      keyEquivalent: "l"
    )
    logItem.keyEquivalentModifierMask = [.command]
    menu.addItem(logItem)

    let settingsItem = NSMenuItem(
      title: "Settings...",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.keyEquivalentModifierMask = [.command]
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit LocalJev",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(quitItem)

    statusItem.menu = menu
  }

  private func refreshStatusPresentation() {
    let color: NSColor
    switch server.state {
    case .stopped:
      color = .secondaryLabelColor
    case .starting:
      color = .systemYellow
    case .running(let ready):
      color = ready ? .systemGreen : .systemOrange
    case .failed:
      color = .systemRed
    }

    let title = NSMutableAttributedString(
      string: "● ",
      attributes: [
        .foregroundColor: color,
        .font: NSFont.systemFont(ofSize: 13),
      ]
    )
    title.append(
      NSAttributedString(
        string: "LocalJev",
        attributes: [
          .foregroundColor: NSColor.labelColor,
          .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        ]
      )
    )
    statusItem.button?.attributedTitle = title

    statusMenuItem.title = "LocalJev: \(server.state.label)"
    let running = server.state.isRunning
    addressMenuItem.title = "http://127.0.0.1:\(store.settings.port)"
    addressMenuItem.isHidden = !running
    startStopMenuItem.title = running ? "Stop Server" : "Start Server"
    startStopMenuItem.isEnabled = server.state != .starting
  }

  // MARK: - Actions

  @objc private func toggleServer() {
    if server.state.isRunning {
      server.stop()
    } else {
      server.start(settings: store.settings)
    }
  }

  @objc private func openSettings() {
    settingsWindowController.present()
  }

  @objc private func openLogs() {
    logWindowController.present()
  }
}
