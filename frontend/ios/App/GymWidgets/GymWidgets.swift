import SwiftUI
import WidgetKit
import ActivityKit
import Charts

private struct GymEntry: TimelineEntry {
    var date: Date
    var data: GymWidgetData
}

private struct GymProvider: TimelineProvider {
    func placeholder(in context: Context) -> GymEntry { GymEntry(date: Date(), data: GymWidgetData()) }
    func getSnapshot(in context: Context, completion: @escaping (GymEntry) -> Void) {
        completion(GymEntry(date: Date(), data: .read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GymEntry>) -> Void) {
        let now = Date(), data = GymWidgetData.read()
        // Pre-render the next midnight so yesterday's water/training never masquerades as today's.
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        completion(Timeline(entries: [GymEntry(date: now, data: data), GymEntry(date: midnight, data: data)],
                            policy: .after(midnight.addingTimeInterval(60))))
    }
}

private struct WaterWidgetView: View {
    var entry: GymEntry
    var total: Int { entry.data.waterDay == GymWidgetData.day(entry.date) ? entry.data.waterML : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("今日喝水", systemImage: "drop.fill").font(.headline).foregroundStyle(.cyan)
            Text("\(total) mL").font(.title2.bold()).minimumScaleFactor(0.6)
            if let goal = entry.data.waterGoal, goal > 0 {
                ProgressView(value: min(Double(total) / Double(goal), 1)).tint(.cyan)
                Text("目标 \(goal) mL").font(.caption).foregroundStyle(.secondary)
            } else { Text("打开 App 设置目标").font(.caption).foregroundStyle(.secondary) }
        }
        .widgetURL(URL(string: "opengym://water"))
        .containerBackground(.background, for: .widget)
    }
}

private struct GoalWidgetView: View {
    var entry: GymEntry
    var plan: GymWidgetData.Plan? { entry.data.plans[GymWidgetData.day(entry.date)] }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("今日锻炼", systemImage: "figure.strengthtraining.traditional").font(.headline).foregroundStyle(.orange)
            Text(plan?.title ?? "打开 App 更新计划").font(.subheadline.bold()).lineLimit(2)
            Text(plan?.done == true ? "今日已练 ✓" : "今日未练").font(.caption).foregroundStyle(.secondary)
            Text(plan?.active == true ? "继续训练 →" : plan?.title == "休息日" ? "安排训练 →" : "开始训练 →")
                .font(.caption.bold()).foregroundStyle(.orange)
        }
        .widgetURL(URL(string: "opengym://workout"))
        .containerBackground(.background, for: .widget)
    }
}

private struct WeightWidgetView: View {
    var entry: GymEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("体重趋势", systemImage: "chart.xyaxis.line").font(.headline)
                Spacer()
                if let last = entry.data.weights.last {
                    Text("\(last.kilograms, specifier: "%.1f") kg").font(.headline).foregroundStyle(.mint)
                }
            }
            if entry.data.weights.isEmpty {
                Spacer()
                Text("记录第一次体重，见证每一点变化").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            } else {
                Chart(entry.data.weights) { point in
                    AreaMark(x: .value("日期", point.date), yStart: .value("基线", lower), yEnd: .value("kg", point.kilograms))
                        .foregroundStyle(LinearGradient(colors: [.mint.opacity(0.35), .mint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("日期", point.date), y: .value("kg", point.kilograms)).foregroundStyle(.mint)
                    PointMark(x: .value("日期", point.date), y: .value("kg", point.kilograms)).foregroundStyle(.mint).symbolSize(12)
                }
                .chartYScale(domain: lower...upper)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .accessibilityLabel("近期 \(entry.data.weights.count) 条体重记录")
            }
        }
        .widgetURL(URL(string: "opengym://body"))
        .containerBackground(.background, for: .widget)
    }
    private var lower: Double { (entry.data.weights.map(\.kilograms).min() ?? 0) - 1 }
    private var upper: Double { (entry.data.weights.map(\.kilograms).max() ?? 0) + 1 }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenGymWater", provider: GymProvider()) { WaterWidgetView(entry: $0) }
            .configurationDisplayName("今日喝水").description("随时查看喝水进度").supportedFamilies([.systemSmall])
    }
}
struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenGymGoal", provider: GymProvider()) { GoalWidgetView(entry: $0) }
            .configurationDisplayName("今日锻炼").description("今日计划与训练入口").supportedFamilies([.systemSmall])
    }
}
struct WeightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenGymWeight", provider: GymProvider()) { WeightWidgetView(entry: $0) }
            .configurationDisplayName("体重趋势").description("最近 30 次体重记录").supportedFamilies([.systemMedium])
    }
}

struct TrainingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainingActivityAttributes.self) { context in
            HStack {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(context.attributes.name).font(.caption).foregroundStyle(.secondary)
                    Text(context.state.exercise).font(.headline).lineLimit(2)
                }
                Spacer()
                Text("\(context.state.completed)/\(context.state.total) 组").monospacedDigit()
            }
            .padding().widgetURL(URL(string: "opengym://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completed)/\(context.state.total) 组").monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.exercise).font(.headline).lineLimit(2) }
            } compactLeading: {
                Text(context.state.exercise).lineLimit(1).frame(maxWidth: 80)
            } compactTrailing: {
                Text("\(context.state.completed)/\(context.state.total)").monospacedDigit()
            } minimal: {
                Text("\(context.state.completed)/\(context.state.total)").font(.caption2).minimumScaleFactor(0.6)
            }
            .widgetURL(URL(string: "opengym://workout"))
        }
    }
}

@main
struct OpenGymWidgets: WidgetBundle {
    var body: some Widget {
        WaterWidget()
        GoalWidget()
        WeightWidget()
        TrainingActivityWidget()
    }
}
