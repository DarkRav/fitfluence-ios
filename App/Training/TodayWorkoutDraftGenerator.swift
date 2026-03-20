import Foundation

struct TodayWorkoutDraftExplanation: Equatable, Sendable {
    let summary: String
    let appliedRules: [String]
    let warnings: [String]
}

struct TodayWorkoutGeneratedDraft: Equatable, Sendable {
    let exercises: [WorkoutCompositionExerciseDraft]
    let explanation: TodayWorkoutDraftExplanation
    let matchedMuscleGroups: [ExerciseCatalogMuscleGroup]
    let missingMuscleGroups: [ExerciseCatalogMuscleGroup]
    let coveredMovementPatterns: [ExerciseCatalogMovementPattern]
    let targetExerciseCount: Int
    let targetWorkingSets: Int
    let isDegraded: Bool
}

protocol TodayWorkoutDraftGenerating: Sendable {
    func generate(
        request: TodayWorkoutPlanningRequest,
        catalogItems: [ExerciseCatalogItem],
        broaderCatalogItems: [ExerciseCatalogItem]
    ) -> TodayWorkoutGeneratedDraft
}

struct TodayWorkoutDraftGenerator: TodayWorkoutDraftGenerating {
    func generate(
        request: TodayWorkoutPlanningRequest,
        catalogItems: [ExerciseCatalogItem],
        broaderCatalogItems: [ExerciseCatalogItem] = []
    ) -> TodayWorkoutGeneratedDraft {
        let requestedMuscles = request.targetMuscleGroups.sorted(by: { $0.sortOrder < $1.sortOrder })
        let uniqueItems = catalogItems.uniqueByExerciseID()
        let broaderItems = broaderCatalogItems.isEmpty ? uniqueItems : broaderCatalogItems.uniqueByExerciseID()
        let muscleFiltered = uniqueItems.filter { item in
            guard !requestedMuscles.isEmpty else { return true }
            return item.muscles.contains(where: { muscle in
                guard let group = muscle.muscleGroup else { return false }
                return request.targetMuscleGroups.contains(group)
            })
        }
        let broaderMuscleFiltered = broaderItems.filter { item in
            guard !requestedMuscles.isEmpty else { return true }
            return item.muscles.contains(where: { muscle in
                guard let group = muscle.muscleGroup else { return false }
                return request.targetMuscleGroups.contains(group)
            })
        }
        let equipmentFiltered = muscleFiltered.filter { item in
            guard !request.availableEquipmentIDs.isEmpty else { return true }
            return item.equipment.contains(where: { request.availableEquipmentIDs.contains($0.id) })
        }

        let desiredPatterns = desiredMovementPatterns(for: requestedMuscles)
        let targetExerciseCount = max(1, request.suggestedExerciseCount)
        let requestedWorkingSets = workingSetTarget(
            durationMinutes: request.desiredDurationMinutes ?? 0,
            focus: request.focus,
        )

        guard !equipmentFiltered.isEmpty else {
            return TodayWorkoutGeneratedDraft(
                exercises: [],
                explanation: degradedExplanation(
                    request: request,
                    hadMuscleMatches: !broaderMuscleFiltered.isEmpty,
                ),
                matchedMuscleGroups: [],
                missingMuscleGroups: requestedMuscles,
                coveredMovementPatterns: [],
                targetExerciseCount: targetExerciseCount,
                targetWorkingSets: requestedWorkingSets,
                isDegraded: true,
            )
        }

        let selectedItems = selectExercises(
            from: equipmentFiltered,
            request: request,
            desiredPatterns: desiredPatterns,
        )
        let resolvedWorkingSets = normalizedWorkingSetTarget(
            requestedWorkingSets: requestedWorkingSets,
            exerciseCount: selectedItems.count,
        )

        let matchedMuscleGroups = requestedMuscles.filter { muscleGroup in
            selectedItems.contains(where: { item in
                item.muscles.contains(where: { $0.muscleGroup == muscleGroup })
            })
        }
        let missingMuscleGroups = requestedMuscles.filter { !matchedMuscleGroups.contains($0) }
        let coveredMovementPatterns = selectedItems.compactMap(\.movementPattern).removingDuplicateMovementPatterns()
        let exercises = buildDraftExercises(
            from: selectedItems,
            request: request,
            targetWorkingSets: resolvedWorkingSets,
        )

        return TodayWorkoutGeneratedDraft(
            exercises: exercises,
            explanation: explanation(
                request: request,
                selectedItems: selectedItems,
                matchedMuscleGroups: matchedMuscleGroups,
                missingMuscleGroups: missingMuscleGroups,
                coveredMovementPatterns: coveredMovementPatterns,
                targetWorkingSets: resolvedWorkingSets,
            ),
            matchedMuscleGroups: matchedMuscleGroups,
            missingMuscleGroups: missingMuscleGroups,
            coveredMovementPatterns: coveredMovementPatterns,
            targetExerciseCount: targetExerciseCount,
            targetWorkingSets: resolvedWorkingSets,
            isDegraded: selectedItems.isEmpty,
        )
    }

    private func selectExercises(
        from items: [ExerciseCatalogItem],
        request: TodayWorkoutPlanningRequest,
        desiredPatterns: [ExerciseCatalogMovementPattern]
    ) -> [ExerciseCatalogItem] {
        let requestedMuscles = request.targetMuscleGroups.sorted(by: { $0.sortOrder < $1.sortOrder })
        let targetExerciseCount = min(max(1, request.suggestedExerciseCount), items.count)
        var remaining = items
        var selected: [ExerciseCatalogItem] = []

        for muscleGroup in requestedMuscles {
            guard selected.count < targetExerciseCount,
                  let next = bestCandidate(
                      in: remaining,
                      request: request,
                      preferredMuscleGroup: muscleGroup,
                      preferredPatterns: desiredPatterns,
                      selectedItems: selected,
                  )
            else { continue }

            selected.append(next)
            remaining.removeAll { $0.id == next.id }
        }

        for pattern in desiredPatterns {
            guard selected.count < targetExerciseCount else { break }
            guard !selected.contains(where: { $0.movementPattern == pattern }) else { continue }
            guard let next = bestCandidate(
                in: remaining,
                request: request,
                preferredMuscleGroup: nil,
                preferredPatterns: [pattern],
                selectedItems: selected,
            ) else { continue }

            selected.append(next)
            remaining.removeAll { $0.id == next.id }
        }

        while selected.count < targetExerciseCount,
              let next = bestCandidate(
                  in: remaining,
                  request: request,
                  preferredMuscleGroup: nil,
                  preferredPatterns: desiredPatterns,
                  selectedItems: selected,
              )
        {
            selected.append(next)
            remaining.removeAll { $0.id == next.id }
        }

        return selected
    }

    private func bestCandidate(
        in items: [ExerciseCatalogItem],
        request: TodayWorkoutPlanningRequest,
        preferredMuscleGroup: ExerciseCatalogMuscleGroup?,
        preferredPatterns: [ExerciseCatalogMovementPattern],
        selectedItems: [ExerciseCatalogItem]
    ) -> ExerciseCatalogItem? {
        items.min { lhs, rhs in
            isCandidate(
                lhs,
                rankedBefore: rhs,
                request: request,
                preferredMuscleGroup: preferredMuscleGroup,
                preferredPatterns: preferredPatterns,
                selectedItems: selectedItems,
            )
        }
    }

    private func isCandidate(
        _ lhs: ExerciseCatalogItem,
        rankedBefore rhs: ExerciseCatalogItem,
        request: TodayWorkoutPlanningRequest,
        preferredMuscleGroup: ExerciseCatalogMuscleGroup?,
        preferredPatterns: [ExerciseCatalogMovementPattern],
        selectedItems: [ExerciseCatalogItem]
    ) -> Bool {
        let lhsPreferredPattern = lhs.movementPattern.map(preferredPatterns.contains) ?? false
        let rhsPreferredPattern = rhs.movementPattern.map(preferredPatterns.contains) ?? false
        if lhsPreferredPattern != rhsPreferredPattern {
            return lhsPreferredPattern && !rhsPreferredPattern
        }

        let lhsPreferredMuscle = preferredMuscleGroup.map { itemMatchesMuscle(lhs, muscleGroup: $0) } ?? false
        let rhsPreferredMuscle = preferredMuscleGroup.map { itemMatchesMuscle(rhs, muscleGroup: $0) } ?? false
        if lhsPreferredMuscle != rhsPreferredMuscle {
            return lhsPreferredMuscle && !rhsPreferredMuscle
        }

        let lhsPatternRank = movementPatternRank(lhs.movementPattern, preferredPatterns: preferredPatterns)
        let rhsPatternRank = movementPatternRank(rhs.movementPattern, preferredPatterns: preferredPatterns)
        if lhsPatternRank != rhsPatternRank {
            return lhsPatternRank < rhsPatternRank
        }

        let lhsCoverage = selectedMuscleCoverageCount(lhs, request: request)
        let rhsCoverage = selectedMuscleCoverageCount(rhs, request: request)
        if lhsCoverage != rhsCoverage {
            return lhsCoverage > rhsCoverage
        }

        let lhsAddsNewPattern = lhs.movementPattern.map { pattern in
            !selectedItems.contains(where: { $0.movementPattern == pattern })
        } ?? false
        let rhsAddsNewPattern = rhs.movementPattern.map { pattern in
            !selectedItems.contains(where: { $0.movementPattern == pattern })
        } ?? false
        if lhsAddsNewPattern != rhsAddsNewPattern {
            return lhsAddsNewPattern && !rhsAddsNewPattern
        }

        let lhsDifficultyRank = difficultyRank(lhs.difficultyLevel)
        let rhsDifficultyRank = difficultyRank(rhs.difficultyLevel)
        if lhsDifficultyRank != rhsDifficultyRank {
            return lhsDifficultyRank < rhsDifficultyRank
        }

        let lhsEquipmentCount = lhs.equipment.count
        let rhsEquipmentCount = rhs.equipment.count
        if lhsEquipmentCount != rhsEquipmentCount {
            return lhsEquipmentCount < rhsEquipmentCount
        }

        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private func buildDraftExercises(
        from items: [ExerciseCatalogItem],
        request: TodayWorkoutPlanningRequest,
        targetWorkingSets: Int
    ) -> [WorkoutCompositionExerciseDraft] {
        let setDistribution = distributedSetCounts(
            exerciseCount: items.count,
            targetWorkingSets: targetWorkingSets,
            focus: request.focus,
        )

        return items.enumerated().map { index, item in
            buildExerciseDraft(
                from: item,
                request: request,
                index: index,
                totalCount: items.count,
                targetSets: setDistribution[index],
            )
        }
    }

    private func buildExerciseDraft(
        from item: ExerciseCatalogItem,
        request: TodayWorkoutPlanningRequest,
        index: Int,
        totalCount: Int,
        targetSets: Int
    ) -> WorkoutCompositionExerciseDraft {
        var draft = WorkoutCompositionExerciseDraft(catalogItem: item)
        let usesCatalogDefaults = item.draftDefaults != nil && request.focus == nil

        draft.sets = max(2, targetSets)

        if usesCatalogDefaults {
            if draft.restSeconds == nil {
                draft.restSeconds = defaultRestSeconds(
                    focus: request.focus,
                    movementPattern: item.movementPattern,
                    index: index,
                )
            }
            if draft.targetRpe == nil {
                draft.targetRpe = defaultTargetRPE(focus: request.focus, index: index)
            }
            return draft
        }

        let prescription = defaultPrescription(
            focus: request.focus,
            movementPattern: item.movementPattern,
            index: index,
            totalCount: totalCount,
        )
        draft.repsMin = prescription.repsMin
        draft.repsMax = prescription.repsMax
        draft.restSeconds = prescription.restSeconds
        draft.targetRpe = prescription.targetRpe
        return draft
    }

    private func explanation(
        request: TodayWorkoutPlanningRequest,
        selectedItems: [ExerciseCatalogItem],
        matchedMuscleGroups: [ExerciseCatalogMuscleGroup],
        missingMuscleGroups: [ExerciseCatalogMuscleGroup],
        coveredMovementPatterns: [ExerciseCatalogMovementPattern],
        targetWorkingSets: Int
    ) -> TodayWorkoutDraftExplanation {
        let durationText = request.desiredDurationMinutes.map { "\($0) мин" } ?? "доступное время"
        let summary: String
        if selectedItems.isEmpty {
            summary = "Каталог не смог честно собрать стартовую тренировку под текущие параметры."
        } else {
            summary = "Собрано \(selectedItems.count) \(exerciseWord(for: selectedItems.count)) и около \(targetWorkingSets) рабочих подходов под \(durationText)."
        }

        var appliedRules = [
            "Сначала отфильтровали упражнения по выбранным мышцам и оборудованию.",
        ]

        if !matchedMuscleGroups.isEmpty {
            appliedRules.append(
                "Постарались покрыть мышечные группы: \(matchedMuscleGroups.map(\.title).joined(separator: ", "))."
            )
        }

        if !coveredMovementPatterns.isEmpty {
            appliedRules.append(
                "Добавили базовый баланс по паттернам движения: \(coveredMovementPatterns.map(\.planningLabel).joined(separator: ", "))."
            )
        }

        appliedRules.append("Объём ограничили до \(targetWorkingSets) рабочих подходов под выбранную длительность.")

        if let focus = request.focus {
            appliedRules.append("Прескрипции выставили под фокус «\(focus.title)» без случайного ранжирования.")
        }

        var warnings: [String] = []
        if !missingMuscleGroups.isEmpty {
            warnings.append("Не хватило упражнений для: \(missingMuscleGroups.map(\.title).joined(separator: ", ")).")
        }

        let itemsWithoutPatterns = selectedItems.filter { $0.movementPattern == nil }
        if !itemsWithoutPatterns.isEmpty, !coveredMovementPatterns.isEmpty {
            warnings.append("У части упражнений нет `movementPattern`, поэтому баланс по паттернам ограничен доступной metadata.")
        } else if !selectedItems.isEmpty, coveredMovementPatterns.isEmpty {
            warnings.append("Каталог не отдал `movementPattern`, поэтому тренировка собрана только по мышцам и оборудованию.")
        }

        if selectedItems.count < request.suggestedExerciseCount {
            warnings.append("Каталог вернул меньше уникальных упражнений, чем хотелось под выбранную длительность.")
        }

        return TodayWorkoutDraftExplanation(
            summary: summary,
            appliedRules: appliedRules,
            warnings: warnings,
        )
    }

    private func degradedExplanation(
        request: TodayWorkoutPlanningRequest,
        hadMuscleMatches: Bool
    ) -> TodayWorkoutDraftExplanation {
        let summary = if hadMuscleMatches {
            "По выбранному оборудованию не нашлось упражнений для стартового черновика."
        } else {
            "По выбранным мышцам каталог не вернул упражнений для стартового черновика."
        }

        var warnings = [
            "Оставили builder в рабочем состоянии без фейкового наполнения.",
        ]
        if !hadMuscleMatches, !request.targetMuscleGroups.isEmpty {
            warnings.append(
                "Нужны упражнения для: \(request.targetMuscleGroups.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.title).joined(separator: ", "))."
            )
        } else if !request.availableEquipmentIDs.isEmpty {
            warnings.append("Снимите часть equipment-фильтров или доберите упражнения вручную через каталог.")
        }

        return TodayWorkoutDraftExplanation(
            summary: summary,
            appliedRules: [
                "Сначала попытались отфильтровать каталог по выбранным мышцам и оборудованию.",
                "Так как честного покрытия не нашлось, генератор не подставлял случайные упражнения.",
            ],
            warnings: warnings,
        )
    }

    private func desiredMovementPatterns(
        for muscles: [ExerciseCatalogMuscleGroup]
    ) -> [ExerciseCatalogMovementPattern] {
        muscles
            .flatMap(\.preferredMovementPatterns)
            .removingDuplicateMovementPatterns()
    }

    private func distributedSetCounts(
        exerciseCount: Int,
        targetWorkingSets: Int,
        focus: TodayWorkoutPlanningFocus?
    ) -> [Int] {
        guard exerciseCount > 0 else { return [] }

        var distribution = baseSetDistribution(
            exerciseCount: exerciseCount,
            focus: focus,
        )
        var totalSets = distribution.reduce(0, +)

        while totalSets < targetWorkingSets {
            for index in distribution.indices {
                guard totalSets < targetWorkingSets else { break }
                guard distribution[index] < 5 else { continue }
                distribution[index] += 1
                totalSets += 1
            }
        }

        while totalSets > targetWorkingSets {
            for index in distribution.indices.reversed() {
                guard totalSets > targetWorkingSets else { break }
                guard distribution[index] > 2 else { continue }
                distribution[index] -= 1
                totalSets -= 1
            }
        }

        return distribution
    }

    private func baseSetDistribution(
        exerciseCount: Int,
        focus: TodayWorkoutPlanningFocus?
    ) -> [Int] {
        let base: [Int]
        switch focus {
        case .strength:
            base = [5, 4, 4, 3, 3, 2]
        case .hypertrophy:
            base = [4, 4, 3, 3, 3, 2]
        case .conditioning:
            base = [3, 3, 2, 2, 2, 2]
        case nil:
            base = [4, 3, 3, 3, 2, 2]
        }

        var result = Array(base.prefix(exerciseCount))
        while result.count < exerciseCount {
            result.append(focus == .conditioning ? 2 : 3)
        }
        return result
    }

    private func normalizedWorkingSetTarget(
        requestedWorkingSets: Int,
        exerciseCount: Int
    ) -> Int {
        guard exerciseCount > 0 else { return requestedWorkingSets }
        let minimum = exerciseCount * 2
        let maximum = exerciseCount * 5
        return min(max(requestedWorkingSets, minimum), maximum)
    }

    private func workingSetTarget(
        durationMinutes: Int,
        focus: TodayWorkoutPlanningFocus?
    ) -> Int {
        let base: Int
        switch durationMinutes {
        case ..<35:
            base = 9
        case ..<50:
            base = 12
        case ..<70:
            base = 15
        default:
            base = 18
        }

        switch focus {
        case .strength:
            return max(8, base - 1)
        case .conditioning:
            return max(6, base - 2)
        case .hypertrophy, nil:
            return base
        }
    }

    private func defaultPrescription(
        focus: TodayWorkoutPlanningFocus?,
        movementPattern: ExerciseCatalogMovementPattern?,
        index: Int,
        totalCount: Int
    ) -> (repsMin: Int, repsMax: Int, restSeconds: Int, targetRpe: Int?) {
        let isPrimarySlot = index < max(1, min(2, totalCount / 2))
        let isHeavyPattern = movementPattern == .squat || movementPattern == .hinge

        switch focus {
        case .strength:
            return (
                repsMin: isPrimarySlot ? 4 : 6,
                repsMax: isPrimarySlot ? 6 : 8,
                restSeconds: isHeavyPattern || isPrimarySlot ? 150 : 120,
                targetRpe: isPrimarySlot ? 8 : 7
            )
        case .hypertrophy:
            return (
                repsMin: isPrimarySlot ? 8 : 10,
                repsMax: isPrimarySlot ? 12 : 15,
                restSeconds: isHeavyPattern && isPrimarySlot ? 105 : 75,
                targetRpe: 8
            )
        case .conditioning:
            return (
                repsMin: 12,
                repsMax: 15,
                restSeconds: isHeavyPattern ? 60 : 45,
                targetRpe: 7
            )
        case nil:
            return (
                repsMin: isPrimarySlot ? 6 : 10,
                repsMax: isPrimarySlot ? 10 : 12,
                restSeconds: isHeavyPattern && isPrimarySlot ? 120 : 75,
                targetRpe: isPrimarySlot ? 8 : 7
            )
        }
    }

    private func defaultRestSeconds(
        focus: TodayWorkoutPlanningFocus?,
        movementPattern: ExerciseCatalogMovementPattern?,
        index: Int
    ) -> Int {
        defaultPrescription(
            focus: focus,
            movementPattern: movementPattern,
            index: index,
            totalCount: 1,
        ).restSeconds
    }

    private func defaultTargetRPE(
        focus: TodayWorkoutPlanningFocus?,
        index: Int
    ) -> Int? {
        defaultPrescription(
            focus: focus,
            movementPattern: nil,
            index: index,
            totalCount: 1,
        ).targetRpe
    }

    private func itemMatchesMuscle(
        _ item: ExerciseCatalogItem,
        muscleGroup: ExerciseCatalogMuscleGroup
    ) -> Bool {
        item.muscles.contains(where: { $0.muscleGroup == muscleGroup })
    }

    private func selectedMuscleCoverageCount(
        _ item: ExerciseCatalogItem,
        request: TodayWorkoutPlanningRequest
    ) -> Int {
        Set(item.muscles.compactMap(\.muscleGroup))
            .intersection(request.targetMuscleGroups)
            .count
    }

    private func difficultyRank(_ level: ExerciseCatalogDifficultyLevel?) -> Int {
        switch level {
        case .beginner:
            0
        case .intermediate, nil:
            1
        case .advanced:
            2
        }
    }

    private func movementPatternRank(
        _ pattern: ExerciseCatalogMovementPattern?,
        preferredPatterns: [ExerciseCatalogMovementPattern]
    ) -> Int {
        guard let pattern else { return preferredPatterns.count + 1 }
        return preferredPatterns.firstIndex(of: pattern) ?? preferredPatterns.count
    }

    private func exerciseWord(for count: Int) -> String {
        let remainder10 = count % 10
        let remainder100 = count % 100
        if remainder10 == 1, remainder100 != 11 {
            return "упражнение"
        }
        if (2 ... 4).contains(remainder10), !(12 ... 14).contains(remainder100) {
            return "упражнения"
        }
        return "упражнений"
    }
}

extension ExerciseCatalogMuscleGroup {
    var title: String {
        switch self {
        case .back:
            "Спина"
        case .chest:
            "Грудь"
        case .legs:
            "Ноги"
        case .shoulders:
            "Плечи"
        case .arms:
            "Руки"
        case .abs:
            "Пресс"
        }
    }

    var sortOrder: Int {
        switch self {
        case .back:
            0
        case .chest:
            1
        case .legs:
            2
        case .shoulders:
            3
        case .arms:
            4
        case .abs:
            5
        }
    }

    var preferredMovementPatterns: [ExerciseCatalogMovementPattern] {
        switch self {
        case .back:
            [.pull]
        case .chest:
            [.push]
        case .legs:
            [.squat, .hinge]
        case .shoulders:
            [.push]
        case .arms:
            [.push, .pull]
        case .abs:
            [.other]
        }
    }
}

extension ExerciseCatalogMovementPattern {
    var planningLabel: String {
        switch self {
        case .push:
            "жим"
        case .pull:
            "тяга"
        case .squat:
            "присед"
        case .hinge:
            "наклон"
        case .other:
            "другое"
        }
    }
}

private extension Array where Element == ExerciseCatalogItem {
    func uniqueByExerciseID() -> [ExerciseCatalogItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

private extension Array where Element == ExerciseCatalogMovementPattern {
    func removingDuplicateMovementPatterns() -> [ExerciseCatalogMovementPattern] {
        var seen = Set<ExerciseCatalogMovementPattern>()
        return filter { seen.insert($0).inserted }
    }
}
