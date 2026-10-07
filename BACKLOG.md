# Strong Babe: Backlog

Status: **todo** · **in progress** · **needs decision** · **done**

## 1. Choose your animal (done)
Pick a mascot in Settings (and during onboarding). It acts out every lift.
- A dozen animals. Proposed: bear (current), bunny, cat, dog, fox, frog, koala, otter, panda, penguin, pig, sloth.
- Each animal performs all 6 lifts: Deadlift, Hang Power Clean, Front Squat, Back Squat, Push Press and Push Jerk.
- **Approach:** one shared "rig" of poses and keyframes for each lift, plus a per-animal "skin" (head, ears, body shape, tail, colors). That gives 72 combinations without 72 hand-made animations.
- The animals keep the line-art scrapbook style, with chunky legs. Reduce Motion is respected.
- **Done:** all 12 animals share one rig, each with its own skin (Design/Animals.swift). The picker is in Settings > Your lifting buddy, and the "Squat bear" sticker follows the chosen animal. Kettle stays the brand. A contact sheet (test mode `-sbc-open animals`) shows every animal doing every lift.

## 2. kg vs lb (done)
- Settings → Units: lb or kg.
- Equipment matches the units:
  - Barbell weight: 45 lb, 35 lb, 20 kg or 15 kg.
  - Plate inventory in that unit.
  - Dumbbell and kettlebell lists in that unit.
- Plate math, rounding steps, ramps, the training max, goals, charts and imports all respect the chosen unit.
- Switching units converts the display without losing precision in stored history.
- **Done:** weights are stored as canonical pounds; the planner runs in the gym's unit; kg preset is a 20 kg bar with 1.25-20 kg pairs. Switching loads that unit's preset and re-rounds training maxes and goals. Covered by core and app tests.

## 3. Choose between 5 timer sounds (done)
- Five sound packs, each with a matching set: round-end bell, "go" cue and "rest" cue. Idea: boxing gym (current), arcade, wind chimes, cowbell, soft marimba.
- Settings lets you preview each pack and pick one. The on/off toggle stays.
- All sounds are self-made or synthesized, so there are no licensing issues.
- **Done:** boxing gym, arcade, wind chimes, cowbell and soft marimba, synthesized by scripts/make-sounds.py (20 files, 1.3 MB). Settings has a pack picker with preview, and lock-screen notifications use the chosen pack.

## 4. Music during workouts (parked, back in the backlog 2026-10-06)
Options, from simplest to richest:
- **a.** "Open my playlist" button: links to a Spotify or Apple Music playlist URL of your choice. No SDK, no account linking, and the app stays offline. Timer sounds already play over music.
- **b.** Apple Music via MusicKit: play and pause a playlist from inside the app. Needs an Apple Music subscription and permission.
- **Decision so far:** parked. The owner has Spotify Premium. The full Spotify SDK is limited to 25 allowlisted users unless Spotify grants extended quota, which is hard for small apps, so it doesn't scale to other users. If we revisit, start with option (a).
- **c.** Spotify SDK: play and pause, plus playlist picking inside the app. Needs a Spotify developer app registration, Spotify Premium and the Spotify app installed. It's the first time the app would talk to an outside service, which changes the privacy story.

## 5. Support other users, not just the owner (in progress)
Features a stranger needs on day one:
- **Onboarding:** name, units, schedule (which days, how many per week), equipment, limits and injuries, animal, and starting maxes. Starting maxes can come from a test week, manual entry, or "I'm new, start light".
- **No coach spreadsheet required:** a generic import template (CSV/JSON), or simply start fresh.
- **Lifts:** choose your main lifts (the default 6, or swap some out), and use different rotations.
- **Data controls:** export everything, plus "delete all my data".
- **Accessibility:** Dynamic Type, VoiceOver labels and contrast checks.
- **Localization:** units and dates are ready; strings are kept translatable.
- **Owner-specific defaults** (Mon/Wed/Fri, these plates, the six lifts, the test-week date) become onboarding choices.
- **App Store readiness:** privacy policy, store screenshots, support contact (see the TestFlight vs App Store notes).
- **Done:**
  - **Onboarding (6 steps, all skippable):** name, units, training days, main lifts, limits, then lifting buddy plus how to start (start light, "I know my weights", or test week).
  - **Existing installs:** any install with data skips onboarding and keeps its settings and dates.
  - **Rotation:** works for any schedule and any choice of lifts. 3 days with the six default lifts keeps the A/B weeks; other set-ups cycle through the chosen lifts. Lifts can be reordered in Settings > Main lifts.
  - **CSV import:** a template (`date,lift,set,reps,weight,unit`) can be shared from Settings, and imports are saved all-or-nothing in batches.
  - **Delete all data:** returns the app to onboarding.
- **Left:**
  - A full Dynamic Type / VoiceOver audit. Fonts scale with the text size and there are labels throughout, but fixed-height rows haven't been checked at the largest sizes.
  - Localization string catalogs.
  - App Store items (privacy policy, store screenshots, support contact).

## Done
- **Round 6 (programming):**
  - One main lift per session, plus a light accessory.
  - The test week is replaced by training maxes from history: 90% of the best e1RM over the last 28 days, with related lifts used for "calibrating" lifts.
  - Block 1 starts Oct 12, 2026.
  - A quarter is 12 training weeks + 2 test weeks (heavy 3 with 1–2 reps in reserve).
- v1 core flow, scrapbook design, real-history import, timers and sounds, streak against the schedule, sick days and breaks, app icon.

## Known polish
- Handwritten (Caveat) labels have a clipped last letter on some screens.
- Progress chart: the leftmost 1Y label is cut off at the scroll edge, and the "All" end labels are crowded.
