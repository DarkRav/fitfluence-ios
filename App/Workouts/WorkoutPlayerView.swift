import ComposableArchitecture
import Foundation
import Observation
import SwiftUI

struct WorkoutPlayerView: View {
    let store: StoreOf<WorkoutPlayerFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: FFSpacing.md) {
                    if viewStore.isShowingCachedData {
                        offlineCard
                    }

                    if viewStore.isLoading, viewStore.workout == nil {
                        FFLoadingState(title: "Открываем тренировку")
                    } else if let error = viewStore.error, viewStore.workout == nil {
                        FFErrorState(
                            title: error.title,
                            message: error.message,
                            retryTitle: "Повторить",
                        ) {
                            viewStore.send(.retry)
                        }
                    } else if let workout = viewStore.workout {
                        topPanel(workout: workout, viewStore: viewStore)

                        if workout.exercises.isEmpty {
                            FFEmptyState(
                                title: "В тренировке нет упражнений",
                                message: "Состав тренировки пока пуст. Вернитесь к программе и выберите другую тренировку.",
                            )
                        } else {
                            exerciseCard(workout: workout, viewStore: viewStore)
                            setsBlock(workout: workout, viewStore: viewStore)
                        }
                    }
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.top, FFSpacing.md)
                .padding(.bottom, FFSpacing.xl)
            }
            .background(FFColors.background)
            .safeAreaInset(edge: .bottom) {
                if let workout = viewStore.workout, !workout.exercises.isEmpty {
                    VStack(spacing: FFSpacing.xs) {
                        if let restTimer = viewStore.restTimer {
                            restTimerCard(restTimer: restTimer, viewStore: viewStore)
                        }
                        stickyActions(workout: workout, viewStore: viewStore)
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.top, FFSpacing.xs)
                    .background(FFColors.background.opacity(0.96))
                }
            }
            .navigationBarBackButtonHidden(true)
            .alert(
                "Завершить тренировку?",
                isPresented: viewStore.binding(
                    get: \.isExitConfirmationPresented,
                    send: { isPresented in
                        isPresented ? .exitTapped : .exitConfirmationDismissed
                    },
                ),
            ) {
                Button("Остаться", role: .cancel) {
                    viewStore.send(.exitConfirmationDismissed)
                }
                Button("Выйти", role: .destructive) {
                    viewStore.send(.exitConfirmed)
                }
            } message: {
                Text("Прогресс сохранится на устройстве.")
            }
            .alert(
                "Продолжить тренировку?",
                isPresented: viewStore.binding(
                    get: \.isResumePromptPresented,
                    send: { _ in .resumePromptContinueTapped },
                ),
            ) {
                Button("Продолжить") {
                    viewStore.send(.resumePromptContinueTapped)
                }
                Button("Начать заново", role: .destructive) {
                    viewStore.send(.resumePromptStartOverTapped)
                }
            } message: {
                Text("Найден сохранённый прогресс этой тренировки на устройстве.")
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }

    private var offlineCard: some View {
        FFCard {
            Text("Оффлайн: показаны сохранённые данные")
                .font(FFTypography.caption.weight(.semibold))
                .foregroundStyle(FFColors.primary)
        }
    }

    private func topPanel(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let total = max(1, workout.exercises.count)
        let current = min(total, viewStore.currentExerciseIndex + 1)

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack(alignment: .top, spacing: FFSpacing.sm) {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(workout.title)
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text("Упражнение \(current) из \(total)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }

                    Spacer(minLength: FFSpacing.xs)

                    Button("Выйти") {
                        viewStore.send(.exitTapped)
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.danger)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Выйти из тренировки")
                }

                ProgressView(value: Double(current), total: Double(total))
                    .tint(FFColors.accent)

                Text("Отметьте выполненные подходы")
                    .font(FFTypography.caption)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    private func exerciseCard(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let exercise = workout.exercises[viewStore.currentExerciseIndex]

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text(exercise.name)
                    .font(FFTypography.h1)
                    .foregroundStyle(FFColors.textPrimary)
                    .multilineTextAlignment(.leading)

                Text(prescriptionText(for: exercise))
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
                    .multilineTextAlignment(.leading)

                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.gray300)
                }

                if viewStore.progressStorageMode == .localOnly {
                    Text("Оффлайн: изменения сохраняются на устройстве")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.accent)
                }
            }
        }
    }

    private func setsBlock(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let exercise = workout.exercises[viewStore.currentExerciseIndex]
        let progress = viewStore.perExerciseState[exercise.id]

        return FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Подходы")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                ForEach(Array((progress?.sets ?? []).enumerated()), id: \.offset) { index, setState in
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        HStack(spacing: FFSpacing.sm) {
                            Text("Подход \(index + 1)")
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)

                            Spacer(minLength: FFSpacing.xs)

                            Button {
                                viewStore.send(.toggleSetComplete(exerciseId: exercise.id, setIndex: index))
                            } label: {
                                Label(
                                    setState.isCompleted ? "Выполнено" : "Отметить",
                                    systemImage: setState.isCompleted ? "checkmark.circle.fill" : "circle",
                                )
                                .font(FFTypography.caption.weight(.semibold))
                                .foregroundStyle(setState.isCompleted ? FFColors.accent : FFColors.textSecondary)
                            }
                            .frame(minHeight: 44)
                            .accessibilityLabel("Подход \(index + 1)")
                            .accessibilityValue(setState.isCompleted ? "Выполнено" : "Не выполнено")
                        }

                        FFTextField(
                            label: "Вес",
                            placeholder: "кг",
                            text: Binding(
                                get: { setState.weightText },
                                set: { value in
                                    viewStore.send(
                                        .updateSetWeight(exerciseId: exercise.id, setIndex: index, value: value),
                                    )
                                },
                            ),
                            helperText: "Например, 40",
                            keyboardType: .decimalPad,
                        )
                        numericStepperRow(
                            minusLabel: "Уменьшить вес",
                            plusLabel: "Увеличить вес",
                        ) {
                            viewStore.send(.decrementSetWeight(exerciseId: exercise.id, setIndex: index))
                        } onPlus: {
                            viewStore.send(.incrementSetWeight(exerciseId: exercise.id, setIndex: index))
                        }

                        FFTextField(
                            label: "Повторы",
                            placeholder: "количество",
                            text: Binding(
                                get: { setState.repsText },
                                set: { value in
                                    viewStore.send(
                                        .updateSetReps(exerciseId: exercise.id, setIndex: index, value: value),
                                    )
                                },
                            ),
                            helperText: "Например, 10",
                            keyboardType: .numberPad,
                        )
                        numericStepperRow(
                            minusLabel: "Уменьшить повторы",
                            plusLabel: "Увеличить повторы",
                        ) {
                            viewStore.send(.decrementSetReps(exerciseId: exercise.id, setIndex: index))
                        } onPlus: {
                            viewStore.send(.incrementSetReps(exerciseId: exercise.id, setIndex: index))
                        }

                        FFTextField(
                            label: "Нагрузка (RPE)",
                            placeholder: "уровень",
                            text: Binding(
                                get: { setState.rpeText },
                                set: { value in
                                    viewStore.send(
                                        .updateSetRPE(exerciseId: exercise.id, setIndex: index, value: value),
                                    )
                                },
                            ),
                            helperText: "Например, 8 из 10",
                            keyboardType: .decimalPad,
                        )
                    }
                    .padding(.vertical, FFSpacing.xs)

                    if index < (progress?.sets.count ?? 0) - 1 {
                        Divider()
                            .overlay(FFColors.gray700)
                    }
                }
            }
        }
    }

    private func stickyActions(
        workout: WorkoutDetailsModel,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        let isFirst = viewStore.currentExerciseIndex == 0
        let isLast = viewStore.currentExerciseIndex >= max(0, workout.exercises.count - 1)

        return FFCard(padding: FFSpacing.sm) {
            VStack(spacing: FFSpacing.sm) {
                HStack(spacing: FFSpacing.sm) {
                    FFButton(
                        title: "Назад",
                        variant: isFirst ? .disabled : .secondary,
                        action: { viewStore.send(.prevExerciseTapped) },
                    )

                    FFButton(
                        title: isLast ? "Завершить тренировку" : "Следующее упражнение",
                        variant: .primary,
                        action: {
                            if isLast {
                                viewStore.send(.finishWorkoutTapped)
                            } else {
                                viewStore.send(.nextExerciseTapped)
                            }
                        },
                    )
                }
            }
        }
    }

    private func restTimerCard(
        restTimer: WorkoutPlayerFeature.RestTimerState,
        viewStore: ViewStore<WorkoutPlayerFeature.State, WorkoutPlayerFeature.Action>,
    ) -> some View {
        FFCard(padding: FFSpacing.sm) {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Отдых: \(formattedTime(restTimer.remainingSeconds))")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                HStack(spacing: FFSpacing.sm) {
                    FFButton(
                        title: restTimer.isRunning ? "Пауза" : "Продолжить",
                        variant: .secondary,
                        action: { viewStore.send(.restTimerPauseTapped) },
                    )
                    FFButton(
                        title: "Сброс",
                        variant: .secondary,
                        action: { viewStore.send(.restTimerResetTapped) },
                    )
                    FFButton(
                        title: "Пропустить",
                        variant: .destructive,
                        action: { viewStore.send(.restTimerSkipTapped) },
                    )
                }
            }
        }
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func numericStepperRow(
        minusLabel: String,
        plusLabel: String,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void,
    ) -> some View {
        HStack(spacing: FFSpacing.sm) {
            stepperButton(title: "−", accessibility: minusLabel, action: onMinus)
            stepperButton(title: "+", accessibility: plusLabel, action: onPlus)
            Spacer()
        }
    }

    private func stepperButton(title: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FFTypography.body.weight(.bold))
                .foregroundStyle(FFColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(FFColors.gray700)
                .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        }
        .accessibilityLabel(accessibility)
    }

    private func prescriptionText(for exercise: WorkoutExercise) -> String {
        let repsPart = if let min = exercise.repsMin, let max = exercise.repsMax {
            "\(min)-\(max) повторов"
        } else if let min = exercise.repsMin {
            "\(min) повторов"
        } else {
            "повторы не указаны"
        }

        let rpePart = exercise.targetRpe.map { "Нагрузка RPE \($0)" } ?? "Нагрузка не указана"
        let restPart = exercise.restSeconds.map { "Отдых \($0) сек" } ?? "Отдых по самочувствию"
        return "\(exercise.sets) подходов • \(repsPart) • \(rpePart) • \(restPart)"
    }
}

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
    private(set) var session: WorkoutSessionState?
    private let sessionManager: WorkoutSessionManager
    private let workout: WorkoutDetailsModel
    private let userSub: String
    private let programId: String

    var restTimer = RestTimerModel()
    var isLoading = false
    var isExitConfirmationPresented = false
    var isFinished = false
    var toastMessage: String?

    init(
        userSub: String,
        programId: String,
        workout: WorkoutDetailsModel,
        sessionManager: WorkoutSessionManager = WorkoutSessionManager(),
    ) {
        self.userSub = userSub
        self.programId = programId
        self.workout = workout
        self.sessionManager = sessionManager
    }

    var title: String { workout.title }

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

    func onAppear() async {
        isLoading = true
        session = await sessionManager.loadOrCreateSession(userSub: userSub, programId: programId, workout: workout)
        isLoading = false
    }

    func toggleSetComplete(setIndex: Int) async {
        guard let currentExercise, let session else { return }
        self.session = await sessionManager.toggleSetComplete(session, exerciseId: currentExercise.id, setIndex: setIndex)
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

    func finish() async {
        guard let session else { return }
        await sessionManager.finish(session)
        isFinished = true
    }

    private func updateNumericField(
        setIndex: Int,
        keyPath: WritableKeyPath<SessionSetState, String>,
        step: Double,
    ) async {
        guard let currentExercise, let exerciseState = currentExerciseState, exerciseState.sets.indices.contains(setIndex) else {
            return
        }
        let currentValue = Double(exerciseState.sets[setIndex][keyPath: keyPath]) ?? 0
        let next = max(0, currentValue + step)
        let nextString: String = if abs(step).truncatingRemainder(dividingBy: 1) > 0 {
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
    let onFinish: () -> Void

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
        .onChange(of: viewModel.isFinished) { _, isFinished in
            if isFinished { onFinish() }
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
                                    numericChip(title: "−2.5") { Task { await viewModel.decrementWeight(setIndex: index) } }
                                    Text("Вес \(set.weightText.isEmpty ? "0" : set.weightText)")
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                    numericChip(title: "+2.5") { Task { await viewModel.incrementWeight(setIndex: index) } }
                                }
                                HStack(spacing: FFSpacing.xs) {
                                    numericChip(title: "−1") { Task { await viewModel.decrementReps(setIndex: index) } }
                                    Text("Повторы \(set.repsText.isEmpty ? "0" : set.repsText)")
                                        .font(FFTypography.caption)
                                        .foregroundStyle(FFColors.textSecondary)
                                    numericChip(title: "+1") { Task { await viewModel.incrementReps(setIndex: index) } }
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
                    FFButton(title: "Следующее упражнение", variant: .primary) {
                        Task { await viewModel.nextExercise() }
                    }
                    FFButton(title: "Завершить", variant: .primary) {
                        Task { await viewModel.finish() }
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
            onFinish: {},
        )
    }
}
