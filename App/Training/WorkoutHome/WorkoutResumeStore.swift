import Foundation

struct StoredResumeWorkout: Codable, Equatable, Sendable {
    let userSub: String
    let programId: String
    let workoutId: String
    let workoutName: String
    let completedExercisesCount: Int
    let totalExercisesCount: Int
    let startedAt: Date?
}

protocol WorkoutResumeStore: Sendable {
    func save(_ workout: StoredResumeWorkout) async
    func latest(userSub: String) async -> StoredResumeWorkout?
    func clear(userSub: String) async
}

actor LocalWorkoutResumeStore: WorkoutResumeStore {
    private let defaults: UserDefaults
    private let keyPrefix = "fitfluence.workout.resume"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ workout: StoredResumeWorkout) async {
        guard let data = try? JSONEncoder().encode(workout) else { return }
        defaults.set(data, forKey: storageKey(userSub: workout.userSub))
    }

    func latest(userSub: String) async -> StoredResumeWorkout? {
        let key = storageKey(userSub: userSub)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StoredResumeWorkout.self, from: data)
    }

    func clear(userSub: String) async {
        defaults.removeObject(forKey: storageKey(userSub: userSub))
    }

    private func storageKey(userSub: String) -> String {
        "\(keyPrefix).\(userSub).latest"
    }
}
