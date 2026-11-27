import SwiftUI
import UIKit

// Hardware-keyboard input for the capture screen: digits, Delete, Return, read
// on key-down (Return's moment is the crossing time). Stays first responder
// while enabled.
struct KeyCatcher: UIViewRepresentable {
    var enabled: Bool
    var onDigit: (String) -> Void
    var onDelete: () -> Void
    var onReturn: () -> Void

    func makeUIView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: KeyCatcherView, context: Context) {
        view.handlers = enabled ? (onDigit, onDelete, onReturn) : nil
        if enabled && !view.isFirstResponder { DispatchQueue.main.async { view.becomeFirstResponder() } }
    }
}

final class KeyCatcherView: UIView {
    var handlers: (digit: (String) -> Void, delete: () -> Void, enter: () -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    // Delete and Return are claimed by the system (SwiftUI's own key commands)
    // before pressesBegan sees them, so they are key commands here, with priority.
    override var keyCommands: [UIKeyCommand]? {
        guard handlers != nil else { return nil }
        return [UIKeyCommand.inputDelete, "\r"].map { input in
            let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(keyCommand(_:)))
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func keyCommand(_ command: UIKeyCommand) {
        if command.input == "\r" { handlers?.enter() } else { handlers?.delete() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let handlers, let key = press.key, key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else {
                unhandled.insert(press)
                continue
            }
            let c = key.charactersIgnoringModifiers
            if key.keyCode == .keyboardReturnOrEnter || key.keyCode == .keypadEnter || c == "\r" || c == "\n" {
                handlers.enter()
            } else if key.keyCode == .keyboardDeleteOrBackspace || c == "\u{8}" || c == "\u{7f}" {
                handlers.delete()
            } else if c.count == 1, let ch = c.first, ch.isASCII, ch.isNumber {
                handlers.digit(c)
            } else {
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
}
