import Foundation

enum TrainingWeightUnit: String, CaseIterable, Codable, Equatable, Sendable {
    case kilograms
    case pounds

    var title: String {
        switch self {
        case .kilograms:
            "Килограммы (кг)"
        case .pounds:
            "Фунты"
        }
    }
}

struct ProfileSettings: Codable, Equatable, Sendable {
    var weightUnit: TrainingWeightUnit
    var weightStep: Double
    var defaultRestSeconds: Int
    var timerVibrationEnabled: Bool
    var timerSoundEnabled: Bool
    var showRPE: Bool

    static let `default` = ProfileSettings(
        weightUnit: .kilograms,
        weightStep: 2.5,
        defaultRestSeconds: 90,
        timerVibrationEnabled: true,
        timerSoundEnabled: false,
        showRPE: true,
    )
}

struct ProfileSessionSnapshot: Equatable, Sendable {
    let session: ActiveWorkoutSession
    let subtitle: String
}

struct ProfileDiagnosticsSnapshot: Equatable, Sendable {
    let isOnline: Bool
    let cacheSizeLabel: String
    let localStorageLabel: String
    let versionLabel: String
    let buildLabel: String
    let pendingSyncOperations: Int
    let lastSyncAttemptLabel: String
    let lastSyncError: String?
}
