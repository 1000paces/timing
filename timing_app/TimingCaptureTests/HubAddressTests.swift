import Foundation
import Testing
@testable import TimingCapture

@Suite struct HubAddressTests {
    @Test(arguments: [
        ("192.168.1.5", "https://192.168.1.5:3443"),
        (" hub.local:3443 ", "https://hub.local:3443"),
        ("https://10.0.0.2", "https://10.0.0.2:3443"),
        ("https://hub.local:8443/", "https://hub.local:8443"),
        ("HUB.local", "https://hub.local:3443"),
    ])
    func typedAddresses(input: String, base: String) {
        let parsed = HubAddress.parse(input, allowHTTP: false)
        #expect(parsed?.base.absoluteString == base)
        #expect(parsed?.code == nil)
    }

    @Test func pastedPairingLink() {
        let parsed = HubAddress.parse("https://hub.local:3443/capture-app/?pair=k7q-4mx", allowHTTP: false)
        #expect(parsed?.base.absoluteString == "https://hub.local:3443")
        #expect(parsed?.code == "K7Q-4MX")
    }

    @Test func plainHTTPOnlyWhenAllowed() {
        #expect(HubAddress.parse("http://localhost:3000", allowHTTP: true)?.base.absoluteString == "http://localhost:3000")
        #expect(HubAddress.parse("http://localhost:3000", allowHTTP: false) == nil)
    }

    @Test(arguments: ["", "   ", "not a host!", "ftp://hub.local", "https://"])
    func rejectsNonsense(input: String) {
        #expect(HubAddress.parse(input, allowHTTP: true) == nil)
    }
}
