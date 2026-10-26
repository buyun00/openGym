import SwiftUI

/// Anatomy is content: licensed vector images tinted by real data. The cards, list,
/// disclosures, progress bars and controls around it are all system components.
struct BodyMuscleMap: View {
    var loads: [MuscleLoad]
    var maximumFigureHeight: CGFloat? = nil
    var showsLegend = true

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                figure("front", title: "正面", ratio: 727.0 / 1280.0)
                figure("back", title: "背面", ratio: 727.0 / 1280.0)
            }
            if showsLegend {
                Text("灰色：本期未覆盖；绿色越鲜明，记录的训练组数越多。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正背面肌群训练量分布")
        .accessibilityValue(loads.isEmpty ? "暂无已记录的训练量" : loads.map { "\(Catalogue.muscleName($0.id))，\(formatKg($0.value))组" }.joined(separator: "；"))
    }

    private func figure(_ side: String, title: String, ratio: Double) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Image("BodyMap-\(side)-silhouette").resizable().renderingMode(.template)
                    .scaledToFit().foregroundStyle(.secondary.opacity(0.4))
                ForEach(Catalogue.muscleOrder, id: \.self) { muscle in
                    Image("BodyMap-\(side)-\(muscle)").resizable().renderingMode(.template)
                        .scaledToFit().foregroundStyle(color(muscle))
                }
            }
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxHeight: maximumFigureHeight)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func color(_ muscle: String) -> Color {
        let value = loads.first { $0.id == muscle }?.value ?? 0
        let peak = loads.map(\.value).max() ?? 1
        guard value > 0 else { return .secondary.opacity(0.25) }
        return .green.opacity(0.35 + 0.65 * min(1, value / max(peak, 0.01)))
    }
}
