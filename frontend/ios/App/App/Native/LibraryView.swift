import SwiftUI

struct LibraryView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onPick: ((ExerciseInfo) -> Void)?
    @State private var query = ""
    @State private var ownedOnly = false

    private var owned: Set<String>? {
        ownedOnly ? Set(store.ownedEquipment) : nil
    }

    private var results: [ExerciseInfo] { Catalogue.search(query, owned: owned) }

    var body: some View {
        List {
            if ownedOnly && store.ownedEquipment.isEmpty {
                ContentUnavailableView("还没选器械", systemImage: "wrench.and.screwdriver", description: Text("先到器械库勾上你有的器械，或者关掉这个筛选。"))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(results) { exercise in
                    if onPick != nil {
                        Button {
                            onPick?(exercise)
                            dismiss()
                        } label: {
                            exerciseRow(exercise)
                        }
                    } else {
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            exerciseRow(exercise)
                        }
                    }
                }
            }
        }
        .navigationTitle(onPick == nil ? "动作库" : "加动作")
        .searchable(text: $query, prompt: "搜索动作")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("只看我的器械", isOn: $ownedOnly)
                    .toggleStyle(.button)
            }
        }
    }

    private func exerciseRow(_ exercise: ExerciseInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .foregroundStyle(.primary)
            Text(rowSubtitle(exercise))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func rowSubtitle(_ exercise: ExerciseInfo) -> String {
        let muscles = Catalogue.muscleSummary(exercise)
        let gear = Catalogue.equipmentName(exercise.equipment)
        if muscles.isEmpty { return gear }
        return "\(gear) · \(muscles)"
    }
}

struct ExerciseDetailView: View {
    var exercise: ExerciseInfo

    private var ranked: [(String, Double)] {
        exercise.muscles.sorted { $0.value > $1.value }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("器械", value: Catalogue.equipmentName(exercise.equipment))
                LabeledContent("部位", value: Catalogue.bodyPartName(exercise.bodyPart))
            }
            Section("练到哪里") {
                if ranked.isEmpty {
                    Text("这个动作没有肌肉标注")
                        .foregroundStyle(.secondary)
                } else {
                    let peak = ranked.first?.1 ?? 1
                    ForEach(ranked, id: \.0) { muscle, weight in
                        HStack {
                            Text(Catalogue.muscleName(muscle))
                            Spacer()
                            ProgressView(value: weight, total: max(peak, 0.01))
                                .frame(width: 120)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
