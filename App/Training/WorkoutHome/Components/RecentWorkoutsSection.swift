import Foundation
import SwiftUI

struct RecentWorkoutsSection: View {
    let workouts: [CompletedWorkoutRecord]
    let isLoading: Bool
    let onOpenWorkout: (CompletedWorkoutRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Последние тренировки")
                .font(.headline.weight(.semibold))
                .foregroundStyle(FFColors.textPrimary)

            if isLoading, workouts.isEmpty {
                compactMessageCard("Загружаем последние тренировки")
            } else if workouts.isEmpty {
                compactMessageCard("Здесь появится история после первой тренировки")
            } else {
                WorkoutCardContainer(cornerRadius: 20, padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(workouts.prefix(6).enumerated()), id: \.element.id) { index, workout in
                            Button {
                                onOpenWorkout(workout)
                            } label: {
                                RecentWorkoutRow(
                                    title: workout.workoutTitle,
                                    dateText: relativeDateText(for: workout.finishedAt),
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            if index < min(workouts.count, 6) - 1 {
                                Divider()
                                    .overlay(FFColors.gray700)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func compactMessageCard(_ text: String) -> some View {
        WorkoutCardContainer(cornerRadius: 20, padding: 12) {
            Text(text)
                .font(FFTypography.caption)
                .foregroundStyle(FFColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func relativeDateText(for date: Date) -> String {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)

        if target == today {
            return "Сегодня"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), target == yesterday {
            return "Вчера"
        }

        let dayDiff = calendar.dateComponents([.day], from: target, to: today).day ?? 0
        if dayDiff > 1, dayDiff < 5 {
            return "\(dayDiff) \(dayWord(for: dayDiff)) назад"
        }

        return shortDateFormatter.string(from: date)
    }

    private func dayWord(for count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100

        if mod10 == 1, mod100 != 11 {
            return "день"
        }

        if (2 ... 4).contains(mod10), !(12 ... 14).contains(mod100) {
            return "дня"
        }

        return "дней"
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "ru_RU")
        return value
    }
}
