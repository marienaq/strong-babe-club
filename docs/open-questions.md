# Open questions (backlog items 1–5)

Each question has a recommended default. I'm building with these defaults until told otherwise.

## Units (kg / lb)
1. **How should weights be stored?** Default: store everything as it was entered, with its unit (history stays in lb). Convert only for display and for planning. Switching units never rewrites history, so nothing is lost.
2. **Rounding in kg.** Default: plates and ramps snap to what the kg plate inventory can actually load. The default kg gym is a 20 kg bar with pairs of 1.25/2.5/5/10/15/20 kg, so the smallest jump is 2.5 kg. Converted history shows one decimal ("83.9 kg").
3. **What happens to training maxes and goals when switching units?** Default: they're converted and re-rounded to the new unit's smallest step (TM to 2.5 kg, goal targets to 2.5 kg). Equipment isn't converted: switching loads the new unit's preset gym, which you then edit. (Alternative: keep the current gym and convert it to odd numbers like 20.4 kg.)

## Timer sounds
4. **Do all five packs keep the same three cues** (round-end bell, "go", "rest") plus the finish? Default: yes, a fixed cue set per pack. The pack choice also applies to lock-screen notifications.

## Animals
5. **Does the chosen animal replace Kettle, the bear sticker, or the app icon?** Default: no. Kettle stays the coach. Only the animal that acts out the lifts changes, and the "Squat bear" sticker becomes "Squat ⟨animal⟩". The icon stays Kettle.
6. **What about the 72 combinations?** Default: one shared pose rig with a per-animal skin, as the backlog suggests. Skin differences: ears, head shape, snout, tail, body colour. All share the same chunky legs.

## Music
7. **Which option?** Default: (a) only, an "Open my playlist" link (https from open.spotify.com or music.apple.com) in Settings, plus a small button on the workout screens. Options (b) and (c) wait for the owner.

## Other users and onboarding
8. **How long is onboarding?** Default: 6 short steps, each skippable and editable later in Settings:
   1. name
   2. units
   3. training days
   4. equipment preset
   5. limits
   6. animal + how to start (test week / enter maxes / "start light")
9. **What does "I'm new, start light" mean?** Default: a bar-only (or bodyweight-ratio) training max. The bar weight is the starting TM for presses and Olympic lifts, and bar + 20 lb (10 kg) for squats and deadlift. Normal progression follows, and a test week is suggested after 4 weeks.
10. **How does the lift rotation work for 2, 4 or 5 days a week?** Default:
    - The user picks main lifts (any subset of the 6, minimum 2). Each lift has a slot (squat / hip-pull / overhead).
    - Training days cycle through the chosen lifts in order, rotating slots so the same lift is never repeated within 7 days when that's possible.
    - With 3 days and the default 6 lifts, the current A/B weeks are unchanged.
    - With 2 days a week, the 6 lifts cycle over 3 weeks.
    - With 4–5 days, extra days repeat the next lift in the cycle, and the 7-day rule picks a different slot.
11. **When does the test week happen for a new user?** Default: "start light" or manual maxes start block 1 next Monday, with no test week. "Test week" makes next Monday the test week. The owner's dates (test week Oct 12) migrate as they are.
12. **Generic import template.** Default: a CSV of `date, lift, set, reps, weight, unit` (one row per set), plus the app's JSON backup. The coach-sheet JSON stays supported. Unknown columns are ignored and the same bounds apply.
13. **Existing install.** Default: anyone with data or saved settings skips onboarding entirely. Their settings, lifts (the 6) and dates stay exactly as they are.
