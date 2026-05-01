import Foundation

struct ModelDownloadProxyConfiguration: Equatable, Sendable {
    let host: String
    let port: Int

    init?(host: String, port: Int) {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, (1...65_535).contains(port) else {
            return nil
        }

        self.host = normalizedHost
        self.port = port
    }

    var connectionProxyDictionary: [AnyHashable: Any] {
        [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: host,
            kCFNetworkProxiesHTTPSPort as String: port
        ]
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self? {
        let proxyValue = [
            "https_proxy",
            "HTTPS_PROXY",
            "http_proxy",
            "HTTP_PROXY"
        ]
            .compactMap { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let proxyValue else { return nil }
        return fromProxyURLString(proxyValue)
    }

    private static func fromProxyURLString(_ value: String) -> Self? {
        let urlString = value.contains("://") ? value : "http://\(value)"
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host else {
            return nil
        }

        let port = components.port ?? (scheme == "https" ? 443 : 80)
        return Self(host: host, port: port)
    }
}
