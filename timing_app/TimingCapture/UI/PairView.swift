import SwiftUI

struct PairView: View {
    @Bindable var model: AppModel
    @State private var address = ""
    @State private var code = ""
    @State private var name = ""
    @State private var unsent = 0
    @State private var confirmed = false
    @State private var exported: URL?

    private var blocked: Bool { unsent > 0 && !confirmed }

    var body: some View {
        NavigationStack {
            Form {
                if unsent > 0 {
                    Section {
                        Label("\(unsent) crossing\(unsent == 1 ? "" : "s") on this phone haven't reached the hub. Export the log and give it to an official before pairing again. The old log stays on this phone either way.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Export log") {
                            Task {
                                do { exported = try await model.exportURL() } catch { model.error = error.localizedDescription }
                            }
                        }
                        Button("Pair anyway") { confirmed = true }.disabled(confirmed)
                    }
                }
                Section {
                    Text("On the console: Capture (or Event) → Phones → Pair a phone. Scan the QR code, or type the code shown under it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Hub") {
                    TextField("Hub address", text: $address, prompt: Text("192.168.1.10"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("hub-address")
                    TextField("Pairing code", text: $code, prompt: Text("K7Q-4MX"))
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .tracking(4)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: code) { _, value in if value != value.uppercased() { code = value.uppercased() } }
                        .accessibilityIdentifier("pairing-code")
                }
                Section("This phone") {
                    TextField("Phone name", text: $name, prompt: Text("e.g. Finish line phone 2"))
                        .accessibilityIdentifier("phone-name")
                }
                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await model.pair(address: address, code: code, name: name) }
                    } label: {
                        HStack {
                            Spacer()
                            if model.pairBusy { ProgressView() } else { Text("Pair").bold() }
                            Spacer()
                        }
                    }
                    .disabled(model.pairBusy || blocked || (code.trimmingCharacters(in: .whitespaces).isEmpty && HubAddress.parse(address)?.code == nil))
                    .accessibilityIdentifier("pair")
                    if model.pairing != nil {
                        Button("Back to capture") { model.pairingAgain = false }.frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Pair this phone")
            .sheet(item: $exported) { url in ShareSheet(url: url) }
            .task {
                name = model.pairing?.name ?? name
                unsent = await model.unsentCount()
            }
        }
    }
}
