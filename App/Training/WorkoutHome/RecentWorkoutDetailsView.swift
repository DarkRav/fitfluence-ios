import SwiftUI

struct RecentWorkoutDetailsView: View {
    let record: CompletedWorkoutRecord
    let onRepeat: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.md) {
                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text(record.workoutTitle)
                            .font(FFTypography.h1)
                            .foregroundStyle(FFColors.textPrimary)
                            .lineLimit(3)

                        Text("\(formattedDate) • \(sourceTitle)")
                            .font(FFTypography.caption)
                            .foregroundStyle(FFColors.textSecondary)
                    }
                }

                FFCard {
                    VStack(alignment: .leading, spacing: FFSpacing.xs) {
                        Text("Сводка")
                            .font(FFTypography.h2)
                            .foregroundStyle(FFColors.textPrimary)

                        metricRow(title: "Длительность", value: formattedDuration(record.durationSeconds))
                        metricRow(title: "Подходы", value: "\(record.completedSets) из \(max(record.totalSets, record.completedSets))")
                        metricRow(title: "Общий объём", value: "\(formattedVolume(record.volume)) кг")

                        if let overallRPE = record.overallRPE {
                            metricRow(title: "Общее RPE", value: "\(overallRPE)")
                        }
                    }
                }

                if let notes = trimmedNotes {
                    FFCard {
                        VStack(alignment: .leading, spacing: FFSpacing.xs) {
                            Text("Заметки")
                                .font(FFTypography.h2)
                                .foregroundStyle(FFColors.textPrimary)

                            Text(notes)
                                .font(FFTypography.body)
                                .foregroundStyle(FFColors.textSecondary)
                        }
                    }
                }

                FFButton(title: "Повторить тренировку", variant: .secondary) {
                    onRepeat()
                }
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.md)
        }
        .background(FFColors.background)
        .navigationTitle("Тренировка")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var formattedDate: String {
        record.finishedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var sourceTitle: String {
        switch record.source {
        case .program:
            return "программа"
        case .freestyle:
            return "быстрая тренировка"
        case .template:
            return "шаблон"
        }
    }

    private var trimmedNotes: String? {
        guard let notes = record.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return nil
        }
        return notes
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FFSpacing.xs) {
            Text(title)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)

            Spacer(minLength: FFSpacing.xs)

            Text(value)
                .font(FFTypography.body.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let totalSeconds = max(0, seconds)
        let minutes = totalSeconds / 60
        if minutes > 0 {
            return "\(minutes) мин"
        }
        return "\(totalSeconds) сек"
    }

    private func formattedVolume(_ volume: Double) -> String {
        if floor(volume) == volume {
            return "\(Int(volume))"
        }
        return String(format: "%.1f", volume)
    }
}

#Preview("Детали завершенной") {
    NavigationStack {
        RecentWorkoutDetailsView(
            record: CompletedWorkoutRecord(
                id: "preview",
                userSub: "preview",
                programId: "program",
                workoutId: "workout",
                workoutTitle: "Домашняя силовая",
                source: .program,
                startedAt: Date().addingTimeInterval(-2_400),
                finishedAt: Date(),
                durationSeconds: 2_400,
                completedSets: 14,
                totalSets: 16,
                volume: 1_560,
                notes: "Отличное самочувствие",
                overallRPE: 7,
            ),
            onRepeat: {},
        )
    }
}
