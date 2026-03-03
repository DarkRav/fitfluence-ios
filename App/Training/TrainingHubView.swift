import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class TrainingHubViewModel {
    private let userSub: String
    private let trainingStore: TrainingStore
    private let progressStore: WorkoutProgressStore
    private let cacheStore: CacheStore

    var isLoading = false
    var activeSession: ActiveWorkoutSession?
    var templates: [WorkoutTemplateDraft] = []
    var recentHistory: [CompletedWorkoutRecord] = []
    var allHistory: [CompletedWorkoutRecord] = []
    var lastCompleted: CompletedWorkoutRecord?

    init(
        userSub: String,
        trainingStore: TrainingStore = LocalTrainingStore(),
        progressStore: WorkoutProgressStore = LocalWorkoutProgressStore(),
        cacheStore: CacheStore = CompositeCacheStore(),
    ) {
        self.userSub = userSub
        self.trainingStore = trainingStore
        self.progressStore = progressStore
        self.cacheStore = cacheStore
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        guard !userSub.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        async let active = progressStore.latestActiveSession(userSub: userSub)
        async let loadedTemplates = trainingStore.templates(userSub: userSub)
        async let history = trainingStore.history(userSub: userSub, source: nil, limit: 180)

        let activeCandidate = await active
        if let activeCandidate, await canLaunch(session: activeCandidate) {
            activeSession = activeCandidate
        } else {
            activeSession = nil
        }
        templates = await Array(loadedTemplates.prefix(4))
        allHistory = await history
        recentHistory = Array(allHistory.prefix(8))
        lastCompleted = recentHistory.first
    }

    func workout(for template: WorkoutTemplateDraft) -> WorkoutDetailsModel {
        let exercises = template.exercises.enumerated().map { index, item in
            WorkoutExercise(
                id: "template-\(template.id)-\(item.id)-\(index)",
                name: item.name,
                sets: max(1, item.sets),
                repsMin: max(1, item.repsMin ?? 8),
                repsMax: max(item.repsMin ?? 8, item.repsMax ?? max(10, item.repsMin ?? 8)),
                targetRpe: nil,
                restSeconds: max(0, item.restSeconds ?? 90),
                notes: nil,
                orderIndex: index,
            )
        }

        return WorkoutDetailsModel.quickWorkout(
            title: template.name,
            exercises: exercises,
        )
    }

    private func canLaunch(session: ActiveWorkoutSession) async -> Bool {
        if session.source == .program, UUID(uuidString: session.programId) != nil {
            return true
        }
        if await cacheStore.get(
            "workout.details:\(session.programId):\(session.workoutId)",
            as: WorkoutDetailsModel.self,
            namespace: userSub,
        ) != nil {
            return true
        }
        if let snapshot = await progressStore.load(
            userSub: session.userSub,
            programId: session.programId,
            workoutId: session.workoutId,
        ),
            snapshot.workoutDetails != nil
        {
            return true
        }
        return false
    }

    var workoutsLast7Days: Int {
        let lowerBound = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))
            ?? Date()
        return allHistory.count(where: { $0.finishedAt >= lowerBound })
    }

    var totalMinutesLast7Days: Int {
        let lowerBound = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))
            ?? Date()
        return allHistory
            .filter { $0.finishedAt >= lowerBound }
            .reduce(0) { $0 + max(1, $1.durationSeconds / 60) }
    }
}

struct TrainingHubView: View {
    @State var viewModel: TrainingHubViewModel

    let onContinueSession: (ActiveWorkoutSession) -> Void
    let onStartQuickWorkout: () -> Void
    let onOpenTemplates: () -> Void
    let onRepeatWorkout: (CompletedWorkoutRecord) -> Void
    let onStartTemplate: (WorkoutTemplateDraft) -> Void
    let onOpenProgress: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                headerCard
                activeSessionCard
                quickActionsCard
                progressEntryCard
                templatesCard
                historyCard
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Тренировка")
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.onAppear()
        }
    }

    private var headerCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.xs) {
                Text("Тренируйтесь без лишних шагов")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)
                Text("Быстрый старт, шаблоны и продолжение незавершённой сессии в одном месте.")
                    .font(FFTypography.body)
                    .foregroundStyle(FFColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var activeSessionCard: some View {
        if let session = viewModel.activeSession {
            FFCard {
                VStack(alignment: .leading, spacing: FFSpacing.sm) {
                    HStack {
                        Text("Незавершённая тренировка")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)
                        Spacer()
                        FFBadge(status: .inProgress)
                    }

                    Text("Последнее изменение: \(session.lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)

                    FFButton(title: "Продолжить", variant: .primary) {
                        onContinueSession(session)
                    }
                    .accessibilityHint("Открывает текущую сессию")
                }
            }
        }
    }

    private var quickActionsCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Быстрые действия")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                VStack(spacing: FFSpacing.xs) {
                    actionTile(
                        title: "Быстрая тренировка",
                        subtitle: "Соберите сессию из упражнений за минуту",
                        systemImage: "bolt.fill",
                        action: onStartQuickWorkout,
                    )
                    actionTile(
                        title: "Шаблоны",
                        subtitle: "Создайте, отредактируйте и запустите свой шаблон",
                        systemImage: "square.stack.3d.up.fill",
                        action: onOpenTemplates,
                    )

                    if let last = viewModel.lastCompleted {
                        actionTile(
                            title: "Повторить последнюю",
                            subtitle: "\(last.workoutTitle) • \(max(1, last.durationSeconds / 60)) мин",
                            systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                            action: { onRepeatWorkout(last) },
                        )
                    }
                }
            }
        }
    }

    private var templatesCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    Text("Мои шаблоны")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    Button("Все шаблоны") {
                        onOpenTemplates()
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.accent)
                }

                if viewModel.templates.isEmpty {
                    Text("Шаблоны пока не созданы. Начните с \"Быстрой тренировки\" и сохраните удачный набор.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                } else {
                    ForEach(viewModel.templates) { template in
                        HStack(spacing: FFSpacing.sm) {
                            VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                                Text(template.name)
                                    .font(FFTypography.body.weight(.semibold))
                                    .foregroundStyle(FFColors.textPrimary)
                                Text(templateSubtitle(template))
                                    .font(FFTypography.caption)
                                    .foregroundStyle(FFColors.textSecondary)
                            }
                            Spacer()
                            Button("Старт") {
                                onStartTemplate(template)
                            }
                            .font(FFTypography.caption.weight(.semibold))
                            .foregroundStyle(FFColors.accent)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .padding(.vertical, FFSpacing.xxs)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(template.name). \(templateSubtitle(template))")
                    }
                }
            }
        }
    }

    private var historyCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                HStack {
                    Text("Недавние тренировки")
                        .font(FFTypography.h2)
                        .foregroundStyle(FFColors.textPrimary)
                    Spacer()
                    Button("Все") {
                        onOpenProgress()
                    }
                    .font(FFTypography.caption.weight(.semibold))
                    .foregroundStyle(FFColors.accent)
                }

                if viewModel.recentHistory.isEmpty {
                    Text("Здесь появятся завершённые тренировки.")
                        .font(FFTypography.body)
                        .foregroundStyle(FFColors.textSecondary)
                } else {
                    ForEach(viewModel.recentHistory.prefix(3)) { record in
                        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                            Text(record.workoutTitle)
                                .font(FFTypography.body.weight(.semibold))
                                .foregroundStyle(FFColors.textPrimary)
                            Text(record.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(FFTypography.caption)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, FFSpacing.xxs)
                    }
                }
            }
        }
    }

    private var progressEntryCard: some View {
        FFCard {
            VStack(alignment: .leading, spacing: FFSpacing.sm) {
                Text("Прогресс и история")
                    .font(FFTypography.h2)
                    .foregroundStyle(FFColors.textPrimary)

                HStack(spacing: FFSpacing.sm) {
                    progressMetric(title: "За 7 дней", value: "\(viewModel.workoutsLast7Days)")
                    progressMetric(title: "Минут", value: "\(viewModel.totalMinutesLast7Days)")
                }

                FFButton(title: "Открыть прогресс", variant: .secondary, action: onOpenProgress)
            }
        }
    }

    private func progressMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: FFSpacing.xxs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(FFTypography.h2)
                .foregroundStyle(FFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FFSpacing.sm)
        .background(FFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                .stroke(FFColors.gray700, lineWidth: 1)
        }
    }

    private func actionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FFSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                        .fill(FFColors.primary.opacity(0.2))
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FFColors.primary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: FFSpacing.xxs) {
                    Text(title)
                        .font(FFTypography.body.weight(.semibold))
                        .foregroundStyle(FFColors.textPrimary)
                    Text(subtitle)
                        .font(FFTypography.caption)
                        .foregroundStyle(FFColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FFColors.textSecondary)
            }
            .padding(.horizontal, FFSpacing.sm)
            .padding(.vertical, FFSpacing.xs)
            .background(FFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: FFTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: FFTheme.Radius.control)
                    .stroke(FFColors.gray700, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private func templateSubtitle(_ template: WorkoutTemplateDraft) -> String {
        let exercises = template.exercises.count
        let estMinutes = max(15, template.exercises.reduce(0) { $0 + max(1, $1.sets) * 2 })
        return "\(exercises) упражнений • ~\(estMinutes) мин"
    }
}

#Preview("С активной сессией") {
    NavigationStack {
        TrainingHubView(
            viewModel: TrainingHubViewModel(userSub: "preview"),
            onContinueSession: { _ in },
            onStartQuickWorkout: {},
            onOpenTemplates: {},
            onRepeatWorkout: { _ in },
            onStartTemplate: { _ in },
            onOpenProgress: {},
        )
    }
}
