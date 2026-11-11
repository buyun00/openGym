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
    @Environment(\.widgetFamily) private var family
    var total: Int { entry.data.waterDay == GymWidgetData.day(entry.date) ? max(0, entry.data.waterML) : 0 }
    private var goal: Int? { entry.data.waterGoal.flatMap { $0 > 0 ? $0 : nil } }
    private var progress: Double { goal.map { min(Double(total) / Double($0), 1) } ?? 0 }
    private var remaining: String {
        guard let goal else { return "轻点设置每日目标" }
        return total >= goal ? "今日目标已达成" : "距离目标还差 \(goal - total) mL"
    }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill").foregroundStyle(.cyan).widgetAccentable()
                    Text("今日喝水").foregroundStyle(.white.opacity(0.88))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.5))
                }.font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(total, format: .number.grouping(.never))
                        .font(.system(size: family == .systemMedium ? 42 : 34, weight: .bold, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
                    Text("mL").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                }
                Text(goal.map { "每日目标 \($0) mL" } ?? "每一口，都是好习惯")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                Spacer(minLength: 8)
                if let goal {
                    GeometryReader { geometry in
                        Capsule().fill(.white.opacity(0.15))
                            .overlay(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: [.cyan, .mint], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * progress)
                            }
                    }.frame(height: 5)
                    HStack(spacing: 4) {
                        Text(total >= goal ? "今日已达标" : "轻点记录喝水")
                        Spacer(minLength: 0)
                        Text("\(Int(progress * 100))%")
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8)).padding(.top, 7)
                } else {
                    Text(remaining).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
            }
            if family == .systemMedium {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                    Circle().trim(from: 0, to: progress)
                        .stroke(.cyan, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 6) {
                        Image(systemName: progress >= 1 ? "checkmark" : "drop.fill")
                            .font(.system(size: 29, weight: .medium)).foregroundStyle(.cyan)
                        Text(goal == nil ? "养成习惯" : "\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                }.frame(width: 96, height: 96).padding(.trailing, 4)
            }
        }
        .foregroundStyle(.white).padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "lingym://water"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日喝水 \(total) 毫升，\(remaining)。打开喝水页面")
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.15, blue: 0.25), Color(red: 0.02, green: 0.27, blue: 0.38)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                WaterWidgetWave(level: 0.18 + progress * 0.27, phase: 0)
                    .fill(.cyan.opacity(0.11))
                WaterWidgetWave(level: 0.13 + progress * 0.27, phase: 1.8)
                    .fill(.mint.opacity(0.09))
            }
        }
    }
}

private struct WaterWidgetWave: Shape {
    var level: Double
    var phase: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.height * (1 - level)
        path.move(to: CGPoint(x: 0, y: rect.height))
        for step in 0...60 {
            let fraction = Double(step) / 60
            let x = rect.width * fraction
            let y = baseline + sin(fraction * .pi * 2 + phase) * 7
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
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
            .configurationDisplayName("今日喝水").description("查看每日饮水进度，轻点直接记录喝水")
            .supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    activityIcon(context.state)
                    VStack(alignment: .leading) {
                        Text(context.attributes.name).font(.caption).foregroundStyle(.secondary)
                        Text(context.state.exercise).font(.headline).lineLimit(2)
                    }
                    Spacer()
                    status(context)
                }
                countdownProgress(context)
            }
            .padding().widgetURL(URL(string: "opengym://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    activityIcon(context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    status(context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.exercise).font(.headline).lineLimit(2)
                        countdownProgress(context)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                if context.state.countdown != nil { activityIcon(context.state) }
                else { Text(context.state.exercise).lineLimit(1).frame(maxWidth: 80) }
            } compactTrailing: {
                compactStatus(context, minimal: false)
            } minimal: {
                compactStatus(context, minimal: true)
            }
            .widgetURL(URL(string: "opengym://workout"))
        }
    }

    private func activityIcon(_ state: TrainingActivityAttributes.ContentState) -> some View {
        let symbol: String
        switch state.countdown?.kind {
        case .rest: symbol = "timer"
        case .cardio: symbol = "figure.run"
        case nil: symbol = "figure.strengthtraining.traditional"
        }
        return Image(systemName: symbol).foregroundStyle(.orange).accessibilityHidden(true)
    }

    @ViewBuilder private func status(_ context: ActivityViewContext<TrainingActivityAttributes>) -> some View {
        if let timer = context.state.countdown {
            VStack(alignment: .trailing, spacing: 2) {
                Text(countdownLabel(timer, ended: context.isStale))
                    .font(.caption).foregroundStyle(.secondary)
                countdownText(timer, ended: context.isStale)
                    .font(.headline)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72, alignment: .trailing)
            }
        } else {
            Text("\(context.state.completed)/\(context.state.total) 组").monospacedDigit()
        }
    }

    @ViewBuilder private func compactStatus(_ context: ActivityViewContext<TrainingActivityAttributes>, minimal: Bool) -> some View {
        if let timer = context.state.countdown {
            countdownText(timer, ended: context.isStale)
                .font(.system(size: minimal ? 9 : 12, weight: .semibold))
                .lineLimit(1)
                .multilineTextAlignment(minimal ? .center : .trailing)
                .frame(width: minimal ? 34 : 46, alignment: minimal ? .center : .trailing)
                .accessibilityLabel(Text(countdownLabel(timer, ended: context.isStale)))
                .accessibilityValue(countdownText(timer, ended: context.isStale))
        } else {
            Text("\(context.state.completed)/\(context.state.total)")
                .font(minimal ? .caption2 : .subheadline)
                .monospacedDigit().minimumScaleFactor(0.6)
        }
    }

    private func countdownText(_ timer: TrainingActivityAttributes.Countdown, ended: Bool) -> Text {
        // The system renders the bounded countdown while the app is suspended.
        (ended ? Text("0:00") : Text(timerInterval: timer.interval, countsDown: true, showsHours: false))
            .monospacedDigit()
    }

    @ViewBuilder private func countdownProgress(_ context: ActivityViewContext<TrainingActivityAttributes>) -> some View {
        if let timer = context.state.countdown, !context.isStale {
            ProgressView(timerInterval: timer.interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.orange)
            .accessibilityHidden(true)
        }
    }

    private func countdownLabel(_ timer: TrainingActivityAttributes.Countdown, ended: Bool) -> String {
        switch timer.kind {
        case .rest: ended ? "休息结束" : "组间休息"
        case .cardio: ended ? "本组计时结束" : "本组有氧剩余"
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
