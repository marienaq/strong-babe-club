REQUIREMENTS
⸻

Workout Tracker & Insights App – Updated Requirements

1. Overview

A web app to log workouts, visualize progress, and deliver automated feedback.
	•	Data import: one-off ad-hoc script run locally by a developer; enforces one record per user per date (with “skip or override” option).
	•	Entry: mobile-web forms with voice-to-text fallback.
	•	Dashboards: desktop-web with interactive, shareable views.
	•	Access: Google OAuth for creators; public tokenized links for viewers.

⸻

2. User Roles & Permissions

Role	View	Create/Edit
Athlete	Own dashboards & public views	Own workouts & goals
Coach	Assigned athlete dashboards	Create/edit workouts for assigned athletes
Admin	All dashboards	Manage users, imports, system settings
Guest	Public dashboards only	—


⸻

3. User Stories
	1.	Historical Import
	•	As an Admin, I run the import script locally to load past sheet data; it skips or prompts to override if a session for that date already exists.
	2.	Session Metadata
	•	As an Athlete, I select an “energy” tag (descriptive category mapped to a background color) and a numeric difficulty slider (1–5, also color-coded) for strength and metabolic segments.
	3.	Workout Logging
	•	As an Athlete, I add warm-up/accessory notes, strength entries (lift name, sets×reps×weight), and metabolic entries (auto-generated name, reps/time, optional heart rate).
	4.	Voice Entry & Validation
	•	As an Athlete, I dictate entries via voice-to-text; system validates that weight ∈ [35–300], sets ∈ [1–20], reps ∈ [5–200], else prompts correction.
	5.	Strength Time Series Charts
	•	As an Athlete, I view two unified charts showing every lift as a series:
	•	Max Weight Chart: max weight per date (with rep count as secondary series).
	•	Total Volume Chart: sum(weight×reps) per date.
	•	I can toggle individual lifts or entire muscle groups on/off. Difficulty and energy appear as light-color bands in the background.
	6.	Lift Frequency Chart
	•	As an Athlete, I see monthly stacked bars where each date is counted once per lift type (i.e. a “lift occurrence”).
	7.	Automated Insights
	•	As an Athlete, I receive monthly email notifications when a lift shows no PR increase for 3 consecutive months (plateau), immediate email on any new PR, and suggestions to add under-trained muscle groups next month.
	8.	Goals
	•	As an Athlete, I can create simple target goals (lift name, target weight, deadline) and view a progress bar. Program templates are deferred to a later phase.
	9.	Voice Coach (Future MVP Stretch)
	•	As an Athlete, I optionally enable a voice coach using TTS scripts (in English only) that: announces each step, prompts for feedback, and adapts if offline by falling back to form entry.
	10.	Public Sharing
	•	As an Athlete, I generate a tokenized, publicly viewable dashboard link (no expiry management required initially).

⸻

4. Data Model & Validation
	•	WorkoutSession
	•	date (unique per user), energyTag (enum), strengthDifficulty (1–5), metabolicDifficulty (1–5)
	•	StrengthEntry
	•	liftName, sets (1–20), repsPerSet (5–200), weightPerSet (35–300)
	•	MetabolicEntry
	•	instruction, generatedName, repsOrTime, heartRate (optional)
	•	Goal
	•	liftName, targetWeight, targetDate

All numeric fields enforce the ranges above; the import script applies the same validations, logging malformed rows.

⸻

5. UI & Interaction

5.1 Workout Entry (Mobile-Web)
	1.	Date selector (defaults to today, prevents duplicates)
	2.	Energy tag picker (e.g. “High,” “Moderate,” “Low”)
	3.	Difficulty slider (1–5)
	4.	Sections for Warm-Up, Strength, Metabolic, Accessory
	5.	Voice-to-text toggle with inline validation errors
	6.	“Skip or Override” prompt if entry exists

5.2 Dashboards (Desktop-Web)
	•	Max Weight & Total Volume Charts: unified multi-series line charts; background color bands encode energy/difficulty.
	•	Lift Frequency Chart: monthly stacked bar by lift occurrences; legend toggles series.
	•	Insights Feed: list of email-driven insights mirrored in-app.

⸻

6. Automation & Notifications
	•	Plateau Detection: monthly batch job checks each lift; if no new max in last 3 months → send email.
	•	PR Alert: immediate email when a new max weight×reps is recorded.
	•	Balance Suggestion: monthly email suggesting 1–2 lifts if a muscle group’s occurrences <15% of total.

⸻

7. Non-Functional Requirements
	•	Performance: supports ~3 workouts/week/user; no special caching required.
	•	Security: HTTPS end-to-end; Google OAuth for creators; public links have unguessable tokens.
	•	Compliance: none required at this stage (personal use).

⸻

8. Tech Stack

Layer	Choice
Frontend	React (TypeScript) on Vercel
Backend/API	Supabase Edge Functions
Database	Supabase (PostgreSQL)
Auth	Google OAuth; role enforcement in Supabase RLS
Notifications	Email via Supabase SMTP or SendGrid
Hosting	Vercel (frontend & functions), Supabase


⸻

9. MVP vs Future Roadmap

Feature	MVP	Future
Ad-hoc import script	✔︎	—
Mobile-web entry + voice	✔︎	Improve ASR
Core charts (max/volume/frequency)	✔︎	Custom filters
Plateau & PR email alerts	✔︎	In-app push
Goal tracking	✔︎	Program templates
Public sharing links	✔︎	Expiry controls
Voice coach (TTS)	—	MVP+

