import AppKit

/// Non-editable, non-bezeled text field (the modern `NSTextField(label:)` equivalent).
private func makeLabel(_ text: String) -> NSTextField {
  let field = NSTextField(string: text)
  field.isEditable = false
  field.isBezeled = false
  field.drawsBackground = false
  field.backgroundColor = .clear
  return field
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
  private let store: SettingsStore
  private let server: ServerController

  private var portField = NSTextField()
  private var listenLabel = NSTextField()
  private var launchCheckbox = NSButton()
  private var upstreamField = NSTextField()
  private var upstreamKeyField = NSSecureTextField()
  private var modelField = NSTextField()
  private var apiKeyField = NSSecureTextField()
  private var errorLabel = NSTextField()

  init(store: SettingsStore, server: ServerController) {
    self.store = store
    self.server = server
    super.init()

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 580, height: 400),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    panel.title = "LocalJev Settings"
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    panel.contentView = buildContentView()
    self.window = panel
  }

  private var window: NSWindow? {
    didSet { window?.delegate = self }
  }

  func present() {
    loadFields(from: store.settings)
    window.map { centerIfNeeded($0) }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func centerIfNeeded(_ window: NSWindow) {
    if window.frame.origin == .zero {
      window.center()
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }

  // MARK: - Layout

  private func sectionLabel(_ text: String) -> NSTextField {
    let field = makeLabel(text)
    field.font = .systemFont(ofSize: 13, weight: .semibold)
    return field
  }

  private func buildContentView() -> NSView {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 400))

    portField = NSTextField()
    portField.placeholderString = "8080"
    portField.frame = NSRect(x: 0, y: 0, width: 90, height: 24)

    listenLabel = makeLabel("")
    listenLabel.font = .systemFont(ofSize: 11)
    listenLabel.textColor = .secondaryLabelColor

    launchCheckbox = NSButton(checkboxWithTitle: "Start server when the app launches", target: nil, action: nil)

    upstreamField = NSTextField()
    upstreamField.placeholderString = "http://127.0.0.1:8000"
    upstreamField.frame = NSRect(x: 0, y: 0, width: 420, height: 24)

    upstreamKeyField = NSSecureTextField()
    upstreamKeyField.placeholderString = "oMLX API Key"
    upstreamKeyField.frame = NSRect(x: 0, y: 0, width: 420, height: 24)

    modelField = NSTextField()
    modelField.placeholderString = "clef-flash"
    modelField.frame = NSRect(x: 0, y: 0, width: 420, height: 24)

    apiKeyField = NSSecureTextField()
    apiKeyField.placeholderString = "LocalJev API key (optional, leave empty to disable authentication)"
    apiKeyField.frame = NSRect(x: 0, y: 0, width: 420, height: 24)

    errorLabel = makeLabel("")
    errorLabel.font = .systemFont(ofSize: 11)
    errorLabel.textColor = .systemRed

    let portRow = NSStackView(views: [makeLabel("Port"), portField])
    portRow.alignment = .centerY
    portRow.spacing = 8

    let column = NSStackView(views: [
      sectionLabel("Server"),
      portRow,
      listenLabel,
      launchCheckbox,
      NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 10)),
      sectionLabel("Upstream Inference (oMLX)"),
      upstreamField,
      upstreamKeyField,
      modelField,
      NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 10)),
      sectionLabel("Local Access"),
      apiKeyField,
      errorLabel,
    ])
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 10
    column.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(column)
    NSLayoutConstraint.activate([
      column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      column.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
      column.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
    ])

    let restoreButton = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
    let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(closePanel))
    cancelButton.keyEquivalent = "\u{1b}"
    let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
    saveButton.keyEquivalent = "\r"
    saveButton.bezelColor = .controlAccentColor

    let buttonRow = NSStackView(views: [restoreButton, NSView(), cancelButton, saveButton])
    buttonRow.spacing = 8
    buttonRow.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(buttonRow)
    NSLayoutConstraint.activate([
      buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
      buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
    ])

    portField.target = self
    portField.action = #selector(updateDerivedLabels)
    return content
  }

  // MARK: - Field binding

  private func loadFields(from settings: ServerSettings) {
    portField.stringValue = String(settings.port)
    upstreamField.stringValue = settings.upstream
    upstreamKeyField.stringValue = settings.upstreamApiKey
    modelField.stringValue = settings.upstreamModel
    apiKeyField.stringValue = settings.apiKey
    launchCheckbox.state = settings.startOnLaunch ? .on : .off
    errorLabel.stringValue = ""
    updateDerivedLabels()
  }

  @objc private func updateDerivedLabels() {
    listenLabel.stringValue = "LocalJev listens on http://127.0.0.1:\(portField.stringValue)"
  }

  @objc private func restoreDefaults() {
    loadFields(from: ServerSettings())
  }

  @objc private func closePanel() {
    window?.orderOut(nil)
  }

  @objc private func save() {
    guard let port = Int(portField.stringValue), (1...65_535).contains(port) else {
      errorLabel.stringValue = "Port must be an integer from 1 to 65535"
      return
    }
    guard !upstreamField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else {
      errorLabel.stringValue = "Upstream URL cannot be empty"
      return
    }
    let wasRunning = server.state.isRunning
    store.settings = ServerSettings(
      port: port,
      upstream: upstreamField.stringValue.trimmingCharacters(in: .whitespaces),
      upstreamApiKey: upstreamKeyField.stringValue,
      upstreamModel: modelField.stringValue.trimmingCharacters(in: .whitespaces),
      apiKey: apiKeyField.stringValue,
      startOnLaunch: launchCheckbox.state == .on
    )
    if wasRunning {
      server.restart(settings: store.settings)
    }
    window?.orderOut(nil)
  }
}
