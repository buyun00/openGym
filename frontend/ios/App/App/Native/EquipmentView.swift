import SwiftUI

struct EquipmentView: View {
    @Environment(GymStore.self) private var store

    var body: some View {
        List {
            if !store.gymEquipment.isEmpty {
                Section("网页器械库") {
                    ForEach(store.gymEquipment) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name).font(.headline)
                            if !item.note.isEmpty { Text(item.note).font(.subheadline) }
                            if !item.location.isEmpty { Text(item.location).font(.caption).foregroundStyle(.secondary) }
                            if !item.exerciseNames.isEmpty { Text(item.exerciseNames.joined(separator: "、")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section {
                Text("勾上你有的器械。动作库里可以只显示这些。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("器械") {
                ForEach(Catalogue.equipment) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { store.ownedEquipment.contains(item.id) },
                        set: { store.setOwned(item.id, $0) }
                    ))
                }
            }
        }
        .navigationTitle("器械库")
    }
}
