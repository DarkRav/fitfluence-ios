# Exercise Catalog Contract Gaps

Эта заметка фиксирует, что уже реализовано в iOS по реальному OpenAPI `fitfluence/openapi/schemas/openapi.yaml`, и чего не хватает для полноценного athlete-side exercise catalog.

## Что уже используется в iOS

- `POST /v1/athlete/exercises/search`
- `GET /v1/athlete/exercises/{exerciseId}`
- Схемы:
  - `Exercise`
  - `ExerciseFilter`
  - `ExercisesSearchRequest`
  - `PagedExerciseResponse`
  - `Muscle`
  - `Equipment`
  - `MovementPattern`
  - `DifficultyLevel`
  - `MuscleGroup`
  - `EquipmentCategory`

## Что реализовано поверх контракта

- Единый domain layer:
  - `ExerciseCatalogItem`
  - `ExerciseCatalogQuery`
  - `ExerciseCatalogRepository`
- Backend-backed source поверх athlete exercise search.
- Mapping из backend `Exercise` в iOS domain без локального seed catalog.
- Honest degraded fallback:
  - пустые/unavailable state
  - fallback только на реальные user-owned `saved templates`

## Contract gaps

1. Для athlete/public части нет endpoints для загрузки справочников `muscles` и `equipment`.
   Сейчас есть только `admin` search для этих сущностей, поэтому iOS не может честно построить полноценные athlete-side filter pickers по мышцам и оборудованию.

2. Нет athlete/public endpoint для curated exercise catalog metadata.
   Можно искать упражнения, но нельзя отдельно загрузить доступные фильтры, facet counts, рекомендованные подборки или готовые catalog sections.

3. Нет backend contract для athlete-side ready template library.
   Поэтому в iOS убраны локальные demo templates, а раздел "Готовые" оставлен без фейкового наполнения.

4. OpenAPI `Exercise` не несёт workout-builder prescription defaults.
   Для добавления упражнения в quick workout/template iOS использует явные local-only draft defaults (`3 x 8-12`, отдых `90 сек`) до тех пор, пока backend не начнёт возвращать такие defaults отдельно.

5. OpenAPI `Exercise` не разделяет primary/secondary muscle contribution и exercise role.
   Для rule-based generator это означает, что iOS может честно балансировать только по `muscleGroup`, `equipment` и `movementPattern`, но не может надёжно различать main lift, secondary lift, accessory или core finisher.

## Что добавить в backend для следующих эпиков

- Athlete/public search/list endpoints для `muscles`.
- Athlete/public search/list endpoints для `equipment`.
- Либо athlete/public endpoint с агрегированными exercise catalog filters:
  - доступные muscles
  - available equipment
  - supported movement patterns
  - supported difficulty levels
- Athlete/public endpoint для ready template library, если нужны backend-curated templates.
- Если нужен более умный builder:
  - отдельный contract для recommendation/prescription defaults на уровень exercise selection.
  - primary vs secondary muscle contribution.
  - exercise role / slot type для workout composition.
