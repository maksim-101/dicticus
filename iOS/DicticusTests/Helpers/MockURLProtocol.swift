import Foundation

/// URLProtocol mock for download tests. Supports chunked progress,
/// pause/resume via HTTP Range header, and failure injection.
///
/// Install via:
///     let cfg = URLSessionConfiguration.ephemeral
///     cfg.protocolClasses = [MockURLProtocol.self]
///     let session = URLSession(configuration: cfg, ...)
///
/// Static state is shared across instances. Always call `MockURLProtocol.reset()`
/// in `setUp()` to avoid cross-test contamination.
final class MockURLProtocol: URLProtocol {

    // Total payload served for a given URL (keyed by absoluteString).
    nonisolated(unsafe) static var responseData: [String: Data] = [:]
    // Number of chunks to split the payload into (progress simulation).
    nonisolated(unsafe) static var chunkCount: Int = 4
    // Delay between chunks in seconds.
    nonisolated(unsafe) static var chunkDelay: TimeInterval = 0.05
    // If non-nil, force a .networkConnectionLost failure after N bytes sent.
    nonisolated(unsafe) static var failAfterBytes: Int? = nil

    static func reset() {
        responseData = [:]
        chunkCount = 4
        chunkDelay = 0.05
        failAfterBytes = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let data = Self.responseData[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        // Honor Range header for resume tests — "bytes=<start>-[<end>]".
        var payload = data
        var startOffset = 0
        if let range = request.value(forHTTPHeaderField: "Range"),
           let bytesStart = range.split(separator: "=").last?.split(separator: "-").first,
           let start = Int(bytesStart),
           start >= 0, start < data.count {
            startOffset = start
            payload = data.subdata(in: start..<data.count)
        }

        let headers: [String: String] = [
            "Content-Length": "\(payload.count)",
            "Content-Range": "bytes \(startOffset)-\(data.count - 1)/\(data.count)",
            "Accept-Ranges": "bytes"
        ]
        let statusCode = startOffset > 0 ? 206 : 200
        let response = HTTPURLResponse(url: url,
                                       statusCode: statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        let chunkSize = max(1, payload.count / max(1, Self.chunkCount))
        var sent = 0
        for offset in stride(from: 0, to: payload.count, by: chunkSize) {
            if let fail = Self.failAfterBytes, sent >= fail {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
            let end = min(offset + chunkSize, payload.count)
            client?.urlProtocol(self, didLoad: payload.subdata(in: offset..<end))
            sent += (end - offset)
            Thread.sleep(forTimeInterval: Self.chunkDelay)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
