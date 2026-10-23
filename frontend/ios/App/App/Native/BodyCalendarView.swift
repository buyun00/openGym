import SwiftUI
import UIKit

/// Thin binding adapter for Apple's calendar, selection and date decorations.
/// No custom calendar cells, gesture recognizers or glass imitation.
struct BodyCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date?
    @Binding var visibleMonth: Date
    var decorations: [Date: Int]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICalendarView {
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        let view = UICalendarView()
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        view.calendar = calendar
        view.locale = .current
        view.fontDesign = .rounded
        view.delegate = context.coordinator
        view.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.setVisibleDateComponents(calendar.dateComponents([.year, .month], from: visibleMonth), animated: false)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        let calendar = view.calendar
        if let selection = view.selectionBehavior as? UICalendarSelectionSingleDate {
            let current = selection.selectedDate.flatMap { calendar.date(from: $0) }
            let desired = selectedDate.map { calendar.startOfDay(for: $0) }
            if current != desired {
                selection.setSelected(desired.map { calendar.dateComponents([.year, .month, .day], from: $0) }, animated: false)
            }
        }
        let month = calendar.dateComponents([.year, .month], from: visibleMonth)
        if view.visibleDateComponents.year != month.year || view.visibleDateComponents.month != month.month {
            view.setVisibleDateComponents(month, animated: false)
        }
        let changed = Set(decorations.keys).union(context.coordinator.previous.keys).filter {
            decorations[$0] != context.coordinator.previous[$0]
        }
        context.coordinator.previous = decorations
        if !changed.isEmpty {
            view.reloadDecorations(forDateComponents: changed.map { calendar.dateComponents([.year, .month, .day], from: $0) }, animated: false)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: BodyCalendarView
        var previous: [Date: Int] = [:]
        var updating = false
        init(_ parent: BodyCalendarView) { self.parent = parent }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let date = calendarView.calendar.date(from: dateComponents),
                  let kind = parent.decorations[calendarView.calendar.startOfDay(for: date)] else { return nil }
            let color: UIColor = kind == 1 ? .systemGreen : kind == 2 ? .systemBlue : kind == 4 ? .systemOrange : .systemPurple
            return .default(color: color, size: .medium)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard !updating else { return }
            parent.selectedDate = dateComponents.flatMap { Calendar.current.date(from: $0) }
        }

        func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {
            guard !updating, let date = calendarView.calendar.date(from: calendarView.visibleDateComponents) else { return }
            // Binding writes are user initiated; updateUIView suppresses delegate echoes.
            parent.visibleMonth = date
            parent.selectedDate = nil
        }
    }
}
