import SwiftUI

struct EquipmentView: View {
    @Environment(GymStore.self) private var store

    var body: some View {
        List {
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
