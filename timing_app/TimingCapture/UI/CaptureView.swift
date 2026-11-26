import SwiftUI

struct CaptureView: View {
    @Bindable var model: AppModel

    private var state: SyncState { model.sync?.state ?? SyncState() }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            banners
            VStack(spacing: 12) {
                bibDisplay
                Keypad(now: { model.tapClock.nowMs() }, onDigit: model.typeDigit, onBack: model.backspace,
                       onEnter: { at in Task { await model.tap(atMs: at) } })
            }
            .padding()
            Divider()
            List(model.entries.filter { $0.kind == .capture }.reversed()) { entry in
                Text(entry.bib ?? "—").bold()
            }
            .listStyle(.plain)
            .accessibilityIdentifier("crossing-log")
        }
        .background(model.flash ? Color.green.opacity(0.35) : Color(.systemBackground))
        .animation(.easeOut(duration: 0.15), value: model.flash)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text(state.roster?.event.name ?? "Capture").font(.headline).lineLimit(1)
            Spacer()
            SyncPill(state: state)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder private var banners: some View {
        if state.stopped {
            Banner(text: "Sync stopped — export the log (menu) and see an official.")
        }
        if state.revoked {
            Banner(text: "This phone was revoked on the hub, so new crossings can't be sent. Export the log (menu), give it to an official, and pair again.")
        }
        if let error = model.error {
            Banner(text: error) { model.error = nil }
        }
    }

    private var bibDisplay: some View {
        Group {
            if model.bib.isEmpty {
                Text("Bib (or Enter for no bib)").font(.title3).foregroundStyle(.tertiary)
            } else {
                Text(model.bib).font(.system(size: 56, weight: .bold)).tracking(4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .accessibilityIdentifier("bib-display")
    }
}

struct Banner: View {
    let text: String
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }.accessibilityLabel("Dismiss")
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(Color.red)
    }
}
