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
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2)
                                    .foregroundStyle(.primary).padding(5)
                                    .background(Color(uiColor: .systemBackground), in: .circle)
                            }
                    }.buttonStyle(.plain).accessibilityLabel("放大动作演示")
                }
                Text(title).font(compact ? .headline : .title3.bold()).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Button("动作选项", systemImage: "ellipsis") { options = true }.labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.large)
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
                        .padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                }
                if let previous = WorkoutLogic.previous(exercise.exerciseId, mode: mode, in: store.workouts, forProgression: false),
                   let last = previous.1.sets.last(where: \.done) {
                    Button { history = true } label: {
                        HStack(spacing: 5) {
                            Text("上次 (\(previous.0.formatted(.dateTime.month().day()))): \(WorkoutLogic.summary(last, mode: mode))")
                            Image(systemName: "clock.arrow.circlepath")
                        }.font(.caption).foregroundStyle(.primary)
                            .frame(minHeight: 44, alignment: .leading).contentShape(.rect)
                    }.buttonStyle(.plain)
                }
            }
            VStack(spacing: 14) {
                if mode == .reps {
                    WorkoutStrengthSetList(
                        sets: exercise.sets,
                        change: { set, metric, value in
                            store.setMetric(metric, exercise: exercise.id, set: set, value: value)
                            return store.saveError == nil
                        },
                        toggle: { store.toggleSet(exercise: exercise.id, set: $0) },
                        copy: { store.copySet(exercise: exercise.id, set: $0) },
                        delete: { store.deleteSet(exercise: exercise.id, set: $0) }
                    )
                } else {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        WorkoutSetEditor(exercise: exercise, set: set, index: index + 1, mode: mode, incline: metadata?.incline ?? false)
                    }
                }
                Button("加一组", systemImage: "plus") { store.addSet(exercise: exercise.id) }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
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
            if typeSize.isAccessibilitySize { stackedRow }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .workoutInputCenter, spacing: 8) {
                        rowMenu()
                        fields
                        checkButton
                    }
                    stackedRow
                }
            }
            if mode == .time && !set.done {
                HStack {
                    if let end = timerEnd {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("保持 \(workoutClock(end.timeIntervalSince(context.date)))").monospacedDigit()
                        }
                        Button("停止计时") { timerEnd = nil }.buttonStyle(.bordered)
                    } else {
                        Button("开始计时", systemImage: "timer") {
                            timerEnd = Date().addingTimeInterval(set.seconds ?? 45)
                        }.buttonStyle(.borderedProminent)
                    }
                }
            }
            if mode == .cardio && !set.done { cardioControls }
        }
        .task(id: timerEnd) {
            guard let end = timerEnd else { return }
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled, store.active?.exercises.first(where: { $0.id == exercise.id })?.sets.first(where: { $0.id == set.id })?.done == false else { return }
            timerEnd = nil
            store.toggleSet(exercise: exercise.id, set: set.id)
        }
    }

    @ViewBuilder private var cardioControls: some View {
        if let timer = store.active?.cardioTimer, timer.exerciseID == exercise.id, timer.setID == set.id {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ViewThatFits(in: .horizontal) {
                    HStack { cardioStatus(timer, now: context.date) }
                    VStack(alignment: .leading) { cardioStatus(timer, now: context.date) }
                }
            }
        } else {
            Button("开始有氧计时", systemImage: "timer") {
                store.startCardioTimer(exercise: exercise.id, set: set.id)
            }
            .buttonStyle(.borderedProminent)
            .disabled((set.minutes ?? 0) <= 0)
        }
    }

    @ViewBuilder private func cardioStatus(_ timer: WorkoutCardioTimer, now: Date) -> some View {
        if now < timer.end {
            Label("剩余 \(workoutClock(ceil(timer.end.timeIntervalSince(now))))", systemImage: "timer").monospacedDigit()
            Button("停止计时") { store.stopCardioTimer(timer) }.buttonStyle(.bordered)
        } else {
            Text("有氧计时结束").foregroundStyle(.secondary)
            Button("完成本组") { store.toggleSet(exercise: exercise.id, set: set.id) }.buttonStyle(.borderedProminent)
            Button("重计", systemImage: "arrow.counterclockwise") {
                store.startCardioTimer(exercise: exercise.id, set: set.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled((set.minutes ?? 0) <= 0)
        }
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                rowMenu(showTitle: true)
                Spacer()
                checkButton
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { fields }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .workoutInputCenter, spacing: 8) { fields }
                    VStack(spacing: 8) { fields }
                }
            }
        }
    }

    private func rowMenu(showTitle: Bool = false) -> some View {
        WorkoutSetMenu(index: index, showTitle: showTitle, copy: {
            store.copySet(exercise: exercise.id, set: set.id)
        }, delete: {
            timerEnd = nil
            store.deleteSet(exercise: exercise.id, set: set.id)
        })
    }

    private var checkButton: some View {
        WorkoutSetCompletionButton(index: index, done: set.done) {
            timerEnd = nil
            store.toggleSet(exercise: exercise.id, set: set.id)
        }
    }

    private var fields: some View {
        ForEach(metrics, id: \.self) { metric in
            VStack(spacing: 6) {
                Text(metric.title).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NumberStepper(title: metric.title, value: metric.value(in: set), bounds: 0...metric.maximum,
                              step: metric.step, keyboard: metric == .reps || metric == .seconds ? .numberPad : .decimalPad) { value in
                    store.setMetric(metric, exercise: exercise.id, set: set.id, value: value)
                }
                .alignmentGuide(.workoutInputCenter) { $0[VerticalAlignment.center] }
            }
        }
    }
}
