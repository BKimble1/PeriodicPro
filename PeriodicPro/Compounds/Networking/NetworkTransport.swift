import Foundation

/// The one seam between the app and the network.
///
/// `PubChemClient` speaks to this and nothing else, so the parser tests run
/// against fixtures through a stub transport and never reach the internet,
/// and UI tests can serve canned answers offline.
protocol NetworkTransport: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real thing: a `URLSession` with short timeouts and no caching of its
/// own, since the app keeps its own compound cache.
struct URLSessionTransport: NetworkTransport {
    let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 30
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PubChemError.malformed("The response was not an HTTP response.")
        }
        return (data, http)
    }
}

/// Serves canned responses by URL, for tests.
///
/// Each route matches a substring of the request's path and query (so a 3D
/// record request, `…/JSON?record_type=3d`, can be told from the 2D fallback
/// at the same path); the first match wins. An unmatched request is answered
/// like an offline device, so a test that forgets a route fails visibly
/// rather than reaching the network.
final class StubTransport: NetworkTransport, @unchecked Sendable {
    struct Route: Sendable {
        let pathContains: String
        let status: Int
        let body: Data
        let headers: [String: String]

        init(pathContains: String, status: Int = 200, body: Data, headers: [String: String] = [:]) {
            self.pathContains = pathContains
            self.status = status
            self.body = body
            self.headers = headers
        }
    }

    private let lock = NSLock()
    private var routes: [Route]
    private(set) var requestedPaths: [String] = []
    /// Optional delay per request, to exercise cancellation and debouncing.
    var latency: Duration = .zero

    init(routes: [Route] = []) {
        self.routes = routes
    }

    func add(_ route: Route) {
        lock.lock()
        routes.append(route)
        lock.unlock()
    }

    /// Records the request and finds its route, under the lock, in a
    /// synchronous helper: taking an `NSLock` inside an async function is an
    /// error in the Swift 6 language mode.
    private func route(for path: String) -> Route? {
        lock.lock()
        defer { lock.unlock() }
        requestedPaths.append(path)
        return routes.first { path.contains($0.pathContains) }
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
        try Task.checkCancellation()
        let path = (request.url?.path ?? "") + (request.url?.query.map { "?" + $0 } ?? "")
        guard let route = route(for: path), let url = request.url else {
            throw URLError(.notConnectedToInternet)
        }
        guard let response = HTTPURLResponse(
            url: url, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: route.headers
        ) else {
            throw PubChemError.malformed("Could not build a stub response.")
        }
        return (route.body, response)
    }
}
