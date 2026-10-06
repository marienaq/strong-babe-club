TECHNICAL DESIGN
⸻

1. High-Level Overview
	•	Frontend
A React/Next.js app hosted on Vercel, responsible for data entry, charting, and user dashboards.
	•	Backend / Data
Supabase (PostgreSQL + Auth + Storage + Edge Functions) as your single source of truth and “serverless” API layer.
	•	ETL / Ad-hoc Import
Lightweight scripts or Supabase Edge Functions triggered on demand or via cron for ingestion.
	•	Charts & Reporting
Client-side charting (e.g. Recharts or Chart.js) with data fetched via Supabase’s auto-generated REST/GraphQL API.
	•	Hosting & CI/CD
Vercel for frontend (automatic git-push preview/deploy), Supabase managed (zero ops).

⸻

2. Tech Stack

Layer	Technology	Why?
Frontend Framework	Next.js (React)	Fast SSR/SSG, first-class Vercel support
Authentication & AuthZ	Supabase Auth	Email/password, OAuth, JWTs
Database	Supabase (Postgres)	Relational data, real-time subscriptions
API	Supabase auto APIs + Edge Functions	Instant CRUD + custom business logic
Storage (if needed)	Supabase Storage	File uploads (e.g. photos, logs)
Scheduled Tasks	Supabase Cron / Edge Fn	Regular or ad-hoc import jobs
Charting Library	Recharts or Chart.js	Declarative, React-friendly
Deployment	Vercel (Frontend)	CI/CD, preview URLs, global CDN


⸻

3. Data Model (Postgres tables)
	1.	users (managed by Supabase Auth)
	2.	workouts
	•	id (uuid)
	•	user_id (fk → users)
	•	date (date)
	•	energy_level (text)        // e.g. “High”, “Medium”, “Low”
	•	difficulty (integer)       // 1–5
	3.	exercises
	•	id (uuid)
	•	workout_id (fk → workouts)
	•	name (text)                // e.g. “Squat”
	•	sets (jsonb)               // array of { weight, reps }
	4.	mood_flags
	•	id (uuid)
	•	workout_id (fk → workouts)
	•	type (text)                // “mood” or “difficulty”
	•	value (text)               // map to color bands on chart
	5.	imports
	•	id (uuid)
	•	user_id (fk)
	•	source (text)              // “CSV”, “API”, etc.
	•	status (text)              // “pending”, “done”, “error”
	•	run_at (timestamp)

⸻

4. Backend / API
	•	Supabase Auto-Generated
	•	REST & Realtime subscriptions on all tables
	•	Custom Business Logic
	•	Use Supabase Edge Functions (TypeScript) for:
	•	Ad-hoc import endpoints (trigger by button or CLI)
	•	Data validation & de-dup checks
	•	Aggregations (e.g. weekly lift frequency)

⸻

5. Data Import Workflow
	1.	Trigger
	•	Button in UI → calls Edge Function
	•	Or scheduled via Supabase Cron
	2.	Edge Function
	•	Fetches external data (CSV/API)
	•	Performs idempotency: checks imports table + unique workout/day constraint
	•	Inserts/updates workouts + related tables
	3.	Status Tracking
	•	Write imports record with status updates
	•	Emit realtime notifications to UI via Supabase subscriptions

⸻

6. Frontend & Visualization
	•	Dashboard Pages
	•	Workout Log: CRUD UI for workouts & exercises
	•	Charts:
	•	Multi-series line chart (max weight, total weight) with toggle per lift/muscle group
	•	Mood & difficulty overlaid as background color bands
	•	Lift-frequency bar chart (counts per week)
	•	Components
	•	Reusable <Chart> wrapper fetching Supabase data
	•	<ImportStatus> subscribing to the imports table

⸻

7. Authentication & Security
	•	Sign-Up / Login via Supabase Auth (email + OAuth)
	•	Row-Level Security on all tables:

CREATE POLICY "Users can manage own workouts"
  ON workouts FOR ALL
  USING ( auth.uid() = user_id );


	•	Audit: log all import jobs and changes

⸻

8. Deployment & CI/CD
	•	Frontend
	•	Connected to your Git repo → Vercel auto-deploy previews + production on main merge
	•	Supabase
	•	Managed migrations via supabase CLI in your repo
	•	Cron jobs configured in Supabase Dashboard or via supabase functions deploy

⸻

9. Observability & Monitoring
	•	Error Reporting
	•	Integrate Sentry (Edge Functions + frontend)
	•	Performance Metrics
	•	Supabase Dashboard for query monitoring
	•	Logging
	•	Edge Functions write to external log sink or Supabase logs table

⸻

Next Steps
	1.	Sketch out DB schema in SQL/migrations.
	2.	Scaffold Next.js app with Supabase client.
	3.	Build authentication flow and basic CRUD screens.
	4.	Implement import Edge Function + UI trigger.
	5.	Add chart pages and filter controls.
