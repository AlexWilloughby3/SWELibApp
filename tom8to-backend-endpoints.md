# Tom8to Backend API - Endpoint Reference

**Stack:** FastAPI + SQLAlchemy + PostgreSQL  
**Base URL:** `/api`

---

## Timezone Model

The application is **timezone-agnostic**. All day/week boundary logic operates relative to the **user's local timezone**, not a fixed server timezone. The client must send the user's IANA timezone identifier (e.g. `America/Denver`, `America/New_York`) with requests that involve date boundaries.

- **"Today", "this week", "midnight"** all refer to the user's local timezone
- Sessions are stored in the DB as UTC. All date math (week starts, midnight splits, graph grouping, goal evaluation) converts to the user's timezone first.
- **Midnight session splitting:** If a focus session spans midnight in the user's timezone, it gets split into two (or more) separate DB rows, one per calendar day in the user's timezone. For example, if a user in MST logs a 60-min session ending at 12:40 AM MST, it becomes a 20-min session (before midnight MST) and a 40-min session (after midnight MST).
- **Week boundaries** are Monday 00:00:00 in the user's timezone
- **Weekly checkbox goals** anchor to Sunday midnight in the user's timezone
- A user in MST and a user in EST will have different day/week boundaries. A session logged at 11:30 PM EST / 9:30 PM MST counts as "today" for the MST user but could flip to "tomorrow" for an EST user at midnight EST. This is correct behavior -- each user's experience aligns with their own clock.

**How the timezone is provided:** The client sends the user's timezone as a query parameter (`tz=America/Denver`) or header on endpoints that involve date-dependent logic (session creation, stats, graph data, checkbox completions, leaderboard). The server must validate that it's a valid IANA timezone. If omitted, the server should return a 400 error on date-sensitive endpoints rather than falling back to a default.

---

## Health Check Endpoints

### `GET /`
- **Preconditions:** None
- **Postconditions:** Returns `{message, status: "healthy", version: "1.0.0"}`

### `GET /api/health`
- **Preconditions:** None
- **Postconditions:** Returns `{status: "healthy"}`

---

## User Endpoints

### `POST /api/users/register`
Initiates registration by sending a verification code to email. Does NOT create the account yet.

- **Preconditions:**
  - `email` (valid email) and `password` (min 8 chars) in body
  - Email must not already be registered (400 if so)
  - Total account count must be < 50 (403 if limit reached)
  - SMTP must be configured and reachable (500 if email fails)
- **Postconditions:**
  - Creates a `PendingRegistration` row (hashed password + 6-digit code + expiry)
  - Sends verification code email
  - Any previous pending registration for that email is replaced
  - Returns `{message: "Verification code sent..."}`

### `POST /api/users/verify-registration` (201)
Completes registration after email verification.

- **Preconditions:**
  - `email` and `code` (6-digit string) in body
  - A matching, non-expired `PendingRegistration` must exist (401 if not)
- **Postconditions:**
  - Creates `UserInformation` row with hashed password, `display_name` defaults to email, `show_on_leaderboard` defaults to `true`
  - Creates 5 default categories: Work, Study, Reading, Exercise, Meditation
  - Deletes the `PendingRegistration` row
  - Returns the new `User` object

### `POST /api/users/login`
Password-based login.

- **Preconditions:**
  - `email` and `password` in body
  - Must match a registered user with correct bcrypt password (401 if not)
- **Postconditions:** Returns `User` object (email, display_name, show_on_leaderboard). No session/token -- stateless.

### `GET /api/users/{email}`
- **Preconditions:** User with that email must exist (404 if not)
- **Postconditions:** Returns `User` object

### `PATCH /api/users/{email}`
- **Preconditions:**
  - User must exist (404 if not)
  - Body can include `show_on_leaderboard` (bool) and/or `display_name` (string, max 255)
- **Postconditions:** Updates only the provided fields. Returns updated `User`.

### `DELETE /api/users/{email}` (204)
- **Preconditions:** User must exist (404 if not)
- **Postconditions:** Deletes user and ALL associated data (focus sessions, goals, categories) via cascade. Returns no body.

---

## Focus Session Endpoints

### `POST /api/users/{email}/focus-sessions` (201)
Creates a focus session timestamped to "now" in the user's timezone.

- **Preconditions:**
  - User must exist (404)
  - Body: `category` (string 1-50 chars), `focus_time_seconds` (int >= 0)
  - User's timezone must be provided (query param or header)
- **Postconditions:**
  - If the category doesn't exist, auto-creates it (unless user already has 20 categories -- then 400)
  - Timestamp = current time in user's timezone
  - **Midnight splitting:** If the session (calculated backward from end time by `focus_time_seconds`) crosses midnight in the user's timezone, it is split into multiple DB rows, one per day
  - All timestamps stored as UTC in DB
  - Returns the last (most recent) split session

### `POST /api/users/{email}/focus-sessions/with-time` (201)
Same as above but with a caller-provided timestamp.

- **Preconditions:** Same as above, plus `time` (datetime) in body
- **Postconditions:** Same as above, using provided `time` as the end time instead of now

### `GET /api/users/{email}/focus-sessions`
- **Preconditions:** User must exist (404)
- **Query params:**
  - `skip` (int >= 0, default 0)
  - `limit` (int 1-500, default 100)
  - `category` (optional string filter)
  - `start_date`, `end_date` (optional datetime filters, inclusive)
- **Postconditions:** Returns list of `FocusSession` ordered by time descending

### `DELETE /api/users/{email}/focus-sessions/{timestamp}` (204)
- **Preconditions:** Session with that email + exact timestamp must exist (404)
- **Postconditions:** Deletes the single session row

---

## Focus Goal Endpoints

Three goal types: `TIME_BASED`, `DAILY_CHECKBOX`, `WEEKLY_CHECKBOX`

### `POST /api/users/{email}/focus-goals` (201)
Creates or updates (upsert) a goal.

- **Preconditions:**
  - User must exist (404)
  - Body: `category`, `goal_type`, optionally `goal_time_per_week_seconds` (0-604800) and `description` (max 255)
  - `TIME_BASED` goals **must** have `goal_time_per_week_seconds` (400 if missing)
  - `DAILY_CHECKBOX` / `WEEKLY_CHECKBOX` goals **must** have `description` (400 if missing)
- **Postconditions:**
  - If goal with same (email, category, goal_type) exists: updates it
  - Otherwise: creates new goal
  - Returns `FocusGoal`

### `GET /api/users/{email}/focus-goals`
- **Preconditions:** User must exist (404)
- **Postconditions:** Returns all goals for user

### `GET /api/users/{email}/focus-goals/{category}?goal_type=...`
- **Preconditions:** User + goal must exist (404). `goal_type` query param is required.
- **Postconditions:** Returns single `FocusGoal`

### `DELETE /api/users/{email}/focus-goals/{category}?goal_type=...` (204)
- **Preconditions:** Goal must exist (404). `goal_type` query param is required.
- **Postconditions:** Deletes the goal. If it's a checkbox goal, also deletes all associated `CheckboxGoalCompletion` rows.

---

## Checkbox Completion Endpoints

### `POST /api/users/{email}/checkbox-completions` (201)
Toggles completion for a checkbox goal.

- **Preconditions:**
  - User must exist (404)
  - Body: `category`, `goal_type` (must be DAILY_CHECKBOX or WEEKLY_CHECKBOX)
  - A matching goal must exist (400 if not)
- **Postconditions:**
  - For `DAILY_CHECKBOX`: uses today's midnight in the user's timezone as `completion_date`
  - For `WEEKLY_CHECKBOX`: uses Sunday midnight in the user's timezone for the current week as `completion_date`
  - If a completion row already exists for that date: toggles `completed` (true->false or false->true)
  - If no row exists: creates one with `completed=true`
  - Stores `completed_at` timestamp when marking complete, clears it when uncompleting
  - All dates stored as UTC

### `GET /api/users/{email}/checkbox-completions`
- **Preconditions:** User must exist (404)
- **Query params:** `category`, `goal_type`, `start_date`, `end_date` (all optional)
- **Postconditions:** Returns list ordered by completion_date descending

---

## Statistics Endpoints

### `GET /api/users/{email}/stats`
- **Preconditions:** User must exist (404)
- **Query params:** `start_date`, `end_date` (optional)
- **Postconditions:** Returns `UserStats`:
  - `total_focus_time_seconds`, `total_sessions` (across active categories only)
  - Per-category breakdown (active categories only): total time, session count, avg time, goal progress %, daily/weekly checkbox completion data
  - Daily checkbox data: last 7 days of completions
  - Weekly checkbox data: current week's completion status

### `GET /api/users/{email}/stats/weekly`
- **Preconditions:** User must exist. User's timezone must be provided.
- **Postconditions:** Same as above but date range is automatically set to current week (Monday 00:00:00 in user's timezone to now)

---

## Category Endpoints

### `POST /api/users/{email}/categories` (201)
- **Preconditions:**
  - User must exist (404)
  - `category` (string 1-50 chars) in body
  - Max 20 categories per user (400 if exceeded)
- **Postconditions:**
  - If category already exists: returns existing (idempotent, no error)
  - Otherwise: creates new active category
  - Returns `Category`

### `GET /api/users/{email}/categories`
- **Preconditions:** User must exist (404)
- **Postconditions:** Returns all categories ordered alphabetically

### `PATCH /api/users/{email}/categories/{category}`
Toggle active status.

- **Preconditions:** User + category must exist (404)
- **Body:** `active` (bool, required)
- **Postconditions:** Updates `active` flag. Inactive categories are excluded from stats/leaderboard but their data is preserved.

### `DELETE /api/users/{email}/categories/{category}` (204)
- **Preconditions:** Category must exist (404)
- **Postconditions:** **Cascade deletes** all focus goals AND all focus sessions for that category. Permanent.

### `PUT /api/users/{email}/categories/{category}`
Rename or merge categories. Two-step process.

- **Preconditions:** User + source category must exist (404/400)
- **Body:** `new_category` (string 1-50 chars, must differ from current name)
- **Query param:** `confirm_merge` (bool, default false)

**Step 1 (confirm_merge=false):** Dry run. Returns info about what will happen:
- If target doesn't exist: `{requires_merge: false, message: "will be renamed..."}`
- If target exists: `{requires_merge: true, message: "sessions will be moved, old goal discarded..."}`

**Step 2 (confirm_merge=true):** Executes the action:
- **Simple rename (target doesn't exist):** Updates all focus sessions, recreates goal with new name, recreates category with new name (preserves active status)
- **Merge (target exists):** Moves all sessions to target category, deletes source goal (keeps target's goal), deletes source category

---

## Graph Data Endpoint

### `GET /api/users/{email}/graph-data`
- **Preconditions:** User must exist (404)
- **Query params:**
  - `time_range` (required): `week` | `month` | `6month` | `ytd` | `custom`
  - `category` (optional filter)
  - `start_date`, `end_date` (required if `custom`, format `YYYY-MM-DD`, interpreted in user's timezone)
  - User's timezone must be provided
- **Postconditions:**
  - Returns `{data_points: [{date, focus_time_seconds}, ...], time_range, category}`
  - **Grouping logic:**
    - `week`: last 7 days, grouped by day
    - `month`: last 30 days, grouped by day
    - `6month`: last 180 days, grouped by week (Monday-start)
    - `ytd`: Jan 1 to now, grouped by day if < 60 days, else by week
    - `custom`: grouped by day if <= 60 days, else by week
  - Missing dates/weeks are filled with 0
  - All date math done in the user's timezone

---

## Authentication Endpoints

### `POST /api/users/request-verification-code`
Passwordless login flow -- sends a 6-digit code.

- **Preconditions:** `email` in body
- **Postconditions:**
  - If user doesn't exist: returns success message anyway (no email leak)
  - If user exists: creates/replaces `VerificationCode` row (code + expiry), sends email
  - Returns `{message: "..."}`

### `POST /api/users/login-with-code`
- **Preconditions:** `email` and `code` (6-digit) in body. Code must match and not be expired (401).
- **Postconditions:** Deletes the used code (single-use). Returns `User`.

### `POST /api/users/{email}/change-password`
- **Preconditions:**
  - `current_password` and `new_password` (min 8 chars) in body
  - Current password must be correct (401)
- **Postconditions:** Updates password hash. Sends confirmation email (best-effort, doesn't fail if email fails).

### `POST /api/users/request-password-reset`
- **Preconditions:** `email` in body
- **Postconditions:**
  - If user doesn't exist: returns success anyway (no email leak)
  - If user exists: generates `PasswordResetToken` (URL-safe, expires in 1 hour), sends email with link
  - Returns `{message: "..."}`

### `POST /api/users/reset-password`
- **Preconditions:** `token` and `new_password` (min 6 chars) in body. Token must exist, not be expired, and not be used (401).
- **Postconditions:** Updates password hash. Marks token as used (`used=1`).

---

## Leaderboard Endpoint

### `GET /api/leaderboard`
- **Preconditions:** None (public endpoint)
- **Postconditions:** Returns list of `LeaderboardEntry` for all users with `show_on_leaderboard=true`, sorted by `focus_hours_this_week` descending. Each entry includes:
  - `display_name`, `focus_hours_this_week`, `focus_hours_all_time`
  - TIME_BASED goals: `goals_completed_this_week` / `total_goals_this_week`
  - Checkbox goals: daily completions this week (out of 7 * num_daily_goals), weekly completions
  - `goals_completed_all_time`: count of goals ever completed in any week/day (each counted at most once)

---

## Data Export/Import Endpoints

### `GET /api/users/{email}/export-data`
- **Preconditions:** User must exist (404)
- **Postconditions:** Returns all user data as JSON:
  - `version: "1.0"`, `export_date` (UTC ISO string)
  - `categories`: [{category, active}]
  - `goals`: [{category, goal_time_per_week_seconds}] (note: only exports TIME_BASED goal fields)
  - `sessions`: [{time (ISO), focus_time_seconds, category}]
  - Data is account-agnostic (no email in exported items)

### `POST /api/users/{email}/import-data`
- **Preconditions:** User must exist (404). Body must match `UserDataImport` schema.
- **Postconditions:**
  - **Categories:** Upsert -- updates `active` if exists, creates if not
  - **Goals:** Upsert -- updates `goal_time_per_week_seconds` if exists, creates if not (only if category exists)
  - **Sessions:** Additive -- all sessions are added (no dedup). Invalid timestamps are silently skipped. Auto-creates categories if needed.
  - Returns `{categories_imported, goals_imported, sessions_imported, message}`
  - Entire import is transactional (rolls back on error)

---

## Global Constraints

| Constraint | Value |
|---|---|
| Max accounts | 50 |
| Max categories per user | 20 |
| Password min length (register) | 8 chars |
| Password min length (reset) | 6 chars |
| Category name max length | 50 chars |
| Goal max time/week | 604,800 seconds (168 hours) |
| Verification code length | 6 digits |
| Verification code expiry | Set by `email_service.get_code_expiry()` |
| Password reset token expiry | 1 hour |
| Focus sessions list max limit | 500 |
| Default display_name | User's email |
| Default show_on_leaderboard | true |
| Default categories on registration | Work, Study, Reading, Exercise, Meditation |

## Auth Model
There is **no session/token-based auth**. Endpoints that take `{email}` in the path are unprotected -- any caller who knows an email can read/modify that user's data. Login endpoints simply verify credentials and return user info. The app relies on obscurity / limited deployment rather than proper authorization.
