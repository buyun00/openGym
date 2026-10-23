import SwiftUI

struct WorkoutExerciseCard: View {
    @Environment(GymStore.self) private var store
    var exercise: WorkoutExercise
    var compact: Bool
    @State private var options = false
    @State private var history = false
    private var metadata: WorkoutCatalogueRecord? { WorkoutCatalogue.records[exercise.exerciseId] }
    private var mode: WorkoutMode { exercise.mode ?? metadata?.mode ?? .reps }
    private var title: String {
        let name = metadata?.name ?? exercise.name
        guard let english = metadata?.englishName, english != name else { return name }
        return "\(name) (\(english.capitalized))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !compact && store.workoutPreferences.media == .full {
                WorkoutMediaView(record: metadata) { store.updateWorkoutPreferences { $0.media = .mini } }
            }
            HStack(alignment: .top, spacing: 12) {
                if !compact && store.workoutPreferences.media == .mini {
                    Button { store.updateWorkoutPreferences { $0.media = .full } } label: {
                        WorkoutThumbnail(record: metadata).frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 12))
                            .overlay(alignment: .bottomTrailing) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2).padding(5).glassEffect() }
                    }.buttonStyle(.plain).accessibilityLabel("放大动作演示")
                }
                Text(title).font(compact ? .headline : .title3.bold()).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Button("动作选项", systemImage: "ellipsis") { options = true }.labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
            }
            if !compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text(mode.title).foregroundStyle(.green).padding(.horizontal, 10).padding(.vertical, 5).background(.green.opacity(0.12), in: .capsule)
                        if let metadata {
                            Text(metadata.target.isEmpty ? Catalogue.bodyPartName(metadata.bodyPart) : metadata.target)
                            Text(Catalogue.equipmentName(metadata.equipment))
                        }
                        if exercise.noProgression == true { Label("不计入进阶", systemImage: "chart.line.downtrend.xyaxis") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if let note = exercise.note, !note.isEmpty {
                    Text(note).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
                if let previous = WorkoutLogic.previous(exercise.exerciseId, mode: mode, in: store.workouts, forProgression: false),
                   let last = previous.1.sets.last(where: \.done) {
                    Button { history = true } label: {
                        HStack(spacing: 5) {
                            Text("上次 (\(previous.0.formatted(.dateTime.month().day()))): \(WorkoutLogic.summary(last, mode: mode))")
                            Image(systemName: "clock.arrow.circlepath")
                        }.font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.glass)
                }
            }
            VStack(spacing: 14) {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    WorkoutSetEditor(exercise: exercise, set: set, index: index + 1, mode: mode, incline: metadata?.incline ?? false)
                }
                Button("加一组", systemImage: "plus") { store.addSet(exercise: exercise.id) }
                    .buttonStyle(.glass).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).background(.regularMaterial, in: .rect(cornerRadius: 20))
        }
        .sheet(isPresented: $options) {
            WorkoutExerciseOptions(exerciseId: exercise.id).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $history) {
            NavigationStack { WorkoutExerciseHistory(exerciseId: exercise.exerciseId) }.presentationDragIndicator(.visible)
        }
    }
}

private struct WorkoutSetEditor: View {
    @Environment(GymStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var exercise: WorkoutExercise
    var set: WorkoutSet
    var index: Int
    var mode: WorkoutMode
    var incline: Bool
    @State private var timerEnd: Date?

    private var metrics: [WorkoutMetric] {
        switch mode {
        case .cardio: return incline ? [.minutes, .speed, .incline] : [.minutes, .speed]
        case .time: return [.weight, .seconds]
        case .reps: return [.weight, .reps]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize { verticalRow }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 6) {
                        rowMenu.frame(width: 20).padding(.bottom, 8)
                        ForEach(metrics, id: \.self) { metric in field(metric).frame(minWidth: 84) }
                        checkButton.frame(width: 40).padding(.bottom, 2)
                    }
                    verticalRow
                }
            }
            if mode == .time && !set.done {
                HStack {
                    if let end = timerEnd {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("保持 \(workoutClock(end.timeIntervalSince(context.date)))").monospacedDigit()
                        }
                        Button("停止计时") { timerEnd = nil }.buttonStyle(.glass)
                    } else {
                        Button("开始计时", systemImage: "timer") {
                            timerEnd = Date().addingTimeInterval(set.seconds ?? 45)
                        }.buttonStyle(.glass)
                    }
                }
            }
            if set.done && store.workoutPreferences.effort != .none {
                Picker("强度 \(store.workoutPreferences.effort.title)", selection: Binding<Int?>(get: { set.rir }, set: { store.setRIR(exercise: exercise.id, set: set.id, value: $0) })) {
                    Text("未记录").tag(Int?.none)
                    ForEach(0...10, id: \.self) { rir in
                        Text(store.workoutPreferences.effort == .rpe ? "RPE \(10 - rir)" : "还能做 \(rir) 次").tag(Optional(rir))
                    }
                }.pickerStyle(.menu).font(.caption)
            }
        }
        .task(id: timerEnd) {
            guard let end = timerEnd else { return }
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled, store.active?.exercises.first(where: { $0.id == exercise.id })?.sets.first(where: { $0.id == set.id })?.done == false else { return }
            timerEnd = nil
            store.toggleSet(exercise: exercise.id, set: set.id)
        }
    }

    private var verticalRow: some View {
        VStack(alignment: .leading) {
            HStack { rowMenu; Text("第 \(index) 组"); Spacer(); checkButton }
            ForEach(metrics, id: \.self) { field($0) }
        }
    }

    private var rowMenu: some View {
        Menu {
            Button("复制这一组", systemImage: "plus.square.on.square") { store.copySet(exercise: exercise.id, set: set.id) }
            Button("删除这一组", systemImage: "trash", role: .destructive) { timerEnd = nil; store.deleteSet(exercise: exercise.id, set: set.id) }
        } label: { Text("\(index)").font(.caption).monospacedDigit().frame(minHeight: 44) }
            .accessibilityLabel("第 \(index) 组操作")
    }

    private var checkButton: some View {
        Button {
            timerEnd = nil
            store.toggleSet(exercise: exercise.id, set: set.id)
        } label: {
            Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.title2).frame(minHeight: 40)
        }
        .buttonStyle(.glass).tint(set.done ? .green : .gray)
        .accessibilityLabel(set.done ? "取消第 \(index) 组完成" : "完成第 \(index) 组")
    }

    private func field(_ metric: WorkoutMetric) -> some View {
        WorkoutNumberField(metric: metric, value: metric.value(in: set)) { value in
            store.setMetric(metric, exercise: exercise.id, set: set.id, value: value)
        }
    }
}

private struct WorkoutNumberField: View {
    var metric: WorkoutMetric
    var value: Double?
    var changed: (Double?) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(metric.title).font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 0) {
                Button { step(-1) } label: { Image(systemName: "minus").frame(width: 24, height: 44) }.accessibilityLabel("减少\(metric.title)")
                TextField("—", text: $draft)
                    .keyboardType(.decimalPad).multilineTextAlignment(.center).monospacedDigit().focused($focused)
                    .accessibilityLabel(metric.title).frame(minWidth: 32)
                    .onChange(of: draft) { _, text in
                        guard focused else { return }
                        if text.isEmpty { changed(nil) }
                        else if let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite { changed(number) }
                    }
                Button { step(1) } label: { Image(systemName: "plus").frame(width: 24, height: 44) }.accessibilityLabel("增加\(metric.title)")
            }
            .buttonStyle(.plain).font(.subheadline)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
        .onAppear { refresh() }
        .onChange(of: value) { _, _ in if !focused { refresh() } }
        .onChange(of: focused) { _, focus in if !focus { refresh() } }
    }

    private func refresh() { draft = value.map(formatKg) ?? "" }
    private func step(_ direction: Double) {
        let next = min(metric.maximum, max(0, (value ?? 0) + direction * metric.step))
        draft = formatKg(next)
        changed(next)
    }
}
