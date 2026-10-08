import AppKit
import Foundation

enum ServerState: Equatable {
  case stopped
  case starting
  case running(ready: Bool)
  case failed(String)

  var label: String {
    switch self {
    case .stopped:
      return "Stopped"
    case .starting:
      return "Starting..."
    case .running(let ready):
      return ready ? "Ready" : "Running, upstream model not ready"
    case .failed(let message):
      return "Failed: \(message)"
    }
  }

  var isRunning: Bool {
    if case .stopped = self { return false }
    return true
  }
}

/// Owns the localjev child process. All callbacks fire on the main queue.
final class ServerController {
  private(set) var state: ServerState = .stopped {
    didSet {
      if state != oldValue { onStateChange?(state) }
    }
  }

  private(set) var logLines: [String] = [] {
    didSet { onLogsChange?(logLines) }
  }

  var onStateChange: ((ServerState) -> Void)?
  var onLogsChange: (([String]) -> Void)?

  static let logFileURL: URL = {
    let directory = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LocalJev", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("localjev.log")
  }()

  private var process: Process?
  private var monitorTimer: Timer?
  private var logFile: FileHandle?
  private var intentionalStop = false
  private var pendingStart: ServerSettings?
  private var currentPort: Int = 8080

  private var ring: [String] = []
  private let ringLock = NSLock()
  private let ringLimit = 500

  private static func bundledBinary() -> URL? {
    Bundle.main.url(forResource: "localjev", withExtension: nil)
  }

  private static func openLogFile() -> FileHandle? {
    if !FileManager.default.fileExists(atPath: logFileURL.path) {
      FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: logFileURL) else { return nil }
    handle.seekToEndOfFile()
    return handle
  }

  // MARK: - Lifecycle

  func start(settings: ServerSettings) {
    guard process == nil, let binary = Self.bundledBinary() else { return }
    intentionalStop = false
    currentPort = settings.port
    state = .starting

    let child = Process()
    child.executableURL = binary
    var env = ProcessInfo.processInfo.environment
    env["LOCALJEV_PORT"] = String(settings.port)
    env["LOCALJEV_UPSTREAM"] = settings.upstream
    env["LOCALJEV_UPSTREAM_API_KEY"] = settings.upstreamApiKey
    env["LOCALJEV_UPSTREAM_MODEL"] = settings.upstreamModel
    if settings.apiKey.isEmpty {
      env["LOCALJEV_API_KEY"] = nil
    } else {
      env["LOCALJEV_API_KEY"] = settings.apiKey
    }
    child.environment = env

    let pipe = Pipe()
    child.standardOutput = pipe
    child.standardError = pipe

    logFile = Self.openLogFile()

    setRing([])
    appendLog(
      "Starting localjev: port \(settings.port), upstream \(settings.upstream), model \(settings.upstreamModel)"
    )

    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty, let self else { return }
      self.logFile?.write(data)
      guard let text = String(data: data, encoding: .utf8) else { return }
      let lines = text
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .newlines) }
        .filter { !$0.isEmpty }
      self.ringLock.lock()
      self.ring.append(contentsOf: lines)
      if self.ring.count > self.ringLimit {
        self.ring.removeFirst(self.ring.count - self.ringLimit)
      }
      let snapshot = self.ring
      self.ringLock.unlock()
      DispatchQueue.main.async { self.logLines = snapshot }
    }

    child.terminationHandler = { [weak self] terminated in
      DispatchQueue.main.async {
        guard let self else { return }
        self.monitorTimer?.invalidate()
        self.monitorTimer = nil
        self.logFile?.closeFile()
        self.logFile = nil
        self.process = nil
        let code: String
        if terminated.terminationReason == .exit {
          code = "\(terminated.terminationStatus)"
        } else {
          code = "signal \(terminated.terminationStatus)"
        }
        if self.intentionalStop {
          self.state = .stopped
          self.appendLog("Server stopped")
        } else {
          self.state = .failed("Process exited (\(code))")
          self.appendLog("Process exited unexpectedly (\(code)). See the log above.")
        }
        if let pending = self.pendingStart {
          self.pendingStart = nil
          self.start(settings: pending)
        }
      }
    }

    do {
      try child.run()
      process = child
      monitorTimer = Timer.scheduledTimer(
        withTimeInterval: 1.5,
        repeats: true
      ) { [weak self] _ in
        self?.pollStatus()
      }
    } catch {
      state = .failed("Unable to start: \(error.localizedDescription)")
    }
  }

  func stop() {
    intentionalStop = true
    monitorTimer?.invalidate()
    monitorTimer = nil
    if let child = process, child.isRunning {
      appendLog("Stopping localjev")
      child.terminate()
    } else {
      process = nil
      logFile?.closeFile()
      logFile = nil
      state = .stopped
    }
  }

  /// Stop, then start with the new settings once the old process has exited.
  func restart(settings: ServerSettings) {
    if process == nil {
      start(settings: settings)
      return
    }
    pendingStart = settings
    stop()
  }

  /// Synchronous stop used during app termination so the child never outlives the app.
  /// Bounded busy-wait: NSTask.waitUntilExit nests a run loop that can deadlock
  /// inside NSApplication termination, so poll isRunning with a 2 s cap instead.
  func stopSync() {
    intentionalStop = true
    monitorTimer?.invalidate()
    monitorTimer = nil
    process?.terminate()
    var waited = 0
    while let child = process, child.isRunning, waited < 200 {
      usleep(10_000)
      waited += 1
    }
    process = nil
    logFile?.closeFile()
    logFile = nil
  }

  // MARK: - Logs

  func clearLogs() {
    setRing([])
    logFile?.closeFile()
    logFile = nil
    try? Data().write(to: Self.logFileURL)
    if process != nil {
      logFile = Self.openLogFile()
    }
  }

  private func setRing(_ lines: [String]) {
    ringLock.lock()
    ring = lines
    ringLock.unlock()
    logLines = lines
  }

  private func appendLog(_ line: String) {
    ringLock.lock()
    ring.append(line)
    if ring.count > ringLimit {
      ring.removeFirst(ring.count - ringLimit)
    }
    let snapshot = ring
    ringLock.unlock()
    logFile?.write(Data((line + "\n").utf8))
    logLines = snapshot
  }

  // MARK: - Status polling

  @objc private func pollStatus() {
    guard process != nil else { return }
    let probe = StatusProbe(port: currentPort)
    probe.checkHealth { [weak self] healthy in
      guard let self, self.process != nil else { return }
      if healthy {
        probe.checkReady { [weak self] ready in
          self?.state = .running(ready: ready)
        }
      } else {
        self.state = .starting
      }
    }
  }
}
