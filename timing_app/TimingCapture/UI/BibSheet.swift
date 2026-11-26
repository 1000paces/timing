import SwiftUI

// Correct a crossing's bib with the same keypad: a big number, who that bib is,
// and Save where Enter sits on the main screen.
struct BibSheet: View {
    let row: Row
    let racerFor: (String) -> (name: String, race: String?)?
    let rosterLoaded: Bool
    let now: () -> Double
    var onCancel: () -> Void
    var onSave: (String) -> Void

    @State private var value: String
    @State private var touched = false // the current bib shows dimmed; the first digit typed replaces it
    @Environment(\.verticalSizeClass) private var vertical

    init(row: Row, racerFor: @escaping (String) -> (name: String, race: String?)?, rosterLoaded: Bool, now: @escaping () -> Double,
         onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.row = row
        self.racerFor = racerFor
        self.rosterLoaded = rosterLoaded
        self.now = now
        self.onCancel = onCancel
        self.onSave = onSave
        _value = State(initialValue: row.bib ?? "")
    }

    private var typed: String { value.trimmingCharacters(in: .whitespaces) }
    private var wide: Bool { vertical == .compact } // a phone in landscape

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Correct bib").font(.headline)
                Spacer()
                Button(action: onCancel) { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
            }
            if wide {
                HStack(spacing: 16) {
                    number.frame(maxWidth: .infinity)
                    keypad.frame(maxWidth: .infinity)
                }
            } else {
                number.padding(.vertical)
                keypad
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bib-sheet")
        .presentationDetents(wide ? [.large] : [.medium, .large])
    }

    private var number: some View {
        VStack(spacing: 6) {
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: wide ? 88 : 72, weight: .bold))
                .tracking(4)
                .foregroundStyle(touched ? .primary : .tertiary)
                .accessibilityIdentifier("sheet-bib")
            racerLine
            if let was = row.bib, was != typed {
                Text("was \(was)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var racerLine: some View {
        if typed.isEmpty {
            Text("Type the bib").foregroundStyle(.secondary)
        } else if let racer = racerFor(typed) {
            Text([racer.name, racer.race].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1)
        } else if rosterLoaded {
            Text("Unknown bib").foregroundStyle(.red)
        } else {
            Text("No roster yet").foregroundStyle(.secondary)
        }
    }

    private var keypad: some View {
        Keypad(enterLabel: "Save", compact: wide, now: now,
               onDigit: { digit in
                   value = String(((touched ? value : "") + digit).prefix(6))
                   touched = true
               },
               onBack: {
                   if !value.isEmpty { value.removeLast() }
                   touched = true
               },
               onEnter: { _ in if !typed.isEmpty { onSave(typed) } })
    }
}
