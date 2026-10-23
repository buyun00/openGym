import SwiftUI

struct WaterView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("喝水", systemImage: "drop")
            } description: {
                Text("喝水记录还没做。这一页先留着。")
            }
            .navigationTitle("喝水")
        }
    }
}
