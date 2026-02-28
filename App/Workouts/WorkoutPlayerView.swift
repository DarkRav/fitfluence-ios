import Foundation
import Observation
import SwiftUI

@Observable
final class RestTimerModel {
    private var task: Task<Void, Never>?
    private var initialSeconds = 0

    var isVisible = false
    var isRunning = false
    var remainingSeconds = 0

    deinit {
        task?.cancel()
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        task?.cancel()
        initialSeconds = seconds
        remainingSeconds = seconds
        isVisible = true
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.remainingSeconds > 0, self.isRunning {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || !self.isRunning { break }
                self.remainingSeconds -= 1
            }
            if self.remainingSeconds == 0 {
                self.isVisible = false
                self.isRunning = false
            }
        }
    }

    func pauseOrResume() {
        if isRunning {
            isRunning = false
            task?.cancel()
            task = nil
        } else {
            start(seconds: remainingSeconds)
        }
    }

    func reset() {
        start(seconds: initialSeconds)
    }

    func add(seconds: Int) {
        guard seconds > 0 else { return }
        if !isVisible {
            start(seconds: seconds)
            return
        }

        task?.cancel()
        initialSeconds += seconds
        remainingSeconds += seconds
        isVisible = true
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.remainingSeconds > 0, self.isRunning {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || !self.isRunning { break }
                self.remainingSeconds -= 1
            }
            if self.remainingSeconds == 0 {
                self.isVisible = false
                self.isRunning = false
            }
        }
    }

    func skip() {
        task?.cancel()
        task = nil
        isVisible = false
        isRunning = false
        remainingSeconds = 0
    }
}

@Observable
@MainActor
final class WorkoutPlayerViewModel {
    struct ExerciseProgressItem: Equatable, Identifiable {
        let id: String
        let title: String
        let completedSets: Int
        let totalSets: Int
        let isCurrent: Bool
        let isSkipped: Bool
    }

    struct CompletionSummary: Equatable, Sendable {
        let workoutTitle: String
        let completedExercises: Int
        let totalExercises: Int
        let completedSets: Int
        let totalSets: Int
    }

    private(set) var session: WorkoutSessionState?
    private let sessionManager: WorkoutSessionManager
    private let workout: WorkoutDetailsModel
    private let userSub: String
    private let programId: String
    private let source: WorkoutSource

    var restTimer = RestTimerModel()
    var isLoading = false
    var isExitConfirmationPresented = false
    var isFinishEarlyConfirmationPresented = false
    var isFinished = false
    var toastMessage: String?
    var completionSummary: CompletionSummary?

    init(
        userSub: String,
        programId: String,
        workout: WorkoutDetailsModel,
        source: WorkoutSource = .program,
        sessionManager: WorkoutSessionManager = WorkoutSessionManager(),
    ) {
        self.userSub = userSub
        self.programId = programId
        self.workout = workout
        self.source = source
        self.sessionManager = sessionManager
    }

    var title: String {
        workout.title
    }

    var currentExerciseIndex: Int {
        session?.currentExerciseIndex ?? 0
    }

    var currentExercise: WorkoutExercise? {
        guard workout.exercises.indices.contains(currentExerciseIndex) else { return nil }
        return workout.exercises[currentExerciseIndex]
    }

    var currentExerciseState: SessionExerciseState? {
        guard let exercise = currentExercise else { return nil }
        return session?.exercises.first(where: { $0.exerciseId == exercise.id })
    }

    var progressLabel: String {
        let current = min(workout.exercises.count, currentExerciseIndex + 1)
        return "Упражнение \(max(1, current)) из \(max(1, workout.exercises.count))"
    }

    var isLastExercise: Bool {
        workout.exercises.isEmpty || currentExerciseIndex >= workout.exercises.count - 1
    }

    var primaryBottomTitle: String {
        isLastExercise ? "Завершить тренировку" : "Следующее упражнение"
    }

    var progressItems: [ExerciseProgressItem] {
        workout.exercises.map { exercise in
            let state = session?.exercises.first(where: { $0.exerciseId == exercise.id })
            let completed = state?.sets.filter(\.isCompleted).count ?? 0
            let total = state?.sets.count ?? max(1, exercise.sets)
            return ExerciseProgressItem(
                id: exercise.id,
                title: exercise.name,
                completedSets: completed,
                totalSets: total,
                isCurrent: exercise.id == currentExercise?.id,
                isSkipped: state?.isSkipped ?? false,
            )
        }
    }

    func onAppear() async {
        isLoading = true
        session = await sessionManager.loadOrCreateSession(
            userSub: userSub,
            programId: programId,
            workout: workout,
            source: source,
        )
        isLoading = false
    }

    func toggleSetComplete(setIndex: Int) async {
        guard let currentExercise, let session else { return }
        self.session = await sessionManager.toggleSetComplete(
            session,
            exerciseId: currentExercise.id,
            setIndex: setIndex,
        )
        if let rest = currentExercise.restSeconds {
            restTimer.start(seconds: rest)
        }
    }

    func incrementWeight(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.weightText, step: 2.5)
    }

    func decrementWeight(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.weightText, step: -2.5)
    }

    func incrementReps(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.repsText, step: 1)
    }

    func decrementReps(setIndex: Int) async {
        await updateNumericField(setIndex: setIndex, keyPath: \.repsText, step: -1)
    }

    func nextExercise() async {
        guard let session else { return }
        self.session = await sessionManager.moveExercise(session, to: currentExerciseIndex + 1)
    }

    func prevExercise() async {
        guard let session else { return }
        self.session = await sessionManager.moveExercise(session, to: currentExerciseIndex - 1)
    }

    func skipExercise() async {
        guard let currentExercise, let session else { return }
        self.session = await sessionManager.skipExercise(session, exerciseId: currentExercise.id)
        toastMessage = "Упражнение пропущено"
    }

    func undoLastChange() async {
        guard let session else { return }
        self.session = await sessionManager.undo(session)
        toastMessage = "Последнее действие отменено"
    }

    func jumpToExercise(_ exerciseID: String) async {
        guard let targetIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let session else { return }
        self.session = await sessionManager.moveExercise(session, to: targetIndex)
    }

    func copyPreviousSet(setIndex: Int) async {
        guard setIndex > 0,
              let currentExercise,
              let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex),
              exerciseState.sets.indices.contains(setIndex - 1),
              let session
        else {
            return
        }

        let previous = exerciseState.sets[setIndex - 1]
        self.session = await sessionManager.updateSetReps(
            session,
            exerciseId: currentExercise.id,
            setIndex: setIndex,
            reps: previous.repsText,
        )
        if let updated = self.session {
            self.session = await sessionManager.updateSetWeight(
                updated,
                exerciseId: currentExercise.id,
                setIndex: setIndex,
                weight: previous.weightText,
            )
        }
        toastMessage = "Скопированы значения из прошлого подхода"
    }

    func addRest(seconds: Int) {
        restTimer.add(seconds: seconds)
    }

    func primaryBottomAction() async {
        if isLastExercise {
            await finish()
        } else {
            await nextExercise()
        }
    }

    func finish() async {
        guard let session else { return }
        let completedExercises = session.exercises.count(where: { exercise in
            !exercise.isSkipped && exercise.sets.contains(where: \.isCompleted)
        })
        completionSummary = CompletionSummary(
            workoutTitle: workout.title,
            completedExercises: completedExercises,
            totalExercises: workout.exercises.count,
            completedSets: session.completedSetsCount,
            totalSets: session.totalSetsCount,
        )
        await sessionManager.finish(session)
        isFinished = true
    }

    private func updateNumericField(
        setIndex: Int,
        keyPath: WritableKeyPath<SessionSetState, String>,
        step: Double,
    ) async {
        guard let currentExercise, let exerciseState = currentExerciseState,
              exerciseState.sets.indices.contains(setIndex)
        else {
            return
        }
        let currentValue = Double(exerciseState.sets[setIndex][keyPath: keyPath]) ?? 0
        let next = max(0, currentValue + step)
        let nextString = if abs(step).truncatingRemainder(dividingBy: 1) > 0 {
            String(format: "%.1f", next)
        } else {
            String(Int(next))
        }
        guard let session else { return }
        if keyPath == \SessionSetState.weightText {
            self.session = await sessionManager.updateSetWeight(
                session,
                exerciseId: currentExercise.id,
                setIndex: setIndex,
                weight: nextString,
            )
        } else {
            self.session = await sessionManager.updateSetReps(
                session,
                exerciseId: currentExercise.id,
                setIndex: setIndex,
                reps: nextString,
            )
        }
    }
}

struct WorkoutPlayerViewV2: View {
    @State var viewModel: WorkoutPlayerViewModel
    let onExit: () -> Void
    let onFinish: (WorkoutPlayerViewModel.CompletionSummary) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                FFLoadingState(title: "Открываем тренировку")
            } else {
                ScrollView {
                    VStack(spacing: FFSpacing.md) {
                        topPanel
                        exerciseCard
                        setsCard
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.top, FFSpacing.md)
                    .padding(.bottom, FFSpacing.xl)
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar
                }
            }
        }
        .background(FFColors.background)
        .task { await viewModel.onAppear() }
        .alert("Завершить тренировку?", isPresented: $viewModel.isExitConfirmationPresented) {
            Button("Остаться", role: .cancel) {}
            Button("Выйти", role: .destructive) { onExit() }
        } message: {
            Text("Прогресс сохранится на устройстве.")
        }
        .alert("Завершить раньше?", isPresented: $viewModel.isFinishEarlyConfirmationPresented) {
            Button("Отмена", role: .cancel) {}
            Button("Завершить", role: .destructive) {
                Task { await viewModel.finish() }
            }
        } message: {
            Text("Текущий прогресс сохранится в историю тренировки.")
        }
        .onChange(of: viewModel.isFinished) { _, isFinished in
            if isFinished, let summary = viewModel.completionSummary {
                onFinish(summary)
            }
        }
        .overlay(alignment: .top) {
            if let message = viewModel.toastMessage {
                Text(message)
                    .font(FFTypography.caption.weight(.semibold))
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.xs)
                    .background(FFColors.gray700)
                    .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                    .padding(.top, FFSpacing.md)
                    .task {
                        try? await Task.sleep(for: .seconds(1.2))
                        viewModel.toastMessage = nil
                    }
            }
        }
    }

    private var topPanel: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                HStack {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(viewModel.title)
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        Text(viewModel.progressLabel)
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                    Spacer()
                    Button("Выйти") { viewModel.isExitConfirmationPresented = true }
                        .font(FFTypography.caption.weight(.semibold))
                        .foregroundStyle(FFColors.danger)
                        .frame(minWidth: 44, minHeight: 44)
                }
                Text("Оффлайн: изменения сохраняются на устройстве")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.accent)
            }
        }
    }

    private var exerciseCard: some View {
        FFCard {
            if let exercise = viewModel.currentExercise {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    Text(exercise.name)
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                    Text(prescription(for: exercise))
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                    HStack(spacing: FFSpacing.sm) {
                        FFButton(title: "Пропустить", variant: .secondary) {
                            Task { await viewModel.skipExercise() }
                        }
                        FFButton(title: "Отменить", variant: .secondary) {
                            Task { await viewModel.undoLastChange() }
                        }
                    }
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Прогресс")
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: FFSpacing.xs) {
                                ForEach(viewModel.progressItems) { item in
                                    Button {
                                        Task { await viewModel.jumpToExercise(item.id) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(FFTypography.caption)
                                                .lineLimit(1)
                                            Text("\(item.completedSets)/\(item.totalSets)")
                                                .font(FFTypography.caption.weight(.semibold))
                                        }
                                        .foregroundStyle(item.isCurrent ? FFColors.background : FFColors.textPrimary)
                                        .padding(.horizontal, FFSpacing.sm)
                                        .padding(.vertical, FFSpacing.xs)
                                        .frame(minHeight: 44)
                                        .background(item.isCurrent ? FFColors.accent : FFColors.gray700)
                                        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                                        .opacity(item.isSkipped ? 0.45 : 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var setsCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Подходы")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                if let exerciseState = viewModel.currentExerciseState {
                    ForEach(Array(exerciseState.sets.enumerated()), id: \.offset) { index, set in
                        HStack(spacing: FFSpacing.sm) {
                            Button {
                                Task { await viewModel.toggleSetComplete(setIndex: index) }
                            } label: {
                                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(set.isCompleted ? FFColors.accent : FFColors.textSecondary)
                                    .frame(width: 44, height: 44)
                            }
                            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                                Text("Подход \(index + 1)")
                                    .font(FFTypography.body.weight(.semibold))
                                HStack(spacing: FFSpacing.xs) {
                                    numericChip(title: "−2.5") {
                                        Task { await viewModel.decrementWeight(setIndex: index) }
                                    }
                                    Text("Вес \(set.weightText.isEmpty ? "0" : set.weightText)")
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                    numericChip(title: "+2.5") {
                                        Task { await viewModel.incrementWeight(setIndex: index) }
                                    }
                                }
                                HStack(spacing: FFSpacing.xs) {
                                    numericChip(title: "−1") { Task { await viewModel.decrementReps(setIndex: index) } }
                                    Text("Повторы \(set.repsText.isEmpty ? "0" : set.repsText)")
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                    numericChip(title: "+1") { Task { await viewModel.incrementReps(setIndex: index) } }
                                }
                                if index > 0 {
                                    Button("Копировать прошлый подход") {
                                        Task { await viewModel.copyPreviousSet(setIndex: index) }
                                    }
                                    .font(FFTypography.caption.weight(.semibold))
                                    .foregroundStyle(FFColors.accent)
                                    .frame(minHeight: 44)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, FFSpacing.xs)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: FFSpacing.xs) {
            if viewModel.restTimer.isVisible {
                FFCard(padding: FFSpacing.sm) {
                    HStack {
                        Text("Отдых: \(formattedTime(viewModel.restTimer.remainingSeconds))")
                            .font(FFTypography.h2)
                        Spacer()
                        FFButton(
                            title: viewModel.restTimer.isRunning ? "Пауза" : "Продолжить",
                            variant: .secondary,
                            action: { viewModel.restTimer.pauseOrResume() },
                        )
                        FFButton(title: "+15", variant: .secondary) { viewModel.addRest(seconds: 15) }
                        FFButton(title: "+30", variant: .secondary) { viewModel.addRest(seconds: 30) }
                        FFButton(title: "Сброс", variant: .secondary) { viewModel.restTimer.reset() }
                        FFButton(title: "Пропустить", variant: .destructive) { viewModel.restTimer.skip() }
                    }
                }
            }
            FFCard(padding: FFSpacing.sm) {
                HStack(spacing: FFSpacing.sm) {
                    FFButton(title: "Назад", variant: .secondary) {
                        Task { await viewModel.prevExercise() }
                    }
                    FFButton(title: viewModel.primaryBottomTitle, variant: .primary) {
                        Task { await viewModel.primaryBottomAction() }
                    }
                    FFButton(title: "Завершить раньше", variant: .secondary) {
                        viewModel.isFinishEarlyConfirmationPresented = true
                    }
                }
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.top, FFSpacing.xs)
        .padding(.bottom, FFSpacing.sm)
        .background(FFColors.background.opacity(0.96))
    }

    private func prescription(for exercise: WorkoutExercise) -> String {
        let reps = if let min = exercise.repsMin, let max = exercise.repsMax {
            "\(min)-\(max)"
        } else if let min = exercise.repsMin {
            "\(min)"
        } else {
            "по самочувствию"
        }
        let rest = exercise.restSeconds.map { "\($0) сек" } ?? "без таймера"
        return "\(exercise.sets) подходов • \(reps) повторов • отдых \(rest)"
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func numericChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
                .padding(.horizontal, FFSpacing.sm)
                .padding(.vertical, FFSpacing.xs)
                .background(FFColors.gray700)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
                .frame(minHeight: 44)
        }
    }
}

struct WorkoutCompletionViewV2: View {
    let summary: WorkoutPlayerViewModel.CompletionSummary
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: FFSpacing.md) {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Тренировка завершена")
                        .font(FFTypography.h1)
                        .foregroundStyle(FFColors.textPrimary)
                    Text(summary.workoutTitle)
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.xs) {
                    Text("Итог")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Text("Упражнений: \(summary.completedExercises) из \(summary.totalExercises)")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                    Text("Подходов: \(summary.completedSets) из \(summary.totalSets)")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                }
            }

            FFButton(title: "Готово", variant: .primary, action: onDone)
            Spacer()
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.md)
        .background(FFColors.background)
    }
}

#Preview("Workout Player V2") {
    NavigationStack {
        WorkoutPlayerViewV2(
            viewModel: WorkoutPlayerViewModel(
                userSub: "athlete-1",
                programId: "program-1",
                workout: WorkoutDetailsModel(
                    id: "w1",
                    title: "Силовая A",
                    dayOrder: 1,
                    coachNote: nil,
                    exercises: [
                        WorkoutExercise(
                            id: "e1",
                            name: "Жим лёжа",
                            sets: 4,
                            repsMin: 6,
                            repsMax: 8,
                            targetRpe: 8,
                            restSeconds: 90,
                            notes: nil,
                            orderIndex: 0,
                        ),
                    ],
                ),
            ),
            onExit: {},
            onFinish: { _ in },
        )
    }
}
