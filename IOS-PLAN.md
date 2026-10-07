# Workout App: iOS Plan (draft 2)

*Revised 2026-10-05 after an iOS developer review and the first round of design feedback.*

Mockups: https://claude.ai/artifact/Qu9MTD776jFoBrZuMsfNEo

## What the app is

A personal iPhone app that **plans each workout for me** in my coach's four-part format. I show up, follow it, enter the weights, and it motivates me to keep going. I never have to build a workout myself.

## Decisions

| Question | Answer |
|---|---|
| Users | Just me |
| Logging | Live, during the workout |
| Charts | In the app. No web dashboard. |
| Units | lb |
| Voice entry | **Dropped**. Typing is easy enough. |
| Adding exercises yourself | **Dropped**. The app does the programming. |
| Stack | SwiftUI + SwiftData on the phone, with no server. Supabase deferred. |
| Workout planning | Rules-based for v1. An AI agent that designs workouts comes later. |
| Strength lifts | Fixed for v1: Deadlift, Hang Power Clean, Front Squat, Back Squat, Push Press, Push Jerk |
| Schedule | Mon / Wed / Fri, matching the coach's sheet |
| Equipment | See "Home gym" below |
| First week | No test week: block 1 starts Mon Oct 12, 2026, with training maxes from recent history |
| Historical data | Import all 123 weeks of the coach's sheet |

## Home gym (the planner only picks what's here)

| Item | Details | Rules |
|---|---|---|
| Barbell + plates | Plates (pairs): 2.5, 5, 10, 10, 15, 25, 25 lb. Bar assumed 45 lb. | Smallest jump is 5 lb (2.5 per side). Max loadable is **230 lb**. The app shows which plates to load on each side. |
| Dumbbells | 10, 15, 20 lb | DB weights snap to these. A heavier DB prescription becomes more reps or a kettlebell. |
| Kettlebells | 22, 26, 35 lb | KB weights snap to these |
| Medicine ball | 12 lb · slams / throw-downs only | No wall balls or overhead throws (nothing to throw against) |
| Boxes | 24" and 32" · box jumps or step-ups | Box jumps and step-ups default to 24"; 32" is a harder option for box jumps. Step-ups replace box jumps when the "no jumping" limit is on. |
| Bench | Bench press, step-ups, tricep dips, rows | |
| Bar for Australian pull-ups | Inverted rows / Australian pull-ups | No strict or kipping pull-ups |
| Bodyweight | Wall walks, push-ups, burpees, sit-ups, planks, etc. | |

All of this goes into Settings → Equipment, so it can change later (e.g. a new pair of dumbbells).

## Strength lifts (fixed for v1)

A two-week rotation. Every lift comes up once every two weeks, and each week covers squat, hip-driven work and overhead once.

| | Monday (squat) | Wednesday (hip / pull) | Friday (overhead) |
|---|---|---|---|
| **Week A** | Back Squat | Deadlift | Push Press |
| **Week B** | Front Squat | Hang Power Clean | Push Jerk |

History in the coach's sheet, and the starting point for each lift's weights:

| Lift | Sessions | Most recent log (lb, going up each set) |
|---|---|---|
| Deadlift | 68 | 85, 110, 135, 160, 185 |
| Front Squat | 61 | 55, 75, 90, 105, 120 |
| Push Press | 62 | 45, 60, 75, 90, 100 |
| Back Squat | 53 | 65, 80, 100, 120, 135 |
| Push Jerk | 38 | 35, 40, 45, 50, 55 |
| Hang Power Clean | 34 | 40, 55, 65, 75 |

- **Format:** the coach's "every 2 min, going up each set" format stays, because it's familiar and works at home. What changes is that each set's reps and weights come from the strength program below instead of being made up.

## Starting point: history-based training maxes (updated Oct 6, 2026)

The planned Oct 12–16 test week is dropped. The recent 10-8-6-4-2 ladders and 5-rep ramps already work as tests.

- **Training max** = 90% of the **best Epley e1RM over the last 28 days** of logged sets, rounded to 5 lb. It's recomputed as new sessions are logged, until block 1 starts.
- **Lifts with no recent log** borrow from a related lift and are flagged **calibrating**:

  | Lift | Borrowed from |
  |---|---|
  | Hang Power Clean | Power Clean × 0.9 |
  | Push Jerk | Split Jerk × 0.9 or Push Press × 1.05, whichever is lower |
  | Front Squat | Back Squat × 0.85 |
  | Back Squat | Front Squat ÷ 0.85 |

- **Calibrating lifts** start conservative. The difficulty rating from the first session moves the training max more than usual: rated 1 → +10%, 2 → +5%, 4–5 → −5%.
- **Owner's starting maxes (Oct 6):**

  | Lift | Training max |
  |---|---|
  | Back Squat | 135 |
  | Front Squat | 120 |
  | Deadlift | 180 |
  | Push Press | 95 |
  | Hang Power Clean | 95 (calibrating) |
  | Push Jerk | 100 (calibrating) |

- **Block 1:**
  - Weeks 1–12 run **Oct 12, 2026 – Jan 3, 2027**.
  - Weeks 13–14 are tests plus benchmarks: **Jan 4–17, 2027**.
  - Block 2 starts **Jan 18, 2027**.
  - Holiday weeks can be marked as excused or swapped to a deload.
- **Plate ceiling:** Deadlift could reach the 230 lb limit within about 2 blocks. The app warns ahead of time that more plates are needed.

## One main lift per session

- Every session has **exactly one** main barbell lift, never two.
- A second strength movement is always a **light secondary accessory**: about RPE 6–7, never tested or maxed, in a complementary pattern. It's shown as "+ 3 × 10 DB rows" next to the main lift.

| Main lift | Accessory options |
|---|---|
| Squats | DB row, Australian pull-up, push-up |
| Deadlift | DB bench press, push-up, DB overhead press |
| Push press / push jerk | goblet squat, DB row, Australian pull-up |
| Hang power clean | split squat, step-up, DB row |

## Quarterly tests

- A quarter is **12 training weeks + 2 test weeks**.
- **Test sessions:**
  - one main lift per session;
  - work up to a **heavy 3 with 1–2 reps in reserve**, never a true 1RM;
  - the e1RM is estimated from that heavy 3;
  - each session also gets a light accessory.
- **Next block's training max** = the lower of (TM + 10 lb for lower body, or + 5 lb for presses and Olympic lifts) and the test result.
- **New users** who choose "test" start with the same 2 test weeks.

## Strength program: quarterly blocks based on a training max

This combines three well-tested ideas, with the coach's every-2-minute ramping sets as the format:
- **Wendler's 5/3/1:** percentages of a *training max*, and slow, steady increases.
- **Block periodization:** a volume phase, then a strength phase, then a peak.
- **Prilepin's chart:** sensible rep ranges for the Olympic lifts.

Each block is 14 weeks (12 training + 2 test), so it lines up with the quarterly benchmark repeats. Every lift comes up twice in each 4-week phase.

**Training max (TM):** 90% of an estimated 1-rep max, worked out from my logged top sets (Epley formula). From the coach's sheet:

| Lift | Recent top set | Est. 1RM | Starting TM |
|---|---|---|---|
| Deadlift | 185 × 5 | ~215 | 195 |
| Back Squat | 135 × 5 | ~160 | 145 |
| Front Squat | 120 × 5 | ~140 | 125 |
| Push Press | 100 × 5 | ~115 | 105 |
| Hang Power Clean | 75 × 5 | ~90 | 80 |
| Push Jerk | 55 × 5 | ~65 | 60 |

**The block (ramping sets every 2 min; top set as % of TM):**

| Weeks | Phase | Squats, Deadlift, Push Press | Hang Power Clean, Push Jerk |
|---|---|---|---|
| 1–4 | Volume | 6 sets × 5, ramping to 75–80% | 6 sets × 3, ramping to 70–75% |
| 5–8 | Strength | 6 sets × 3, ramping to 85–90% | 6 sets × 2, ramping to 80–85% |
| 9–11 | Peak | 5 × 2 then a 1, ramping to 90–95% | 6 sets × 1–2, ramping to 85–90% |
| 12 | Deload | 5 × 5 at 60%, fast and crisp | 5 × 2 at 60% |
| 13 | Test + benchmarks | Work up to a heavy 3 (or a single if feeling good) | Heavy single, but only if the technique is clean |

- **Olympic lifts** (Hang Power Clean, Push Jerk) never go above 3 reps per set. Speed and technique fall apart when tired, so these stay low-rep and are never ground out.
- **Ramp:** the sets in between climb evenly from about 50% up to the top set, matching the coach's "go up each set".
- **Rounding:** weights round to what the plates can make.
- **New block:** the TM goes up by **+10 lb on lower-body lifts and +5 lb on presses and Olympic lifts**, or is reset from the week-13 test, whichever is lower. This slow, steady increase is what makes 5/3/1 last for years.
- **Adjusting to how sessions feel:**
  - Rated 1–2 and every rep done → the next session's top set can go up by one extra plate step.
  - Rated 5 or a missed rep → the next session repeats the same weight.
  - Two misses in a row → the TM for that lift drops by 10%.
  - Low energy / comeback / "just show up" → the top set is capped at the lower end of the phase's range.

- **Warm-ups** come from the coach's library and prime the day's lift.
- **Metabolic and cool-down movements** stay open (dumbbells, kettlebells, bodyweight). The fixed list applies only to the strength section.

## Workout format (from my coach's sheet)

Every workout has four sections, each with an instruction and a place for my notes:

1. **Warm-up:** 3 rounds of A/B/C/D. One move raises my heart rate (jumping jacks, burpees, toe taps). The other three warm up the muscles today's strength work will use.
2. **Strength / skill:** usually 1 lift, sometimes 2 (A/B).
   - Formats:
     - Every 2 min for 10–12 min, going up each set (e.g. 5 front squats).
     - Ladders such as 10-8-6-4-2.
     - 5 × 7 going up.
     - Every 3 min when there are two lifts.
   - Reps are pre-filled. **I only enter the weight for each set.**
3. **Metabolic conditioning:** formats are interval (work/rest), AMRAP with rest, descending ladder for time, Tabata and EMOM.
   - It has its own **start/stop timer** that handles work and rest.
   - I log reps or rounds+reps for each round, or my time, so repeats can be compared.
   - Name format: `structure-rounds-time-word`, e.g. `amrap-5-4-fungi`.
4. **Cool-down / accessory:** core work (sit-ups, planks, leg raises at 15-15-15-15-15) plus stretches.

Weights for each move (e.g. "A = 20 lb") are part of the plan, as on the sheet.

## Today screen: motivation

- **Streak:** planned workouts done in a row. It counts workouts, not days, because I train about 3 times a week. Also shows my best streak.
- **Last 30 days:** % of planned workouts done. Sick days can be marked as excused so they don't count against me. This is the forgiving number.
- **Start workout** is the main button.
- **Coach's note:** one message based on my last 4–6 weeks, picked from these situations:
  - *Push:* consistent, but a lift has stalled → "you've earned a heavier day", and the plan is set heavier.
  - *Comeback:* recent missed workouts → "today restarts it", and the plan is set lighter.
  - *Just show up:* low energy or high difficulty several times in a row → "showing up is the win", and the plan is lighter and shorter.
  - Later: *Celebrate* (new PR or best streak) and *Variety* (doing the same things too often).
- **Next workout:** the four sections at a glance, with "Why this?" and "Shuffle" buttons.

## The programming engine (the new core of the app)

Rule-based and running on the phone, so it works offline, costs nothing and can always explain itself.

1. **Movement library:**
   - Each move is tagged with a pattern (squat, hinge, press, pull, lunge, carry, core, cardio) and its muscles.
   - It also records the equipment needed, whether it's high impact (jumping), and a joint-stress flag (knee, wrist).
   - It's seeded from my coach's past workouts.
2. **Format library:** strength formats, metabolic formats and warm-up/cool-down formats, each with typical rounds, times and reps.
3. **Weekly rotation:**
   - Main lifts rotate squat → hinge → press/pull across the week.
   - The same main lift is never repeated within 7 days.
   - Muscle groups are kept balanced over 2 weeks.
4. **Building a workout:**
   - Pick the strength lift.
   - Build a warm-up that primes it.
   - Pick a metabolic piece that doesn't overload the same muscles. Sometimes it's a repeat of an old one, so I can beat my score.
   - Add core work for the cool-down.
5. **Weights:**
   - Strength weights come from the quarterly block (see "Strength program").
   - Metabolic weights snap to my dumbbells and kettlebells, and go up or down with my difficulty ratings.
   - Plateau → the next block starts from a reset TM instead of grinding on.
6. **Limits I can set:**
   - Avoid jumping.
   - Go easy on the knee or wrist.
   - My equipment: dumbbells, kettlebell, barbell + plates, bench, bike.
   - Target length of about 50 min.
7. **Why this?** The reasons come from the rules that fired, e.g. "squat is next in the rotation; your last two squat days were rated 2/5".
8. **Shuffle:** re-picks one section, or the whole workout, within the same limits.

**Later: an AI agent that designs workouts.**
- It replaces the rules engine behind the same interface: given my history, feedback, limits and schedule, it returns a planned workout plus its reasons.
- Keeping that boundary clean in v1 means the agent can be swapped in without touching the screens.
- The agent would run through Claude, using the coach's 2.5 years of sheets and my logs as context.
- It needs a small server (a Supabase or Netlify function) to keep the API key off the phone. That's the point where Supabase comes in.
- The rules engine stays as the offline fallback.

## Quarterly benchmark repeats

- **Benchmarks:** about 6 metabolic workouts are tagged as benchmarks. They start as favourites from the coach's sheet and are a mix of AMRAP, interval, for-time and ladder formats.
- **Schedule:** each benchmark comes back **once a quarter**, spread across the 12 training weeks (about one every two weeks; the test weeks catch up any missed). Every other metabolic piece is remixed.
- **Exact repeats:** a benchmark repeats exactly, with the same moves, weights and timing and the same name (e.g. `amrap-5-4-fungi`), so scores can be compared.
- **Screens:**
  - Metabolic and Finish show last quarter's score next to today's, round by round.
  - Progress gets a "Benchmarks" view: one row per benchmark showing its score each quarter.
  - Beating a score counts as a PR.
- **Limits:** if a limit rules out a benchmark move (e.g. no jumping), the move is substituted and the score is marked "modified", so it isn't compared like for like.

## Data model (on the phone, sync-ready)

All tables have `id` (UUID), `created_at`, `updated_at` and `deleted_at`.

- **movement:** name, pattern, muscles[], equipment[], high_impact, joint_flags[], default_weight.
- **planned_workout:** date, status (planned / done / skipped / excused), generator_reasons (JSON), coach_note_type.
- **benchmark:** name, section template (moves, weights, timing), active, quarter_slot.
- **section:** workout_id, benchmark_id (nullable), kind (warmup / strength / metabolic / cooldown), format, name (e.g. `amrap-5-4-fungi`), instructions, rounds, work_sec, rest_sec, interval_sec, athlete_note.
- **section_item:** section_id, letter (A–D), movement_id, reps or reps_scheme (e.g. "10-8-6-4-2"), time_sec, prescribed_weight.
- **set_log:** section_item_id, set_number, reps, weight, completed_at. Used for strength.
- **round_log:** section_id, round_number, rounds, reps, time_sec. Used for metabolic.
- **workout_feedback:** workout_id, energy, strength_difficulty, metabolic_difficulty, notes.
- **lift_program:** lift, training_max, block_start_date, block_week, phase.
- **settings:** schedule (e.g. Mon/Wed/Fri), equipment, limits, target_minutes.

## Visual design (Today screen approved Oct 5, 2026)

- **Style:** scrapbook / doodle journal. Dotted paper with a margin line, Caveat handwriting for labels, Nunito for body text.
- **Colors (Sherbet):** cream #FFF4E8, ink #2B1B3D, tangerine #FF6B3D (strength), sunny #FFC94D (warm-up), sky #6E9BFF (metabolic), mint #3CC8A5 (cool-down), bubblegum #FF9EC0.
- **Stickers everywhere:** die-cut barbell, kettlebell and dumbbell stickers. The sticker page shows the last 12 workouts. After each workout **you pick your own sticker** from a sheet: barbell, Kettle, dumbbell, squat bear, flame and so on. Rare stickers only unlock on special days, e.g. the PR star on a PR day and special stickers at streak milestones. The one you pick goes on your sticker page and that day's Journal entry.
- **Kettle:** a kettlebell mascot who delivers the coach's note.
- **Line-art bear:** acts out the day's strength lift. Six animations, one per lift.
- **Today screen, top to bottom:**
  - Greeting.
  - Sticker page.
  - Streak card and last-30-days card: label, value and a short summary only.
  - "Let's lift!" button, which jiggles.
  - Kettle's note.
  - Today's list, with the bear beside it.
- **Motion:** stickers slap on, doodles draw themselves in, and highlighter swipes animate. Everything respects the phone's Reduce Motion setting.
- **All 7 screens restyled (Oct 5):** see the "Scrapbook: full flow" row on the canvas. These replace the earlier dark mockups.

## Screens (see the mockups)

1. **Today:** streak, last-30-days %, Start, coach's note (try the three versions under the Tweaks button), next workout.
2. **Workout, strength:** section progress bar, the lift and its instructions, a countdown to the next set, reps pre-filled, weight input, a ✓ for each set, my notes. Finish sits at the bottom.
3. **Workout, metabolic:** the workout's name, the moves with their weights, a work/rest ring timer with start/pause, rounds+reps per round next to last time's scores.
4. **Why this workout:** the reasons for each section, Shuffle for each section, and Shuffle everything.
5. **Finish:**
   - Strength in orange (top set, total lifted) and metabolic in blue (time, score vs last time).
   - Any PR.
   - Energy, the two difficulty ratings and notes.
6. **History:** unchanged for now.
7. **Progress:** unchanged for now.
8. **Settings** (not mocked up): schedule, equipment, limits, import and export.

## Build phases

0. **Setup (about 1 week):** Xcode, and a Hello World app on my iPhone.
1. **Run a workout (2–3 weeks):**
   - Data model.
   - Hand-written seed workouts in my coach's format.
   - Active workout screens with both timers, Finish, and History.
   - **I start using it.**
2. **Import historical data (1 week):** bring all 123 weeks of the coach's sheet into the app. The parser is already being built: `tools/import_sheet.py` → `data/history.json` + `data/movements.json`.
   - **Workouts:** every Mon/Wed/Fri workout with its four sections, the coach's notes and my notes.
   - **My logs:** strength weights become set logs and metabolic scores become round logs, so History, Progress charts, PRs and the "last time" values are full from day one.
   - **Libraries:** the movement library and the benchmark candidates are seeded from it.
   - **Starting point:** it's the fallback for training maxes, and it sets the starting training maxes (best e1RM over the last 28 days).
3. **Programming engine (2–3 weeks):** rotation, weights, why/shuffle, limits.
4. **Motivation (1 week):** streak, % completed, excused days, coach's notes.
5. **Progress (1–2 weeks):** charts and goals.
6. **Later:** TestFlight ($99/yr), Lock Screen timer, Apple Watch heart rate, Claude-written notes.

## Open questions

- Is the barbell 45 lb (standard) or 35 lb?

- Which ~6 of the coach's metabolic workouts become the first benchmarks? (Default: the app proposes 6 based on how often you did them and your logged scores, and you approve the list.)

