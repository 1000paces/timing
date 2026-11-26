import SwiftUI

// Big keys for gloves and cold hands; our own, so the phone's keyboard never covers the list.
// compact: shorter keys, for short (landscape) screens. fill: stretch the rows to the space given.
// onEnter gets the moment the key was touched down, not released.
struct Keypad: View {
    var enterLabel = "Enter"
    var compact = false
    var fill = false
    var now: () -> Double
    var onDigit: (String) -> Void
    var onBack: () -> Void
    var onEnter: ((Double) -> Void)?

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "enter"]]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        cell(key)
                    }
                }
            }
        }
    }

    private var height: CGFloat? { fill ? nil : compact ? 44 : 56 }

    @ViewBuilder private func cell(_ key: String) -> some View {
        switch key {
        case "⌫":
            Button(action: onBack) {
                Image(systemName: "delete.left").font(.title2).keyFace(height: height)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .accessibilityLabel("Backspace")
        case "enter":
            if let onEnter {
                EnterKey(label: enterLabel, height: height, now: now, action: onEnter)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        default:
            Button { onDigit(key) } label: {
                Text(key).font(.system(size: compact || fill ? 26 : 28, weight: .medium)).keyFace(height: height)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 10))
        }
    }
}

// Records on touch-down: the time a timer presses is the crossing time.
private struct EnterKey: View {
    let label: String
    let height: CGFloat?
    let now: () -> Double
    let action: (Double) -> Void
    @State private var down = false

    var body: some View {
        Text(label)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .keyFace(height: height)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(down ? 0.7 : 1)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !down else { return }
                    down = true
                    action(now())
                }
                .onEnded { _ in down = false })
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction { action(now()) }
    }
}

private extension View {
    func keyFace(height: CGFloat?) -> some View {
        frame(maxWidth: .infinity, minHeight: height ?? 0, maxHeight: height == nil ? .infinity : height)
    }
}
