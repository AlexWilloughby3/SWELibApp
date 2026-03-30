# SWELibApp: Productivity Tracker — Application Plan

## 1. What This Is

A productivity tracker with a Lean 4 backend, Python test harness, and lightweight frontend. A **local provisioner** creates a GCE VM and deploys Docker containers to it via SSH. The **Lean server runs inside a Docker container on the VM**, serving HTTPS and connecting to a Postgres container on the same Docker network. A local supervisor process monitors VM and container health via the GCE API and SSH.

The formal specifications and the running application code live in the same language. This repo depends on SWELib for generic formalizations (HTTP, TLS, JWT, SQL, GCE, OAuth2, etc.) and adds app-specific specs in `spec/ProductivityTracker/`. The `spec/` layer states the properties; the `server/` layer implements them; trust boundaries are explicit (e.g., "Postgres implements the SQL semantics we've specified" — uses SWELib's bridge axioms).

---

## 2. System Architecture

```
LOCAL MACHINE                              GCE VM
┌───────────────────────┐                  ┌──────────────────────────────────┐
│  Provisioner /        │──HTTPS──────────▶│                                  │
│  Supervisor           │  (GCE API)       │  ┌──────────────┐               │
│  (Lean binary that    │──SSH────────────▶│  │ Lean server   │               │
│   creates VM,         │  (deploy,        │  │ container     │               │
│   deploys containers, │   health probes) │  │ (verified     │               │
│   monitors health)    │                  │  │  code, HTTPS  │──db:5432────┐ │
└───────────────────────┘                  │  │  :443/:8000)  │             │ │
                                           │  └──────────────┘             │ │
                                           │                               │ │
                                           │  ┌──────────────┐             │ │
                                           │  │ PostgreSQL    │◀────────────┘ │
                                           │  │ container     │               │
                                           │  │ :5432         │               │
                                           │  └──────────────┘               │
                                           │                                  │
                                           │  docker-compose.yml deployed     │
                                           │  via SCP, managed via SSH        │
                                           └──────────────────────────────────┘
                                                    ▲
                                                    │ HTTPS :443
                                                    │
                                           External Clients
                                           (test harness, future frontend)
```

### Communication Channels

Two separate concerns:

**Control plane** (local provisioner/supervisor → VM):
1. **HTTPS → GCE REST API** (`compute.googleapis.com`): VM lifecycle (create, start, stop, delete, get status). Authenticated via OAuth2 service account token.
2. **SSH → VM**: Container management (`docker compose up/down/restart/ps`), file transfer (`scp` for docker-compose.yml, Dockerfile), health probes (`pg_isready`, `curl`).

**Data plane** (Lean server container → Postgres container, both on VM):
- Docker compose network — the Lean container connects to `db:5432` (internal DNS). No SSH tunnels, no firewall rules for Postgres. Postgres is never exposed outside the VM.

---

## 3. Lifecycle Management & Supervisor

The Lean server doesn't just start containers and forget about them. It runs a **supervisor loop** — a background fiber that continuously monitors the health of every component and takes corrective action.

### 3.1 Startup Sequence

```
$ ./productivity-tracker deploy

1. Read config from environment / .env file
   (GCP_PROJECT, GCP_ZONE, GCP_SERVICE_ACCOUNT_KEY, JWT_SECRET_KEY, PG_PASSWORD, etc.)
2. Validate config (fail fast if required vars missing)
3. Authenticate to GCP:
   a. Parse service account JSON key
   b. Create a signed JWT for OAuth2 token exchange
   c. POST https://oauth2.googleapis.com/token → get access_token (1hr TTL)
4. Provision/verify GCE VM:
   a. GET /compute/v1/projects/{p}/zones/{z}/instances/{name}
      → If 404: create VM (POST with machine type, disk, SSH key metadata)
      → If TERMINATED: start VM (POST .../start)
      → If RUNNING: reuse
   b. Wait for VM to reach RUNNING state (poll every 2s, max 60s)
   c. Get VM external IP from instance metadata
5. Build and deploy containers via SSH:
   a. SCP docker-compose.yml, Dockerfile, .env, and compiled Lean binary to VM
   b. SSH: docker compose build (builds Lean server image)
   c. SSH: docker compose up -d  (Lean server + Postgres)
6. Wait for containers to be healthy:
   a. SSH: pg_isready until Postgres healthy (max 30s, then abort)
   b. SSH: curl -s https://localhost:443/health until 200 (max 10s, then abort)
      (Lean server runs migrations + seeds on startup, then reports healthy)
7. Log: "Deployed to {vm_ip}, server healthy on :443"
8. Start local supervisor loop (monitors VM + containers, see §3.2)
```

Note: The Lean server container handles its own startup internally:
- Connect to Postgres at `db:5432` (Docker network)
- Run schema migrations (idempotent — IF NOT EXISTS)
- Seed default roles/permissions (idempotent — ON CONFLICT DO NOTHING)
- Bind HTTPS :443, start accepting requests
- Report healthy on `/health`

### 3.2 Supervisor Loop

A local process that runs every N seconds (configurable, default 5s). This runs on your machine, not on the VM. It only uses the GCE API and SSH — it never handles user traffic.

```
loop forever:
  -- Refresh GCP OAuth2 token if near expiry (tokens last 1hr)
  if tokenExpiresWithin 5.minutes:
    accessToken ← refreshOAuth2Token(serviceAccountKey)

  -- Check VM is running
  vmStatus ← GET /compute/v1/.../instances/{name}
  if vmStatus ≠ RUNNING:
    log "VM not running (state: {vmStatus}), starting..."
    POST .../instances/{name}/start
    wait for RUNNING (poll, max 60s)

  -- Check Postgres container (via SSH)
  if not (ssh vm "docker compose exec db pg_isready -U productivity"):
    log "Postgres unhealthy, restarting container"
    ssh vm "docker compose restart db"
    wait for pg_isready via SSH (max 30s)

  -- Check Lean server container (via HTTPS to VM IP)
  if not (curl -s https://{vm_ip}/health = 200):
    log "Lean server unhealthy, restarting container"
    ssh vm "docker compose restart api"
    wait for /health 200 (max 10s)

  -- Check disk on VM
  diskUsage ← ssh vm "df /var/lib/docker --output=pcent | tail -1"
  if diskUsage > 90%:
    log "WARNING: VM disk at {diskUsage}% capacity"

  sleep supervisorInterval
```

### 3.3 Health Check Endpoints

The Lean server container exposes its own health:

```
GET /health          → 200 { "status": "healthy" }
                     → 503 { "status": "degraded", "issues": [...] }

GET /health/detailed → 200 {
  "server": "healthy",
  "postgres": "healthy" | "unhealthy" | "reconnecting",
  "uptime_seconds": 3600,
  "pg_connections_active": 5,
  "pg_connections_idle": 3
}
```

The simple `/health` endpoint is what the local supervisor checks, and what Docker's HEALTHCHECK uses. The detailed one is for operators.

### 3.4 Graceful Shutdown

Two levels of shutdown:

**Lean server container** (on SIGTERM inside the container):
```
1. Stop accepting new HTTP connections
2. Drain in-flight requests (timeout: 30s)
3. Close Postgres connection pool
4. Exit 0
```

**Local supervisor** (on SIGTERM/SIGINT on your machine):
```
1. Optionally: SSH into VM, docker compose down
2. Optionally: stop the GCE VM (POST .../instances/{name}/stop)
   — or leave it running to avoid cold-start on next deploy
3. Exit 0
```

On crash of either: The VM and its containers keep running (they're independent of the local process). On next `deploy`, the provisioner detects the VM is RUNNING and containers are up, and reattaches.

**Cost note**: A stopped VM incurs no compute charges (only disk). The `--stop-on-shutdown` config option controls whether the supervisor stops the VM on exit (saves money) or leaves it running (faster restart).

### 3.5 Crash Recovery

If the local supervisor crashes, on next `deploy`:

```
-- Check VM and container state
vmStatus ← GET /compute/v1/.../instances/{name}
if vmStatus = RUNNING:
  containerStatus ← ssh vm "docker compose ps --format json"
  if api + db are running and healthy:
    log "Already running, reattaching supervisor"
  if containers are in bad state:
    ssh vm "docker compose down && docker compose up -d"
    wait for health
elif vmStatus = TERMINATED:
  POST .../instances/{name}/start
  wait for RUNNING, then redeploy containers
elif vmStatus = 404:
  create VM from scratch
```

If the Lean server container crashes, Docker's `restart: unless-stopped` policy restarts it automatically. The supervisor also detects this via the `/health` check and can force a restart via SSH if needed.

The VM's persistent disk preserves Postgres data across VM stops/starts and container restarts.

### 3.6 What Gets Formalized

The supervisor (local process) is formalized in `spec/ProductivityTracker/Supervisor.lean`:

```
-- Liveness: if a container is unhealthy, supervisor eventually restarts it
theorem supervisor_restarts_unhealthy : ∀ state container,
  ¬containerHealthy state container →
  ∃ n, supervisorStep^n state = state' ∧ containerHealthy state' container

-- Safety: supervisor never takes down a healthy component
theorem supervisor_preserves_healthy : ∀ state component,
  healthy component state →
  supervisorStep state = state' →
  healthy component state'

-- Idempotency: migrations can run multiple times safely
theorem migrations_idempotent : ∀ schema,
  applyMigrations (applyMigrations schema) = applyMigrations schema
```

The server's own internal behavior (connect to PG, run migrations, serve requests) is formalized in `spec/ProductivityTracker/Invariants.lean` via ProductLayer proof obligations.

---

## 4. Python Test Harness

A separate Python project that acts as an adversarial client. Its job: **try to break the application**. If the API handles every test correctly, we have empirical evidence that the formal properties hold in practice.

### 4.1 Philosophy

The test suite is organized around the question: "What should NOT be possible?" Each test tries to do something the formalization says is impossible, and asserts that the server correctly rejects it.

### 4.2 Test Categories

#### Authentication Tests (`tests/test_auth.py`)
```python
# Happy path
def test_register_and_login():
    """Register → login → get valid JWT → access protected endpoint."""

def test_token_refresh():
    """Use refresh token to get new access token."""

# Attack surface
def test_expired_token_rejected():
    """Wait for token expiry, confirm 401."""

def test_malformed_jwt_rejected():
    """Send garbage in Authorization header."""

def test_tampered_jwt_rejected():
    """Modify JWT payload, keep old signature → 401."""

def test_wrong_password_rejected():
    """Login with wrong password → 401."""

def test_sql_injection_in_email():
    """Register with email = \"'; DROP TABLE users; --\" → rejected."""

def test_empty_password_rejected():
    """Register with empty password → 400."""

def test_duplicate_email_rejected():
    """Register twice with same email → 409."""
```

#### RBAC Tests (`tests/test_rbac.py`)
```python
def test_user_cannot_access_admin_endpoints():
    """Normal user hits /admin/* → 403."""

def test_user_cannot_read_other_users_data():
    """User A tries to read User B's sessions → 403."""

def test_user_cannot_escalate_own_role():
    """User tries PATCH /admin/users/{self}/roles → 403."""

def test_admin_can_access_admin_endpoints():
    """Admin hits /admin/* → 200."""

def test_unauthenticated_gets_401():
    """Hit protected endpoint with no token → 401."""
```

#### Data Integrity Tests (`tests/test_integrity.py`)
```python
def test_delete_user_cascades():
    """Delete user → their sessions, goals, categories all gone."""

def test_delete_category_cascades_sessions():
    """Delete category → sessions in that category gone."""

def test_goal_uniqueness():
    """Create same (user, category, goal_type) twice → 409."""

def test_category_uniqueness_per_user():
    """Same category name for same user → 409. Different user → OK."""

def test_session_duration_must_be_positive():
    """Create session with duration=0 → 400."""
    """Create session with duration=-1 → 400."""
```

#### Session Splitting Tests (`tests/test_sessions.py`)
```python
def test_midnight_split():
    """Create session crossing midnight → two records, durations sum correctly."""

def test_session_no_split_same_day():
    """Create session not crossing midnight → one record."""

def test_session_list_pagination():
    """Create 50 sessions, paginate with per_page=10 → 5 pages."""

def test_session_filter_by_date_range():
    """Filter sessions to a specific week → only those sessions returned."""
```

#### Stress & Resilience Tests (`tests/test_resilience.py`)
```python
def test_concurrent_registrations():
    """50 concurrent registration requests → no duplicates, no crashes."""

def test_concurrent_session_logging():
    """100 concurrent session creates for same user → all succeed, correct count."""

def test_large_payload_rejected():
    """Send 10MB JSON body → 413."""

def test_health_endpoint_under_load():
    """/health returns 200 even while other endpoints are busy."""

def test_postgres_restart_recovery():
    """docker compose restart db → server recovers, requests eventually succeed."""

def test_server_restart_preserves_data():
    """Create data → restart Lean server → data still there."""
```

#### Goal & Stats Tests (`tests/test_goals.py`, `tests/test_stats.py`)
```python
def test_checkbox_toggle_idempotent_within_day():
    """Toggle → complete. Toggle again → incomplete. Toggle → complete."""

def test_weekly_stats_correct():
    """Log known sessions → weekly stats match expected totals."""

def test_goal_progress_percentage():
    """Set 60min goal, log 30min → progress = 50%."""

def test_stats_exclude_other_users():
    """User A's stats don't include User B's sessions."""
```

### 4.3 Test Infrastructure

```
tests/
├── conftest.py              — Fixtures: base URL, create_user(), login(), auth_headers()
├── client.py                — Thin wrapper around requests with base URL and auth
├── test_auth.py
├── test_rbac.py
├── test_integrity.py
├── test_sessions.py
├── test_goals.py
├── test_stats.py
├── test_resilience.py
└── requirements.txt         — pytest, requests, pytest-asyncio, faker
```

**Key fixtures**:
```python
@pytest.fixture
def api():
    """API client pointed at the running server."""
    return ApiClient(base_url="http://localhost:8000/api/v1")

@pytest.fixture
def user(api):
    """Register a fresh user and return (email, password, tokens)."""
    email = f"test-{uuid4()}@example.com"
    password = "Test1234!@#$"
    api.post("/auth/register", json={"email": email, "password": password, "display_name": "Test"})
    tokens = api.post("/auth/login", json={"email": email, "password": password}).json()
    return {"email": email, "password": password, "tokens": tokens}

@pytest.fixture
def admin(api):
    """A user with admin role (seeded or promoted via direct DB)."""
    ...
```

### 4.4 Running Tests

```bash
# Start the application first
./productivity-tracker serve &

# Run all tests
cd tests && pytest -v

# Run specific category
pytest -v test_auth.py

# Run with parallel workers
pytest -v -n 4

# Run stress tests only
pytest -v -k "resilience"
```

---

## 5. Frontend

**Status: TBD.** The frontend will be a React/TypeScript SPA, vibe-coded separately. It is not a formalized component — just a consumer of the API.

### 5.1 Current Plan

The frontend will be built with React + TypeScript + Tailwind + Vite. The exact pages, components, and structure will be determined when we get to it. The API (Section 7) is the contract — the frontend just calls it.

### 5.2 Deployment (Future)

When the frontend exists, an **Nginx container** will be added to the docker-compose stack on the VM:
- Serves the React static build (`dist/`)
- Reverse-proxies `/api` requests to the Lean server container
- Handles TLS termination for the frontend

This is punted until the frontend is actually built. For now, the Lean server container is the only public-facing service on the VM. The test harness (Python) and any manual testing hit the Lean server directly.

### 5.3 What This Means for SWELib

Nothing. Nginx routing is not formalized. When we add the Nginx container, it's just a config file in docker-compose — no SWELib work needed.

---

## 6. Core Features

### 6.1 User System & Authentication

| Feature | Description |
|---------|-------------|
| **Registration** | Email + password. Password hashed with bcrypt before storage. |
| **Login** | Email + password → JWT access token (15 min) + refresh token (7 days). |
| **Token refresh** | Refresh token → new access token. |
| **Password storage** | Passwords hashed with bcrypt (cost factor 12). Only the hash is stored. |
| **Password change** | Authenticated endpoint. Old password required. |
| **Account deletion** | Authenticated. Cascades to all user data. |

### 6.2 Role-Based Access Control (RBAC)

Action-centric: every API endpoint declares which roles can invoke it.

```
Role: a named identity (e.g., "user", "admin")
Permission: an (action, resource, scope) triple (e.g., ("create", "session", "own"))
RoleBinding: maps Role → Set of Permissions
```

| Role | Permissions |
|------|------------|
| `user` | CRUD own sessions, goals, categories. Read own stats. Change own password. Delete own account. |
| `admin` | Everything `user` can do + read/modify any user's data, manage roles, view system stats. |

Extensibility: adding a new role = INSERT into `roles` + `role_permissions`. No code changes.

### 6.3 Database: PostgreSQL

Separate Postgres container. Lean server connects over TCP via the PostgreSQL wire protocol.

Formalization strategy is documented in `doc/sketches/07-postgres-formalization.md`: we formalize SQL semantics and schema invariants, trust libpq for the wire protocol and Postgres for SQL execution (bridge axiom pattern).

### 6.4 Productivity Features

#### Categories
- Default categories created on signup: **Work, Study, Exercise, Reading, Personal**
- Custom categories (max 20), rename, delete (cascading), toggle active/inactive

#### Focus Sessions
- Record: `(category, duration_seconds, started_at)`
- Immutable once created (no editing, only delete)
- Query by date range, category
- Midnight-crossing sessions split into two records

#### Goals
- **Time-based**: weekly target in minutes
- **Daily checkbox**: yes/no habit tracked daily
- **Weekly checkbox**: yes/no habit tracked weekly

#### Stats & Analytics
- Per-category: total time, session count, average session length, goal progress %
- Date range filtering, weekly summary, graph data (time series)

---

## 7. API Design

Base path: `/api/v1`

### Health
```
GET    /health                  — Simple health (200/503)
GET    /health/detailed         — Component-level health status
```

### Auth
```
POST   /auth/register          — Create account
POST   /auth/login             — Get JWT tokens
POST   /auth/refresh           — Refresh access token
```

### Users (authenticated)
```
GET    /users/me               — Get own profile
PATCH  /users/me               — Update display name, settings
DELETE /users/me               — Delete account
POST   /users/me/change-password — Change password
```

### Categories (authenticated)
```
POST   /users/me/categories              — Create category
GET    /users/me/categories              — List categories
PATCH  /users/me/categories/{id}         — Update category
DELETE /users/me/categories/{id}         — Delete category + cascade
```

### Sessions (authenticated)
```
POST   /users/me/sessions               — Log a focus session
GET    /users/me/sessions               — List sessions (filters + pagination)
DELETE /users/me/sessions/{id}          — Delete a session
```

### Goals (authenticated)
```
POST   /users/me/goals                  — Create/update a goal
GET    /users/me/goals                  — List all goals
GET    /users/me/goals/{category}       — Get goals for a category
DELETE /users/me/goals/{category}/{type} — Delete a goal
POST   /users/me/goals/{id}/toggle      — Toggle checkbox goal completion
```

### Stats (authenticated)
```
GET    /users/me/stats                  — Stats with date range query params
GET    /users/me/stats/weekly           — This week's summary
GET    /users/me/graph-data             — Time series for charting
```

### Admin (admin role required)
```
GET    /admin/users                     — List all users
GET    /admin/users/{id}                — Get any user's profile
PATCH  /admin/users/{id}/roles          — Assign/remove roles
GET    /admin/stats                     — System-wide stats
```

---

## 8. Database Schema

Stored in Postgres. Managed by the Lean server via migration SQL at startup.

```sql
CREATE TABLE users (
    id           UUID PRIMARY KEY,
    email        TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE roles (
    id   UUID PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE permissions (
    id       UUID PRIMARY KEY,
    action   TEXT NOT NULL,
    resource TEXT NOT NULL,
    scope    TEXT NOT NULL,
    UNIQUE(action, resource, scope)
);

CREATE TABLE role_permissions (
    role_id       UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE refresh_tokens (
    token      TEXT PRIMARY KEY,
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE categories (
    id         UUID PRIMARY KEY,
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    is_active  BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, name)
);

CREATE TABLE focus_sessions (
    id               UUID PRIMARY KEY,
    user_id          UUID REFERENCES users(id) ON DELETE CASCADE,
    category_id      UUID REFERENCES categories(id) ON DELETE CASCADE,
    duration_seconds INTEGER NOT NULL CHECK(duration_seconds > 0),
    started_at       TIMESTAMPTZ NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE goals (
    id             UUID PRIMARY KEY,
    user_id        UUID REFERENCES users(id) ON DELETE CASCADE,
    category_id    UUID REFERENCES categories(id) ON DELETE CASCADE,
    goal_type      TEXT NOT NULL CHECK(goal_type IN ('time_based', 'daily_checkbox', 'weekly_checkbox')),
    target_minutes INTEGER,
    description    TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, category_id, goal_type)
);

CREATE TABLE checkbox_completions (
    id             UUID PRIMARY KEY,
    goal_id        UUID REFERENCES goals(id) ON DELETE CASCADE,
    completed_date DATE NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(goal_id, completed_date)
);
```

---

## 9. Cloud Infrastructure

### 9.1 GCE VM Provisioning

The Lean server creates and manages a single GCE VM via the Compute Engine REST API. All API calls go to `https://compute.googleapis.com/compute/v1/projects/{project}/zones/{zone}/`.

**VM Specification**:

| Property | Value | Why |
|----------|-------|-----|
| Machine type | `e2-small` (2 vCPU, 2GB RAM) | Enough for Nginx + Postgres for a side project |
| Image | `debian-12` + Docker installed via startup script | More flexible than Container-Optimized OS (supports docker compose) |
| Disk | 20GB persistent SSD (`pd-ssd`) | Persists Postgres data across VM stops |
| Region | `us-central1-a` (configurable) | Low cost |
| Firewall | Allow TCP :80, :443 from 0.0.0.0/0 (HTTP/HTTPS) | Public web traffic to Nginx |
| SSH | Project-level SSH key in instance metadata | Lean server SSHs in to manage containers |

**GCE API Calls Used**:

```
-- VM lifecycle
POST   /instances                    — Create VM
POST   /instances/{name}/start       — Start stopped VM
POST   /instances/{name}/stop        — Stop VM (preserves disk)
DELETE /instances/{name}             — Delete VM
GET    /instances/{name}             — Get VM status + external IP

-- Firewall (one-time setup)
POST   /global/firewalls             — Create firewall rule for :80/:443

-- Auth
POST   https://oauth2.googleapis.com/token  — Exchange service account JWT for access token
```

**OAuth2 Authentication Flow**:

The Lean server authenticates to GCP using a service account key (JSON file):

```
1. Read service_account.json (has private_key, client_email)
2. Create a JWT:
   header: {"alg": "RS256", "typ": "JWT"}
   claims: {
     "iss": client_email,
     "scope": "https://www.googleapis.com/auth/compute",
     "aud": "https://oauth2.googleapis.com/token",
     "iat": now, "exp": now + 3600
   }
3. Sign JWT with RS256 using the private key (FFI to OpenSSL)
4. POST https://oauth2.googleapis.com/token
   grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion={signed_jwt}
5. Response: {"access_token": "ya29...", "expires_in": 3600}
6. Use access_token in Authorization: Bearer header for all GCE API calls
7. Refresh before expiry (supervisor loop handles this)
```

**VM Startup Script** (passed as instance metadata, runs on first boot):

```bash
#!/bin/bash
apt-get update
apt-get install -y docker.io docker-compose-plugin
systemctl enable docker
usermod -aG docker $USER
```

### 9.2 Docker Compose on the VM

The local provisioner SCPs this file (plus the Lean binary and Dockerfile) to the VM and runs `docker compose up -d` via SSH.

```yaml
# docker-compose.yml (deployed to VM via SCP)
services:
  api:
    build: .                    # Dockerfile for the Lean server
    ports:
      - "443:443"               # HTTPS — public-facing
      - "8000:8000"             # HTTP — for health checks / dev
    environment:
      - PG_HOST=db
      - PG_PORT=5432
      - PG_USER=productivity
      - PG_PASSWORD=${PG_PASSWORD}
      - PG_DB=productivity
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8000/health || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 10
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    # No published ports — only accessible from the Docker network
    volumes:
      - pg-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=productivity
      - POSTGRES_PASSWORD=${PG_PASSWORD}
      - POSTGRES_DB=productivity
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U productivity"]
      interval: 2s
      timeout: 5s
      retries: 10
    restart: unless-stopped

volumes:
  pg-data:
```

```dockerfile
# Dockerfile (deployed to VM alongside the compiled Lean binary)
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y libpq5 libssl3 ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY productivity-tracker /usr/local/bin/
EXPOSE 443 8000
CMD ["productivity-tracker", "serve"]
```

The Lean server container and Postgres container share a Docker network. The `api` container connects to Postgres at `db:5432` — no SSH tunnels, no firewall rules for the database. Postgres is never exposed outside the VM.

### 9.3 Networking

Simple — everything runs on the same VM in Docker containers:

```
Internet → :443 → Lean server container (HTTPS, TLS termination)
                        │
                        └── db:5432 → Postgres container (Docker internal network)
```

- **Postgres is never exposed** — no published ports, no firewall rule for :5432. Only the `api` container can reach it via Docker DNS (`db:5432`).
- **The Lean server handles TLS** directly (using SWELib's TLS implementation). No Nginx needed for the API.
- **GCE firewall** only allows TCP :443 from `0.0.0.0/0` (HTTPS to Lean server).
- **SSH** is only used by the local provisioner/supervisor for control plane operations (deploy, restart, health probes). It is not part of the data path.

**Future (when frontend exists)**: Add an Nginx container that serves static files and proxies `/api` to the `api` container. At that point, Nginx handles TLS for the frontend, and the Lean server can drop to plain HTTP behind Nginx (internal Docker network).

### 9.4 What Gets Formalized

The infrastructure adds these to the formalization:

- **GCE API contract** (`spec/SWELib/Cloud/Gce/`): VM lifecycle state machine (PROVISIONING → STAGING → RUNNING → STOPPING → TERMINATED), API request/response schemas
- **OAuth2 service account flow** (`spec/SWELib/Security/OAuth2/`): JWT creation for token exchange, token refresh lifecycle
- **SSH as a trust boundary** (`bridge/`): We trust that SSH delivers commands faithfully to the VM. Axiomatized, not proven. (SSH is control-plane only — deploy, restart, health probes.)
- **Docker networking as a trust boundary**: We trust that Docker DNS resolves `db` to the Postgres container and that the internal network is isolated. Axiomatized.
- **Existing SWELib specs used**: `Networking.Http` (API serving + GCE API calls), `Networking.Tls` (HTTPS termination + HTTPS to GCE API), `Security.Jwt` (app auth + OAuth2 JWT creation), `Db.Sql` (query semantics)

---

## 10. Project Structure

```
SWELibApp/
├── plan.md                          — This file
├── docker-compose.yml               — Deployed to VM (api + db containers)
├── Dockerfile                       — Builds Lean server container image
├── .env.example
│
├── server/                          — Lean project (the application server)
│   ├── lakefile.lean                — Depends on SWELib + SWELibCode
│   ├── lean-toolchain
│   ├── Server.lean                  — Root import
│   ├── Server/
│   │   ├── Main.lean               — Entry point (connect to PG, migrate, serve)
│   │   ├── Config.lean             — Environment config parsing
│   │   │
│   │   ├── Http/                   — HTTP server layer
│   │   │   ├── Server.lean         — Socket listener, TLS, request parsing
│   │   │   ├── Router.lean         — Route matching, dispatch
│   │   │   ├── Request.lean        — HTTP request type
│   │   │   ├── Response.lean       — HTTP response builder
│   │   │   └── Middleware.lean     — Auth + RBAC middleware chain
│   │   │
│   │   ├── Domain/                 — Business logic (pure Lean, no IO)
│   │   │   ├── User.lean
│   │   │   ├── Category.lean
│   │   │   ├── Session.lean        — Focus session logic, midnight splitting
│   │   │   ├── Goal.lean
│   │   │   └── Stats.lean
│   │   │
│   │   ├── Handlers/               — Route handlers (IO glue)
│   │   │   ├── Auth.lean
│   │   │   ├── Users.lean
│   │   │   ├── Categories.lean
│   │   │   ├── Sessions.lean
│   │   │   ├── Goals.lean
│   │   │   ├── Stats.lean
│   │   │   ├── Admin.lean
│   │   │   └── Health.lean
│   │   │
│   │   └── Db/                     — App-specific database code
│   │       ├── Migrations.lean     — Schema migration SQL
│   │       ├── Queries.lean        — Parameterized query builders
│   │       └── Seed.lean           — Default roles, permissions
│   │
│   └── ffi/                        — C code for FFI (if not covered by SWELib)
│       └── (minimal — SWELib provides libpq, libssl, bcrypt FFI)
│
├── provisioner/                     — Local tool: deploy + supervise (separate Lean binary)
│   ├── Provisioner.lean
│   ├── Provisioner/
│   │   ├── Main.lean               — Entry point (deploy or supervise subcommand)
│   │   ├── Gce.lean                — GCE REST API client (uses SWELibCode.Cloud.GcpClient)
│   │   ├── Deploy.lean             — SCP files to VM, docker compose up
│   │   └── Supervisor.lean         — Health check loop, restart, token refresh
│   └── lakefile.lean               — Depends on SWELib
│
├── frontend/                       — React/TypeScript SPA (TBD — vibe-coded later)
│   └── (structure determined when frontend work begins)
│       (when built: add Nginx container to docker-compose for
│        static file serving + /api reverse proxy to Lean server)
│
├── tests/                          — Python test harness
│   ├── requirements.txt            — pytest, requests, pytest-xdist, faker
│   ├── conftest.py                 — Fixtures: api client, user creation, auth
│   ├── client.py                   — API client wrapper
│   ├── test_auth.py                — Auth attack surface tests
│   ├── test_rbac.py                — Permission boundary tests
│   ├── test_integrity.py           — Data integrity / cascade tests
│   ├── test_sessions.py            — Session CRUD + midnight splitting
│   ├── test_goals.py               — Goal lifecycle + checkbox toggle
│   ├── test_stats.py               — Stats correctness
│   └── test_resilience.py          — Stress, concurrency, crash recovery
│
└── spec/                           — App-specific formalizations (imports SWELib)
    └── ProductivityTracker/
        ├── Types.lean              — Domain types
        ├── Auth.lean               — JWT lifecycle, password hashing
        ├── Rbac.lean               — Role/permission model, access control proofs
        ├── Schema.lean             — DB schema, referential integrity
        ├── Endpoints.lean          — API endpoint specs
        ├── Invariants.lean         — Cross-cutting invariants
        ├── SessionSplitting.lean   — Midnight split correctness
        ├── Supervisor.lean         — Liveness/safety of supervisor loop
        └── Infra.lean              — VM provisioning, SSH trust, container topology

    NOTE: App specs import from SWELib (e.g., `import SWELib.Security.Jwt`,
    `import SWELib.Cloud.Gce`, `import SWELib.Networking.Http`). Generic
    formalizations (GCE API, OAuth2, SSH) live in SWELib itself, not here.
    Only app-specific properties (schema invariants, RBAC model, session
    splitting) live in this repo.
```

---

## 11. Application Invariants

Properties the application must maintain. These are formalized in `spec/ProductivityTracker/Invariants.lean` and tested empirically by the Python test harness.

### Authentication

- **Expired tokens rejected**: A JWT whose `exp` claim is in the past is always rejected with 401. The server never processes a request with an expired token.
- **Tampered tokens rejected**: If a JWT's signature doesn't match `hmac(header ++ payload, secret)`, it's rejected. Modifying any byte of the payload invalidates the token.
- **Password not recoverable**: Given a bcrypt hash, there's no efficient way to recover the original password. (Cryptographic hardness — axiomatized in bridge/.)
- **Refresh token rotation**: When a refresh token is used, the old one is invalidated. A stolen refresh token can only be used once.
- **No plaintext passwords in storage**: The raw password string from a request body is never written to the database. Only bcrypt output is stored.

### Access Control

- **Default deny**: If a user has no role granting a permission, the request is denied (403). There is no "allow unless explicitly denied" path.
- **No self-escalation**: A user without the "manage roles" permission cannot grant themselves (or anyone) new roles.
- **Scope enforcement**: A user with `scope: "own"` on a resource can only access records where `owner_id = user.id`. The handler queries are always filtered by user ID.
- **Admin superset**: The admin role's permissions are a strict superset of the user role's permissions. An admin can do everything a user can.

### Data Integrity

- **Cascade completeness**: Deleting a user removes all their sessions, goals, categories, checkbox completions, and refresh tokens. No orphaned rows.
- **Goal uniqueness**: At most one goal per `(user, category, goal_type)` combination. Enforced by UNIQUE constraint and ON CONFLICT handling.
- **Session duration positive**: Every focus session has `duration_seconds > 0`. Enforced by CHECK constraint and input validation.
- **Category ownership**: A session's category always belongs to the same user as the session. The handler only queries categories owned by the authenticated user.
- **Category cap**: A user can have at most 20 categories. Enforced by a count check before INSERT.

### Session Splitting

- **Split preserves total duration**: If a session crosses midnight and is split into two records, `a.duration + b.duration = original.duration`. No time is lost or gained.
- **Split produces adjacent days**: The two resulting sessions are on consecutive calendar days.
- **No split when same day**: A session that starts and ends on the same day is stored as a single record.

### Supervisor

- **Healthy components preserved**: The supervisor never restarts or disrupts a component that is currently healthy.
- **Unhealthy Postgres eventually restarted**: If Postgres fails a health check, the supervisor will attempt reconnection, then container restart. Under fairness (the container runtime eventually responds), Postgres is eventually restored.
- **Migrations idempotent**: Running migrations multiple times produces the same schema as running them once. All CREATE TABLE uses IF NOT EXISTS; all seed INSERTs use ON CONFLICT DO NOTHING.
- **Crash recovery**: If the Lean server crashes and restarts, it detects already-running containers and reattaches rather than starting duplicates.

### Infrastructure

- **Postgres is never externally reachable**: No published ports on the Postgres container. Only the Lean server container can reach it via Docker internal network (`db:5432`). External traffic goes to the Lean server on :443.
- **Database persists across VM stops**: The Postgres data directory is on a Docker named volume on the VM's persistent disk. VM stop/start cycles and container restarts preserve all data.
- **VM lifecycle is recoverable**: If the VM is TERMINATED (manually stopped, preempted, or crashed), the local supervisor detects this and re-starts it. If the VM is deleted, the supervisor creates a new one and re-deploys.
- **Container auto-restart**: Docker's `restart: unless-stopped` policy handles transient container crashes. The supervisor handles deeper failures (VM down, containers in bad state).
- **OAuth2 tokens are refreshed**: The local supervisor refreshes the GCP access token before its 1hr expiry. GCE API calls never fail due to token expiration during normal operation.

---

## 12. Implementation Order

### Phase 1: Lean Server Container (runs on VM)
1. `server/lakefile.lean` with SWELib dependency (both `SWELib` spec and `SWELibCode`)
2. Basic HTTP/HTTPS server (using `SWELibCode.Networking.HttpServer`, hardcoded 200)
3. Connect to Postgres at `db:5432` (Docker network, using `SWELibCode.Db.PgClient`)
4. Dockerfile + docker-compose.yml (api + db containers)
5. Migration runner + seed script (app-specific SQL)

### Phase 2: Auth & RBAC
6. Password hashing (bcrypt via `SWELibCode.Security.HashOps`)
7. JWT create/validate (via `SWELibCode.Security.JwtValidator`)
8. Auth middleware + RBAC middleware
9. Auth handlers (register, login, refresh)
10. Health endpoints (`/health`, `/health/detailed`)

### Phase 3: Core Features
11. Category handlers (CRUD)
12. Session handlers (create with midnight split, list, delete)
13. Goal handlers (create, list, delete, checkbox toggle)
14. Stats handlers
15. Admin handlers

### Phase 4: Provisioner + Supervisor (runs locally)
16. `provisioner/` — separate Lean binary
17. OAuth2 service account authentication (JWT creation + token exchange)
18. GCE API client (create/start/stop/get VM)
19. SSH/SCP deploy (docker-compose.yml, Dockerfile, binary → VM)
20. Supervisor loop (health checks via HTTPS + SSH, container restart, token refresh)
21. Graceful shutdown (optionally stop VM)
22. Crash recovery (detect running VM + reattach)

### Phase 5: Python Test Harness
23. Test infrastructure (conftest, client, fixtures)
24. Auth tests (happy path + attack surface)
25. RBAC tests (permission boundaries)
26. Data integrity tests (cascades, uniqueness)
27. Session + goal + stats tests
28. Resilience tests (concurrency, restart recovery)

### Phase 6: Frontend (TBD — vibe-coded separately)
29. React + TypeScript + Tailwind SPA
30. Add Nginx container to docker-compose (static files + /api proxy)
31. Structure and details determined when this phase begins

### Phase 7: Formalization

**In SWELib repo** (upstream — generic specs the app depends on):
32. Flesh out `Security/Oauth.lean` — OAuth2 grant types, JWT-bearer flow for service accounts
33. Flesh out `Cloud/Gcp.lean` → create `Cloud/Gce/` — VM lifecycle state machine, API contracts
34. Create `Networking/Ssh/` — SSH connection types, command execution semantics
35. Create `bridge/SWELibBridge/Ssh.lean` — SSH trust axiom
36. Flesh out `Security/Rbac` — generic RBAC model
37. Flesh out `Db/Transactions` — ACID transaction semantics
38. Extend `Security/Hashing` — bcrypt password hashing

**In SWELibApp repo** (app-specific specs, imports SWELib):
39. Domain types in `spec/ProductivityTracker/Types.lean`
40. Auth properties (JWT lifecycle, password hashing)
41. RBAC model (default deny, no escalation, monotonicity)
42. Schema invariants (referential integrity, cascades)
43. Session splitting correctness
44. Supervisor properties (liveness, safety, idempotent migrations)
45. Infrastructure properties (VM provisioning, container topology)
46. Bridge axioms: Postgres implements SQL semantics (uses SWELib's libpq bridge)

---

## 13. Tech Decisions Summary

| Decision | Choice | Why |
|----------|--------|-----|
| Server language | Lean 4 | Same language for spec and implementation |
| Server deployment | Docker container on GCE VM | Verified code runs on the VM, not locally |
| Frontend | React + TypeScript + Tailwind (TBD) | Vibe-coded later, not formalized |
| Test harness | Python + pytest | Easy to write adversarial HTTP tests quickly |
| HTTP server | Built from scratch in Lean | Simple; uses SWELib types directly |
| TLS termination | Lean server (SWELib TLS) | Server handles HTTPS directly, no Nginx needed for API |
| Database | PostgreSQL 16 | Proper RDBMS; formalized at wire boundary |
| DB connectivity | Docker network (`db:5432`) | Lean + PG containers on same compose network, no SSH tunnel |
| DB client | libpq via FFI | Battle-tested C library |
| Auth | JWT (HS256 for app, RS256 for GCP OAuth2) | SWELib has JWT formalization |
| Hashing | bcrypt (cost 12) | Industry standard |
| Cloud provider | Google Compute Engine | Major provider, REST API, formalizeable VM lifecycle |
| Infra management | GCE API (HTTPS) + SSH (control plane only) | SSH for deploy/restart/health; not on data path |
| VM image | Debian 12 + Docker | Supports docker compose, flexible |
| Container orchestration | Docker Compose on single VM | Simple, no K8s overhead — Lean server + Postgres |
| Proxy | Nginx (future, for frontend only) | Punted — only needed when React frontend is built |
| IDs | UUID v4 | SWELib has UUID formalization |
| PG trust model | SQL semantics + libpq trust axiom | See `doc/sketches/07-postgres-formalization.md` |
| Docker network trust | Internal DNS resolves correctly | Axiomatized — Docker network is trusted |
| SSH trust model | Commands delivered faithfully | Axiomatized bridge — SSH is trusted transport (control plane) |
| GCE trust model | API conforms to documented spec | Axiomatized bridge — GCE is trusted infra provider |

---

## 14. Typeclass Layer Architecture

The **server** (which runs on the VM) is organized as a stack of typeclasses. The **provisioner/supervisor** (which runs locally) is a separate binary outside this layer stack. Each layer is a pure interface — it declares methods and proof obligations in its own domain language, with zero knowledge of the layers below it. Layers are connected through instance declarations in separate glue modules.

### 14.1 The Layer Stack

The **server** (runs on VM in a Docker container) uses two layers:

```
ProductLayer    — domain: users, auth, sessions, goals, stats, RBAC
    ↓ depends on
DataLayer       — storage: queries, transactions, connection management
```

The **provisioner/supervisor** (runs locally) is a separate binary that uses:

```
InfraLayer      — runtime: VMs, containers, SSH, OAuth2 tokens
    ↓ depends on
CILayer         — foundation: migrations, deployment, rollback
```

Each arrow means "the higher layer's instance declaration requires the lower layer as a typeclass precondition." A layer can only call methods from the layer directly below it — never skip levels. The dependency is declared per-instance, not per-typeclass: the typeclass definitions are fully independent and share no imports.

The server never imports InfraLayer or CILayer — it doesn't know about VMs, SSH, or deployment. The provisioner never imports ProductLayer or DataLayer — it doesn't know about users, sessions, or SQL queries.

### 14.2 Layer Definitions

#### CILayer — Foundation

Handles deployment primitives: running schema migrations, deploying artifacts to environments, and rolling back. Everything above this assumes migrations and deploys work correctly.

```lean
class CILayer (ctx : Type) where
  -- Methods
  runMigration    : ctx → Migration → IO MigrationResult
  deployArtifact  : ctx → Artifact → Environment → IO DeployResult
  rollback        : ctx → Environment → Version → IO RollbackResult
  currentVersion  : ctx → Environment → IO Version

  -- Proof obligations
  migrations_idempotent : ∀ c m,
    runMigration c m >> runMigration c m ≈ runMigration c m
  rollback_restores : ∀ c env v artifact,
    deployArtifact c artifact env >> rollback c env v →
    currentVersion c env = pure v
  deploy_monotonic : ∀ c artifact env,
    let v₀ ← currentVersion c env
    deployArtifact c artifact env >>
    let v₁ ← currentVersion c env
    v₁ > v₀
```

#### InfraLayer — Runtime Environment

Manages GCE VMs, Docker containers, SSH connections, OAuth2 tokens. Depends on CILayer for deploying compose files and running migrations on provisioned VMs.

```lean
class InfraLayer (ctx : Type) where
  -- VM lifecycle
  provisionVM      : ctx → VMConfig → IO VMInstance
  startVM          : ctx → VMId → IO VMStatus
  stopVM           : ctx → VMId → IO VMStatus
  getVMStatus      : ctx → VMId → IO VMStatus

  -- Container management
  deployContainers : ctx → VMInstance → ComposeFile → IO Unit
  restartContainer : ctx → VMInstance → ContainerName → IO Unit
  containerHealth  : ctx → VMInstance → ContainerName → IO HealthStatus

  -- Auth to cloud provider
  refreshToken     : ctx → IO Token
  tokenValid       : ctx → IO Bool

  -- Proof obligations
  vm_recoverable : ∀ c vmId,
    getVMStatus c vmId = pure .terminated →
    startVM c vmId >> getVMStatus c vmId = pure .running
  healthy_preserved : ∀ c vm container,
    containerHealth c vm container = pure .healthy →
    supervisorStep c →
    containerHealth c vm container = pure .healthy
  token_refresh_before_expiry : ∀ c,
    ¬tokenValid c → refreshToken c >> tokenValid c = pure true
```

#### DataLayer — Storage

Executes queries against Postgres, manages transactions and connection state. Depends on InfraLayer for the underlying VM/container being up and the SSH tunnel or network path existing.

```lean
class DataLayer (ctx : Type) where
  -- Query execution
  execQuery       : ctx → Query → IO ResultSet
  execInsert      : ctx → Query → IO (Option RowId)
  execUpdate      : ctx → Query → IO Nat  -- rows affected
  execDelete      : ctx → Query → IO Nat  -- rows affected

  -- Transactions
  withTransaction : ctx → (ctx → IO α) → IO α

  -- Connection management
  isConnected     : ctx → IO Bool
  reconnect       : ctx → IO Unit

  -- Proof obligations
  transaction_atomicity : ∀ c (f : ctx → IO α),
    withTransaction c f either fully commits all writes or commits none
  query_parameterized : ∀ c q,
    execQuery c q does not permit SQL injection
    (query values are always bound parameters, never interpolated)
  reconnect_idempotent : ∀ c,
    isConnected c = pure true → reconnect c preserves connection state
```

#### ProductLayer — Domain

The top-level interface. Speaks entirely in domain terms: users, sessions, goals, categories, stats, auth, RBAC. No mention of SQL, VMs, containers, tokens, or connections anywhere in this typeclass. A product agent works exclusively at this level.

```lean
class ProductLayer (ctx : Type) where
  -- Auth
  register        : ctx → Email → Password → DisplayName → IO User
  login           : ctx → Email → Password → IO (Option TokenPair)
  validateToken   : ctx → Token → IO (Option User)
  refreshAuth     : ctx → RefreshToken → IO (Option TokenPair)
  changePassword  : ctx → UserId → Password → Password → IO Bool

  -- RBAC
  authorize       : ctx → User → Permission → IO Bool
  grantRole       : ctx → UserId → RoleName → IO (Result RbacError Unit)
  userPermissions : ctx → UserId → IO (List Permission)

  -- Categories
  createCategory  : ctx → UserId → CategoryName → IO (Result DomainError Category)
  listCategories  : ctx → UserId → IO (List Category)
  deleteCategory  : ctx → UserId → CategoryId → IO (Result DomainError Unit)

  -- Sessions
  logSession      : ctx → UserId → CategoryId → Duration → StartTime → IO (List Session)
  listSessions    : ctx → UserId → DateRange → PageParams → IO (Page Session)
  deleteSession   : ctx → UserId → SessionId → IO (Result DomainError Unit)

  -- Goals
  createGoal      : ctx → UserId → CategoryId → GoalType → IO (Result DomainError Goal)
  toggleGoal      : ctx → UserId → GoalId → Date → IO Bool
  goalProgress    : ctx → UserId → CategoryId → DateRange → IO GoalProgress

  -- Stats
  userStats       : ctx → UserId → DateRange → IO Stats
  weeklySummary   : ctx → UserId → IO WeeklySummary
  graphData       : ctx → UserId → DateRange → IO (List DataPoint)

  -- Proof obligations: ALL stated in domain language

  -- Auth invariants
  expired_rejected : ∀ c t,
    isExpired t → validateToken c t = pure none
  tampered_rejected : ∀ c t,
    ¬validSignature t → validateToken c t = pure none
  no_plaintext_storage : ∀ c email pw name,
    register c email pw name does not write pw to any persistent store
  refresh_invalidates_old : ∀ c rt,
    refreshAuth c rt = pure (some newPair) →
    refreshAuth c rt = pure none  -- old token is consumed

  -- RBAC invariants
  default_deny : ∀ c u p,
    ¬hasRoleGranting u p → authorize c u p = pure false
  no_self_escalation : ∀ c uid role,
    ¬(authorize c uid "manage_roles") →
    grantRole c uid role = pure (Err .forbidden)
  admin_superset : ∀ c u p,
    isAdmin u → authorize c u p = pure true

  -- Data integrity invariants
  category_cap : ∀ c uid name,
    (listCategories c uid).length ≥ 20 →
    createCategory c uid name = pure (Err .limitReached)
  category_ownership : ∀ c uid catId dur start,
    ¬ownsCategory uid catId →
    logSession c uid catId dur start = pure (Err .notFound)
  cascade_complete : ∀ c uid,
    deleteUser c uid removes all sessions, goals, categories,
    checkbox completions, and refresh tokens for uid
  session_duration_positive : ∀ c uid cat dur start,
    dur ≤ 0 → logSession c uid cat dur start = pure (Err .invalidDuration)

  -- Session splitting invariants
  split_preserves_duration : ∀ c uid cat dur start,
    crossesMidnight start dur →
    let sessions ← logSession c uid cat dur start
    sumDurations sessions = dur
  split_adjacent_days : ∀ c uid cat dur start,
    crossesMidnight start dur →
    let [s₁, s₂] ← logSession c uid cat dur start
    s₂.date = s₁.date.addDays 1
  no_split_same_day : ∀ c uid cat dur start,
    ¬crossesMidnight start dur →
    (logSession c uid cat dur start).length = 1
```

### 14.3 Context Structures — The Concrete Runtime

Each binary has its own context. They are not layers — they are bags of mutable state.

**Server** (on VM):
```lean
structure AppContext where
  pgConn : IORef PgConnection
  config : AppConfig   -- JWT_SECRET, PG_HOST, etc.
```

**Provisioner** (local):
```lean
structure ProvisionerContext where
  oauthToken : IORef Token
  config     : ProvisionerConfig   -- GCP_PROJECT, GCP_ZONE, SSH key, etc.
  vmInstance : IORef (Option VMInstance)
```

### 14.4 Instance Chain — The Glue

Each layer is implemented in a separate glue file. The glue is the **only** code that imports two adjacent layers.

**Server glue** (on VM):
```
server/Glue/
├── DataFromContext.lean     — instance : DataLayer AppContext (uses SWELibCode.Db.PgClient)
└── ProductFromData.lean     — instance [DataLayer AppContext] : ProductLayer AppContext
```

**Provisioner glue** (local):
```
provisioner/Glue/
├── CIFromContext.lean       — instance : CILayer ProvisionerContext
└── InfraFromCI.lean         — instance [CILayer ProvisionerContext] : InfraLayer ProvisionerContext
```

**DataFromContext.lean** — The server's bottom layer. Directly uses `AppContext.pgConn` to execute queries. No InfraLayer dependency — the server trusts that Postgres is reachable at `db:5432` (Docker handles this).

```lean
instance : DataLayer AppContext where
  execQuery ctx query := do
    let conn ← ctx.pgConn.get
    SWELibCode.Db.PgClient.exec conn query
  withTransaction ctx f := do
    let conn ← ctx.pgConn.get
    SWELibCode.Db.PgClient.exec conn "BEGIN"
    try
      let result ← f ctx
      SWELibCode.Db.PgClient.exec conn "COMMIT"
      pure result
    catch e =>
      SWELibCode.Db.PgClient.exec conn "ROLLBACK"
      throw e
  reconnect ctx := do
    let conn ← SWELibCode.Db.PgClient.connect ctx.config.pgConnString
    ctx.pgConn.set conn
  ...
```

**ProductFromData.lean** — Uses DataLayer to store/retrieve domain objects. Implements all product logic: auth, RBAC, sessions, goals, stats. Proves all product-layer invariants using knowledge of the queries.

```lean
instance [DataLayer AppContext] : ProductLayer AppContext where
  register ctx email password displayName := do
    let hash ← SWELibCode.Security.HashOps.bcryptHash password
    let id ← DataLayer.execInsert ctx (insertUserQuery email hash displayName)
    let _ ← DataLayer.execInsert ctx (assignDefaultRoleQuery id)
    let _ ← DataLayer.execInsert ctx (seedDefaultCategoriesQuery id)
    pure { id, email, displayName }

  logSession ctx userId catId duration startTime := do
    if crossesMidnight startTime duration then
      let (d1, d2) := splitAtMidnight startTime duration
      DataLayer.withTransaction ctx fun ctx => do
        let s1 ← DataLayer.execInsert ctx (insertSessionQuery userId catId d1.duration d1.start)
        let s2 ← DataLayer.execInsert ctx (insertSessionQuery userId catId d2.duration d2.start)
        pure [s1, s2]
    else
      let s ← DataLayer.execInsert ctx (insertSessionQuery userId catId duration startTime)
      pure [s]

  split_preserves_duration := by
    intro c uid cat dur start hcross
    simp [logSession, hcross, splitAtMidnight]
    exact splitAtMidnight_sum_eq dur start
  ...
```

**CIFromContext.lean** (provisioner) — Uses SSH/SCP to deploy and run migrations remotely.

```lean
instance : CILayer ProvisionerContext where
  runMigration ctx migration := do
    SWELibCode.OS.ProcessOps.exec "ssh" [ctx.vmHost, migrationToSQL migration]
  deployArtifact ctx artifact env := do
    SWELibCode.OS.ProcessOps.exec "scp" [artifact.path, envToHost env]
    SWELibCode.OS.ProcessOps.exec "ssh" [envToHost env, "docker compose up -d"]
  ...
```

**InfraFromCI.lean** (provisioner) — Uses CILayer + GCE API for VM lifecycle.

```lean
instance [CILayer ProvisionerContext] : InfraLayer ProvisionerContext where
  provisionVM ctx cfg := do
    let vm ← SWELibCode.Cloud.GcpClient.createInstance (← ctx.oauthToken.get) cfg
    CILayer.deployArtifact ctx (composeArtifact cfg) (vmToEnv vm)
    pure vm
  refreshToken ctx := do
    let tok ← SWELibCode.Cloud.GcpClient.exchangeServiceAccountJwt ctx.config.saKey
    ctx.oauthToken.set tok; pure tok
  ...
```

### 14.5 Who Works Where

**Server** (on VM):

| Role | Sees | Doesn't see |
|------|------|-------------|
| Product agent | `ProductLayer` typeclass, domain types | SQL, VMs, containers, SSH, OAuth |
| Data agent | `DataLayer` typeclass, `ProductFromData.lean` glue, query builders | VMs, containers, SSH, OAuth |

**Provisioner** (local):

| Role | Sees | Doesn't see |
|------|------|-------------|
| Infra agent | `InfraLayer` typeclass, GCE/SSH/Docker code | Domain logic, RBAC, SQL queries |
| CI/deploy agent | `CILayer` typeclass, migration runner | Everything above |

A product agent changes a spec (e.g., "sessions now track location"). They modify `ProductLayer` only — adding a `Location` parameter to `logSession` and a new proof obligation. The compiler then fails in `ProductFromData.lean` (the glue), which is the data agent's problem. The data agent updates the query and the glue. If a schema migration is needed, they add it to `Db/Migrations.lean`. Each agent works in isolation; the compiler is the coordination mechanism.

The provisioner is completely decoupled — it doesn't even share a Lean project with the server. Changing business logic never touches the provisioner. Changing cloud providers never touches the server.

### 14.6 Swapping Implementations

Replacing Postgres with SQLite means:
1. Write a new `DataFromContext.lean` that calls SQLite instead of libpq
2. Re-prove the `DataLayer` proof obligations for SQLite semantics
3. **Nothing else changes.** `ProductLayer`, `ProductFromData.lean` — all untouched

Replacing GCE with AWS EC2 means:
1. Write a new provisioner that calls EC2 API instead of GCE API
2. Re-prove the `InfraLayer` proof obligations for EC2's state machine
3. **The server is completely untouched.** ProductLayer and DataLayer don't know about the cloud provider.

The typeclass boundary is the swap point. Everything above the boundary is insulated.

### 14.7 Updated Project Structure

Two separate Lean projects reflecting the split:

```
server/Server/                   — THE SERVER (runs on VM in Docker container)
├── Main.lean                    — Entry point: connect to PG, migrate, seed, serve HTTPS
├── Config.lean                  — Environment config parsing (PG_HOST, JWT_SECRET, etc.)
├── AppContext.lean              — Runtime state (PG connection, config)
│
├── Layers/                      — Typeclass definitions (pure interfaces)
│   ├── Data.lean                — class DataLayer
│   └── Product.lean             — class ProductLayer
│
├── Glue/                        — Instance declarations
│   ├── DataFromContext.lean     — instance : DataLayer AppContext (uses SWELibCode.Db.PgClient)
│   └── ProductFromData.lean     — instance [DataLayer _] : ProductLayer AppContext
│
├── Domain/                      — Pure domain types and logic (no IO)
│   ├── User.lean
│   ├── Category.lean
│   ├── Session.lean             — splitAtMidnight, duration arithmetic
│   ├── Goal.lean
│   ├── Stats.lean
│   └── Rbac.lean                — Role, Permission, access check logic
│
├── Http/                        — HTTP/HTTPS server (uses ProductLayer only)
│   ├── Server.lean              — TLS termination, socket listener
│   ├── Router.lean
│   └── Middleware.lean          — Auth + RBAC middleware chain
│
├── Handlers/                    — Route handlers (use ProductLayer only)
│   ├── Auth.lean
│   ├── Users.lean
│   ├── Categories.lean
│   ├── Sessions.lean
│   ├── Goals.lean
│   ├── Stats.lean
│   ├── Admin.lean
│   └── Health.lean
│
└── Db/                          — App-specific database code
    ├── Migrations.lean          — Schema migration SQL
    ├── Queries.lean             — Parameterized query builders
    └── Seed.lean                — Default roles, permissions

provisioner/Provisioner/         — THE PROVISIONER (runs locally)
├── Main.lean                    — Entry point: deploy or supervise subcommand
├── Config.lean                  — GCP project, zone, service account key, SSH key
│
├── Layers/                      — Typeclass definitions (pure interfaces)
│   ├── CI.lean                  — class CILayer
│   └── Infra.lean               — class InfraLayer
│
├── Glue/                        — Instance declarations
│   ├── CIFromContext.lean       — instance : CILayer ProvisionerContext
│   └── InfraFromCI.lean         — instance [CILayer _] : InfraLayer ProvisionerContext
│
├── Gce.lean                     — GCE REST API client (uses SWELibCode.Cloud.GcpClient)
├── Deploy.lean                  — SCP files to VM, docker compose up
└── Supervisor.lean              — Health check loop, restart, token refresh, shutdown
```

Key points:
- `server/` has no GCE, SSH, OAuth2, or Docker code — it just serves HTTP and talks to Postgres
- `provisioner/` has no SQL, auth, RBAC, or business logic — it just manages infrastructure
- Both import from SWELib/SWELibCode but share no code with each other
- `Handlers/` imports only `Layers/Product.lean` — never `Glue/` or `SWELibCode.*` directly
