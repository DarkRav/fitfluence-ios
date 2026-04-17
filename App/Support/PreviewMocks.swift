import Foundation

enum PreviewMocks {
    static let environment = AppEnvironment(
        name: "PREVIEW",
        baseURL: URL(string: "https://preview.fitfluence.local"),
    )

    static let sampleProgramsPage = PagedProgramResponse(
        content: [
            ProgramListItem(
                id: "program-1",
                title: "Сильная спина за 6 недель",
                description: "Программа для устойчивого набора силы в базовых тягах.",
                status: .published,
                isFeatured: true,
                influencer: InfluencerBrief(
                    id: "inf-1",
                    displayName: "Алина Спорт",
                    avatar: nil,
                    bio: nil,
                ),
                cover: nil,
                media: nil,
                goals: ["Сила", "Техника"],
                currentPublishedVersion: ProgramVersionSummary(
                    id: "ver-1",
                    versionNumber: 1,
                    status: .published,
                    publishedAt: nil,
                    level: "BEGINNER",
                    frequencyPerWeek: 3,
                    requirements: nil,
                ),
                level: "BEGINNER",
                daysPerWeek: 3,
                estimatedDurationMinutes: 55,
                equipment: ["Штанга", "Скамья"],
                createdAt: nil,
                updatedAt: nil,
            ),
        ],
        metadata: PageMetadata(page: 0, size: 20, totalElements: 1, totalPages: 1),
    )

    static let sampleProgramDetails = ProgramDetails(
        id: "program-1",
        title: "Сильная спина за 6 недель",
        description: "Пошаговый план тренировок с фокусом на тяговые движения.",
        status: .published,
        isFeatured: true,
        influencer: InfluencerBrief(id: "inf-1", displayName: "Алина Спорт", avatar: nil, bio: "Тренер"),
        cover: nil,
        media: nil,
        goals: ["Сила", "Выносливость"],
        currentPublishedVersion: ProgramVersionSummary(
            id: "ver-1",
            versionNumber: 1,
            status: .published,
            publishedAt: nil,
            level: "BEGINNER",
            frequencyPerWeek: 3,
            requirements: nil,
        ),
        createdAt: nil,
        updatedAt: nil,
        versions: nil,
        workouts: [
            WorkoutTemplate(
                id: "wk-1",
                dayOrder: 1,
                title: "День 1: Тяга",
                coachNote: "Контролируйте технику.",
                exercises: nil,
                media: nil,
            ),
        ],
    )
}
