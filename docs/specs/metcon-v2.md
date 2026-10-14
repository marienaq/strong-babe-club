# Metcon v2: requirements spec

Status: **approved with owner decisions (§0)**, v2.1 · Scope: `Packages/WorkoutCore` (planner, library, formats, benchmarks, importer, timer) plus the app's persistence of the new section fields.

> **v2.1 (§17–§23)** adds athlete-calibrated pace, density rules, default loads, a quality score with best-of-N selection, feedback learning, and optional strength recommendations. Where v2.1 changes an earlier value, the earlier text has been updated or points to the v2.1 section. If anything still conflicts, **v2.1 wins**.

## 0. Owner decisions (2026-10-14): these override everything below

| Q | Decision | Spec impact |
|---|---|---|
| Q1 | **Yes: generated metcons may include barbell lifts**, never the day's strength lift. The §4 lift-clash rules (no loaded move of the day's pattern) still apply. | Barbell moves (deadlift, back/front squat, hang power clean, power clean, push press, push jerk, thruster, shoulder press) become eligible for remixes, not only `benchmarkOnly`. Load = 50% of TM for squats and deadlift, 55% for cleans and presses, rounded to plates (§19). At most **one barbell move per metcon**. Barbell moves count as `technical` in the quality score. Supersedes §13 Q1 and §15 "barbell lifts in remixed metcons". |
| Q2 | **Tabata: one move at a time, 40 s work / 20 s rest.** Example: 3 moves × 6 rounds = 18 min. | **No extra rest between moves:** the 20 s rest is the change-over, so `roundRestSec = 0`. Duration = `n × R × 60 − 20` s. Shapes: 3×4 (12), 3×5 (15), 4×4 (16), 3×6 (18), 4×5 (20), 3×7 (21), 4×6 (24), 5×4 (20). Update §5, MC-7 and the timer accordingly. |
| Q3 | **Yes:** fast full-body moves (KB swings, thrusters, snatches, slams) can fill the heart-rate slot and count as full-body. | As proposed. |
| Q4 | **Keep the 50-min soft session target.** | As proposed. |
| Q5 | No answer. **Use the default:** auto-replace a retired benchmark from history, labelled "new". It can be turned off. | As proposed. |
| Q6 | **Yes:** the heaviest lift's day leans shorter. | Reinterpreted under Q7: within the narrow weekly spread, the heaviest day gets the shortest piece. |
| Q7 | **Days are about the same length, like the coach's.** Sometimes Friday (the last scheduled day) is lighter. | **Replace the S/M/L weekly spread (MC-14).** Each week picks one target length around the **middle band (17–21 min)**, adjusted by phase (§8). Spread across the week's days ≤ 3 min. The heaviest-lift day gets the lowest value of that range. About 1 week in 4 (deterministic from the week seed), the last scheduled day is "lighter": short band (12–16) or weights −1 step. Format variety (MC-16) stays. MC-15 holds within the narrow spread. |
| Q8 | **Yes:** learn pace and density from scores and ratings, within the §22 limits. | As proposed. |
| Strength S1–S5 | Not decided. **Strength programming is unchanged in this build.** | Only MC-65 (comeback metcon) is in scope. |

**Plan refresh (app):** `AppStore.ensurePlan` re-plans an untouched future plan only when `source` is `"rules-v1"` or `"missed"`. If v2 plans use a new source (e.g. `"rules-v2"`), include it there and re-plan untouched `"rules-v1"` plans on first launch after the update, so the next workout immediately follows these rules.

This spec redesigns how the planner builds the **metabolic conditioning section ("metcon")** of each workout. A developer should be able to implement it and write the listed tests without further questions. Requirements are numbered `MC-n`. Each has acceptance criteria a unit test can check.

---

## 1. Background

### 1.1 What went wrong

On Mon Oct 12, 2026, the planner produced a Tabata with a single movement, about 6 minutes long. The causes:

| # | Cause | Where |
|---|---|---|
| 1 | Templates allow 2 moves (Tabata, 21-15-9). Tabata is fixed at 8 min. | `FormatLibrary.metabolic` |
| 2 | When filters run out (muscle overlap, no repeated pattern, no timed moves in Tabata/interval), the move picker silently returns fewer moves. | `buildMetabolic` |
| 3 | `fitLength` trims AMRAP/EMOM/for-time to 6 min and interval rounds to 2. "Just show up" shortens further. | `fitLength` |
| 4 | Test-week templates are 8 min. | `FormatLibrary.short` |
| 5 | Benchmarks are copied verbatim with no lift-clash or length check. The first proposed benchmark contains Back Squats and was scheduled on Back Squat day. | `BenchmarkScheduler`, `BenchmarkProposer` |
| 6 | Nothing links metcon length or style to the strength phase or the day. | — |
| 7 | **Found during this review:** interval `rounds` are treated as single work periods, not full circuits. An imported 6-round 40/20 piece with 3 moves is estimated at 6 min (really 18), and the importer drops the "per station" flag, so station pieces get the wrong timer. | `WorkoutDuration.estimate`, `IntervalPlan.forSection`, `HistoryImporter` |
| 8 | **Found during this review:** `buildMetabolic` skips benchmarks entirely in test weeks, so the "test weeks catch up missed benchmarks" rule never runs. | `buildMetabolic` |

### 1.2 What the coach's 373 historical metcons show

These are aggregate stats from the imported history. They are the calibration target.

| Measure | Finding |
|---|---|
| Moves per metcon | 3 moves: 44% · 4: 52% · 5: 5% · never 1 or 2 |
| Length (pieces with a computable length, n = 305) | 15–27 min, median ≈ 19.5. 97% fall in 12–24 min. |
| Formats | AMRAP (one block or rounds with rest) 53% · stations/interval 27% · for time 18% · EMOM ~1% · Tabata 0% |
| Most common shapes | 5 × 3-min AMRAP with 1 min rest · 4 rounds of 4 one-minute stations, 1 min rest · AMRAP 18–20 · 10-down-to-1 and 1-up-to-10 for time · 40/20 circuits of 3–4 moves |
| Coverage | legs or full-body 100% · arms or full-body 95–98% · full-body 77–90% (depends on how cleans are counted) · cardio 63% · core 29–31% |
| Push vs pull | about 14 push moves for every pull |
| Day's lift in metcon | 0 of 373 |
| Day's pattern in metcon | squat-type moves on squat days: 4 of 112 (all bodyweight or light). Overhead DB presses on press days: none (push-ups and DB bench press are common). Swings and snatches on hinge days: common. |
| Barbell lifts in metcons | 61% of metcons include a light barbell lift (a different one from the day's lift) |
| Jumping moves | 35% of metcons have one; 2.4% have two or more |
| Length by day or lift | no pattern; every day averages about 20 min |
| Typical reps in AMRAPs (median) | push-ups 4, KB swings 7, up/downs 4, burpees 3, jumping jacks 12, lunges 6, DB push press 7–8, DB snatch 8, sit-ups 8, goblet squats 5 |

### 1.3 Owner's rules

- Every metcon has **3–5 moves** and lasts **12–24 minutes**.
- Shorter (12–16) suits continuous work or a heavy strength day. Longer (up to 24) suits pieces with rest, or a metabolic-focus day.
- Mental model: **one move for heart rate, one for arms, one for legs**. Sometimes one move covers two areas. Sometimes a 4th or 5th move adds core or agility.
- Tabata stays only as **40 s work / 20 s rest**.

---

## 2. Goals, non-goals, user-visible changes

### Goals
1. Every planner-built metcon meets the owner's hard rules: 3–5 moves, 12–24 min, no day's-lift clash.
2. Metcons look like the coach's: heart + legs + arms coverage, reps sized to time, familiar shapes.
3. Length and style follow the strength program and spread across the week.
4. Benchmarks obey the same hard rules and stay exactly comparable between quarters.
5. Every choice can be explained in the "Why this?" sheet.

### Non-goals
- No change to strength programming, lift rotation, warm-up or cool-down content (only the warm-up round count may be trimmed, as today).
- No AI planner.
- No new user settings (except the defaults in §13 if the owner picks them).

### User-visible changes
| Area | Before | After |
|---|---|---|
| Metcon size | 1–4 moves, 6–20 min | always 3–5 moves, 12–24 min |
| Week shape | random lengths | a short, a middle and a long piece each week (by default) |
| Formats | Tabata 20/10, 8 min | Tabata 40/20 (12–24 min); new **stations** format; interval rounds are full circuits |
| Heavy days | no link | heavier strength day → shorter metcon; peak weeks never long; deload weeks longer and easier |
| Test weeks | 8-min pieces | 12–16-min pieces, plus missed benchmarks caught up |
| "Just show up" | as short as 6 min | 12–14 min, never shorter |
| Benchmarks | can clash with the day's lift | moved to a compatible day; benchmarks that break the rules are retired, never altered |
| "Why this?" | "A fresh amrap that stays off the muscles…" | stimulus, length reason, slot coverage, what was avoided and why |

---

## 3. Glossary

| Term | Meaning |
|---|---|
| **Slot** | A role a move fills in a metcon: `heart`, `legs`, `arms`, `core`, `agility`. |
| **Required slots** | `heart`, `legs`, `arms`. |
| **Full-body move** | A move whose `fills` set contains both `legs` and `arms`, or `legs`/`arms` plus `heart`. |
| **Stimulus** | The intended feel: `grind`, `repeat`, `race`, `intervals` (§6.1). |
| **Band** | Target length range: `short` 12:00–16:59, `middle` 17:00–20:59, `long` 21:00–24:00 (by estimated seconds). |
| **Shape** | One concrete catalog entry: format + rounds + work/rest + move count (§6.2). |
| **Day slot** | The day's main lift slot: `squat`, `hipPull`, `overhead` (`LiftSlot`). |
| **Conflict** | A move tagged as loading the same pattern as a day slot (`conflictsWith`). |
| **E** | Estimated finish time of a for-time piece, in seconds. |

---

## 4. Movement tagging

### 4.1 New fields on `Movement`

| Field | Type | Meaning | Default when missing |
|---|---|---|---|
| `fills` | `Set<MetconSlot>` | Slots this move can fill | `[]` (not metcon-eligible by slot) |
| `legKind` | `LegKind?` (`squat`, `lunge`, `hinge`) | Kind of leg work | nil |
| `armKind` | `ArmKind?` (`push`, `pull`) | Kind of arm work | nil |
| `overhead` | `Bool` | Arm work goes overhead | false |
| `secondsPerRep` | `Double` | Typical seconds per counted rep at metcon pace (for steps/alternating moves: per counted rep) | required for metcon moves |
| `repRange` | `ClosedRange<Int>` | Reps per set the athlete can do unbroken at metcon pace | required for metcon moves |
| `countsEachSide` | `Bool` | Reps are counted per side; prescribed reps must be even | false |
| `gripHeavy` | `Bool` | Taxes grip (KB/DB held, hanging, pulling) | false |
| `shoulderHeavy` | `Bool` | Taxes shoulders (overhead, wall walks, many push-ups) | false |
| `technical` | `Bool` | Needs care; goes first in order | false |
| `conflictsWith` | `Set<LiftSlot>` | Day slots on which this move is not allowed | `[]` |
| `metconTimedOnly` | `Bool` | Only usable in time-based formats (holds) | equals `timed` |

`MetconSlot`, `LegKind`, `ArmKind` are new enums. All new fields are code-defined on the seed library (not persisted), so no data migration is needed for movements.

`MovementRole` gets one new case: `benchmarkOnly`. Moves with this role are tagged (so benchmarks can be checked) but are never picked for remixed metcons.

### 4.2 Slot taxonomy (rules)

- **heart**: raises heart rate fast. Cardio moves, plus fast cyclical full-body moves (swings, snatches, thrusters, slams).
- **legs**: `squat` (bilateral knee-dominant), `lunge` (single-leg, step-ups), `hinge` (hip-dominant).
- **arms**: `push` (horizontal or overhead) or `pull` (rows, pull-ups, high pulls, snatches/cleans count as pull).
- **core**: trunk flexion, rotation, holds.
- **agility**: lateral or multi-directional footwork, crawling.
- A full-body move may fill **up to two** of legs/arms/heart for coverage purposes. If its `fills` has three, the planner counts the two that are still uncovered.

### 4.3 Conflicts with the day's lift (rules)

| Day slot | Excluded (`conflictsWith` contains slot) | Still allowed (coach does it) |
|---|---|---|
| `squat` (Back/Front Squat) | All **loaded** squat-kind moves: goblet squat, DB front squat, DB thruster, DB hang squat clean, barbell squats | lunges, step-ups, hinges, swings. Bodyweight squats (air squat, box jump, squat to stand) at most **1** per metcon |
| `hipPull` (Deadlift/Hang Power Clean) | Loaded slow hinges and cleans: KB deadlift, DB RDL, DB deadlift, DB glute bridge, KB sumo deadlift high pull, DB hang squat clean, DB hang clean + push press, barbell deadlift/cleans | KB swings, DB snatches, plate/DB ground-to-overhead, glute bridges (bodyweight) |
| `overhead` (Push Press/Push Jerk) | Loaded overhead presses: DB push press, DB strict press, DB curl + press, DB hang clean + push press, DB thruster, wall walks, barbell presses/jerks | push-ups, DB bench/floor press, ground-to-overhead (max 1 `shoulderHeavy` move on overhead days) |

The day's lift itself (`lift.movementID`) is always excluded, whatever its tags.

### 4.4 Existing library movements: metcon tags

> The `s/rep` values in this section are generic priors. The planner uses the **athlete-calibrated values in §17.2**. Default weights are in §19.

`s/rep` = `secondsPerRep`. Flags: **HI** high impact (existing), **G** grip-heavy, **S** shoulder-heavy, **T** technical, **2** counts each side. Conflicts use `sq` / `hp` / `oh`.

Metcon-eligible moves must have the `metabolic` role. "Add role" means the role is added by this spec.

**Heart**

| id | fills | kinds | s/rep | repRange | flags | conflicts | note |
|---|---|---|---|---|---|---|---|
| jumping-jack | heart | — | 1.0 | 10–30 | HI | — | |
| toe-tap | heart | — | 0.6 | 10–40 | 2 | — | |
| burpee | heart | — | 4.0 | 3–10 | HI | — | |
| up-down | heart | — | 3.0 | 3–10 | | — | |
| squat-thrust-hold (Squat to Stand) | heart, legs | squat | 2.5 | 4–12 | | — | bodyweight squat |
| high-knees | heart | — | 0.5 | 20–50 | HI, 2 | — | add `metabolic` role |
| marching-knees | heart | — | 0.5 | 20–50 | 2 | — | add `metabolic` role; low-intensity fallback |
| mountain-climber | heart, core | — | 0.6 | 10–40 | 2 | — | |
| bike-cal | heart | — | 4.0 | 5–20 | | — | needs bike |
| box-jump | heart, legs | squat | 2.7 | 3–10 | HI, T | — | bodyweight squat |

**Legs**

| id | fills | kinds | s/rep | repRange | flags | conflicts |
|---|---|---|---|---|---|---|
| air-squat | legs | squat | 1.5 | 6–20 | | — (bodyweight squat) |
| goblet-squat | legs | squat | 2.4 | 5–15 | G | sq |
| lunge | legs | lunge | 2.0 | 6–20 | 2 | — |
| db-reverse-lunge | legs | lunge | 2.2 | 6–16 | 2, G | — |
| bench-step-up | legs | lunge | 1.8 | 6–20 | 2 | — |
| box-step-up | legs | lunge | 1.8 | 6–20 | 2 | — |
| db-split-squat | legs | lunge | 2.5 | 6–12 | 2, G | — |
| glute-bridge | legs | hinge | 1.5 | 8–20 | | — |
| db-glute-bridge | legs | hinge | 1.8 | 8–20 | | hp |
| kb-deadlift | legs | hinge | 1.8 | 6–15 | G | hp |
| db-rdl | legs | hinge | 2.2 | 6–12 | G | hp |

**Full-body**

| id | fills | kinds | s/rep | repRange | flags | conflicts |
|---|---|---|---|---|---|---|
| kb-swing | legs, heart | hinge | 1.7 | 6–20 | G | — |
| db-snatch | legs, arms, heart | hinge, pull, overhead | 1.5 | 6–16 | 2, G, S, T | — |
| db-hang-squat-clean | legs, arms | squat, pull | 2.4 | 4–10 | G, T | sq, hp |
| db-thruster | legs, arms, heart | squat, push, overhead | 2.4 | 5–12 | S | sq, oh |
| plate-ground-to-overhead | legs, arms | hinge, push, overhead | 2.0 | 5–12 | S | — |
| kb-high-pull | legs, arms | hinge, pull | 2.0 | 6–15 | G | hp |
| med-ball-slam | heart, core | — | 2.0 | 6–15 | | — |

**Arms**

| id | fills | kinds | s/rep | repRange | flags | conflicts |
|---|---|---|---|---|---|---|
| push-up | arms | push | 3.0 | 3–12 | | — |
| db-floor-press | arms | push | 2.0 | 6–15 | | — |
| db-bench-press | arms | push | 2.0 | 6–15 | | — |
| db-push-press | arms | push, overhead | 1.6 | 5–12 | S | oh |
| db-strict-press | arms | push, overhead | 2.0 | 5–12 | S | oh · add `metabolic` role |
| tricep-dip | arms | push | 1.8 | 6–15 | | — |
| wall-walk | arms, core | push, overhead | 12.0 | 1–5 | S, T | oh |
| db-row | arms | pull | 2.0 | 6–16 | 2, G | — |
| australian-pull-up | arms | pull | 3.0 | 3–12 | G | — |

**Core and agility**

| id | fills | s/rep | repRange | flags | note |
|---|---|---|---|---|---|
| sit-up | core | 1.5 | 6–20 | | |
| v-up | core | 2.0 | 5–15 | | |
| leg-raise | core | 2.0 | 6–15 | | add `metabolic` role |
| lemon-squeezer | core | 1.8 | 6–15 | | add `metabolic` role |
| russian-twist | core | 0.8 | 10–30 | 2 | add `metabolic` role |
| flutter-kick | core | 0.5 | 10–40 | 2 | add `metabolic` role |
| plank-hold | core | timed | — | | add `metabolic` role; time-based formats only |
| hollow-hold | core | timed | — | | add `metabolic` role; time-based formats only |
| bear-crawl | agility, core | 0.8 | 10–30 | S | change `jointSubstitute` from marching-knees to skater-step (keeps the agility slot) |
| kb-farmer-carry (Suitcase March) | core | 0.8 | 10–40 | 2, G | |

**Not used in metcons (no change):** cossack-squat, good-morning, inchworm, inchworm-shoulder-tap, arm-circle (warm-up only); dead-bug, side-plank (cool-down only); all 10 stretches.

**The six main lifts** (role `mainLift`, never picked for remixes; tagged so benchmarks can be checked):

| id | fills | kinds | conflicts |
|---|---|---|---|
| back squat, front squat | legs | squat | sq |
| deadlift | legs | hinge | hp |
| hang power clean | legs, arms | hinge, pull | hp |
| push press, push jerk | arms | push, overhead | oh |

### 4.5 Library gaps: new movements

These fill gaps found in the coach's history, the agility slot and limit-heavy configurations. All get the `metabolic` role unless marked.

| id | name | equipment | fills / kinds | s/rep | repRange | flags | conflicts | substitutes |
|---|---|---|---|---|---|---|---|---|
| db-front-squat | DB Front Squats | DB pair | legs / squat | 2.4 | 5–15 | G | sq | joint(knee) → db-glute-bridge |
| db-step-up | DB Step-Ups | DB pair + box | legs / lunge | 2.0 | 6–16 | 2, G | — | joint(knee) → db-glute-bridge |
| db-front-rack-lunge | DB Front Rack Lunges | DB pair | legs / lunge | 2.2 | 6–16 | 2, G | — | joint(knee) → db-glute-bridge |
| overhead-plate-lunge | Overhead Plate Lunges | barbell (plate) | legs, arms / lunge, push, overhead | 2.2 | 6–12 | 2, S | oh | joint(knee) → plate-ground-to-overhead |
| db-deadlift | DB Deadlifts | DB pair | legs / hinge | 1.8 | 6–15 | G | hp | — |
| db-ground-to-overhead | DB Ground to Overhead | DB | legs, arms / hinge, push, overhead | 2.2 | 5–12 | S | — | — |
| db-curl-press | DB Curl + Press | DB pair | arms / pull, push, overhead | 2.4 | 5–12 | S | oh | — |
| db-hang-clean-push-press | DB Hang Clean + Push Press | DB pair | legs, arms / hinge, push, overhead | 2.6 | 4–10 | G, S, T | hp, oh | — |
| db-bent-over-row | DB Bent-Over Rows | DB pair | arms / pull | 2.0 | 6–15 | G | — | — |
| prone-swimmer | Prone Swimmers | bodyweight | arms / pull | 1.5 | 6–16 | | — | — |
| hand-release-push-up | Hand-Release Push-Ups | bodyweight | arms / push | 3.5 | 3–10 | | — | joint(wrist) → db-floor-press |
| lateral-bench-step-over | Lateral Bench Step-Overs | bench | agility, heart | 1.5 | 6–20 | | — | joint(knee) → lateral-shuffle-touch |
| skater | Skaters | bodyweight | agility, heart | 0.8 | 10–30 | HI, 2 | — | noJump → skater-step |
| skater-step | Skater Steps | bodyweight | agility | 1.0 | 10–30 | 2 | — | — |
| lateral-shuffle-touch | Lateral Shuffle Touches | bodyweight | agility, heart | 1.5 | 6–20 | 2 | — | — |
| power-clean | Power Cleans | barbell | legs, arms / hinge, pull | — | — | G, T | hp | role `benchmarkOnly` |
| barbell-shoulder-press | Shoulder Press | barbell | arms / push, overhead | — | — | S | oh | role `benchmarkOnly` |
| kb-overhead-swing | Overhead KB Swings | KB | legs, heart, arms / hinge, push, overhead | 2.0 | 6–15 | G, S | oh | role `benchmarkOnly` |
| db-curl | DB Curls | DB pair | arms / pull | — | — | G | — | role `benchmarkOnly` |

`prone-swimmer` exists so that a bodyweight-only gym with "easy on wrist" can still fill the arms slot.

### 4.6 Name aliases

`MovementLibrary` gets an alias table (`aliases: [String: String]`, slug → id) used by `lookup(name:)`. Every movement name used in at least 5 of the coach's metcons must resolve. The list (generic names only):

| Coach-style name | id |
|---|---|
| Up/Down | up-down |
| Push Up | push-up |
| KB Swing, Russian KB Swing | kb-swing |
| Burpee | burpee |
| Deadlift, Back Squat, Front Squat, Hang Power Clean, Push Press, Push Jerk | the main-lift ids |
| Sit Up, Strict Sit Up | sit-up |
| DB Push Press | db-push-press |
| Plate Ground To Overhead | plate-ground-to-overhead |
| Goblet Squat, KB Goblet Squat, DB Goblet Squat | goblet-squat |
| Single Arm DB Power Snatch, DB Power Snatch | db-snatch |
| Jumping Jack | jumping-jack |
| Lunge, Forward Lunge, Reverse Lunge | lunge |
| Bench Step Up, Step Up | bench-step-up |
| Air Squat | air-squat |
| V-Up | v-up |
| DB Curl + DB Press | db-curl-press |
| Power Clean | power-clean |
| DB Bench Press | db-bench-press |
| DB Front Squat | db-front-squat |
| Bench Jump | box-jump |
| Overhead KB Swing | kb-overhead-swing |
| DB Front Rack Lunge, DB Lunge | db-front-rack-lunge |
| Shoulder Press | barbell-shoulder-press |
| Overhead Plate Lunge | overhead-plate-lunge |
| DB Hang Squat Clean | db-hang-squat-clean |
| DB Ground To Overhead | db-ground-to-overhead |
| DB Step Up, DB Bench Step Up | db-step-up |
| Australian Pull Up | australian-pull-up |
| DB Hang Power Clean + Push Press | db-hang-clean-push-press |
| DB Deadlift | db-deadlift |
| DB Thruster | db-thruster |
| Lemon Squeezer | lemon-squeezer |
| DB Curl | db-curl |
| Toe Tap | toe-tap |
| Leg Raise | leg-raise |
| Wall Walk | wall-walk |

### Requirements: tagging

**MC-1 Tag completeness.** Every movement with role `metabolic` has non-empty `fills`, `secondsPerRep > 0` (unless `metconTimedOnly`), a `repRange` with lower ≥ 1, and `legKind` set if `fills` contains legs and `armKind` set if `fills` contains arms.
- *Test:* iterate `MovementLibrary.standard`; assert each property.

**MC-2 Tag values.** The tags of every movement in §4.4 and §4.5 match the tables exactly.
- *Test:* a table-driven test with one row per movement id.

**MC-3 Main lifts are tagged but never remixed.** The six main lifts and `benchmarkOnly` moves have `fills` and `conflictsWith` set and never appear in a remixed (non-benchmark) metcon.
- *Test:* year property test (§12) asserts no remixed item has role `mainLift` or `benchmarkOnly`.

**MC-4 Aliases.** `lookup(name:)` resolves every name in §4.6 to the listed id.
- *Test:* table-driven.

**MC-5 Substitute chains stay valid.** For every metcon move and every one of the 8 limit combinations × the equipment sets in §14.1, `resolve` returns either nil or a move that is allowed and has at least one `fills` slot in common with the original.
- *Test:* exhaustive loop.

---

## 5. Format catalog

### 5.1 Formats

`SectionFormat` gets a new case: **`stations`** (`nameStructure` "stations", `displayName` "stations"). `WorkoutSection` gets two optional fields: **`roundRestSec: Int?`** (rest between rounds for stations, rest between moves for Tabata) and **`stimulus: MetconStimulus?`** (raw string). Both decode as nil from older data.

| Format | Stimulus | Work pattern | Reps or time per move | Moves |
|---|---|---|---|---|
| `amrap` | grind | One continuous block | reps (§7.4) | 3–5 (5 only if ≥ 15 min) |
| `emom` | grind | Each minute, the next move in order | reps sized to ~35 s | per shape |
| `amrapWithRest` | repeat | R blocks of W min, rest X between blocks | reps (§7.4) | 3–4 (5 if W ≥ 4 min) |
| `stations` | repeat | R rounds; each move is a 60 s station, no rest between stations; 60 s rest between rounds | time (60 s, max reps) | per shape |
| `interval` | intervals | R circuits; each move gets W s work then X s rest, in order | time | per shape |
| `tabata` | intervals | One move at a time: R rounds of **40 s work / 20 s rest**, then 60 s rest, then the next move | time | per shape |
| `forTime` | race | A rep scheme for every move, as fast as possible, under a cap | rep scheme per move | 3–5 |

`ladder` and `everyNMin` are not used for metcons. Imported `ladder` pieces stay `forTime`, as today.

### 5.2 Duration math (seconds)

`n` = number of moves. No trailing rest is counted after the last work period (this matches `IntervalPlan.workRest`).

| Format | `estimateSeconds` |
|---|---|
| `amrap` | `durationMin × 60` |
| `emom` | `durationMin × 60` |
| `amrapWithRest` | `R × W + (R − 1) × X` |
| `stations` | `R × n × 60 + (R − 1) × roundRestSec` |
| `interval` | `R × n × (W + X) − X` |
| `tabata` | `n × (R × 60 − 20) + (n − 1) × roundRestSec` (roundRestSec = 60) |
| `forTime` | `cap × 60` |

`WorkoutDuration.estimate` (minutes) = `estimateSeconds / 60`, rounded half up.

**Hard rule:** `720 ≤ estimateSeconds ≤ 1440`. Band membership uses seconds: short 720–1019, middle 1020–1259, long 1260–1440.

### 5.3 Shape catalog

Shapes are a fixed list (`MetconCatalog.shapes`). The planner never invents rounds or times outside it. Seconds are shown so tests can check them.

**amrap (grind)**

| id | min | sec | band |
|---|---|---|---|
| amrap-12 | 12 | 720 | S |
| amrap-14 | 14 | 840 | S |
| amrap-15 | 15 | 900 | S |
| amrap-16 | 16 | 960 | S |
| amrap-18 | 18 | 1080 | M |
| amrap-20 | 20 | 1200 | M |

**emom (grind):** minutes = moves × cycles

| id | moves × cycles | sec | band |
|---|---|---|---|
| emom-3x4 | 3 × 4 | 720 | S |
| emom-4x3 | 4 × 3 | 720 | S |
| emom-3x5 | 3 × 5 | 900 | S |
| emom-5x3 | 5 × 3 | 900 | S |
| emom-4x4 | 4 × 4 | 960 | S |
| emom-3x6 | 3 × 6 | 1080 | M |
| emom-4x5 | 4 × 5 | 1200 | M |
| emom-5x4 | 5 × 4 | 1200 | M |

**amrapWithRest (repeat)**

| id | R × W, rest | sec | band |
|---|---|---|---|
| rest-3x4 | 3 × 4 min, 60 s | 840 | S |
| rest-4x3 | 4 × 3 min, 60 s | 900 | S |
| rest-3x5 | 3 × 5 min, 60 s | 1020 | M |
| rest-5x3 | 5 × 3 min, 60 s | 1140 | M |
| rest-4x4 | 4 × 4 min, 60 s | 1140 | M |
| rest-8x2 | 8 × 2 min, 30 s | 1170 | M |
| rest-3x6 | 3 × 6 min, 60 s | 1200 | M |
| rest-6x3 | 6 × 3 min, 60 s | 1380 | L |
| rest-4x5 | 4 × 5 min, 60 s | 1380 | L |
| rest-5x4 | 5 × 4 min, 60 s | 1440 | L |

**stations (repeat):** 60 s per station, 60 s between rounds

| id | rounds × stations | sec | band |
|---|---|---|---|
| stations-3x4 | 3 × 4 | 840 | S |
| stations-4x3 | 4 × 3 | 900 | S |
| stations-3x5 | 3 × 5 | 1020 | M |
| stations-5x3 | 5 × 3 | 1140 | M |
| stations-4x4 | 4 × 4 | 1140 | M |
| stations-6x3 | 6 × 3 | 1380 | L |
| stations-4x5 | 4 × 5 | 1380 | L |
| stations-5x4 | 5 × 4 | 1440 | L |

**interval (intervals):** work/rest is one of 30/30, 40/20, 45/15. Seconds below are for 30/30 (other pairs are 10–15 s longer and stay in the same band).

| id | moves × circuits | sec (30/30) | band |
|---|---|---|---|
| interval-3x5 | 3 × 5 | 870 | S |
| interval-5x3 | 5 × 3 | 870 | S |
| interval-4x4 | 4 × 4 | 930 | S |
| interval-3x6 | 3 × 6 | 1050 | M |
| interval-4x5 | 4 × 5 | 1170 | M |
| interval-5x4 | 5 × 4 | 1170 | M |
| interval-3x7 | 3 × 7 | 1230 | M |
| interval-4x6 | 4 × 6 | 1410 | L |
| interval-3x8 | 3 × 8 | 1410 | L |

**tabata (intervals):** always 40/20, 60 s between moves

| id | moves × rounds per move | sec | band |
|---|---|---|---|
| tabata-3x4 | 3 × 4 | 780 | S |
| tabata-3x5 | 3 × 5 | 960 | S |
| tabata-4x4 | 4 × 4 | 1060 | M |
| tabata-3x6 | 3 × 6 | 1140 | M |
| tabata-4x5 | 4 × 5 | 1300 | L |
| tabata-3x7 | 3 × 7 | 1320 | L |
| tabata-5x4 | 5 × 4 | 1340 | L |

**forTime (race):** rep schemes

| id | scheme | reps per move |
|---|---|---|
| ft-21-15-9 | 21-15-9 | 45 |
| ft-15-3 | 15-12-9-6-3 | 45 |
| ft-10-2 | 10-8-6-4-2 | 30 |
| ft-10-1 | 10-9-8-7-6-5-4-3-2-1 | 55 |
| ft-1-10 | 1-2-3-4-5-6-7-8-9-10 | 55 |
| ft-21-3 | 21-18-15-12-9-6-3 | 84 |

For-time sizing (v2.1; calibrated in §17.4):
- Each move gets a multiplier `m`: 3 if `secondsPerRep ≤ 0.6`, 2 if `≤ 1.0`, else 1. Its scheme is the base scheme × `m` (shown on the item's `repsScheme`, e.g. "20-16-12-8-4").
- `E = pace.forTime × Σ(totalReps × m × secondsPerRep) + 5 × n × rungs`, where `pace.forTime` comes from the pace model (§17.3, default 1.35).
- A scheme/move set is valid only if `720 ≤ E ≤ 1200`, the largest rung × `m` ≤ 2 × `repRange.upperBound` for every move, and no move has `secondsPerRep ≥ 5` or is timed.
- `cap = min(24, ceil(1.2 × E / 60))` minutes (so 15–24). The band comes from the cap's seconds, so for-time can be S, M or L.
- Scheme preference: `ft-10-1` and `ft-1-10` get weight 3; the others get 1. (These two make up 93% of the coach's for-time pieces.)

### 5.4 Timer and logging

| Format | Timer work phases | Rest phases | Log rows (`prescribedRounds`) |
|---|---|---|---|
| amrap | 1 (duration) | — | 1 |
| emom | minutes × 60 s | — | minutes |
| amrapWithRest | R × W | X between blocks | R |
| stations | R × n × 60 s, back to back | roundRestSec between rounds | R |
| interval | R × n × W | X after each work except the last | R |
| tabata | n × R × 40 s | 20 s within a move; roundRestSec (60) between moves; none at the end | n × R |
| forTime | 1 (cap) | — | rungs |

### Requirements: formats

**MC-6 Catalog validity.** Every shape in the catalog has `720 ≤ estimateSeconds ≤ 1440`, move count 3–5, and the band listed in §5.3.
- *Test:* iterate the catalog.

**MC-7 Tabata is 40/20.** Every planner-built `tabata` section has `workSec == 40`, `restSec == 20`, `roundRestSec == 60`, 3–5 moves and 12–24 min. No 20/10 Tabata is ever built.
- *Test:* year property test plus a catalog test.

**MC-8 Timer equals estimate.** For every catalog shape and every for-time cap, `IntervalPlan.forSection(s).totalDuration == WorkoutDuration.estimateSeconds(s)`, and the number of work phases matches §5.4.
- *Test:* iterate the catalog, build a section with n dummy items, compare.

**MC-9 Interval rounds are circuits.** `estimateSeconds` for an `interval` section with R = 6, 40/20 and 3 items is 1060 s (18 min, not 6).
- *Test:* direct.

**MC-10 Importer keeps stations.** `HistoryImporter` maps `interval` with `per_station: true` to `.stations` (`workSec` = station seconds, `restSec` = 0, `roundRestSec` = rest between rounds). An imported 4 rounds × 4 stations × 60 s, 60 s rest piece estimates 1140 s (19 min).
- *Test:* importer fixture.

**MC-11 Legacy stored sections.** Imported sections already stored with format `interval`, `workSec == 60`, `restSec == 60` and `source == "import"` are read as `stations` with `roundRestSec = 60` (a one-time migration on load). No other stored section changes.
- *Test:* migration unit test.

**MC-12 Codable compatibility.** A `WorkoutSection` JSON without `roundRestSec`/`stimulus` decodes; a section with them round-trips. The app's SwiftData section record stores both new fields (optional columns).
- *Test:* decode an old fixture; app test for the record mapping.

---

## 6. Stimulus, length band and weekly plan

### 6.1 Stimuli

| Stimulus | Feel | Formats | Bands | Default weight |
|---|---|---|---|---|
| grind | steady, continuous, sustainable pace | amrap (17), emom (3) | S, M | 20 |
| repeat | hard efforts with rest, repeatable | amrapWithRest (30), stations (15) | S, M, L | 45 |
| race | finish the work fast | forTime | S, M, L (v2.1) | 17 |
| intervals | work/rest on the clock | interval (10), tabata (8) | S, M, L | 18 |

Format weights (in brackets) sum to 100 and approximate the coach's mix with Tabata added.

### 6.2 Week plan

A new pure function `MetconWeekPlan.make(weekStart:settings:) -> [LocalDate: DayMetconPlan]` decides each scheduled day's **band**, **format** and **arms preference**. It depends only on settings and dates (not history), so it is stable under shuffles and re-plans.

Steps:
1. List the week's scheduled days and each day's rotation lift (`settings.rotation.lift(for:)`).
2. Rank days by strength load: Deadlift 3, Back Squat 3, Front Squat 2, Push Press 2, Hang Power Clean 1, Push Jerk 1. Ties: earlier day ranks heavier.
3. Take the phase's band pattern (§8) and assign shortest band to heaviest day, and so on. For N scheduled days: N = 1 → [middle]; N = 2 → [first, last of pattern]; N = 3 → pattern; N ≥ 4 → pattern with extra middles inserted before the last (e.g. S, M, M, L).
4. For each day, heaviest first, pick a format by weight from formats that have at least one shape in the day's band, excluding formats already picked this week. If none remain, allow repeats. A format that was planned on the same weekday last week gets half weight.
5. Arms preference: the overhead-slot day (or, if none, the last scheduled day) is the **pull day**. On that day the arms slot must be filled with a `pull` move if one is available.
6. RNG: `SeededRandom(date: weekStart, salt: 0x3E7B)`.

With the default Mon/Wed/Fri schedule, week A gives Back Squat short, Deadlift middle, Push Press long. Week B gives Front Squat short, Hang Power Clean middle, Push Jerk long.

### 6.3 Day adjustments (applied in this order)

1. **Phase** (§8): already in the pattern.
2. **Coach note** (§10): "just show up" forces short, clipped to 12–14 min. "Comeback" caps at middle.
3. **Session budget** (§9): `maxSec = clamp((target − nonMetconMin) × 60, 720, 1440)`. If the band's lower bound is above `maxSec`, drop to the next shorter band. Clip the band's upper bound to `maxSec`.
4. If the planned format has no shape in the adjusted band, re-pick a format as in step 4 of §6.2 for this day only.

### Requirements: stimulus and week

**MC-13 Week plan is deterministic.** Same week start and settings give the same plan. Changing history or salts does not change it.
- *Test:* call twice; call with different salts/history.

**MC-14 Length spread.** In every 3-day week in phases volume, strength and pre-program, with no coach-note override, no benchmark and no budget change of band (clipping the upper bound within the same band is fine), the three metcons are one short, one middle and one long.
- *Test:* year property test over weeks matching the condition.

**MC-15 Heavier day, shorter piece.** In every week, the day with the highest strength-load rank never has a longer band than any other day that week (before benchmark substitution).
- *Test:* year property test.

**MC-16 Format variety.** In every week with ≥ 3 scheduled metcons (no shuffles), no two non-benchmark metcons share a format. Over every 4-week window, at least 3 of the 4 stimuli appear.
- *Test:* year property test.

**MC-17 Format mix.** Over a year of the default setup (no limits, full home gym, no shuffles), each stimulus's share of non-benchmark metcons is within ±10 percentage points of its default weight.
- *Test:* year property test.

**MC-18 Stimulus is recorded.** Every planner-built metcon has `stimulus` set, and its format belongs to that stimulus (§6.1).
- *Test:* year property test.

---

## 7. Composition algorithm

### 7.1 Ordered steps

`buildMetabolic` runs after strength and warm-up (as today). Given the day's lift, accessory, phase, coach note, limits, equipment, history and salts:

1. **Benchmark check** (§11). If a compatible benchmark is due and the metabolic salt is 0, return it. Stop.
2. **Day plan.** Read the week plan for the date, apply the day adjustments (§6.3). If the metabolic salt > 0 (shuffle), see §10.3.
3. **Shape.** Pick a shape of the day's format whose seconds fall in the adjusted band. For `amrap`, `amrapWithRest` and `forTime` (no fixed move count), pick the move count: 3 (weight 45), 4 (50), 5 (5), limited by the format's allowed counts.
4. **Pool.** Start from moves with role `metabolic`. Resolve each through `library.resolve` (substitution for equipment and limits). Then remove:
   - the day's lift and any move whose `conflictsWith` contains the day slot;
   - the strength accessory's movement;
   - moves with role `mainLift` or `benchmarkOnly`;
   - `metconTimedOnly` moves unless the format is `stations`, `interval` or `tabata`;
   - for `forTime`, moves with `secondsPerRep ≥ 5`.
5. **Fill required slots.** Fill `legs`, `arms`, `heart` in order of fewest candidates first (ties: legs, arms, heart). For each uncovered slot, pick a move that fills it, using the weights in §7.2 and the constraints in §7.3. A move that also fills another uncovered required slot counts for both.
6. **Fill extras** until the target move count is reached. For each extra, pick a slot by weight: core 35, legs (a different `legKind` from those present) 25, arms (pull if only push is present, else push) 25, agility 15. Then pick a move for it.
7. **Order** the moves (§7.5) and assign letters A–E.
8. **Reps or time** (§7.4), then weights through the existing `makeItem`/snapper, with the weight shift (§8, §10).
9. **For time only:** pick the scheme and multipliers that give a valid E (§5.3). Try schemes in random order; if none fits, use the fallbacks.
10. **Name** (§11.6), instructions (§7.6), reasons (§12).
11. **Validate** against MC-19 to MC-24. On failure, use the fallbacks (§7.7). The planner never returns a metcon that fails a hard rule.
12. **(v2.1) Best of N.** Steps 3–11 run for N = 12 candidates and the one with the lowest quality penalty is kept (§20).

### 7.2 Pick weights (soft preferences)

`weight = 1.0`, then multiplied by:

| Factor | Multiplier |
|---|---|
| Fills an additional uncovered required slot | × 1.3 |
| Muscle freshness (existing 14-day usage) | × (0.3 + freshness) |
| Same movement used in a metcon in the last 7 days | × 0.4 |
| Same movement in today's warm-up | × 0.5 |
| Bodyweight move of the day slot's pattern (e.g. air squat on squat day) | × 0.3 |
| High-impact move (no limit set) | × 0.7 |
| Arms slot on a non-pull day: push | × 3 vs pull × 1 |

### 7.3 Constraints within one metcon

| Rule | Limit |
|---|---|
| Distinct movement ids | all different |
| Same `legKind` | at most 1 move per kind, unless the fallback F3 applies |
| Same `armKind` | at most 2 moves, and never 2 overhead |
| High impact | at most 1 |
| Grip-heavy | at most 2 |
| Shoulder-heavy | at most 2; at most 1 on overhead days |
| Bodyweight move of the day slot's pattern | at most 1 |
| Core moves | at most 1 (at most 2 when there are 5 moves) |
| High impact across the week | if 2 earlier metcons this week (in history, any status) already had a high-impact move, no high-impact move today |

### 7.4 Reps sizing

Reps come from `secondsPerRep` (§17.2) so that a round fits a target time and every set can be done unbroken. **The target round times are in §17.3 (v2.1).**

| Format | Formula |
|---|---|
| amrap, amrapWithRest | `share = (targetFreshRoundSec − 5n) / n`; `reps = share / secondsPerRep` |
| emom | `reps = 35 / secondsPerRep` (≈ 35 s of work in each minute) |
| stations, interval, tabata | time-based: `timeSec = work`; `reps = nil` (max reps) |
| forTime | scheme × multiplier (§5.3) on the item's `repsScheme` |

Then: round half up to a whole number; clamp to `repRange`; if `countsEachSide`, round up to even; above 20, round to the nearest 5. Then apply the density multiplier from the feedback loop (§22) and re-clamp.

Worked example (MC-51): `rest-5x3` with push-ups, KB swings and up/downs gives 4 / 6 / 4.

The old intensity factor (`.low` = half reps) is removed.

### 7.5 Ordering

1. Technical moves first (if several, loaded before bodyweight).
2. Then arrange the rest so that no two adjacent moves are both grip-heavy or both shoulder-heavy. For round-based formats (all except forTime), adjacency wraps from the last move to the first.
3. Prefer alternating upper and lower body where possible.
4. Use the first order (in a deterministic permutation search, ≤ 120 orders) that satisfies 1–2; if none does, keep rule 1 only and add no reason.

### 7.6 Instructions copy

| Format | Instructions |
|---|---|
| amrap | "As many rounds as you can in {D} min" |
| emom | "Every minute for {D} min · one move per minute, in order" |
| amrapWithRest | "{R} rounds · as many as you can in {W} min · rest {rest}" |
| stations | "{R} rounds · {S} s at each station, no rest between stations · rest {rest} after each round" |
| interval | "{R} rounds · {W} s work / {X} s rest on each move, in order" |
| tabata | "Tabata 40/20 · {R} rounds of 40 s work / 20 s rest on each move · rest 1 min before the next move" |
| forTime | "{scheme} for time · cap {C} min" |

Deload weeks append "\nEasy, steady pace." Rest is shown as "1 min" or "30 s".

### 7.7 Fallbacks (when the pool shrinks)

Applied in order, one at a time, re-running steps 5–9 after each, until the metcon passes validation:

| Step | Action |
|---|---|
| F1 | Substitute (already done in step 4 through `resolve`). |
| F2 | Drop soft preferences: freshness, recent-use and warm-up penalties, extra-slot weights, push preference, adjacency ordering. |
| F3 | Allow a second move of the same `legKind` or `armKind` (never the same id). |
| F4 | Pick another shape of the same format with fewer moves (never below 3). |
| F5 | Change format: first another format of the same stimulus, then any format with a shape in the band. Time-based formats come first when the pool has timed core moves but few rep moves. |
| F6 | Relax coverage: if a required slot has **no** candidate in the whole pool, fill it with a move from another slot. Add reason `metabolic.coverage_relaxed`. |
| F7 | If the pool has fewer than 3 distinct moves after all of the above, throw `PlannerError.metconPoolTooSmall(available:)`. The app shows: "Your equipment and limits leave fewer than 3 metcon moves. Add equipment or relax a limit in Settings." |

Never allowed, at any step: fewer than 3 moves, more than 5, under 12 or over 24 min, the day's lift, a conflict move, a move not allowed by equipment or limits.

### Requirements: composition

**MC-19 Move count.** Every metcon (remixed or benchmark) has 3–5 items.

**MC-20 Length.** Every metcon has `720 ≤ estimateSeconds ≤ 1440`. For-time also has `E ≥ 720`.

**MC-21 No day's-lift overlap.** No item's movement id equals the day's lift `movementID`, and no item's movement (looked up by id or name) has `conflictsWith` containing the day slot. Benchmarks included.

**MC-22 Slot coverage.** Every remixed metcon covers heart, legs and arms (each by at least one item's `fills`), unless reason `metabolic.coverage_relaxed` is present. For the configurations in §14.1 that reason never appears.

**MC-23 Constraints.** Every remixed metcon satisfies §7.3. Every item's reps are within its `repRange` (even if `countsEachSide`). For for-time, the largest rung ≤ 2 × `repRange.upperBound`.

**MC-24 Allowed moves.** Every remixed item's movement is allowed by the equipment and limits. Timed-only moves appear only in stations, interval or tabata.

**MC-25 Reps calibration.** Superseded by MC-51 (§17).
- *Test:* golden test with a fixed shape and move list.

**MC-26 Ordering.** In every remixed metcon, technical moves come first, and (when a valid order exists) no two adjacent moves (wrapping for round formats) are both grip-heavy or both shoulder-heavy.

**MC-27 Pull day.** On the week plan's pull day, if a pull move is in the pool, the metcon contains a move with `armKind` pull. In every full-home-gym week, at least one metcon has a pull move.

**MC-28 Fallback floor.** For every configuration in §14.1, planning never throws. `metconPoolTooSmall` is thrown only for a pool of < 3 moves (unit test with a custom 2-move library).

**MC-29 Determinism.** Same request (date, settings, history, benchmarks, salts) gives an identical metcon.

---

## 8. Strength-phase interaction

| Phase | Weeks | Band pattern (3 days) | Stimuli allowed | Weight shift | Notes |
|---|---|---|---|---|---|
| pre-program | before block 1 | S, M, L | all | 0 | |
| volume | 1–4 | S, M, L | all | 0 | room for long pieces |
| strength | 5–8 | S, M, L | all | 0 | heaviest day is short |
| peak | 9–11 | S, M, M | all; no `race` on the heaviest day | 0 | never long, so lifts stay fresh |
| deload (incl. swapped weeks) | 12 | M, L, L | grind, repeat, intervals (no race) | −1 | "easy, steady pace" |
| test | 13–14 | S, S, S | grind, intervals | 0 | catch-up benchmarks keep their own length |

**MC-30 Phase bands.** Every non-benchmark metcon's band follows the table after the §6.3 adjustments: peak weeks never long, test weeks never above 16:59, deload weeks never short unless a coach note or the budget forces it.
- *Test:* year property test grouped by phase.

**MC-31 Phase stimuli.** No `forTime` in deload weeks or on the heaviest peak day. Test weeks use only grind or intervals (for non-benchmark days).

**MC-32 Deload weights.** In deload weeks, every loaded metcon item is one snap step lighter than the same move would be in a volume week (same history), and instructions contain "Easy, steady pace."

---

## 9. Duration estimate and length fitting

Today the non-metcon sections estimate about 27 min (warm-up 3 rounds = 9, strength every 2 min × 6 sets = 12, cool-down 6). With the 50-min target, that leaves 23 min for the metcon.

Rules:
- The metcon is sized **before** `fitLength` runs, using the budget in §6.3 step 3. So `fitLength` rarely has anything to do.
- `fitLength` order when the total still exceeds the target:
  1. Warm-up 3 → 2 rounds (saves 3 min). Reason `length.warmup_trimmed`.
  2. Metcon: step down to a shorter shape of the same format in the same band (for amrap/emom, −2 min; rounds −1), never below the band minimum or 720 s.
  3. Stop. The workout may run over the target; add reason `length.over_target` ("About {N} min today, a little over your {T}-min target, so the metcon still gets its 12 minutes.").
- Strength and cool-down are never trimmed. Benchmarks are never trimmed (only step 1 applies).
- The 50-min target stays a soft target. Sessions run about 39–50 min, benchmark days up to about 51.

**MC-33 Never trimmed below the floor.** For targets 20, 30, 40, 50, 60 and every day of the year property test, the metcon has ≥ 3 items and `estimateSeconds ≥ 720`.

**MC-34 Trim order.** With a target that forces trimming, the warm-up is trimmed to 2 rounds before the metcon is shortened. The warm-up never goes below 2 rounds.

**MC-35 Budget sizing.** For every remixed metcon, `estimateSeconds ≤ max(720, (target − nonMetconMinutes) × 60)`, where `nonMetconMinutes` is the warm-up + strength + cool-down estimate before fitting. With target 50 and a 6-set strength section this means at most 23 min; with target 60, long days can reach 24.

**MC-36 Workout estimate.** `PlannedWorkout.durationMin` equals the sum of section estimates using the new seconds-based metcon estimate.

---

## 10. Coach notes, energy and shuffle

### 10.1 Coach notes

| Note / signal | Band | Weights | Warm-up | Benchmark due today |
|---|---|---|---|---|
| Just show up (`makesPlanShorter`) | short, clipped to 12–14 min (720–840 s) | −1 | 2 rounds | deferred to the next compatible day |
| Comeback (`makesPlanLighter`) | capped at middle | −1 | unchanged | runs (comeback is not a low-energy signal) |
| Push | unchanged | unchanged | unchanged | runs |
| Last session's energy was "sleepy" | unchanged | −1 | unchanged | runs |
| Last two metcons rated ≥ 4.5 / ≤ 2 average | unchanged | −1 / +1 | unchanged | runs (benchmarks keep their own weights) |

**MC-37 Just show up.** On a "just show up" day: metcon 720–840 s, 3–4 moves, warm-up 2 rounds, weights −1, no benchmark. Reason `metabolic.length` mentions "showing up is the win".

**MC-38 Lighter never shortens below 12.** No coach note or energy signal produces a metcon under 720 s or under 3 moves.

### 10.2 Benchmarks are never resized
Benchmark sections ignore the weight shift, reps sizing, band and fitting. Only limit substitutions change them (marked "modified").

### 10.3 Shuffle

- Shuffling the metcon (metabolic salt > 0) keeps the day's **band** (after adjustments). It picks a new format by weight from formats with a shape in the band, preferring one different from the current format and from other days' formats this week. Then steps 3–11 run with the salted RNG.
- Shuffling on a benchmark day defers the benchmark to the next compatible day (as today) and builds a remix.
- Shuffle everything follows the same rule for the metcon.

**MC-39 Shuffle obeys all rules.** For 20 consecutive salts on 30 sampled days, every shuffled metcon passes MC-19 to MC-24 and keeps the unshuffled metcon's band.

**MC-40 Shuffle changes something.** For salts 0 and 1 on the same day, the metcon differs in format or in at least one movement.

---

## 11. Benchmarks and test weeks

### 11.1 Validation

`BenchmarkValidator` returns issues in two groups.

**Intrinsic issues** (the benchmark itself breaks the rules):
- move count not 3–5;
- `estimateSeconds` (new formulas) outside 720–1440; for-time uses its cap;
- a movement that can't be resolved by id, name or alias;
- no `legs` or no `arms` coverage (heart is not required, because benchmarks are the coach's design);
- blocked on every lift slot in the rotation (its moves conflict with all of the user's lift slots);
- format `other`.

**Day issues** (the benchmark is fine, but not today):
- a move is the day's lift or conflicts with the day slot (after limit substitution);
- today is a "just show up" day.

### 11.2 Proposing

**MC-41 Proposer skips invalid candidates.** `BenchmarkProposer.propose` only returns benchmarks with no intrinsic issues. It keeps its existing ranking and the max-2-per-format rule, moving down the ranked list to fill 6.
- *Test:* a fixture history whose top-ranked candidate has 2 moves and the next has 3 valid moves; the 2-move one is not proposed.

### 11.3 Existing (stored) benchmarks that break the rules

- A stored benchmark with intrinsic issues is **retired**: `active = false`, new optional field `retiredReason: String` (for example "Only 2 moves; metcons need 3–5."). Its content is never changed. Its past scores stay visible in Progress → Benchmarks with a "retired" label.
- The retired benchmark's quarter slot is filled by the next valid proposal from history (see open question Q5).

**MC-42 Retire, never alter.** Loading a stored 2-move benchmark marks it retired with a reason, and its `template` is byte-for-byte unchanged. It is never scheduled again.

### 11.4 Scheduling

- A benchmark is due from its slot's week, as today, but runs only on a day with **no day issues**. The scheduler checks each scheduled day in order; the first compatible day runs it.
- At most one benchmark per week in weeks 1–12 (unchanged).
- **Test weeks (13–14):** benchmarks not yet done this block are caught up, at most one per day, on compatible days. (This fixes the current code, which skips benchmarks in test weeks.)
- If a benchmark finds no compatible day before the block ends, it is skipped for that quarter. Reason on the last eligible day: "{name} couldn't fit this quarter."
- Reason when moved: `benchmark.rescheduled`: "{name} was due {weekday} but has {move}, and that's {lift} day. It moved here so it doesn't clash."

**MC-43 Back Squat clash regression.** With the default settings and a benchmark of Back Squats, Up/Downs and Plate Ground to Overhead (5 × 3-min AMRAP, 1 min rest, slot 0): Mon Oct 12, 2026 (Back Squat) gets a remix; Wed Oct 14 (Deadlift) gets the benchmark, with reason `benchmark.rescheduled`.

**MC-44 Front Squat clash.** A benchmark containing Front Squats is never placed on a Back Squat or Front Squat day.

**MC-45 Test-week catch-up.** A benchmark not done by week 12 runs in week 13 or 14 on a compatible day.

**MC-46 Exact repeat.** A scheduled benchmark's moves, reps, schemes, weights, rounds, work, rest, `roundRestSec` and name equal its template, except for limit substitutions, which set `isModified`.

### 11.5 Test weeks (non-benchmark days)

Test days are heavy (work up to a heavy 3). Their metcon is **short (12–16 min)**, grind or intervals, normal weights. `FormatLibrary.short` is removed.

**MC-47 Test-week length.** Every non-benchmark test-week metcon is 720–1019 s with 3–5 moves (replaces the current "≤ 8 min" test).

### 11.6 Naming

`structure-rounds-minutes-word` stays. Values per format:

| Format | structure | rounds | minutes | Example |
|---|---|---|---|---|
| amrap | amrap | 1 | duration | amrap-1-15-fig |
| amrapWithRest | amrap | R | W (block minutes) | amrap-5-3-fungi |
| stations | stations | R | rounded total | stations-4-19-otter |
| interval | interval | R | rounded total | interval-6-18-kiwi |
| tabata | tabata | rounds per move | rounded total | tabata-6-19-mango |
| emom | emom | minutes | minutes | emom-15-15-fern |
| forTime | fortime | 1 | cap | fortime-1-16-coral |

**MC-48 Names.** Every planner-built metcon name passes `WorkoutNamer.isValid`, starts with the structure above, and its numbers match the section.

---

## 12. "Why this?" copy

Reasons use `PlanReason(section: .metabolic, rule:, text:)`. Rule ids are stable so tests can find them. `metabolic.remix` is removed.

| Rule id | When | Template |
|---|---|---|
| `metabolic.stimulus` | always (remix) | "{Stimulus title}: {stimulus line}." |
| `metabolic.length` | always (remix) | "{N} min today: {length reason}." |
| `metabolic.slots` | always (remix) | "Covers heart rate ({move}), legs ({move}) and arms ({move}){extras}." |
| `metabolic.avoids_lift` | always (remix) | "No {pattern} work in here: today is {lift} day." |
| `metabolic.reps` | rep-based formats | "Reps are sized so a round takes about {T} s and every set can go unbroken." |
| `metabolic.lighter` / `metabolic.heavier` | weight shift ≠ 0 | existing text; add "deload week" as a cause |
| `limits.substitute` | substitution | existing text |
| `equipment.snap` | snap notes | existing text |
| `metabolic.coverage_relaxed` | F6 | "Your equipment and limits leave no {slot} move, so {move} fills in." |
| `length.warmup_trimmed` | fit step 1 | "Warm-up cut to 2 rounds so the session fits about {T} min." |
| `length.over_target` | fit step 3 | see §9 |
| `benchmark.rescheduled` | §11.4 | see §11.4 |
| `benchmark.retired` | Benchmarks view / proposer | "{name} was retired: {retiredReason}. Its old scores are kept." |
| `metabolic.benchmark`, `benchmark.modified`, `benchmark.deferred` | unchanged | existing text |

Stimulus lines:

| Stimulus | Title | Line |
|---|---|---|
| grind | Steady grind | "pick a pace you can hold the whole time and keep moving" |
| repeat | Repeat efforts | "push each round hard; the rest lets you do it again" |
| race | Race | "get the work done as fast as you can, under the cap" |
| intervals | Intervals | "the clock runs the work and rest; go hard in every work period" |

Length reasons (first match wins):

| Condition | Text |
|---|---|
| Just show up | "showing up is the win, so it's the shortest version" |
| Test week | "test week: a short piece after your heavy lift" |
| Peak week, short day | "{lift} is your heaviest lift this week, and peak weeks keep metcons short" |
| Heaviest day of the week | "{lift} is your heaviest lift this week, so the metcon is the short one" |
| Deload week | "deload week: a longer, easier piece" |
| Long band | "the long piece of your week, with time to settle into it" |
| Middle band | "the middle piece of your week" |
| Budget clipped | append " (sized to fit your {T}-min session)" |

Extras in `metabolic.slots`: ", plus core ({move})" / ", plus agility ({move})". If a full-body move covers two slots: "{move} works legs and arms together" replaces the two entries.

**MC-49 Reasons present.** Every remixed metcon has exactly one each of `metabolic.stimulus`, `metabolic.length`, `metabolic.slots` and `metabolic.avoids_lift`. Every rep-based remix has `metabolic.reps`. No reason contains "remix" or the old "stays off the muscles" text.

**MC-50 Reasons are true.** The minutes in `metabolic.length` equal `WorkoutDuration.estimate`; every move named in `metabolic.slots` is an item in the section and fills the slot it is listed under.

---

## 13. Open questions for the owner

Each has a recommended default. The developer proceeds with the default unless the owner says otherwise.

| # | Question | Recommended default | Why it matters |
|---|---|---|---|
| Q1 | The coach puts a light barbell lift (not the day's lift) in about 60% of metcons. Should remixed metcons use barbell lifts too? | **No in v2.** Remixes use DB, KB, plate, box, bench, bar and bodyweight moves. Barbell lifts appear only inside benchmarks. | Barbell metcon moves need light-weight rules, plate changes and more conflict checks. Worth a follow-up. |
| Q2 | Tabata (the owner has decided it stays 40/20; only the structure is open): one move at a time (several rounds of A, rest 1 min, then B), or alternate moves every round? | **One move at a time.** Alternating 40/20 already exists as the interval format. | Changes the timer and logging (§5.4). |
| Q3 | Must every metcon have a dedicated heart-rate move, or can a fast full-body move (swings, snatches, thrusters, slams) count as the heart move? | **A fast full-body move can count** (tagged `heart` in §4.4). | The coach had a separate cardio move in only 63% of metcons. |
| Q4 | The 50-min session target leaves about 23 min for the metcon, so "up to 24" is effectively 23 on normal days. Keep 50, or raise the default to 55? | **Keep 50** as a soft target. The long piece is 21–23 min; benchmark days may run about 1 min over. | A 55 default would allow full 24-min pieces but makes every session longer. |
| Q5 | When a stored benchmark is retired, should the app automatically add a replacement from history into its quarter slot? | **Yes, automatically**, labelled "new" in the Benchmarks view. The owner can turn it off there. | Keeps about 6 benchmarks per quarter without a manual step. |
| Q6 | Which day gets the short metcon? | **The heaviest lift's day** (Deadlift/Back Squat > Front Squat/Push Press > Olympic lifts). With Mon/Wed/Fri, Monday is short and Friday is long in both weeks. | The alternative is rotating short/long days each week for variety. |
| Q7 | (v2.1) The coach usually kept all three metcons in a week about the same length (median spread 0.25 min), and in about a third of weeks used one format all week. Keep the short/middle/long spread and the "no repeated format" rule? | **Keep both** (they were the owner's request). Add an optional "theme week" later if missed. | Changes MC-14 and MC-16. |
| Q8 | (v2.1) Should the planner learn the athlete's pace and adjust reps from scores and ratings automatically (bounded, §22)? | **Yes**, within the bounds in §22, explained in "Why this?". | Without it, reps stay on the fixed calibration in §17. |

Strength recommendations from the v2.1 analysis are **not** open questions for this build. They are listed separately in §21 for the owner to decide later.

---

## 14. Test plan

### 14.1 Year property test (core)

Harness `MetconYearHarness`:
- Plans every scheduled day from **2026-10-12 to 2027-10-11**.
- Starts with the shared test fixture history. After each day, appends the plan to history as `done`, with feedback (energy okay, metabolic difficulty 3) and one round log, so benchmarks progress and become "done".
- Benchmarks: a fixture set of 6 that includes (a) a valid 3-move benchmark with Back Squats, (b) a valid one with Front Squats, (c) a 2-move benchmark, (d) a 6-min benchmark, (e) a valid stations benchmark, (f) a valid for-time benchmark.

Configurations (referenced elsewhere as "the configurations in §14.1"):

| Dimension | Values |
|---|---|
| Limits | all 8 combinations of avoid jumping / easy on knee / easy on wrist |
| Equipment | full home gym · bodyweight only · bodyweight + dumbbells · bodyweight + kettlebells · home gym without bench, box and low bar · kg preset gym |
| Schedule | Mon/Wed/Fri (classic) · Tue/Thu · Mon/Tue/Thu/Fri · Mon–Fri |
| Target minutes | 50 (all configurations); 20, 30, 40, 60 (full home gym, no limits, classic only) |

Assertions for every metcon in every configuration: MC-19, MC-20, MC-21, MC-22 (no `coverage_relaxed` in any configuration; `prone-swimmer`, `toe-tap` and `air-squat`/`glute-bridge` keep bodyweight-only + all limits covered), MC-23, MC-24, MC-26, MC-29, MC-33, MC-48, MC-49, MC-50, and timer = estimate (MC-8).

Weekly assertions (full home gym, classic schedule, no limits): MC-14, MC-15, MC-16, MC-27, at most 2 metcons with a high-impact move per week.

Year assertions (full home gym, classic, no limits): MC-17; move-count shares: 3 moves 35–55%, 4 moves 40–60%, 5 moves 2–12%.

Phase assertions: MC-30, MC-31, MC-32, MC-47.

Runtime budget: the whole property suite runs in under 60 s in release mode on a laptop. If needed, run the full matrix in `LocalRunner` and a reduced matrix (classic, full gym, 8 limit combos) in `swift test`.

### 14.2 Regression tests

| ID | Test | Expectation |
|---|---|---|
| R1 | Mon Oct 12, 2026, default settings, no history, no benchmarks, metabolic salts 0–50 | Never fewer than 3 moves or under 720 s. Any Tabata is 40/20. |
| R2 | Back Squat benchmark clash (MC-43) | Remix on Oct 12; benchmark on Oct 14 with `benchmark.rescheduled`. |
| R3 | Front Squat benchmark (MC-44) | Never on a squat day across block 1. |
| R4 | 2-move benchmark (MC-41, MC-42) | Not proposed; stored copy retired, unchanged, never scheduled. |
| R5 | Imported 6-round 40/20 circuit with 3 moves (MC-9) | Estimate 18 min; timer 1060 s with 18 work phases. |
| R6 | Imported 4 × 4 stations (MC-10, MC-11) | Format `stations`; estimate 19 min; timer 1140 s. |
| R7 | "Just show up" day (MC-37) | 720–840 s, 3–4 moves, warm-up 2 rounds, no benchmark. |
| R8 | Test week, Jan 4, 2027 (MC-47) | 720–1019 s; replaces `testTestWeeksHaveOneHeavyTriplePlusAccessory`'s "≤ 8 min" assertion. |
| R9 | Target 20 min (MC-33) | Metcon ≥ 720 s and ≥ 3 moves; reason `length.over_target`. |
| R10 | Bodyweight only + all three limits, classic schedule, one year | Never throws; every metcon has 3–5 moves and covers legs and arms. |
| R11 | Reps calibration (MC-51) | 4 / 6 / 4. |
| R12 | Shuffle (MC-39, MC-40) | as stated. |

### 14.3 Existing tests to update

| Test | Change |
|---|---|
| `PlannerTests.testTestWeeksHaveOneHeavyTriplePlusAccessory` | "≤ 8 min" becomes 720–1019 s |
| `TimerRoundsTests.testPlannerSectionsAgreeWithTimer` | interval/stations/tabata phase counts per §5.4; seen formats include `.stations` |
| `TimerRoundsTests.testTabataInstructionsMatch` | uses the new catalog and "40 s work / 20 s rest" |
| `TimerRoundsTests` Tabata fixture (8 × 20/10) | 40/20 shapes |
| `BenchmarkProgressTests` Tabata 20/10 timer | 40/20 timing |
| `EquipmentTests` namer with `tabata, 8, 8` | still valid (namer is format-agnostic); keep |

### 14.4 Dev tool

`wcplan` gets a `--simulate-done` flag: each printed day is appended to history as done, so benchmarks progress across a multi-day run (today the CLI shows the same benchmark every day). It prints the stimulus, band and `estimateSeconds` for each metcon.

---

## 15. Out of scope

- Strength programming, lift rotation, training maxes, warm-up and cool-down content: unchanged.
- Barbell lifts in remixed metcons (Q1).
- Heart-rate data, Apple Watch, AI planner.
- Owner-editable benchmarks.

**Observation for later** (expanded into optional recommendations in §21): with the two-week A/B rotation, each main lift comes up only once every two weeks (twice per 4-week phase). That is a low frequency for building strength. It is outside this spec, but it affects how heavy each day feels and so how the metcon length is assigned (§6.2).

---

## 16. Implementation notes (non-normative)

- Suggested new files: `Library/MetconCatalog.swift` (shapes, stimuli, bands), `Engine/MetconBuilder.swift` (steps 3–11), `Engine/MetconWeekPlan.swift`, `Engine/BenchmarkValidator.swift`.
- `MetabolicTemplate` and `FormatLibrary.metabolic` / `.short` are replaced by the catalog. `FormatLibrary.warmupRounds`, `coreScheme`, `coreTimedSets` stay.
- The old muscle-overlap filter (`overlap >= 2 && implement != .bodyweight`) is replaced by `conflictsWith`. Muscle freshness stays as a soft weight.
- Keep `source` on planned workouts as `"rules-v2"` so v1 and v2 plans can be told apart.
- Planned (not done) workouts dated today or later are re-planned on first launch after the update, keeping their salts. Done workouts are never changed.

---

# Part 2 · v2.1: calibrated to the athlete

v2.1 comes from a deeper analysis of the imported history: 514 timed observations from 212 scored metcons, 250 logged strength sessions and the metcon load prescriptions. Only aggregates appear here. Per-date details are in a private, gitignored analysis file.

## 17. Athlete pace

### 17.1 Findings

| Finding | Value |
|---|---|
| Data | 413 AMRAP windows (2–7 min), 58 continuous AMRAPs (15–25 min), 43 for-time pieces |
| Model | time = (Σ reps × secondsPerRep + 5 s per move switch) × format pace factor; movement adjustments shrunk toward generic priors |
| Fit | median error ≈ 10% in sample; 9–11% on a 2026 hold-out for AMRAP windows |
| Pace in short windows (≤ 3 min) | ≈ generic prior × 1.05 ("fresh pace") |
| Pace in 4–6 min windows | fresh × 1.1 |
| Pace in continuous AMRAPs | fresh × 1.26 (15 min) to 1.5 (25 min); 1.22 in 2026 |
| Pace in for-time | fresh × 1.5 overall; 1.25 in 2026 (small sample) |
| For-time finish times | median 18 min (p10 13.6, p90 23.4) |
| Movement-specific pace | only four moves differ robustly from the generic prior: push-ups, up/downs and lunges are faster (× 0.8), burpees slower (× 1.1). The others are within the noise. |
| Trend | metcon pace has been stable (±5%) over 2.4 years, slightly faster recently |

Conclusion: the biggest effect is **how long the piece runs**, not which movement. The long-piece factors drift, so they are learned (§22).

### 17.2 Calibrated secondsPerRep (supersedes the s/rep column in §4.4 and §4.5)

Value = generic prior × 1.05, × the movement adjustment where it is robust. Confidence: **high** = ≥ 50 observations, **medium** = 10–49, **low** = < 10, **generic** = not in the data.

| id | s/rep | conf. | id | s/rep | conf. |
|---|---|---|---|---|---|
| push-up | 2.5 | high | up-down | 2.5 | high |
| kb-swing | 1.8 | high | lunge | 1.7 | high |
| plate-ground-to-overhead | 2.1 | high | burpee | 4.6 | high |
| db-push-press | 1.7 | high | goblet-squat | 2.5 | high |
| db-snatch | 1.6 | medium | bench-step-up | 1.9 | medium |
| box-step-up | 1.9 | medium | jumping-jack | 1.1 | medium |
| air-squat | 1.6 | medium | sit-up | 1.6 | medium |
| box-jump | 2.8 | medium | db-ground-to-overhead | 2.3 | medium |
| db-front-squat | 2.5 | medium | db-hang-squat-clean | 2.5 | medium |
| australian-pull-up | 3.2 | medium | overhead-plate-lunge | 2.3 | medium |
| db-hang-clean-push-press | 2.7 | medium | v-up | 2.1 | medium |
| db-bench-press | 2.1 | medium | db-step-up | 2.1 | low |
| db-deadlift | 1.9 | low | db-front-rack-lunge | 2.3 | low |
| wall-walk | 12.6 | low | db-thruster | 2.5 | low |
| lemon-squeezer | 1.9 | low | leg-raise | 2.1 | low |
| db-curl-press | 2.5 | medium | toe-tap | 0.6 | generic |
| squat-thrust-hold | 2.6 | generic | high-knees | 0.5 | generic |
| marching-knees | 0.5 | generic | mountain-climber | 0.6 | generic |
| bike-cal | 4.2 | generic | db-reverse-lunge | 2.3 | generic |
| db-split-squat | 2.6 | generic | glute-bridge | 1.6 | generic |
| db-glute-bridge | 1.9 | generic | kb-deadlift | 1.9 | generic |
| db-rdl | 2.3 | generic | kb-high-pull | 2.1 | generic |
| med-ball-slam | 2.1 | generic | db-floor-press | 2.1 | generic |
| db-strict-press | 2.1 | generic | tricep-dip | 1.9 | generic |
| db-row | 2.1 | generic | db-bent-over-row | 2.1 | generic |
| prone-swimmer | 1.6 | generic | hand-release-push-up | 3.7 | generic |
| russian-twist | 0.8 | generic | flutter-kick | 0.5 | generic |
| bear-crawl | 0.8 | generic | kb-farmer-carry | 0.8 | generic |
| lateral-bench-step-over | 1.6 | generic | skater | 0.8 | generic |
| skater-step | 1.1 | generic | lateral-shuffle-touch | 1.6 | generic |

### 17.3 Pace model and target rounds

`PaceModel` gives a pace factor per piece (multiplies fresh time):

| Piece | Default factor | Learned multiplier family (§22) |
|---|---|---|
| amrapWithRest, W = 2 min | 0.9 | windows |
| amrapWithRest, W = 3 min | 1.0 | windows |
| amrapWithRest, W = 4–6 min | 1.1 | windows |
| amrap, D min | 1 + 0.015 × D (12 → 1.18, 20 → 1.30) | continuous |
| emom | 1.0 | none |
| forTime | 1.35 | forTime |

Reps are sized to hit a **target number of rounds**, taken from the coach's medians:

| Piece | Target rounds | Fresh round seconds at default pace (`targetFreshRoundSec`) |
|---|---|---|
| W = 2 | 3.6 per window | 37 |
| W = 3 | 3.7 per window | 49 |
| W = 4 | 4.4 per window | 50 |
| W = 5 | 5.2 per window | 52 |
| W = 6 | 6.0 per window | 55 |
| amrap 12–14 | 9.2 total | 66 (12 min) to 75 (14 min) |
| amrap 15–16 | 10.5 total | 70–74 |
| amrap 18 | 10.6 total | 80 |
| amrap 20 | 11.0 total | 84 |

`targetFreshRoundSec = windowSec / (targetRounds × defaultFactor × learnedMultiplier)`, used unrounded (the table shows rounded values). It is clamped to 35–60 s for windows and 55–105 s for continuous AMRAPs (the coach's p5–p95).

New optional section field **`expectedScore: Double?`**: expected rounds per window (AMRAPs), or expected finish seconds `E` (for-time). Nil for time-based formats. It is used by the feedback loop.

### 17.4 For time

For-time uses `pace.forTime` in E (§5.3). E must be 12–20 min (the coach's finish times were mostly 13.6–23.4); the cap is `min(24, ceil(1.2 × E))`.

### Requirements: pace

**MC-51 Reps golden test.** `rest-5x3` (W = 3, default pace, multiplier 1.0, density 1.0) with push-ups, KB swings and up/downs gives **4 / 6 / 4** (target 180 / 3.7 = 48.6 s; share 11.2 s). Each is within ±1 of the coach's typical 4 / 7 / 4.

**MC-52 Expected rounds in range.** For every remixed AMRAP in the year property test, `expectedScore` (at the learned pace) is 3.2–6.5 rounds per window for amrapWithRest, and 7.5–13.5 rounds for continuous AMRAPs.

**MC-53 For-time realism.** Every remixed for-time piece has `720 ≤ E ≤ 1200`, cap ≤ 24, and `expectedScore == E`.

**MC-54 Table values.** The library's `secondsPerRep` equals §17.2 for every listed id.

## 18. Fade and density

### 18.1 Findings
- **No fade.** In multi-round AMRAPs the later windows score the same or better than round 1: +4% (round 2), +5% (round 4), +9% (round 5) for 3-min windows; 4–5-min windows stay within ±3%. Station reps rise up to +25% by round 4, intervals +8% by round 5 (n = 5–6, low confidence).
- The athlete starts conservatively, so 60 s rest after 3–6-min windows and 30 s after 2-min windows is enough.
- Coach work density (work ÷ total time): p5 0.67, median 0.83, continuous pieces 1.0.

### 18.2 Rules
- Reps per round are the **same in every round**. No tapering.
- Expected score per window is the same for every window (no planned fade).
- Work density limits: repeat formats (amrapWithRest, stations) 0.67–0.90; intervals and Tabata 0.50–0.75; continuous (1.0) only as `amrap` ≤ 20 min or `emom`.
- Rest: windows of ≥ 3 min are followed by ≥ 60 s rest, 2-min windows by ≥ 30 s (except after the last).

**MC-55 No taper.** Every remixed multi-round piece prescribes identical reps in every round.

**MC-56 Density bounds.** Every catalog shape and every remixed metcon meets the §18.2 density limits (computed from the §5.2 formulas: work seconds ÷ estimateSeconds).

**MC-57 Rest rule.** Every amrapWithRest and stations shape meets the §18.2 rest rule.

## 19. Default loads

### 19.1 Findings
- The coach's metcon loads were almost fixed for 2.4 years. They sit at or near the top of the home gym's implements: KB swings always 35 lb, DB moves 20 lb per hand, plate 25 lb.
- Lighter exceptions: DB curl + press (20 → 10–15 over time), DB step-ups (10), DB ground-to-overhead (10–15), overhead plate lunge (10–15).
- Barbell metcon lifts (benchmarks only, §13 Q1) ran at about 48–58% of the current training max.
- After a long break the coach dropped metcon loads one step (DB 20 → 15, KB 35 → 22) for several weeks.

### 19.2 Default weights (lb; converted and snapped for kg gyms)

| id | Default | Change from v2 |
|---|---|---|
| kb-swing | 35 | was 26 |
| goblet-squat | 35 | was 26 |
| plate-ground-to-overhead | 25 | was 10 |
| db-thruster | 20 per hand | was 15 |
| db-push-press, db-snatch, db-bench-press, db-floor-press, db-hang-squat-clean, db-rdl, db-row, db-bent-over-row, db-front-squat, db-deadlift, db-hang-clean-push-press, db-front-rack-lunge | 20 per hand | |
| db-curl-press | 15 per hand | new |
| db-ground-to-overhead | 15 (one DB) | new |
| db-step-up, db-strict-press | 10 per hand | |
| db-reverse-lunge, db-split-squat | 15 per hand | |
| overhead-plate-lunge | 15 | new |
| kb-deadlift, kb-farmer-carry | 35 | |
| kb-high-pull | 26 | |
| med-ball-slam | 12 (ball) | |

### 19.3 Load rules
- Metcon loads **never progress automatically.** They change only by a snap step from a rule that fires and is shown as a reason: deload −1, coach note lighter −1, ratings ±1 (existing), comeback −1 (§21.4 / MC-65).
- The total shift is clamped to −2…+1 steps. Snapping to the gym's implements is unchanged.
- If a future version allows barbell lifts in remixed metcons (Q1), the default load is 50% of the training max for squats and deadlift and 55% for cleans and presses, rounded to the plates.

**MC-58 Default loads.** With no weight shift, every remixed loaded item's prescribed weight equals the §19.2 default, snapped to the gym.

**MC-59 No silent progression.** Over the year property test (neutral feedback), each movement's prescribed weight changes only on days with a `metabolic.lighter`, `metabolic.heavier`, deload or comeback reason.

## 20. Quality score and best-of-N

### 20.1 Features (per remixed metcon)

| Feature | OK range (no penalty) | Penalty reaches the weight at | Weight |
|---|---|---|---|
| High-impact moves | 0–1 | 2 | 2.0 |
| Technical moves | 0–1 | 3 | 1.0 |
| Grip-heavy moves | 0–2 | 3 | 1.0 |
| Adjacent grip-heavy pairs (wrapping) | 0 | 2 | 1.0 |
| Shoulder-heavy moves | 0–1 | 2 | 1.5 |
| Adjacent shoulder-heavy pairs | 0 | 1 | 2.0 |
| Work density | ≥ 0.67 | 0.50 | 1.0 |
| Reps per round (rep formats) | 12–40 | 8 below / 50 above | 1.0 |
| Largest move's share of fresh round time | ≤ 0.45 | 0.55 | 1.0 |
| Fresh round seconds, windows | 39–60 | 30 / 75 | 1.5 |
| Fresh round seconds, continuous | 56–102 | 45 / 120 | 1.5 |
| Expected rounds per window | 3.0–6.5 | 2.0 / 8.0 | 1.5 |
| Expected rounds, continuous | 7.5–13.5 | 5.0 / 16.0 | 1.5 |
| Same movement in another metcon this week | 0 | 1 | 0.5 per move |

Penalty per feature = weight × min(2, distance outside the OK range ÷ distance from the OK edge to the "reaches" value). The total penalty is the sum.

### 20.2 Calibration on the coach's metcons
Coach metcons score: median 0, p75 0.5, p90 1.6, p95 2.0. **94% score ≤ 2.0.** So a threshold of 2.0 means "looks like the coach".

### 20.3 Selection
- Build N = 12 candidates (steps 3–11 of §7.1, each with a sub-seed of the day's metabolic RNG). Discard any that fail a hard rule. Keep the one with the lowest penalty; ties go to the earliest candidate.
- If every candidate scores above 2.0, keep the best one and add reason `metabolic.quality_relaxed` ("Your limits make this one a bit unusual: {top penalty feature}.").

**MC-60 Score function.** Unit tests on synthetic, generic fixtures:
- "5 × 3-min AMRAP: 4 push-ups, 7 KB swings, 4 up/downs" scores 0.
- "AMRAP 20: 6 up/downs, 8 air squats, 6 KB deadlifts, 8 DB push press" scores ≤ 0.5.
- Two jumping moves score ≥ 2.0.
- Three adjacent shoulder-heavy moves score > 2.0.
- 60 reps per round scores > 1.0.

**MC-61 Threshold.** In the year property test with the full home gym (any limits), every remixed metcon scores ≤ 2.0. Bodyweight-only configurations may exceed 2.0, but only with `metabolic.quality_relaxed`.

**MC-62 Typical quality.** Full home gym, no limits, one year: median penalty ≤ 0.5 and p90 ≤ 1.5 (at least as good as the coach).

**MC-63 Best-of-N is deterministic and better.** Same request gives the same winner. On 50 sampled days, the winner's penalty ≤ the first candidate's penalty.

## 21. Strength: OPTIONAL recommendations (not part of this build)

Strength programming is out of scope. These findings and options are for the owner to decide later. Nothing here changes code in this build, **except MC-65**, which is metcon-only.

### 21.1 Findings
| Topic | Coach era | Our block |
|---|---|---|
| Frequency | each lift every 14 days (median), same as ours | every 14 days |
| Sets | 5–6 ramping sets every 2 min, starting at ~50% of the top set | same format |
| Top-set reps | varied 5–10 every session | 5 → 3 → 2/1 by phase |
| Progression | session to session (same reps): 50% up (median +10 lb), 15% same, 35% down; no fixed plan | % of TM, +10/+5 lb per quarter |
| Long-term trend | e1RM up 15–50% in the first ~3 quarters, then flat or slowly down for ~5 quarters | — |
| Short break (19 days) | first session back −6% to −24% (median ≈ −10%); back to pre-break weight in 1–3 sessions | no rule |
| Long break (56 days) | first session back −25% to −46% (median ≈ −38%); presses and front squat back in 3–4 sessions; deadlift and back squat not yet back after 4 | no rule |

### 21.2 Options for the owner
| # | Option | Why | Suggested default |
|---|---|---|---|
| S1 | Keep the 14-day frequency, but give the volume phase 6–8-rep top sets for squats, deadlift and push press (Olympic lifts stay ≤ 3) | The athlete is used to 5–10 reps; jumping to 5s and then singles is a big change after a long plateau | Try in block 2 |
| S2 | Raise frequency for the four non-Olympic lifts to about every 7–9 days (for example a 4-lift rotation, or a 4th training day) | The plateau happened at a 14-day frequency; more frequent practice is the usual fix | Owner's call; not before block 2 |
| S3 | Keep +10 / +5 lb per quarter, capped by the test result (already the rule) | +5–7% per quarter is ambitious for a plateaued lifter, but the "lower of" rule protects | Keep |
| S4 | Add the comeback ramp (§21.3) for strength | Breaks cost 10–40%, and jumping straight back to the plan risks misses | Adopt |
| S5 | Plan known long breaks (e.g. summer) as a deload plus a ramp, not as missed weeks | Each lift recurs every 2 weeks, so a missed week costs a whole exposure | Adopt with S4 |

### 21.3 Comeback ramp proposal (strength, optional)
Break = days since the last done workout.

| Break | Week 1 back | Week 2 | Week 3 | Week 4 | Extra |
|---|---|---|---|---|---|
| < 14 days | 100% | — | — | — | none |
| 14–27 days | 90% of the planned top set | 95% | 100% | — | — |
| 28–55 days | 80% | 90% | 95% | 100% | — |
| ≥ 56 days | 70% | 80% | 90% | 95% | re-estimate the TM from the week-3 top set (Epley) and take the lower |

The ramp is time-based, not session-based, because each lift only comes up every 2 weeks.

### 21.4 Comeback metcon (in scope)

**MC-65 Comeback metcon.** If the last done workout is ≥ 28 days before the plan date, then for the next 14 days every metcon is capped at the middle band, its weights shift −1, and it has reason `metabolic.comeback` ("Welcome back: a middle-length piece with lighter weights for your first two weeks."). For breaks of < 28 days the existing coach-note rules apply.

## 22. Feedback loop

All of these are pure functions of history, so plans stay deterministic.

### 22.1 Pace learning
- `PaceModel.learned(from: history)` keeps one multiplier per family: windows, continuous, forTime.
- For each done, scored, remixed or benchmark piece with `expectedScore`: `r = expected rounds ÷ actual rounds` (AMRAPs), or `actual seconds ÷ E` (for-time). Ignore r outside 0.5–2.0. Pieces with "modified" substitutions count.
- Multiplier = median r over the family's last 8 pieces; needs ≥ 3, otherwise 1.0. Clamped to **0.80–1.25**.
- It feeds target rounds (§17.3) and E (§17.4). Reason when the multiplier is ≠ 1.0 by more than 5%: `metabolic.pace` ("Reps sized to your recent pace: about {k} rounds per {W}-min block.").

### 22.2 Density from ratings
- `d` starts at 1.0. Replay the last 6 done metcons that have a `metabolicDifficulty` rating, oldest first:
  - rating 5: −0.10; 4: −0.05; 3: move 0.05 toward 1.0; 2: +0.05; 1: +0.10.
- Clamp `d` to **0.80–1.20**. Reps (rep formats only) × `d`, then re-clamp to `repRange`.
- If `d ≤ 0.90`, the band is capped at middle.
- Time-based formats ignore `d`. Benchmarks ignore `d`.
- The existing weight shift (last 2 ratings) still applies. Weights and reps may both move, within their own bounds.

### 22.3 Fade signal
If in 2 of the last 3 scored multi-round pieces the last round scored < 85% of round 1, apply an extra −0.10 to `d` (once, until a later piece no longer shows it). The athlete's normal pattern is flat or rising, so this flags a piece that was too dense.

**MC-66 Pace bounds.** With synthetic history where every piece took twice the expected time per round (r = 2.0), the multiplier is 1.25. A piece with r = 0.4 is ignored as an outlier. With fewer than 3 pieces it is 1.0. The result is identical for identical history.

**MC-67 Density replay.** Ratings [5, 5, 5, 5, 5, 5] give d = 0.80 and a middle-band cap. [1 × 6] gives 1.20. [5, 3, 3, 3, 3, 3] gives 1.0. Reps stay within `repRange`.

**MC-68 Fade signal.** Two of three recent pieces with last/first < 0.85 lower d by 0.10 exactly once.

**MC-69 Feedback never breaks hard rules.** The year property test, rerun with adversarial synthetic feedback (all 5s, all 1s, alternating), still passes MC-19 to MC-24 and MC-52 (with the learned pace).

## 23. Weekly rhythm and v2.1 test plan

### 23.1 Weekly rhythm findings
- Monday, Wednesday and Friday did not differ in metcon format, length (19.6 / 19.6 / 20.1 min) or move count. Days differed only by lift (squat / hinge / press), which our rotation already matches. Fridays had slightly more jumping moves.
- The coach kept the three lengths in a week nearly equal and ran one format all week in about a third of weeks. The owner asked for spread and variety, so §6.2 keeps them (see Q7).
- No weekday-specific rule is added. The weekly plan stays lift-driven.

### 23.2 Test plan additions
Add to the year property test (§14.1): MC-52, MC-53, MC-55, MC-56, MC-58, MC-59, MC-61, MC-62, MC-65 (with a synthetic 30-day gap), MC-69. Add unit tests: MC-51, MC-54, MC-57, MC-60, MC-63, MC-66, MC-67, MC-68.

Test fixtures stay synthetic and generic. Tests never read the private history. The calibration numbers above are fixed constants in code.

### 23.3 New reason ids (add to §12)
`metabolic.pace`, `metabolic.quality_relaxed`, `metabolic.comeback`. MC-49 additionally requires `metabolic.reps` to state the expected rounds ("about {k} rounds per block") for AMRAPs.
