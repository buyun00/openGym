import SwiftUI
import HealthKit

/// A manual choice is the only write path. Loading and previews never mutate the session.
struct WorkoutHealthPicker: View {
    @Environment(GymStore.self) private var store
    let session: WorkoutSession
    var finishing = false
    var importing = false
    var close: () -> Void
    @State private var reader = WorkoutHealthReader()
    @State private var choices: [HKWorkout] = []
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?
    @State private var pending: HKWorkout?
    @State private var expectedHealth: WorkoutHealth?
    @State private var confirmReplacement = false
    @State private var replacementID: UUID?
    @State private var endedAt = Date()
    @State private var operation: Task<Void, Never>?

    private var currentHealth: WorkoutHealth? {
        if importing { return pending.flatMap { store.workoutLinked(to: $0.uuid)?.health } }
        if store.active?.id == session.id { return store.active?.health }
        return store.workouts.first { $0.id == session.id }?.health
    }

    var body: some View {
        List {
            Section {
                Text(importing ? "从健康导入运动" : session.name).font(.headline)
                Text(importing ? "无需开启 openGym 训练。手选一条运动，保存为独立训练记录并同步，用于训练分析。" :
                     finishing ? "选择一条健康运动记录，随本次训练保存并上传。也可以跳过，仅保存训练。" :
                     session.finishedAt == nil ? "手选后先保存到当前会话，结束训练时确认上传；进行中的训练不会提前上传。" :
                     "选择后将保存到这次训练并立即尝试同步。补传不会重复发送完成邮件。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("读取体能训练、心率和活动能量。仅你点选的记录会随训练发送到已配置的服务器，用于邮件和总结。")
                    .font(.caption).foregroundStyle(.secondary)
                if finishing && session.exercises.flatMap(\.sets).contains(where: { !$0.done }) {
                    Text("还有未完成的组；选择或跳过都将结束本次训练。").foregroundStyle(.orange)
                }
                if currentHealth != nil { Text("本次已有健康数据，选择其他记录需确认覆盖。").font(.caption) }
            }
            if let message {
                Section {
                    Text(message)
                    if importing || session.finishedAt != nil {
                        Button("重试同步") { operation = Task { await syncSaved() } }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section("近期体能训练 · 最多 30 条") {
                if loading { ProgressView("读取健康运动列表…") }
                else if choices.isEmpty {
                    Text("没有可读取的体能训练。请在“健康”中允许 openGym 读取体能训练、心率和活动能量，并等待手表同步后刷新。拒绝读取与没有记录可能显示相同结果。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(choices, id: \.uuid) { workout in
                    Button { choose(workout) } label: {
                        WorkoutHealthChoiceRow(workout: workout, reader: reader,
                            overlaps: !importing && workout.startDate < (session.finishedAt ?? endedAt) && workout.endDate > session.startedAt)
                    }.buttonStyle(.plain)
                }
                Button("刷新列表") { operation = Task { await load() } }
                    .disabled(loading)
            }
            if busy { ProgressView("读取所选运动并保存…") }
        }
        .navigationTitle(importing ? "上传健康运动" : finishing ? "选择运动并结束" : "上传本次运动")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if finishing {
                VStack(spacing: 4) {
                    Button("跳过健康数据，仅保存训练") {
                        if store.finishActive(id: session.id, health: nil, at: endedAt, expectedHealth: currentHealth) { close() }
                        else { error = store.saveError }
                    }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Text("跳过会移除本次已选择的健康数据，之后仍可手动补传。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding().background(.regularMaterial)
            }
        }
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .task { await load() }
        .onDisappear { operation?.cancel() }
        .confirmationDialog(importing ? "这条运动已有训练记录，更新原记录？" : "覆盖本次已有的健康数据？", isPresented: $confirmReplacement, titleVisibility: .visible) {
            Button(importing ? "更新原记录" : "覆盖并保存") { if let pending { begin(pending) } }
            Button("取消", role: .cancel) { pending = nil }
        } message: { Text(importing ? "不会重复创建训练或再次发送完成邮件，仅更新原记录的健康数据。" : "只替换 openGym 中本次训练的健康数据，不修改“健康”中的原始记录。") }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await reader.recent(around: importing ? Date() : session.finishedAt ?? endedAt)
            guard !Task.isCancelled else { return }
            choices = result
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func choose(_ workout: HKWorkout) {
        pending = workout
        expectedHealth = currentHealth
        replacementID = importing ? store.workoutLinked(to: workout.uuid)?.id : nil
        if expectedHealth != nil || replacementID != nil { confirmReplacement = true }
        else { begin(workout) }
    }

    private func begin(_ workout: HKWorkout) {
        guard !busy else { return }
        busy = true; error = nil; message = nil
        operation = Task {
            defer { busy = false }
            do {
                let health = try await reader.read(workout)
                guard !Task.isCancelled else { return }
                let saved: Bool
                if importing {
                    saved = store.importHealthWorkout(health, name: "\(workout.openGymActivityName) · 健康导入", replacing: replacementID, expectedHealth: expectedHealth)
                } else if finishing {
                    saved = store.finishActive(id: session.id, health: health, at: endedAt, expectedHealth: expectedHealth)
                } else {
                    saved = store.attachWorkoutHealth(health, to: session.id, expectedHealth: expectedHealth)
                }
                guard saved else { error = store.saveError; return }
                if finishing { close(); return }
                if !importing && store.active?.id == session.id {
                    message = "已保存所选运动到本次会话，结束训练时请再次确认选择后上传。"
                } else { await syncSaved() }
            } catch { if !Task.isCancelled { self.error = "未替换原数据：\(error.localizedDescription)" } }
        }
    }

    private func syncSaved() async {
        await store.cloud.sync(store: store)
        message = "\(importing ? "健康运动已保存为训练记录" : "已保存到本机")。同步状态：\(store.cloud.status)"
        if let syncError = store.cloud.errorMessage { message = "已保存到本机，尚未同步：\(syncError)" }
    }
}

private struct WorkoutHealthChoiceRow: View {
    let workout: HKWorkout
    let reader: WorkoutHealthReader
    var overlaps: Bool
    @State private var preview: WorkoutHealth?
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(workout.openGymActivityName).font(.headline)
                Spacer()
                if overlaps { Text("时间重叠").font(.caption).foregroundStyle(.green) }
            }
            Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
            Text("\(Int(workout.duration / 60)) 分钟 · \(workout.sourceRevision.source.name)")
                .font(.caption).foregroundStyle(.secondary)
            if failed { Text("指标暂不可读，点选可重试").font(.caption).foregroundStyle(.secondary) }
            else if !loaded { Text("心率 / 能量：读取中…").font(.caption).foregroundStyle(.secondary) }
            else {
                Text("心率：\(preview?.heart_rate_avg_bpm.map { "平均 \(formatKg($0)) bpm" } ?? "无可读数据") · 能量：\(preview?.active_energy_kcal.map { "\(formatKg($0)) kcal" } ?? "无可读数据")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
        .task {
            do { preview = try await reader.read(workout) }
            catch { failed = true }
            loaded = true
        }
    }

}

private extension HKWorkout {
    var openGymActivityName: String {
        switch workoutActivityType {
        case .traditionalStrengthTraining: return "传统力量训练"
        case .functionalStrengthTraining: return "功能性力量训练"
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .highIntensityIntervalTraining: return "高强度间歇训练"
        case .yoga: return "瑜伽"
        case .elliptical: return "椭圆机"
        case .rowing: return "划船"
        case .hiking: return "徒步"
        case .coreTraining: return "核心训练"
        case .pilates: return "普拉提"
        default: return "其他体能训练"
        }
    }
}

struct WorkoutHealthUploadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    var body: some View {
        NavigationStack {
            WorkoutHealthPicker(session: session, close: { dismiss() })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

/// Presentation reference only: never inserts or starts an openGym active session.
struct WorkoutHealthImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reference = WorkoutSession(id: UUID(), name: "健康运动导入",
        startedAt: Date(), finishedAt: Date(), exercises: [])
    var body: some View {
        NavigationStack {
            WorkoutHealthPicker(session: reference, importing: true, close: { dismiss() })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
