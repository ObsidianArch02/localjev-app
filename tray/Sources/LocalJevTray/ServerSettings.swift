import Foundation

struct ServerSettings: Codable, Equatable {
  var port: Int = 8080
  var upstream: String = "http://127.0.0.1:8000"
  var upstreamApiKey: String = ""
  var upstreamModel: String = "clef-flash"
  var apiKey: String = ""
  var startOnLaunch: Bool = true
}

final class SettingsStore {
  private static let storageKey = "serverSettings"

  var settings: ServerSettings {
    didSet { save() }
  }

  init() {
    if
      let data = UserDefaults.standard.data(forKey: Self.storageKey),
      let decoded = try? JSONDecoder().decode(ServerSettings.self, from: data)
    {
      settings = decoded
      return
    }
    // First run: seed from the environment when LOCALJEV_* is exported (dev convenience).
    let env = ProcessInfo.processInfo.environment
    var seeded = ServerSettings()
    if let raw = env["LOCALJEV_PORT"], let port = Int(raw) {
      seeded.port = port
    }
    if let value = env["LOCALJEV_UPSTREAM"], !value.isEmpty {
      seeded.upstream = value
    }
    if let value = env["LOCALJEV_UPSTREAM_API_KEY"] {
      seeded.upstreamApiKey = value
    }
    if let value = env["LOCALJEV_UPSTREAM_MODEL"], !value.isEmpty {
      seeded.upstreamModel = value
    }
    if let value = env["LOCALJEV_API_KEY"] {
      seeded.apiKey = value
    }
    settings = seeded
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    UserDefaults.standard.set(data, forKey: Self.storageKey)
  }
}
