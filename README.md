# Strong Babe Club

A personal iPhone workout app that **plans each workout for you** in a coach's four-part format (warm-up, strength, metabolic, cool-down), runs it with timers, and keeps you going with streaks, stickers and a scrapbook journal. Fully offline. Built for one person (the owner); public so others can learn from it.

Repo: [github.com/marienaq/strong-babe-club](https://github.com/marienaq/strong-babe-club)

> Screenshots: _coming once the app runs on a device_. Until then, the approved design mockups live in [`docs/design/`](docs/design/) (open any `*.dc.html` in a browser).

## What it does

- **Plans every workout** with a rules-based engine: a two-week A/B rotation of six barbell lifts (Mon squat / Wed hip-pull / Fri overhead), quarterly 13-week training-max blocks (volume → strength → peak → deload → test), ramping "every 2 min, go up each set" strength work, a warm-up that primes the lift, a metabolic piece that stays off the same muscles, and core + stretch to finish.
- **Explains itself**: every rule that fires leaves a "why this?" reason. Shuffle one section or everything.
- **Knows the home gym**: plate math for the owner's plate pairs (45 lb bar, 230 lb ceiling, warnings ahead of time), dumbbells/kettlebells snapped to what's on the rack, limits like "no jumping" or "easy on the knee".
- **Quarterly benchmarks** repeat exactly (same moves, weights, timing, name like `amrap-5-4-fungi`) so scores compare quarter to quarter.
- **Motivation**: streak counted in planned workouts (sick days excused), last-30-days %, Kettle the kettlebell's coach note (push / comeback / just show up), pick-your-own stickers with rare unlocks (PR star, streak milestones).
- **Progress**: Swift Charts for top set and volume, benchmark table, block strip, goals.
- **Import / export**: imports the coach-sheet history (via `tools/import_sheet.py`) or an app backup; exports JSON backups and CSV set logs, only when you ask.

The full product plan is [`IOS-PLAN.md`](IOS-PLAN.md) (the source of truth). `docs/archive/` holds the outdated originals.

## Architecture

```
Packages/WorkoutCore/        Swift package, platform-agnostic, zero dependencies
  Sources/WorkoutCore/
    Foundation/              LocalDate (civil dates), seeded SplitMix64 RNG
    Models/                  value types matching IOS-PLAN's data model
    Strength/                program calendar, A/B rotation, TM math (Epley, 90%),
                             prescriptions + ramps, session-feel rules, TM book
    Equipment/               plate calculator + ceiling forecast, DB/KB snapping
    Library/                 movement library (patterns, muscles, impact, joints),
                             formats, workout namer
    Engine/                  WorkoutPlanner protocol + RulesWorkoutPlanner,
                             benchmark scheduler/proposer
    Motivation/              streak, 30-day %, coach notes, stickers
    Progress/                scores, PRs, chart series, goals
    Timer/                   interval timer state machine (EMOM, work/rest)
    Import/                  bounded coach-history importer, backups, safe CSV
  Sources/wcplan/            dev CLI: print planned workouts for a date range
  Tests/                     158 unit tests + invented fixture
  TestSupport/XCTest/        tiny XCTest shim for machines without Xcode
App/StrongBabeClub/          iOS 17 SwiftUI app
  Store/                     AppStore (@Observable) over a Repository protocol
  Persistence/               SwiftData records + repository (file protection)
  Screens/                   Today, workout (strength/metabolic/warm-up), Why,
                             Finish, Journal, Progress, Settings
  Design/                    palette, fonts, paper, tape, stickers, bear, motion
  Services/                  timers + notifications, logging, file protection
App/StrongBabeClubTests/     store + SwiftData round-trip tests
App/StrongBabeClubUITests/   launch-and-walk smoke test
project.yml                  XcodeGen spec (the .xcodeproj is generated, not committed)
tools/import_sheet.py        coach spreadsheet -> history.json (run locally)
```

Key seams:
- **`WorkoutPlanner`** (async protocol) is the only way screens get workouts. v1 is `RulesWorkoutPlanner` (deterministic for a date + shuffle salts). A future AI planner plugs in here; see [CONTRIBUTING.md](CONTRIBUTING.md).
- **`Repository`** is the only persistence boundary: SwiftData in the app, in-memory in UI tests and previews. Views never touch SwiftData.

## Build and test

Requirements: macOS 14+, Swift 5.10+. Full Xcode 16+ for the iOS app.

```sh
# Core logic tests
cd Packages/WorkoutCore && swift test            # with Xcode installed
scripts/test-core.sh                             # auto: swift test, or the shim runner without Xcode

# Look at what the planner would do (reads only files you pass)
cd Packages/WorkoutCore && swift run wcplan 2026-10-19 --days 6
swift run wcplan 2026-10-12 --history /path/to/your/history.json --days 3

# Type-check the app's UI layer without Xcode (macOS SDK)
scripts/typecheck-app.sh

# iOS app (needs Xcode + XcodeGen)
brew install xcodegen
xcodegen generate
open StrongBabeClub.xcodeproj    # set your Team under Signing, run on device/simulator
xcodebuild test -project StrongBabeClub.xcodeproj -scheme StrongBabeClub \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Importing your coach sheet (personal data stays local and is git-ignored):

```sh
pip install openpyxl
python3 tools/import_sheet.py ~/path/to/sheet.xlsx --out-dir ~/strong-babe-data
# then in the app: Settings > Import history or backup > pick history.json
```

## Status: verified vs not yet verified

| Area | Status |
|---|---|
| WorkoutCore build (macOS) | Verified locally (`swift build`, Swift 5.10, Command Line Tools) |
| WorkoutCore tests | Verified locally: **158 tests, 0 failures**, ~92% line coverage, via the XCTest shim runner (`scripts/test-core.sh`). CI also runs them under real XCTest. |
| Planner output | Spot-checked locally with `wcplan` against real imported history (test week, block 1 weeks) |
| App UI layer (views, store, timers, services: 21 files) | **Type-checked** locally against the macOS 14 SDK (`scripts/typecheck-app.sh`). Not yet compiled for iOS. |
| SwiftData persistence + `@main` | **Not compiled locally** (SwiftData macros ship only with Xcode). Covered by CI's iOS build and `SwiftDataRepositoryTests`. |
| iOS build, app unit tests, UI smoke test | **Pending CI** (GitHub Actions `macos-15` with Xcode) or a local Xcode install |
| XcodeGen project | Verified locally: `xcodegen generate` produces the project, Info.plist and entitlements |
| On-device behaviour (fonts, haptics, notifications, file protection, animations) | Not verified yet: needs a device |

Known gaps / deferred: app icon, Lock Screen timer, Apple Watch, the AI planner, CSV import (JSON import only), movement library editing, "Celebrate"/"Variety" coach notes.

## Roadmap

1. Install Xcode, run on the owner's iPhone, fix whatever CI/devices surface.
2. Use it for the test week (Oct 12–16, 2026) and block 1.
3. Approve the 6 proposed benchmarks; tune movement tags from real use.
4. Celebrate / Variety coach notes, more bear animations polish, app icon.
5. AI planner behind `WorkoutPlanner` via a small server proxy (see CONTRIBUTING).
6. TestFlight, Lock Screen / Live Activity timer, Apple Watch heart rate.

## License

MIT, see [LICENSE](LICENSE). Bundled fonts Caveat and Nunito are under the SIL Open Font License 1.1 (license texts in `App/StrongBabeClub/Resources/Fonts/`).
