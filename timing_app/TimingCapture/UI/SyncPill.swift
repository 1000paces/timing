import SwiftUI

// Green synced, orange sending, red offline or stopped; plus the clock.
// Synced is the icon alone (the top bar is tight); the other states keep their words,
// since they carry the count still to send. VoiceOver and the UI tests read the label.
struct SyncPill: View {
    let state: SyncState

    var body: some View {
        let text = syncLabel(state)
        HStack(spacing: 6) {
            Label(text, systemImage: icon)
                .labelStyle(PillLabelStyle(iconOnly: text == "Synced"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.18)))
                .foregroundStyle(color)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
                .accessibilityIdentifier("sync-pill")
            Image(systemName: state.clockSynced ? "timer" : "timer.slash")
                .foregroundStyle(state.clockSynced ? .green : .orange)
                .accessibilityLabel(state.clockSynced ? "Clock synced" : "Clock not synced")
        }
    }

    private var color: Color {
        if state.stopped || state.revoked || !state.online { return .red }
        if state.pending > 0 { return .orange }
        return state.contacted ? .green : .secondary
    }

    private var icon: String {
        if state.stopped || state.revoked { return "exclamationmark.octagon.fill" }
        if !state.online { return "icloud.slash" }
        if state.pending > 0 { return "icloud.and.arrow.up" }
        return "checkmark.icloud"
    }
}

private struct PillLabelStyle: LabelStyle {
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly { configuration.icon } else { Label(configuration).labelStyle(.titleAndIcon) }
    }
}
