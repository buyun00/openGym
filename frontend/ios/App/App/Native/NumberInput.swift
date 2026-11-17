import SwiftUI
import UIKit

struct ReplacingNumberField: UIViewRepresentable {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType
    var centered: Bool
    var autofocus: Bool
    var editingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .decimalPad,
         centered: Bool = false, autofocus: Bool = false, editingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.title = title
        _text = text
        self.keyboard = keyboard
        self.centered = centered
        self.autofocus = autofocus
        self.editingChanged = editingChanged
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field: UITextField = autofocus ? AutofocusTextField() : UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.keyboardType = keyboard
        field.returnKeyType = .done
        field.textColor = .label
        field.textAlignment = centered ? .center : .natural
        field.font = centered
            ? UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .monospacedDigitSystemFont(ofSize: 15, weight: .regular))
            : .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.adjustsFontSizeToFitWidth = centered
        field.minimumFontSize = 12
        field.clearButtonMode = centered ? .never : .whileEditing

        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "完成", image: nil, primaryAction: UIAction { [weak field] _ in
                field?.resignFirstResponder()
            }, menu: nil)
        ]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        field.placeholder = centered ? "—" : title
        field.accessibilityLabel = title
        if field.text != text { field.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? (centered ? 50 : 160)
        return CGSize(width: width, height: max(44, uiView.intrinsicContentSize.height))
    }

    private final class AutofocusTextField: UITextField {
        private var requestedFocus = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !requestedFocus else { return }
            requestedFocus = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ReplacingNumberField
        private var replaceOnFirstEdit = false

        init(_ parent: ReplacingNumberField) { self.parent = parent }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            replaceOnFirstEdit = true
            textField.selectedTextRange = textField.textRange(
                from: textField.beginningOfDocument, to: textField.endOfDocument
            )
            parent.editingChanged(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            replaceOnFirstEdit = false
            parent.editingChanged(false)
        }

        func textField(_ textField: UITextField, shouldChangeCharactersInRanges ranges: [NSValue],
                       replacementString string: String) -> Bool {
            allowChange(in: textField, replacement: string)
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            allowChange(in: textField, replacement: string)
        }

        private func allowChange(in textField: UITextField, replacement: String) -> Bool {
            guard replaceOnFirstEdit else { return true }
            replaceOnFirstEdit = false
            guard let current = textField.text, !current.isEmpty else { return true }

            // The initial tap can move the cursor after focus begins. Use the new input
            // as the full value even if UIKit proposes changing only the caret range.
            textField.text = replacement
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
            textField.sendActions(for: .editingChanged)
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
    }
}

struct NumberStepButton: View {
    var symbol: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct NumberStepper: View {
    var title: String
    var value: Double?
    var bounds: ClosedRange<Double>
    var step: Double = 1
    var keyboard: UIKeyboardType = .decimalPad
    var changed: (Double?) -> Void
    @State private var draft = ""
    @State private var editing = false
    @ScaledMetric(relativeTo: .subheadline) private var fieldWidth: CGFloat = 50

    private var formatted: String { value.map(formatKg) ?? "" }

    var body: some View {
        HStack(spacing: 0) {
            NumberStepButton(symbol: "minus", label: "减少\(title)") { adjust(by: -step) }
                .disabled((value ?? bounds.lowerBound) <= bounds.lowerBound)
            ReplacingNumberField(title, text: Binding(get: { editing ? draft : formatted }, set: edit),
                                 keyboard: keyboard, centered: true) { isEditing in
                if isEditing { draft = formatted }
                editing = isEditing
            }
            .frame(minWidth: min(fieldWidth, 90), maxWidth: .infinity, minHeight: 44)
            NumberStepButton(symbol: "plus", label: "增加\(title)") { adjust(by: step) }
                .disabled((value ?? bounds.lowerBound) >= bounds.upperBound)
        }
        .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(editing ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: editing ? 1.5 : 0.5)
                .allowsHitTesting(false)
        }
    }

    private func edit(_ text: String) {
        draft = text
        applyNumberInput(text) { changed($0.map(bounded)) }
    }

    private func adjust(by delta: Double) {
        let next = bounded((value ?? 0) + delta)
        draft = formatKg(next)
        changed(next)
    }

    private func bounded(_ number: Double) -> Double {
        min(bounds.upperBound, max(bounds.lowerBound, number))
    }
}

func applyNumberInput(_ text: String, changed: (Double?) -> Void) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    if normalized.isEmpty { changed(nil) }
    else if let number = Double(normalized), number.isFinite { changed(number) }
}
