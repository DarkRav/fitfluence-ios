# Backend Gaps For New Athlete Flow

Этот список зафиксирован по текущей реализации нового контура `Сегодня → Плеер 2.0 → Завершение`.

## 1) Home / Today

### Требуется endpoint "тренировка дня"
- **Назначение:** чтобы `Сегодня` показывал не первый элемент из кэша, а реальную тренировку на текущую дату.
- **Контракт (предложение):**
  - `GET /v1/athlete/today-workout`
  - `200`:
    - `programId: string`
    - `workoutId: string`
    - `title: string`
    - `scheduledDate: string (ISO date)`
    - `estimatedDurationMinutes: int`

### Требуется endpoint "последняя завершённая тренировка"
- **Назначение:** корректный CTA `Повторить`.
- **Контракт (предложение):**
  - `GET /v1/athlete/workouts/last-completed`
  - `200`:
    - `programId: string`
    - `workoutId: string`
    - `finishedAt: string (ISO datetime)`
    - `summary: { completedSets: int, totalSets: int }`

## 2) Workout Completion

### Требуется серверная фиксация завершения
- **Сейчас:** завершение фиксируется локально.
- **Нужно:**
  - `POST /v1/athlete/workouts/{workoutId}/complete`
  - body:
    - `programId: string`
    - `completedAt: string`
    - `sets: [ { exerciseId, setIndex, completed, reps, weight, rpe } ]`

### Требуется чтение истории
- **Назначение:** вкладка `Прогресс`.
- **Контракт (предложение):**
  - `GET /v1/athlete/workouts/history?limit=...&cursor=...`
  - `GET /v1/athlete/workouts/history/{sessionId}`

## 3) Partial Sync (offline-first)

### Требуется endpoint idempotent upsert по сессии
- **Назначение:** синхронизировать офлайн-изменения после восстановления сети.
- **Контракт (предложение):**
  - `PUT /v1/athlete/workout-sessions/{sessionId}`
  - body:
    - `programId`
    - `workoutId`
    - `currentExerciseIndex`
    - `updatedAt`
    - `sets[]`

## 4) Program / Workout Metadata

### Требуется флаг "isScheduledToday" в списке тренировок программы
- **Назначение:** точная маркировка в `План`.
- **Контракт (предложение):**
  - расширить текущий workout summary:
    - `isScheduledToday: bool`
    - `orderToday: int?`

