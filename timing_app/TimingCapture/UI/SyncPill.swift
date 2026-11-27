import SwiftUI

// Green synced, orange sending, red offline or stopped; plus the clock.
struct SyncPill: View {
    let state: SyncState

    var body: some View {
        HStack(spacing: 6) {
            Label(syncLabel(state), systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.18)))
                .foregroundStyle(color)
                .accessibilityIdentifier("sync-pill")
            Image(systemName: state.clockSynced ? "timer" : "timer.slash")
                .foregroundStyle(state.clockSynced ? .green : .orange)
                .accessibilityLabel(state.clockSynced ? "Clock synced" : "Clock not synced")
        }
        .labelStyle(.titleAndIcon)
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
