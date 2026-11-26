import Foundation

// The hub's address as a volunteer types or pastes it: a bare host ("192.168.1.10"),
// host:port, a URL, or the console's whole pairing link
// (https://<hub>:3443/capture-app/?pair=<CODE>), which also carries the code.
enum HubAddress {
    static let defaultPort = 3443

    #if DEBUG
    static let allowsHTTP = true // a dev hub on http://localhost:3000
    #else
    static let allowsHTTP = false
    #endif

    static func parse(_ input: String, allowHTTP: Bool = allowsHTTP) -> (base: URL, code: String?)? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let parts = URLComponents(string: text.contains("://") ? text : "https://\(text)"),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || (scheme == "http" && allowHTTP),
              let host = parts.host?.lowercased(), !host.isEmpty,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return nil }
        var base = URLComponents()
        base.scheme = scheme
        base.host = host
        base.port = parts.port ?? (scheme == "https" ? defaultPort : nil)
        guard let url = base.url else { return nil }
        let code = parts.queryItems?.first { $0.name == "pair" }?.value?.uppercased()
        return (url, code?.isEmpty == false ? code : nil)
    }
}
