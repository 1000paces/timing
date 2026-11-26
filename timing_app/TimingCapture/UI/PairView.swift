import SwiftUI

struct PairView: View {
    @Bindable var model: AppModel
    @State private var address = ""
    @State private var code = ""
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
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
                    .disabled(model.pairBusy || (code.trimmingCharacters(in: .whitespaces).isEmpty && HubAddress.parse(address)?.code == nil))
                    .accessibilityIdentifier("pair")
                }
            }
            .navigationTitle("Pair this phone")
            .onAppear { name = model.pairing?.name ?? name }
        }
    }
}
