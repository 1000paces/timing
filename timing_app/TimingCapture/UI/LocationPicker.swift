import SwiftUI
import UIKit

// "Where is this phone?" — the finish, or a checkpoint on the course.
struct LocationPicker: View {
    let roster: Roster?
    let current: String?
    var onPick: (String?) -> Void

    var body: some View {
        NavigationStack {
            List {
                row(id: nil, name: "Finish")
                ForEach(roster?.checkpoints ?? [], id: \.id) { row(id: $0.id, name: $0.name) }
            }
            .navigationTitle("Where is this phone?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func row(id: String?, name: String) -> some View {
        Button { onPick(id) } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if id == current { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}

// The system share sheet, for the exported log.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
