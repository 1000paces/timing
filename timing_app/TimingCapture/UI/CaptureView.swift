import SwiftUI

struct CaptureView: View {
    static let page = 20

    @Bindable var model: AppModel
    @State private var shown = CaptureView.page
    @State private var onlyBib: String?
    @State private var editing: Row?
    @State private var deleting: Row?

    private var state: SyncState { model.sync?.state ?? SyncState() }

    private var rows: [Row] { captureRows(model.entries, roster: state.roster, status: state.status, ackSeq: state.ackSeq) }

    private func racerFor(_ bib: String) -> (name: String, race: String?)? {
        guard let roster = state.roster, let racer = roster.racers.first(where: { $0.bib == bib }) else { return nil }
        return (racer.name, roster.event.races.first { $0.id == racer.race_id }?.name)
    }

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
            crossingLog
        }
        .background(model.flash ? Color.green.opacity(0.35) : Color(.systemBackground))
        .animation(.easeOut(duration: 0.15), value: model.flash)
        .sheet(item: $editing) { row in
            BibSheet(row: row, racerFor: racerFor, rosterLoaded: state.roster != nil, now: { model.tapClock.nowMs() },
                     onCancel: { editing = nil },
                     onSave: { bib in
                         editing = nil
                         guard bib != row.bib else { return }
                         Task { await model.correct(rowId: row.id, bib: bib) }
                     })
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { row in
            Button("Delete", role: .destructive) { Task { await model.remove(rowId: row.id) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deleteTitle: String {
        guard let row = deleting else { return "" }
        let what = row.bib.map { "bib \($0)" } ?? "the no-bib crossing"
        return "Delete \(what) at \(formatClock(row.atMs + (state.offsetMs ?? 0)))?"
    }

    private var crossingLog: some View {
        let visible = onlyBib.map { bib in rows.filter { $0.bib == bib } } ?? rows
        return List {
            if let onlyBib {
                Button { self.onlyBib = nil } label: {
                    Label("Bib \(onlyBib)", systemImage: "xmark.circle.fill")
                }
                .accessibilityLabel("Show all bibs")
            }
            ForEach(visible.prefix(shown)) { row in
                CrossingRow(row: row, offsetMs: state.offsetMs ?? 0,
                            onFilter: { onlyBib = row.bib }, onEdit: { editing = row }, onDelete: { deleting = row })
            }
            if visible.isEmpty {
                Text("No crossings yet.").foregroundStyle(.secondary)
            }
            if visible.count > shown {
                Button("Show more") { shown += Self.page }.frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("crossing-log")
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
