import ComputerPresence
import Foundation

final class PresenceReporter: NSObject, URLSessionTaskDelegate {
    private let activity = ComputerActivity()
    private let endpoint: URL
    private var lastSent: Bool?
    private var pending = false
    private var retryOnHeartbeat = false
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    init(endpoint: URL) {
        self.endpoint = endpoint
        super.init()
        activity.onChange = { [weak self] in
            DispatchQueue.main.async { self?.report() }
        }
    }

    func report(heartbeat: Bool = false) {
        guard !pending, heartbeat || !retryOnHeartbeat else { return }
        let active = activity.active
        guard heartbeat || active != lastSent else { return }

        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((active ? "{\"computer_active\":true}" : "{\"computer_active\":false}").utf8)
        pending = true
        session.dataTask(with: request) { [weak self] _, response, error in
            let accepted = error == nil && (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pending = false
                self.retryOnHeartbeat = !accepted
                if accepted {
                    self.lastSent = active
                    self.report()
                }
            }
        }.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

guard CommandLine.arguments.count == 2,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let config = try? JSONDecoder().decode([String: URL].self, from: data),
      let url = config["webhook"], let scheme = url.scheme,
      ["http", "https"].contains(scheme), url.host != nil, url.user == nil, url.password == nil,
      url.path.hasPrefix("/api/webhook/"), url.path.count > "/api/webhook/".count,
      url.query == nil, url.fragment == nil else {
    FileHandle.standardError.write(Data("Usage: DeskPresence <private-config.json>\n".utf8))
    exit(64)
}
let reporter = PresenceReporter(endpoint: url)
reporter.report(heartbeat: true)
Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in reporter.report(heartbeat: true) }
RunLoop.main.run()
