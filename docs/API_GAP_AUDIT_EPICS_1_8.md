# API Gap Audit After Epics 1-8

## Executive Summary

- Most desynchronized domains: `Planning`, `Workout Logging / Active Workout`, `Exercise Catalog / Picker`, and `Home / Today / Plan summaries`.
- Main blockers:
  - iOS supports local-first workout structure editing (`add/remove set`, `warm-up`, `add/replace exercise`) but athlete contract only persists set upserts.
  - planning and template-driven flows are mostly client-side and are not backed by athlete planning/custom-workout persistence contracts.
  - Home/Today/Plan surfaces need aggregated athlete payloads, but currently compose them from `active enrollment`, `calendar`, cached program details, and local stores.
- Safe temporary client-side areas:
  - Today workout draft generation and recommendation explanation.
  - local template library.
  - local program scheduling fallback after enrollment.
  - some progress derivations from local history plus `stats/summary`, `prs`, `exercise history`, `comparison`.

## Contract Gap Inventory

| Domain | Screen / Flow | Current iOS expectation | Current OpenAPI / backend reality | Gap type | Severity | Recommended action | Exact files / endpoints / schemas |
|---|---|---|---|---|---|---|---|
| Exercise Catalog / Picker | `QuickWorkoutBuilder`, `ExercisePicker`, `TodayWorkoutPlanning` | athlete-usable search with `muscleGroups`, `equipmentIds`, `movementPattern`, `difficulty`, plus stable equipment options for filters | `POST /v1/athlete/exercises/search` exists and supports filters, but there are no athlete endpoints for standalone muscle/equipment dictionaries; iOS explicitly records this as contract gap and degrades to template/local suggestions | missing backend capability | important | update backend + OpenAPI | iOS: `App/Training/ExerciseCatalog.swift`, `App/Training/ExercisePickerFeature.swift`, `App/Training/TodayWorkoutPlanningView.swift`; OpenAPI: `/v1/athlete/exercises/search`, `ExercisesSearchRequest`, missing athlete list endpoints for `Muscle` / `Equipment` |
| Exercise Catalog / Picker | `ExercisePicker` suggestions | recent athlete exercises section built from actual execution history | backend has `exercise history by exerciseId`, but no “recent athlete exercises” endpoint; iOS falls back to local plans/templates only | missing backend capability | later | keep client-side for now | iOS: `App/Training/ExercisePickerFeature.swift`; OpenAPI: missing athlete endpoint, related existing `/v1/athlete/exercises/{exerciseId}/history` |
| Exercise Catalog / Planning | `TodayWorkoutPlanning` | planning needs equipment choices, muscle coverage, movement-pattern coverage, explanation and honest degraded state | search contract is enough for partial generation, but there is no planning endpoint, no persistence contract, no readiness/recovery use in flow | missing backend capability | important | keep client-side for now | iOS: `App/Training/TodayWorkoutPlanningView.swift`, `App/Training/TodayWorkoutDraftGenerator.swift`; OpenAPI: `/v1/athlete/exercises/search`, no planning schema/endpoint |
| Exercise Catalog / Models | all exercise-driven flows | iOS enums assume fixed subsets for `MuscleGroup`, `MovementPattern`, `EquipmentCategory`, `DifficultyLevel` | OpenAPI matches current values, but iOS hard-defaults unknown values to `.back`, `.other`, `.freeWeight`, `.beginner`, hiding future enum drift | naming/typing mismatch | later | update iOS model only | iOS: `App/Training/ExerciseCatalog.swift`; OpenAPI: `MuscleGroup`, `MovementPattern`, `EquipmentCategory`, `DifficultyLevel` |
| Workout Logging / Active Workout | `WorkoutPlayerView` | per-set sync for weight/reps/RPE/completion plus local rest flow | supported: `PUT /v1/athlete/exercise-executions/{exerciseExecutionId}/sets/{setNumber}` with `weight`, `reps`, `rpe`, `isCompleted`, `restSecondsActual` | no gap for core set logging | n/a | none | iOS: `App/Networking/AthleteTrainingClient.swift`, `App/Workouts/WorkoutPlayerView.swift`; OpenAPI: `UpsertSetExecutionRequest`, `SetExecution` |
| Workout Logging / Active Workout | `WorkoutPlayerView` structural editing | add/remove sets, mark warm-up, add exercise after current, replace current exercise during active workout | athlete contract has custom workout exercise add/patch endpoints, but no contract for set count mutation, warm-up flag, or structural edits for program workout instances; iOS marks such sessions as `hasLocalOnlyStructuralChanges` and stops sync | missing backend capability | blocker | update backend + OpenAPI | iOS: `App/Workouts/WorkoutPlayerView.swift`, `App/Workouts/ProgressStore.swift`; OpenAPI: `PUT /v1/athlete/exercise-executions/.../sets/...`, `/v1/athlete/workouts/{workoutInstanceId}/exercises`, `/v1/athlete/workouts/{workoutInstanceId}/exercises/{exerciseExecutionId}` |
| Workout Logging / Active Workout | program workout completion | finish flow wants server-backed summary, comparison, PR highlights, next workout | backend supports `complete`, `comparison`, `active enrollment`; iOS still derives duration/sets/reps/volume locally first and enriches later | optional enhancement | important | keep client-side for now | iOS: `App/Root/RootView.swift`, `App/Workouts/WorkoutPlayerView.swift`; OpenAPI: `/v1/athlete/workouts/{id}/complete`, `/comparison`, `/enrollments/active` |
| Workout Logging / Active Workout | completed workout history details | history record should preserve notes and full per-exercise execution details for later review/repeat | local `CompletedWorkoutRecord` stores `notes` and `overallRPE`, but finish path writes `notes: nil`; no athlete endpoint returns completed workout summary/history list for a workout session | iOS model mismatch + missing backend capability | important | update backend + OpenAPI | iOS: `App/Training/TrainingStore.swift`, `App/Workouts/ProgressStore.swift`, `App/Training/WorkoutHome/RecentWorkoutDetailsView.swift`; OpenAPI: no athlete completed-workout history/list endpoint |
| Workout Logging / Active Workout | custom workout lifecycle | builder/template/planned quick workout expect durable athlete custom workouts | OpenAPI has `POST /v1/athlete/workouts/custom`, `GET /v1/athlete/workouts/custom/{id}`, add/patch exercise, and workout search; iOS does not integrate these endpoints and keeps quick/template flows local-only | missing iOS model/client alignment | important | update iOS model only | iOS: `App/Training/QuickWorkoutBuilderView.swift`, `App/Training/TemplateLibraryView.swift`, `App/Training/TrainingStore.swift`; OpenAPI: `/v1/athlete/workouts/custom`, `/v1/athlete/workouts/search`, custom workout schemas |
| Planning | `TodayWorkoutPlanningView` -> `QuickWorkoutBuilder` -> optional save to plan | planning request with muscles, equipment, duration, focus, generated draft persistence, save-to-plan | no planning contract in OpenAPI; generated draft is purely client-derived and saved only into local plan/template flows | missing backend capability | blocker | keep client-side for now | iOS: `App/Training/TodayWorkoutPlanningView.swift`, `App/Training/QuickWorkoutBuilderView.swift`; OpenAPI: none |
| Planning | `ProgramDetails` onboarding scheduling | after enrollment, iOS can recommend weekdays and schedule full program into calendar | backend has `active enrollment` and read-only `schedule`, but no athlete write contract for scheduling selected weekdays/start date; iOS writes local `TrainingDayPlan` only | missing backend capability | important | update backend + OpenAPI | iOS: `App/ProgramDetails/ProgramDetailsView.swift`, `App/Plan/PlanScheduleView.swift`, `App/Training/TrainingStore.swift`; OpenAPI: `/v1/athlete/enrollments/{id}/schedule` is read-only |
| Planning | `PlanScheduleView` | merged monthly plan across remote program workouts plus local manual/template entries with actionable details | backend provides `calendar` and `enrollment schedule`, but only for program workouts; manual/template plans are local-only and remote plans often lack detail payloads, forcing cache fetches per workout | missing backend capability | important | update backend + OpenAPI | iOS: `App/Plan/PlanScheduleView.swift`; OpenAPI: `/v1/athlete/calendar`, `/v1/athlete/enrollments/{id}/schedule`, `/v1/athlete/workouts/{id}` |
| Programs | `CatalogView` | rich program cards with level, days/week, estimated duration, equipment summary, featured state | OpenAPI exposes these as optional enrichment fields on `ProgramListItem`; iOS already treats many as optional and falls back safely | optional enhancement | later | keep client-side for now | iOS: `App/Catalog/CatalogView.swift`; OpenAPI: `ProgramListItem`, `/v1/programs/published/search`, `/v1/programs/featured` |
| Programs | `ProgramDetailsView` | program details screen wants author card, goals, equipment summary, weekly structure, progress card, next workout, first workout start | static program details are covered reasonably; dynamic enrolled-state UX comes from separate athlete endpoints and local scheduling. No single joined contract exists for “program details with athlete state” | missing backend capability | important | update backend + OpenAPI | iOS: `App/ProgramDetails/ProgramDetailsView.swift`, `App/Networking/ProgramsClient.swift`, `App/Networking/AthleteTrainingClient.swift`; OpenAPI: `ProgramDetails`, `/v1/athlete/enrollments/active`, `/v1/athlete/workouts/{id}` |
| Programs | first workout launch after enrollment | if `nextWorkoutInstanceId` is absent, iOS falls back to program template id and opens template as executable workout | backend contract distinguishes workout instance ids from template ids; template fallback is an iOS workaround, not a real athlete execution contract | missing backend capability | blocker | update backend + OpenAPI | iOS: `App/ProgramDetails/ProgramDetailsView.swift`; OpenAPI: `ActiveEnrollmentProgress.currentWorkoutId/nextWorkoutId`, `WorkoutTemplate`, `WorkoutInstance` |
| Programs / Creator | creator follow/profile in program details | creator card wants followers/program counts, follow state, social links, optional enriched biography fields | follow endpoints exist; iOS decoders accept extra alias keys not present in current spec, indicating defensive decoding against payload drift | iOS model mismatch | later | update OpenAPI only | iOS: `App/Networking/ProgramsClient.swift`; OpenAPI: `InfluencerPublicCard`, `SocialLink`, `/v1/athlete/follows`, `/v1/influencers/search` |
| Home / Today / Summaries | `HomeView`, `WorkoutHomeViewModel`, `RootView` completion summary | cohesive today surface with active session, next workout, planned workout, equipment/focus, sync state, completion summary, PR highlights | data is split across `active enrollment`, `calendar`, `program details`, `workout details`, `comparison`, local session state, local plan state, and caches; no dedicated athlete home/today summary payload | missing backend capability | important | update backend + OpenAPI | iOS: `App/Home/HomeView.swift`, `App/Training/WorkoutHome/WorkoutHomeViewModel.swift`, `App/Root/RootView.swift`; OpenAPI: related athlete endpoints only, no summary endpoint |
| Home / Today / Summaries | completion summary | summary wants next workout CTA and PR highlights immediately after finish | backend can provide `comparison` and `active enrollment`, but requires multiple round-trips; no single completion response includes summary payload | optional enhancement | later | update backend + OpenAPI | iOS: `App/Root/RootView.swift`; OpenAPI: `/complete`, `/comparison`, `/enrollments/active` |
| Progress / History | `TrainingInsightsView`, `WorkoutPlayerView`, `RecentWorkoutDetailsView` | overview, streak, history, PRs, exercise trends, weekly highlight, recent workout details | backend covers `stats/summary`, `prs`, `exercise history`, `comparison`; iOS still supplements with local history, local snapshots, and derived volume/adherence because no athlete workout history list endpoint exists | missing backend capability | important | update backend + OpenAPI | iOS: `App/Training/TrainingInsightsView.swift`, `App/Training/WorkoutHome/RecentWorkoutDetailsView.swift`, `App/Training/TrainingStore.swift`; OpenAPI: existing progress endpoints, missing workout-history list/details endpoint |
| Progress / History | readiness/recovery lite | product context mentions readiness proxies/recommendation lite | OpenAPI has `/v1/athlete/recovery/today`, but current iOS audit target does not wire it into Today/Home/Planning flows | missing iOS model/client alignment | later | update iOS model only | iOS: no current consumer in audited flows; OpenAPI: `/v1/athlete/recovery/today`, `AthleteRecoveryTodayResponse` |

## Backend Backlog Proposal

### Package A: Exercise Catalog
- Why: stabilize picker, builder, and planning inputs without admin/influencer leakage.
- Change:
  - add athlete/public list endpoints for muscles and equipment dictionaries.
  - define whether athlete exercise search is authoritative for planning/catalog use.
  - optionally add recent-athlete-exercises endpoint for picker suggestions.
- Unlocks:
  - honest filter pickers.
  - stronger planning seed generation.
  - less fallback to local templates.
- Priority: `important`

### Package B: Workout Logging / Active Workout
- Why: current iOS active workout editing exceeds server contract and silently falls back to local-only structure changes.
- Change:
  - add program/custom workout structural mutation contract for add/remove set, warm-up flag, add exercise, replace exercise.
  - clarify whether mutations apply to workout instance, exercise execution, or custom draft/workout.
  - add completed workout history/details endpoint if server should own post-workout review.
- Unlocks:
  - reliable server-backed active workout editing.
  - safe sync for workout player.
  - consistent history/repeat flows.
- Priority: `blocker`

### Package C: Planning
- Why: planning and save-to-plan are mostly local and will fragment once backend alignment starts.
- Change:
  - define whether backend owns planning request/generation or only plan persistence.
  - add athlete write endpoint for scheduled plan items or enrollment scheduling preferences.
  - clarify relation between program schedule, manual plan entries, and custom workouts.
- Unlocks:
  - today planning persistence.
  - remote program scheduling after enrollment.
  - cleaner plan/today/home surfaces.
- Priority: `blocker`

### Package D: Programs
- Why: static program browsing works, but enrolled-state/start-flow remains stitched across contracts.
- Change:
  - add joined athlete-aware program details payload or enrich current progress contract with explicit first-launch/next-launch links.
  - guarantee next workout instance creation immediately after enrollment.
  - clarify template id vs workout instance id usage.
- Unlocks:
  - stable start-today / continue-program UX.
  - removal of template-execution fallback.
  - better program detail summaries.
- Priority: `important`

### Package E: Summaries / Progress / Home
- Why: home/today/progress assemble too much manually from caches and local stores.
- Change:
  - add athlete home/today summary payload.
  - add athlete completed workout history list/details.
  - optionally add completion-summary payload on workout complete.
- Unlocks:
  - simpler Today/Home implementation.
  - more accurate progress/history.
  - fewer cache joins and local heuristics.
- Priority: `important`

## iOS Model Alignment Backlog

- `CompletedWorkoutRecord` is richer than server-backed data, but finish flow persists `notes: nil`; decide whether notes stay local or become server-backed.
- `ProgramsClient` and `AthleteTrainingClient` use lossy decoding and alias keys in several places, masking payload/spec drift instead of surfacing it.
- `HomeView` and `ProgramDetailsView` derive equipment/duration/focus from mixed sources; once backend packages land, replace derived placeholders with contract fields.
- `QuickWorkoutBuilder`, `TemplateLibrary`, and `TrainingStore` can be aligned to custom-workout endpoints without waiting for planning redesign.
- `ExerciseCatalog` enum mapping should stop silently coercing unknown enum values once backend contract is frozen.

## Open Questions / Assumptions

- Should planning stay client-side generation with only server persistence, or move to backend-generated drafts?
- Are custom workouts intended as athlete-owned durable entities, or only transient workout instances?
- For program enrollment, must backend create the first workout instance immediately, or can iOS still launch from template data?
- Should warm-up sets be a first-class backend concept, or purely client annotation?
- Should athlete history expose workout-level details/listing, or is local snapshot retention the intended source of truth?

## Recommended Execution Order

1. Package B (`Workout Logging / Active Workout`) and Package D (`Programs`) first. Do not start server-backed in-workout editing or remove template fallback before contract is explicit.
2. Package C (`Planning`) next, because plan persistence and enrollment scheduling currently diverge.
3. Package A (`Exercise Catalog`) in parallel with Package C if backend capacity allows. Dictionary endpoints and search guarantees are largely independent.
4. Package E (`Summaries / Progress / Home`) after upstream contracts stabilize, otherwise summary endpoints will freeze current inconsistencies into API.
