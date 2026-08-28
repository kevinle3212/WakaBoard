import Foundation

/// A narrow boundary that makes HTTP behavior deterministic in tests.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed HTTP client that exposes only validated HTTP responses.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WakaTimeError.transport }
            return (data, http)
        } catch is CancellationError { throw CancellationError() }
        catch { throw WakaTimeError.transport }
    }
}

/// Errors are safe to display as coarse recovery states and never contain request secrets or bodies.
public enum WakaTimeError: Error, Equatable, Sendable {
    case invalidEndpoint
    case unauthenticated
    case forbidden
    case unavailable
    case rateLimited(retryAfter: TimeInterval?)
    case serviceUnavailable
    case transport
    case decoding
}

/// Typed read-only WakaTime API endpoint construction.
public enum WakaTimeEndpoint: Sendable {
    case currentUser
    case summaries(ActivityRange)
    case stats(String)
    case projects

    public func request(baseURL: URL = URL(string: "https://wakatime.com")!, authorization: String) throws -> URLRequest {
        guard baseURL.scheme == "https", baseURL.host == "wakatime.com", !authorization.isEmpty else { throw WakaTimeError.invalidEndpoint }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        switch self {
        case .currentUser: components?.path = "/api/v1/users/current"
        case .projects: components?.path = "/api/v1/users/current/projects"
        case .stats(let range):
            guard range.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { throw WakaTimeError.invalidEndpoint }
            components?.path = "/api/v1/users/current/stats/\(range)"
        case .summaries(let range):
            components?.path = "/api/v1/users/current/summaries"
            let dates = range.queryDates()
            components?.queryItems = [URLQueryItem(name: "start", value: dates.start), URLQueryItem(name: "end", value: dates.end)]
        }
        guard let url = components?.url else { throw WakaTimeError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Basic \(authorization)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// The parts of the summaries response needed at the repository boundary.
public struct WakaTimeSummariesResponse: Decodable, Sendable {
    public let data: [WakaTimeSummaryDay]
}

public struct WakaTimeSummaryDay: Decodable, Sendable {
    public let range: WakaTimeRange
    public let grandTotal: WakaTimeDuration
    public let projects: [WakaTimeNamedDuration]
    public let languages: [WakaTimeNamedDuration]

    enum CodingKeys: String, CodingKey { case range; case grandTotal = "grand_total"; case projects; case languages }
}

public struct WakaTimeRange: Decodable, Sendable { public let date: String }
public struct WakaTimeDuration: Decodable, Sendable { public let totalSeconds: Double; enum CodingKeys: String, CodingKey { case totalSeconds = "total_seconds" } }
public struct WakaTimeNamedDuration: Decodable, Sendable { public let name: String; public let totalSeconds: Double; enum CodingKeys: String, CodingKey { case name; case totalSeconds = "total_seconds" } }

public extension WakaTimeSummariesResponse {
    func normalized(calendar: Calendar = .current, timeZone: TimeZone) throws -> [ActivityDay] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return try data.map { item in
            guard let date = formatter.date(from: item.range.date) else { throw WakaTimeError.decoding }
            return ActivityDay(date: date, duration: item.grandTotal.totalSeconds, projects: item.projects.map { Usage(name: $0.name, duration: $0.totalSeconds) }, languages: item.languages.map { Usage(name: $0.name, duration: $0.totalSeconds) })
        }
    }
}

/// Reads typed WakaTime endpoints and maps protocol/HTTP/decoder failures safely.
public struct WakaTimeClient: Sendable {
    private let http: any HTTPClient
    private let decoder: JSONDecoder

    public init(http: any HTTPClient = URLSessionHTTPClient(), decoder: JSONDecoder = JSONDecoder()) {
        self.http = http
        self.decoder = decoder
    }

    public func summaries(range: ActivityRange, authorization: String, timeZone: TimeZone) async throws -> [ActivityDay] {
        let request = try WakaTimeEndpoint.summaries(range).request(authorization: authorization)
        let (data, response) = try await http.data(for: request)
        try map(response: response)
        do { return try decoder.decode(WakaTimeSummariesResponse.self, from: data).normalized(timeZone: timeZone) }
        catch let error as WakaTimeError { throw error }
        catch { throw WakaTimeError.decoding }
    }

    private func map(response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200 ... 299: return
        case 401: throw WakaTimeError.unauthenticated
        case 403: throw WakaTimeError.forbidden
        case 404: throw WakaTimeError.unavailable
        case 429: throw WakaTimeError.rateLimited(retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        case 500 ... 599: throw WakaTimeError.serviceUnavailable
        default: throw WakaTimeError.transport
        }
    }
}
