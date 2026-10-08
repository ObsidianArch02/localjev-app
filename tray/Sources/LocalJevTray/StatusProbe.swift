import Foundation

/// Probes the local LocalJev HTTP endpoints; all completions fire on the main queue.
struct StatusProbe {
  let port: Int

  func checkHealth(_ completion: @escaping (Bool) -> Void) {
    get("/health", expecting: "ok", completion: completion)
  }

  func checkReady(_ completion: @escaping (Bool) -> Void) {
    get("/ready", expecting: "ready", completion: completion)
  }

  private func get(
    _ path: String,
    expecting status: String,
    completion: @escaping (Bool) -> Void
  ) {
    guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
      completion(false)
      return
    }
    let task = URLSession.shared.dataTask(with: url) { data, response, _ in
      var ok = false
      if
        let data,
        let http = response as? HTTPURLResponse,
        http.statusCode == 200,
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        object["status"] as? String == status
      {
        ok = true
      }
      DispatchQueue.main.async { completion(ok) }
    }
    task.resume()
  }
}
