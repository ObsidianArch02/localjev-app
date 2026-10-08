import AppKit

final class LogWindowController: NSObject, NSWindowDelegate {
  private let server: ServerController
  private let textView = NSTextView()

  init(server: ServerController) {
    self.server = server
    super.init()

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "LocalJev Logs"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = buildContentView()
    self.window = window

    server.onLogsChange = { [weak self] lines in
      DispatchQueue.main.async {
        self?.render(lines: lines)
      }
    }
  }

  private var window: NSWindow? {
    didSet { window?.delegate = self }
  }

  func present() {
    render(lines: server.logLines)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }

  private func buildContentView() -> NSView {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 440))

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    textView.isEditable = false
    textView.isSelectable = true
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    scrollView.documentView = textView
    content.addSubview(scrollView)

    let revealButton = NSButton(
      title: "Show Log File in Finder",
      target: self,
      action: #selector(revealLogFile)
    )
    let clearButton = NSButton(title: "Clear Display", target: self, action: #selector(clearLogs))
    let buttonRow = NSStackView(views: [revealButton, NSView(), clearButton])
    buttonRow.spacing = 8
    buttonRow.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(buttonRow)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: content.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -8),
      buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
      buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
    ])
    return content
  }

  private func render(lines: [String]) {
    guard window?.isVisible == true else { return }
    textView.string = lines.joined(separator: "\n")
    textView.scrollToEndOfDocument(nil)
  }

  @objc private func revealLogFile() {
    NSWorkspace.shared.selectFile(
      ServerController.logFileURL.path,
      inFileViewerRootedAtPath: ""
    )
  }

  @objc private func clearLogs() {
    server.clearLogs()
  }
}
