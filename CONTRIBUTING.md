# Contributing notes

This is a personal app, but it's structured so that future work (including by AI coding agents) stays safe and predictable.

## Ground rules

- `IOS-PLAN.md` is the product source of truth. Change the plan first, then the code.
- Keep logic in `Packages/WorkoutCore` (pure Swift, no UI, no I/O beyond `Data` in / `Data` out) and cover it with tests. The app layer should stay thin.
- Never commit personal data: no spreadsheets, no `data/`, no real names or emails in code or fixtures. Use invented fixtures.
- No new third-party dependencies without a strong reason; if one is added, pin an exact version and explain why in the PR.
- Pin any new GitHub Action to a full commit SHA with a `# vX.Y.Z` comment.
- Run before pushing: `scripts/test-core.sh` and `scripts/typecheck-app.sh` (and the Xcode tests if you have Xcode).

## Adding an AI planner

The screens only ever call the `WorkoutPlanner` protocol (`Packages/WorkoutCore/Sources/WorkoutCore/Engine/WorkoutPlanner.swift`):

```swift
public protocol WorkoutPlanner: Sendable {
    func plan(_ request: PlanRequest) async throws -> PlannedWorkout
    func shuffle(_ workout: PlannedWorkout, section: SectionKind?, request: PlanRequest) async throws -> PlannedWorkout
}
```

To add an `AIWorkoutPlanner`:

1. **Input:** build a compact, minimal context from `PlanRequest`: settings (schedule, equipment, limits, target minutes), training maxes, block position, the last 4–6 weeks of workouts with ratings, and active benchmarks. Leave free-text notes out unless the owner opts in.
2. **Transport:** call the project's server proxy over HTTPS. The proxy holds the model API key. **No API keys in the app, ever** (see SECURITY.md).
3. **Output:** ask for JSON matching `PlannedWorkout` (sections, items, planned sets, `reasons`). Decode strictly, then validate the way imports are validated: bounds, loadable barbell weights (`PlateCalculator`), DB/KB snapping (`ImplementSnapper`), limits (`MovementLibrary.resolve`), Olympic lifts ≤ 3 reps, and the 7-day no-repeat rule.
4. **Reasons:** every section needs at least one `PlanReason`, so "why this?" keeps working.
5. **Fallback:** on any network/decoding/validation error, or offline, return `RulesWorkoutPlanner().makePlan(request)` and add a reason saying so.
6. **Tests:** put the validation in WorkoutCore and test it with recorded (invented) responses, including malformed and hostile ones. Don't hit the network in tests.
7. **Wiring:** `AppStore(repository:planner:)` already accepts any planner; switch it in `StrongBabeClubApp` behind a setting.

## Determinism

`RulesWorkoutPlanner` is deterministic: the same date, history, settings and `SectionSalts` always produce the same workout (IDs included). Shuffle increments a section's salt. Keep it that way: use `SeededRandom`, never `SystemRandomNumberGenerator`, and inject `now` instead of calling `Date()` in the core.
