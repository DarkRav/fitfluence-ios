import Foundation
import OSLog

enum FFLog {
    private static let logger = Logger(subsystem: "com.fitfluence.ios", category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

enum ClientAnalyticsEvent: String, Sendable {
    case workoutHubScreenOpened = "экран_workout_hub_открыт"
    case workoutContinueButtonTapped = "нажата_кнопка_продолжить_тренировку"
    case workoutStartNextButtonTapped = "нажата_кнопка_начать_следующую_тренировку"
    case workoutStartButtonTapped = "нажата_кнопка_начать_тренировку"
    case workoutQuickButtonTapped = "нажата_кнопка_быстрая_тренировка"
    case workoutTemplatesButtonTapped = "нажата_кнопка_шаблоны"
    case workoutRepeatLastButtonTapped = "нажата_кнопка_повторить_последнюю"
    case hubOpened = "hub_opened"
    case workoutStartTapped = "workout_start_tapped"
    case workoutContinueTapped = "workout_continue_tapped"
    case programEnrolled = "program_enrolled"
    case firstWorkoutStarted = "first_workout_started"
    case firstWorkoutCompleted = "first_workout_completed"
    case creatorViewed = "creator_viewed"
    case creatorFollowed = "creator_followed"
    case creatorUnfollowed = "creator_unfollowed"
    case creatorProgramOpened = "creator_program_opened"
    case creatorProgramEnrolled = "creator_program_enrolled"
}

enum ClientAnalytics {
    static func track(_ event: ClientAnalyticsEvent, properties: [String: String] = [:]) {
        if properties.isEmpty {
            FFLog.info("analytics event=\(event.rawValue)")
            return
        }

        let metadata = properties
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        FFLog.info("analytics event=\(event.rawValue) \(metadata)")
    }
}
