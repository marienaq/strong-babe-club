# Security and privacy

Strong Babe is a single-user, fully offline iPhone app. This document covers the threat model, how data is handled, what the repo does to stay safe as a **public** repository, and how to report a problem.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** on this repository (Security tab → "Report a vulnerability"). Don't open a public issue for security problems. Expect a reply within a week; this is a personal project, so there is no bounty.

## Threat model (brief)

What we protect: the owner's training history, body-related notes ("knee felt off"), ratings and the display name. Sensitive-ish health-adjacent data, but no credentials, payments or contacts.

| Threat | Mitigation |
|---|---|
| Someone with the phone while it's locked reads the journal | SwiftData store in Application Support with `NSFileProtectionComplete`, plus the `com.apple.developer.default-data-protection = NSFileProtectionComplete` entitlement for every file the app creates. |
| Data leaves the device | No network code at all (no URLSession, no analytics/crash SDKs, no CloudKit: `cloudKitDatabase: .none`). App Transport Security is left at its secure defaults. Exports only happen when the user taps Export and picks a destination. |
| Logs leak personal data | `os.Logger` only. We log counts and error *types* (`privacy: .public`); never notes, names, weights or dates. Nothing personal is printed in crash paths. |
| A malicious or corrupted import file | User-picked via `fileImporter` (system picker, security-scoped access released after reading); size checked before reading (20 MB cap); strict typed decoding (wrong types reject the record); every number range-checked (weights 0–1000 lb, reps 0–1000, durations ≤ 4 h, dates 2000–2100); strings stripped of control characters and truncated; counts capped; the whole import is refused if more than half the records are invalid. Nothing is evaluated or executed. Covered by unit tests with malformed inputs. |
| A half-finished import corrupts the journal | Imports are decoded off the main thread, then saved in batches. If any batch fails, everything written so far is removed again (and any replaced records restored), and the error is shown. Re-importing replaces earlier imports but never overwrites days logged in the app. |
| Test data mixed with real data | Test mode (`-ui-testing`) uses an in-memory store, separate preferences, a fixed date, and a visible badge. It is never used on a device someone is using. |
| CSV export opened in a spreadsheet runs a formula | Cells beginning with `= + - @` (that aren't numbers) are prefixed with `'`; quoting per RFC 4180. |
| Supply-chain compromise | Zero third-party Swift dependencies. GitHub Actions pinned to full commit SHAs with version comments; Dependabot keeps them current. CI downloads XcodeGen and gitleaks at pinned versions and verifies SHA-256 checksums. Workflows run with `permissions: contents: read` (CodeQL adds only `security-events: write`). `persist-credentials: false` on checkout. |
| Secrets committed to the public repo | There are no secrets. `DEVELOPMENT_TEAM` is empty in `project.yml` (set it locally in Xcode). CI runs gitleaks over the full git history; GitHub secret scanning + push protection should be enabled in repo settings. `.gitignore` blocks `.env*`, certificates and provisioning profiles. |
| Personal data committed to the public repo | `.gitignore` excludes `*.xlsx`, `*.csv`, `data/` (history.json, movements.json, import_report.md) and exports. CI fails if any such file is tracked. Tests use an invented fixture (`Packages/WorkoutCore/Tests/Fixtures/sample_history.json`). The importer takes the input path as an argument; no personal file names are hard-coded. |
| Code-quality bugs with security impact | CodeQL (Swift) runs on pushes, PRs and weekly. |

Out of scope: a jailbroken device, an attacker with the unlocked phone, or someone with the owner's iCloud backup password (device backups include app data; encrypted backups keep it encrypted).

### Why `NSFileProtectionComplete` is safe here

`Complete` makes files unreadable ~10 seconds after the device locks. The app has no background modes and never touches the store in the background: every change is saved immediately while the app is in the foreground, and interval-timer alerts while backgrounded are pre-scheduled **local** notifications that need no file access. So the stricter class costs nothing. If background work is ever added (e.g. a Live Activity writing logs), revisit this and consider `completeUntilFirstUserAuthentication` for that specific file only.

## Data handling

- **Stored on device:** workouts and their sections, set/round logs, feedback and notes, sticker picks, training maxes, benchmarks, goals and settings (including the optional display name). Store: `Application Support/StrongBabeClub/journal.store`.
- **UserDefaults:** UI preferences only (Progress chart tab, lift, range and year toggle; timer sounds on/off) via `@AppStorage`, declared in `PrivacyInfo.xcprivacy` as `CA92.1`.
- **Privacy manifest:** `NSPrivacyTracking = false`, no tracking domains, no collected data types.
- **Permissions:** only notifications, requested at runtime the first time a timer starts. No camera, location, health, contacts or tracking prompts.
- **Deleting data:** Settings → Delete all data removes every record; deleting the app removes the store.

## Future AI planner: rules for keeping it safe

An AI-designed workout planner is on the roadmap. When it lands:

- **Never ship an API key in the app** (not in code, Info.plist, xcconfig, or obfuscated). Anything in an app binary can be extracted.
- The app talks to a **small server-side proxy** (e.g. a Supabase or Netlify function) that holds the model provider key, authenticates the single user, rate-limits, and forwards only what's needed.
- Send the minimum: recent workouts, ratings and limits. Strip or summarise free-text notes unless the user opts in.
- Validate the planner's response exactly like an import: decode into `PlannedWorkout`, bound every value, check equipment and limits, and fall back to `RulesWorkoutPlanner` on any error or when offline.
- Adding networking means revisiting this document, the privacy manifest (collected data types) and the App Store privacy label.
