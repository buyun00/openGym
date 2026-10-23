import SwiftUI

struct BodyEntryRequest: Identifiable {
    enum Kind: Equatable { case weight, measurement }
    let id = UUID()
    var kind: Kind
    var date: Date
    var weighIn: WeighIn?
    var measurement: BodyMeasurement?

    static func weight(_ entry: WeighIn? = nil) -> Self {
        Self(kind: .weight, date: entry?.date ?? .now, weighIn: entry)
    }
    static func measurement(_ entry: BodyMeasurement? = nil) -> Self {
        Self(kind: .measurement, date: entry?.date ?? .now, measurement: entry)
    }
}

struct BodyEntrySheet: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: BodyEntryRequest
    @State private var date: Date
    @State private var weight: String
    @State private var fat: String
    @State private var measurements: [String: String]

    init(request: BodyEntryRequest) {
        self.request = request
        _date = State(initialValue: request.date)
        _weight = State(initialValue: request.weighIn.map { formatKg($0.kilograms) } ?? "")
        _fat = State(initialValue: request.weighIn?.bodyFatPercent.map(formatKg) ?? "")
        _measurements = State(initialValue: request.measurement?.centimeters.mapValues(formatKg) ?? [:])
    }

    private var editing: Bool { request.weighIn != nil || request.measurement != nil }
    private func number(_ text: String, below maximum: Double) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0, value < maximum else { return nil }
        return value
    }
    private var valid: Bool {
        switch request.kind {
        case .weight: return parseKg(weight) != nil && (fat.isEmpty || number(fat, below: 100) != nil)
        case .measurement:
            let entries = measurements.values.filter { !$0.isEmpty }
            return !entries.isEmpty && entries.allSatisfy { number($0, below: 300) != nil }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .disabled(editing)
                }
                if request.kind == .weight {
                    Section {
                        TextField("体重 kg", text: $weight).keyboardType(.decimalPad)
                        TextField("体脂率 %（选填）", text: $fat).keyboardType(.decimalPad)
                        if let kg = parseKg(weight), let percent = number(fat, below: 100) {
                            LabeledContent("去脂体重（估算）", value: "\(formatKg(kg * (1 - percent / 100))) kg")
                        }
                    } footer: { Text("每天保留一条称重记录。同日保存会更新已有记录；体脂率可留空。") }
                } else {
                    Section {
                        ForEach(BodyMeasurement.fields, id: \.self) { field in
                            TextField("\(field) cm（选填）", text: Binding(
                                get: { measurements[field] ?? "" },
                                set: { measurements[field] = $0 }
                            )).keyboardType(.decimalPad)
                        }
                    } footer: { Text("至少填写一项。每天保留一条围度记录；保存会更新所选日期的围度。") }
                }
            }
            .navigationTitle(request.kind == .weight ? "记体重与体脂" : "记围度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!valid) }
            }
            .onAppear { if !editing { loadDay() } }
            .onChange(of: date) { _, _ in if !editing { loadDay() } }
            .alert("记录未保存", isPresented: Binding(
                get: { store.saveError != nil },
                set: { if !$0 { store.saveError = nil } }
            )) {
                Button("好") { store.saveError = nil }
            } message: { Text(store.saveError ?? "") }
        }
        .presentationDetents([.large])
    }

    private func loadDay() {
        let existing = store.weighIns.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        weight = existing.map { formatKg($0.kilograms) } ?? ""
        fat = existing?.bodyFatPercent.map(formatKg) ?? ""
        measurements = store.bodyMeasurements.first { Calendar.current.isDate($0.date, inSameDayAs: date) }?.centimeters.mapValues(formatKg) ?? [:]
    }

    private func save() {
        guard valid else { return }
        let saved: Bool
        switch request.kind {
        case .weight:
            guard let kg = parseKg(weight) else { return }
            saved = store.addWeighIn(kilograms: kg, date: date, bodyFatPercent: number(fat, below: 100), keepExistingBodyFat: false)
        case .measurement:
            saved = store.addMeasurement(date: date, centimeters: measurements.compactMapValues { number($0, below: 300) })
        }
        if saved { dismiss() }
    }
}
