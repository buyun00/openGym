import SwiftUI
import UIKit

// Align the set menu and completion button with the selected number in each wheel.
private enum WorkoutInputCenter: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
}

extension VerticalAlignment {
    static let workoutInputCenter = VerticalAlignment(WorkoutInputCenter.self)
}

struct WorkoutStrengthSetList: View {
    var sets: [WorkoutSet]
    var change: (UUID, WorkoutMetric, Double?) -> Bool
    var toggle: (UUID) -> Void
    var copy: (UUID) -> Void
    var delete: (UUID) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var groupWidth: CGFloat = 74
    @State private var selectedSetID: UUID?

    private var expandedSetID: UUID? {
        if let selectedSetID, sets.contains(where: { $0.id == selectedSetID }) { return selectedSetID }
        return sets.first(where: { !$0.done })?.id
    }

    var body: some View {
        let expandedID = expandedSetID
        VStack(spacing: 0) {
            ForEach(Array(sets.enumerated()), id: \.element.id) { offset, set in
                row(set, index: offset + 1, expanded: set.id == expandedID)
                if offset + 1 < sets.count { Divider() }
            }
        }
    }

    private func row(_ set: WorkoutSet, index: Int, expanded: Bool) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    HStack {
                        menu(for: set, index: index, expanded: expanded)
                        Spacer()
                        completion(for: set, index: index)
                    }
                    HStack(alignment: .workoutInputCenter, spacing: 8) {
                        numbers(for: set, index: index, expanded: expanded)
                    }
                }
            } else {
                HStack(alignment: .workoutInputCenter, spacing: 8) {
                    menu(for: set, index: index, expanded: expanded)
                        .frame(width: min(groupWidth, 90), alignment: .leading)
                    numbers(for: set, index: index, expanded: expanded)
                    completion(for: set, index: index)
                }
            }
        }
        .padding(.vertical, expanded ? 10 : 0)
        .frame(minHeight: 54)
    }

    @ViewBuilder private func numbers(for set: WorkoutSet, index: Int, expanded: Bool) -> some View {
        number(.weight, set: set, index: index, expanded: expanded, unit: "kg")
        number(.reps, set: set, index: index, expanded: expanded, unit: "次")
    }

    private func number(_ metric: WorkoutMetric, set: WorkoutSet, index: Int, expanded: Bool, unit: String) -> some View {
        let value = metric.value(in: set) ?? 0
        let formatted = formatKg(value)
        let label = "第 \(index) 组\(metric.title)"
        return Group {
            if expanded {
                WorkoutSetWheel(metric: metric, value: value, label: label) { change(set.id, metric, $0) }
            } else {
                Button { selectedSetID = set.id } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatted).font(.body.weight(.semibold)).monospacedDigit()
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityValue("\(formatted) \(unit)")
            }
        }
        .frame(minWidth: 48, maxWidth: .infinity)
    }

    private func menu(for set: WorkoutSet, index: Int, expanded: Bool) -> some View {
        WorkoutSetMenu(index: index, showTitle: true, emphasized: expanded,
                       copy: { copy(set.id) }, delete: { delete(set.id) })
    }

    private func completion(for set: WorkoutSet, index: Int) -> some View {
        WorkoutSetCompletionButton(index: index, done: set.done) {
            toggle(set.id)
            if !set.done && selectedSetID == set.id { selectedSetID = nil }
        }
    }
}

struct WorkoutSetMenu: View {
    var index: Int
    var showTitle: Bool
    var emphasized = false
    var copy: () -> Void
    var delete: () -> Void

    var body: some View {
        Menu {
            Button("复制这一组", systemImage: "plus.square.on.square", action: copy)
            Button("删除这一组", systemImage: "trash", role: .destructive, action: delete)
        } label: {
            Text(showTitle ? "第 \(index) 组" : "\(index)")
                .font(emphasized ? .subheadline.weight(.semibold) : .subheadline).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
        }
        .accessibilityLabel("第 \(index) 组操作")
    }
}

struct WorkoutSetCompletionButton: View {
    var index: Int
    var done: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 28, weight: .regular))
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain).foregroundStyle(done ? Color.green : Color.secondary)
        .accessibilityLabel(done ? "取消第 \(index) 组完成" : "完成第 \(index) 组")
        .accessibilityValue(done ? "已完成" : "未完成")
    }
}

private struct WorkoutSetWheel: View {
    private static let weights = (0...Int(WorkoutMetric.weight.maximum)).map { Double($0) }
    private static let reps = (0...Int(WorkoutMetric.reps.maximum)).map { Double($0) }

    var metric: WorkoutMetric
    var value: Double
    var label: String
    var changed: (Double?) -> Bool
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 28
    @State private var draft: String?

    private var choices: [Double] {
        let wholeValues = metric == .weight ? Self.weights : Self.reps
        // Show a previously saved fractional weight exactly until the user picks a new value.
        guard value.isFinite, !wholeValues.contains(value) else { return wholeValues }
        return (wholeValues + [value]).sorted()
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(metric.title).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            WorkoutWheelPicker(choices: choices, value: value, label: label, rowHeight: rowHeight,
                               select: { changed($0) }, edit: { draft = formatKg(value) })
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight * 3)
                .allowsHitTesting(draft == nil)
                .accessibilityHidden(draft != nil)
                .overlay {
                    if draft != nil {
                        ReplacingNumberField(label, text: Binding(get: { draft ?? "" }, set: edit),
                                             keyboard: metric == .reps ? .numberPad : .decimalPad,
                                             centered: true, autofocus: true) { editing in
                            if !editing { draft = nil }
                        }
                        .frame(height: max(44, rowHeight))
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 8))
                    }
                }
                .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12))
                .clipShape(.rect(cornerRadius: 12))
                .alignmentGuide(.workoutInputCenter) { $0[VerticalAlignment.center] }
        }
    }

    private func edit(_ text: String) {
        draft = text
        applyNumberInput(text) { number in
            if !changed(number) { draft = formatKg(value) }
        }
    }
}

private struct WorkoutWheelPicker: UIViewRepresentable {
    var choices: [Double]
    var value: Double
    var label: String
    var rowHeight: CGFloat
    var select: (Double) -> Bool
    var edit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapSelection(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        picker.addGestureRecognizer(tap)
        picker.reloadAllComponents()
        showSelection(in: picker)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        let previous = context.coordinator.parent
        context.coordinator.parent = self
        picker.accessibilityLabel = label
        let reload = previous.choices != choices || previous.rowHeight != rowHeight
        if reload { picker.reloadAllComponents() }
        if reload || previous.value != value { showSelection(in: picker) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 76
        return CGSize(width: width, height: rowHeight * 3)
    }

    private func showSelection(in picker: UIPickerView) {
        let row = choices.firstIndex(of: value) ?? 0
        if picker.selectedRow(inComponent: 0) != row { picker.selectRow(row, inComponent: 0, animated: false) }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate, UIGestureRecognizerDelegate {
        var parent: WorkoutWheelPicker

        init(_ parent: WorkoutWheelPicker) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { parent.choices.count }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { parent.rowHeight }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            formatKg(parent.choices[row])
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard parent.choices.indices.contains(row) else { return }
            let value = parent.choices[row]
            if value != parent.value, !parent.select(value) {
                parent.showSelection(in: pickerView)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view else { return false }
            return abs(touch.location(in: view).y - view.bounds.midY) <= max(22, parent.rowHeight / 2)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func tapSelection(_ recognizer: UITapGestureRecognizer) { parent.edit() }
    }
}
