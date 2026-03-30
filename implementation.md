# Implementation Plan

Productivity tracker: Lean 4 server runs in a Docker container on a GCE VM alongside Postgres. A local provisioner/supervisor manages the VM via GCE API + SSH. React frontend TBD (vibe-coded later).
Two separate binaries, each with its own **typeclass layer stack**. SWELibApp only contains app-specific code — everything generic is in SWELib.

---

## 0. SWELib vs SWELibApp Boundary

**SWELib** (upstream library) owns all generic, reusable formalizations and implementations:

| Area | SWELib already has |
|------|-------------------|
| **Specs** | `Security/Jwt/*`, `Security/Oauth`, `Security/Rbac`, `Security/Hashing`, `Security/Iam/Gcp/*` |
| | `Networking/Http/*`, `Networking/Tls/*`, `Networking/Rest` |
| | `Db/Sql`, `Cloud/Gcp`, `Basics/Uuid`, `Basics/Time` |
| **Code** | `Networking/HttpServer`, `Networking/HttpClient`, `Networking/TcpServer`, `Networking/TlsClient` |
| | `Security/JwtValidator`, `Security/HashOps` |
| | `Db/PgClient`, `Db/QueryBuilder`, `Db/ConnectionPool/*` |
| | `Cloud/GcpClient`, `Ffi/Libpq`, `Ffi/Libssl` |
| | `OS/SocketOps`, `OS/ProcessOps`, `OS/SignalOps` |
| **Bridges** | `Libpq/*` (Connect, Exec, Result, Validation), `Libssl/*` (Hash, Handshake, Record, Cert) |
| | `Libcurl/*` (Get, Post, Response, HttpServer), `Encoding/Base64url` |

**If something needs formalizing and it's not app-specific, it goes in SWELib.** Examples:
- GCE VM lifecycle state machine → SWELib (`Cloud/Gce/`)
- OAuth2 service-account JWT-bearer flow → SWELib (`Security/Oauth`)
- SSH command execution semantics → SWELib (new `Networking/Ssh/`)
- SSH trust boundary → SWELib (new `bridge/SWELibBridge/Ssh`)
- Docker compose semantics → SWELib (new `Cloud/Docker/`)
- bcrypt cost-factor properties → SWELib (`Security/Hashing`)

**SWELibApp** only owns what is unique to this productivity tracker:

| SWELibApp owns | Why it's app-specific |
|---------------|----------------------|
| `spec/ProductivityTracker/Types.lean` | User, Category, Session, Goal — domain types |
| `spec/ProductivityTracker/Schema.lean` | This app's DB schema + referential integrity |
| `spec/ProductivityTracker/SessionSplitting.lean` | Midnight-split correctness (this app's business rule) |
| `spec/ProductivityTracker/Rbac.lean` | This app's role/permission model (user, admin) |
| `spec/ProductivityTracker/Invariants.lean` | Cross-cutting app invariants (category cap, cascade rules) |
| `spec/ProductivityTracker/Supervisor.lean` | Liveness/safety of this app's supervisor loop |
| `server/` | All runtime code (layers, glue, handlers, supervisor) |
| `frontend/` | React SPA |
| `tests/` | Python test harness |

**Rule of thumb:** SWELibApp `spec/` files `import SWELib.*` and add app-specific constraints on top. They never re-formalize something SWELib already covers.

---

## 1. The Layer Stacks

**Server** (runs on VM in Docker container):
```
ProductLayer   — users, auth, sessions, goals, stats, RBAC (pure domain language)
    ↓
DataLayer      — queries, transactions, connection management
```

**Provisioner/Supervisor** (runs locally):
```
InfraLayer     — VMs, containers, SSH, OAuth2 tokens
    ↓
CILayer        — migrations, deployment, rollback
```

Each layer is a typeclass. Layers only call one level down. Definitions share no imports.
Swapping Postgres for SQLite = rewrite one glue file in `server/`. Swapping GCE for EC2 = rewrite one glue file in `provisioner/`. The two binaries share no code.

---

## 2. Directory Layout

```
server/                        — THE SERVER (runs on VM in Docker container)
├── lakefile.lean              — Depends on SWELib + SWELibCode
├── Dockerfile                 — Builds Lean server container image
├── Server/
│   ├── Main.lean              — Connect to PG, migrate, seed, serve HTTPS
│   ├── Config.lean            — Env config parsing (PG_HOST, JWT_SECRET, etc.)
│   ├── AppContext.lean        — Runtime state (PG conn, config)
│   │
│   ├── Layers/                — Typeclass definitions only (pure interfaces)
│   │   ├── Data.lean          — class DataLayer
│   │   └── Product.lean       — class ProductLayer
│   │
│   ├── Glue/                  — Instance declarations
│   │   ├── DataFromContext.lean   — instance : DataLayer AppContext
│   │   └── ProductFromData.lean   — instance [DataLayer _] : ProductLayer AppContext
│   │
│   ├── Domain/                — Pure types + logic (no IO, no SWELib imports)
│   │   ├── User.lean
│   │   ├── Category.lean
│   │   ├── Session.lean       — splitAtMidnight
│   │   ├── Goal.lean
│   │   ├── Stats.lean
│   │   └── Rbac.lean
│   │
│   ├── Http/                  — Thin wiring to SWELibCode.Networking.HttpServer
│   │   ├── Server.lean        — TLS termination, socket listener
│   │   ├── Router.lean        — Route matching, dispatch
│   │   └── Middleware.lean    — Auth + RBAC middleware chain
│   │
│   ├── Handlers/              — Route handlers (import ProductLayer only)
│   │   ├── Auth.lean
│   │   ├── Users.lean
│   │   ├── Categories.lean
│   │   ├── Sessions.lean
│   │   ├── Goals.lean
│   │   ├── Stats.lean
│   │   ├── Admin.lean
│   │   └── Health.lean
│   │
│   └── Db/                    — App-specific database code
│       ├── Migrations.lean
│       ├── Queries.lean
│       └── Seed.lean

provisioner/                   — THE PROVISIONER (runs locally)
├── lakefile.lean              — Depends on SWELib + SWELibCode
├── Provisioner/
│   ├── Main.lean              — deploy / supervise subcommands
│   ├── Config.lean            — GCP project, zone, service account key
│   │
│   ├── Layers/
│   │   ├── CI.lean            — class CILayer
│   │   └── Infra.lean         — class InfraLayer
│   │
│   ├── Glue/
│   │   ├── CIFromContext.lean     — instance : CILayer ProvisionerContext
│   │   └── InfraFromCI.lean       — instance [CILayer _] : InfraLayer ProvisionerContext
│   │
│   ├── Gce.lean               — GCE REST API client
│   ├── Deploy.lean            — SCP files to VM, docker compose up
│   └── Supervisor.lean        — Health check loop, restart, token refresh

docker-compose.yml             — Deployed to VM (api + db containers)

spec/ProductivityTracker/      — App-specific formalizations (imports SWELib.*)
├── Types.lean
├── Schema.lean
├── SessionSplitting.lean
├── Rbac.lean
├── Invariants.lean
└── Supervisor.lean

frontend/                      — React/Vite/Tailwind SPA (TBD)
tests/                         — Python pytest harness
```

**No `Impl/` or `ffi/` directory** — SWELib already provides `SWELibCode.Db.PgClient`, `SWELibCode.Security.JwtValidator`, `SWELibCode.Security.HashOps`, `SWELibCode.Cloud.GcpClient`, `SWELibCode.Networking.HttpServer`, etc. Glue files import these directly from SWELib.

---

## 3. Layer Definitions — Code Patterns

### Server Layers

#### DataLayer

```lean
class DataLayer (ctx : Type) where
  execQuery       : ctx → Query → IO ResultSet
  execInsert      : ctx → Query → IO (Option RowId)
  execUpdate      : ctx → Query → IO Nat
  execDelete      : ctx → Query → IO Nat
  withTransaction : ctx → (ctx → IO α) → IO α
  isConnected     : ctx → IO Bool
  reconnect       : ctx → IO Unit

  transaction_atomicity : ∀ c f,
    withTransaction c f either fully commits or commits nothing
  query_parameterized : ∀ c q,
    execQuery c q uses bound parameters (no SQL injection)
```

#### ProductLayer

```lean
class ProductLayer (ctx : Type) where
  -- Auth
  register      : ctx → Email → Password → DisplayName → IO User
  login         : ctx → Email → Password → IO (Option TokenPair)
  validateToken : ctx → Token → IO (Option User)
  refreshAuth   : ctx → RefreshToken → IO (Option TokenPair)

  -- RBAC
  authorize     : ctx → User → Permission → IO Bool

  -- Categories
  createCategory : ctx → UserId → CategoryName → IO (Result DomainError Category)
  listCategories : ctx → UserId → IO (List Category)
  deleteCategory : ctx → UserId → CategoryId → IO (Result DomainError Unit)

  -- Sessions
  logSession     : ctx → UserId → CategoryId → Duration → StartTime → IO (List Session)
  listSessions   : ctx → UserId → DateRange → PageParams → IO (Page Session)

  -- Goals
  createGoal  : ctx → UserId → CategoryId → GoalType → IO (Result DomainError Goal)
  toggleGoal  : ctx → UserId → GoalId → Date → IO Bool

  -- Stats
  userStats     : ctx → UserId → DateRange → IO Stats
  weeklySummary : ctx → UserId → IO WeeklySummary

  -- Proof obligations (all in domain language, no SQL/infra)
  expired_rejected : ∀ c t, isExpired t → validateToken c t = pure none
  default_deny : ∀ c u p, ¬hasRoleGranting u p → authorize c u p = pure false
  split_preserves_duration : ∀ c uid cat dur start,
    crossesMidnight start dur →
    sumDurations (← logSession c uid cat dur start) = dur
  no_split_same_day : ∀ c uid cat dur start,
    ¬crossesMidnight start dur → (← logSession c uid cat dur start).length = 1
  category_cap : ∀ c uid name,
    (← listCategories c uid).length ≥ 20 →
    createCategory c uid name = pure (Err .limitReached)
```

### Provisioner Layers

#### CILayer

```lean
class CILayer (ctx : Type) where
  runMigration    : ctx → Migration → IO MigrationResult
  deployArtifact  : ctx → Artifact → Environment → IO DeployResult
  rollback        : ctx → Environment → Version → IO RollbackResult
  currentVersion  : ctx → Environment → IO Version

  migrations_idempotent : ∀ c m,
    runMigration c m >> runMigration c m ≈ runMigration c m
  rollback_restores : ∀ c env v artifact,
    deployArtifact c artifact env >> rollback c env v →
    currentVersion c env = pure v
```

#### InfraLayer

```lean
class InfraLayer (ctx : Type) where
  provisionVM      : ctx → VMConfig → IO VMInstance
  startVM          : ctx → VMId → IO VMStatus
  stopVM           : ctx → VMId → IO VMStatus
  getVMStatus      : ctx → VMId → IO VMStatus
  deployContainers : ctx → VMInstance → ComposeFile → IO Unit
  restartContainer : ctx → VMInstance → ContainerName → IO Unit
  containerHealth  : ctx → VMInstance → ContainerName → IO HealthStatus
  refreshToken     : ctx → IO Token
  tokenValid       : ctx → IO Bool

  vm_recoverable : ∀ c vmId,
    getVMStatus c vmId = pure .terminated →
    startVM c vmId >> getVMStatus c vmId = pure .running
  healthy_preserved : ∀ c vm container,
    containerHealth c vm container = pure .healthy →
    supervisorStep c → containerHealth c vm container = pure .healthy
```

---

## 4. Glue — Instance Chain

Each glue file connects two adjacent layers. **Only** code that imports both.
Glue files call SWELib code implementations — no local FFI wrappers needed.

### Server Glue

#### DataFromContext.lean (uses SWELib's PgClient + ConnectionPool)

```lean
import SWELibCode.Db.PgClient
import SWELibCode.Db.ConnectionPool

instance : DataLayer AppContext where
  execQuery ctx query := SWELibCode.Db.PgClient.exec (← ctx.pgConn.get) query
  withTransaction ctx f := do
    let conn ← ctx.pgConn.get
    SWELibCode.Db.PgClient.exec conn "BEGIN"
    try let r ← f ctx; SWELibCode.Db.PgClient.exec conn "COMMIT"; pure r
    catch e => SWELibCode.Db.PgClient.exec conn "ROLLBACK"; throw e
  reconnect ctx := do
    ctx.pgConn.set (← SWELibCode.Db.PgClient.connect ctx.config.pgConnString)
```

#### ProductFromData.lean (uses SWELib's HashOps, JwtValidator + app Domain/)

```lean
import SWELibCode.Security.HashOps      -- bcrypt
import SWELibCode.Security.JwtValidator  -- JWT create/validate
import Server.Domain.Session             -- splitAtMidnight (app-specific)

instance [DataLayer AppContext] : ProductLayer AppContext where
  register ctx email pw name := do
    let hash ← SWELibCode.Security.HashOps.bcryptHash pw
    let id ← DataLayer.execInsert ctx (insertUserQuery email hash name)
    DataLayer.execInsert ctx (assignDefaultRoleQuery id)
    DataLayer.execInsert ctx (seedDefaultCategoriesQuery id)
    pure { id, email, displayName := name }

  logSession ctx uid catId dur start := do
    if crossesMidnight start dur then
      let (d1, d2) := splitAtMidnight start dur
      DataLayer.withTransaction ctx fun c => do
        let s1 ← DataLayer.execInsert c (insertSessionQ uid catId d1.dur d1.start)
        let s2 ← DataLayer.execInsert c (insertSessionQ uid catId d2.dur d2.start)
        pure [s1, s2]
    else pure [← DataLayer.execInsert ctx (insertSessionQ uid catId dur start)]

  split_preserves_duration := by
    intro c uid cat dur start hcross
    simp [logSession, hcross, splitAtMidnight]
    exact splitAtMidnight_sum_eq dur start
```

### Provisioner Glue

#### CIFromContext.lean (uses SWELib's ProcessOps for SSH)

```lean
import SWELibCode.OS.ProcessOps       -- SSH/SCP via shell

instance : CILayer ProvisionerContext where
  deployArtifact ctx artifact env := do
    SWELibCode.OS.ProcessOps.exec "scp" [artifact.path, envToHost env]
    SWELibCode.OS.ProcessOps.exec "ssh" [envToHost env, "docker compose up -d"]
```

#### InfraFromCI.lean (uses SWELib's GcpClient)

```lean
import SWELibCode.Cloud.GcpClient     -- GCE VM create/start/stop/get

instance [CILayer ProvisionerContext] : InfraLayer ProvisionerContext where
  provisionVM ctx cfg := do
    let vm ← SWELibCode.Cloud.GcpClient.createInstance (← ctx.oauthToken.get) cfg
    CILayer.deployArtifact ctx (composeArtifact cfg) (vmToEnv vm)
    pure vm
  refreshToken ctx := do
    let tok ← SWELibCode.Cloud.GcpClient.exchangeServiceAccountJwt ctx.config.saKey
    ctx.oauthToken.set tok; pure tok
```

---

## 5. Context Structures — Runtime State

**Server** (on VM):
```lean
structure AppContext where
  pgConn : IORef SWELibCode.Db.PgClient.Connection
  config : AppConfig   -- JWT_SECRET, PG_HOST, etc.
```

**Provisioner** (local):
```lean
structure ProvisionerContext where
  oauthToken : IORef SWELib.Security.Oauth.Token
  config     : ProvisionerConfig   -- GCP_PROJECT, GCP_ZONE, SSH key
  vmInstance : IORef (Option SWELibCode.Cloud.GcpClient.VMInstance)
```

Not layers. Just bags of mutable state that layers are instantiated over.

---

## 6. Import Rules

**Server** (on VM):

| Code | Can import | Cannot import |
|------|-----------|---------------|
| `Handlers/*` | `Layers/Product`, `Domain/*` | `Layers/Data`, `Glue/*`, `SWELibCode.*` |
| `Http/*` | `Layers/Product`, `SWELibCode.Networking.HttpServer` | `Layers/Data` |
| `Glue/ProductFromData` | `Layers/Product`, `Layers/Data`, `Domain/*`, `SWELibCode.Security.*` | nothing in provisioner/ |
| `Glue/DataFromContext` | `Layers/Data`, `SWELibCode.Db.*` | `Layers/Product` |
| `Domain/*` | nothing (pure Lean, no IO, no SWELib) | everything |

**Provisioner** (local):

| Code | Can import | Cannot import |
|------|-----------|---------------|
| `Supervisor` | `Layers/Infra` | `Layers/CI`, server/* |
| `Glue/InfraFromCI` | `Layers/Infra`, `Layers/CI`, `SWELibCode.Cloud.*` | server/* |
| `Glue/CIFromContext` | `Layers/CI`, `SWELibCode.OS.ProcessOps` | server/* |

**Specs:**

| Code | Can import | Cannot import |
|------|-----------|---------------|
| `spec/ProductivityTracker/*` | `SWELib.Security.*`, `SWELib.Db.*`, `SWELib.Networking.*` | `server/*`, `provisioner/*` |

---

## 7. Build Order

### Phase 1: Server Skeleton (runs on VM)
1. `server/lakefile.lean` with SWELib dependency (both `SWELib` spec and `SWELibCode`)
2. `Layers/Data.lean` typeclass
3. `Glue/DataFromContext` (using `SWELibCode.Db.PgClient`, `SWELibCode.Db.ConnectionPool`)
4. Basic HTTPS server (using `SWELibCode.Networking.HttpServer`, hardcoded 200)
5. Connect to Postgres at `db:5432` (Docker network)
6. Dockerfile + docker-compose.yml (api + db containers)

### Phase 2: Auth & RBAC
7. `Layers/Product.lean` — auth subset first
8. `Glue/ProductFromData` — auth subset (using `SWELibCode.Security.HashOps`, `JwtValidator`)
9. Migrations + seed (app-specific SQL in `Db/Migrations.lean`, `Db/Seed.lean`)
10. Auth + RBAC middleware, auth handlers
11. Health endpoints (`/health`, `/health/detailed`)

### Phase 3: Core Features
12. `Domain/*` — pure session splitting, goal logic, stats (no SWELib imports)
13. Expand `ProductLayer` + `ProductFromData` with sessions, goals, stats, categories
14. All handlers

### Phase 4: Provisioner + Supervisor (runs locally)
15. `provisioner/lakefile.lean` with SWELib dependency
16. `Layers/CI.lean`, `Layers/Infra.lean` typeclasses
17. `Glue/CIFromContext` (using `SWELibCode.OS.ProcessOps` for SSH/SCP)
18. `Glue/InfraFromCI` (using `SWELibCode.Cloud.GcpClient`)
19. Deploy subcommand (SCP files to VM, docker compose up)
20. Supervisor subcommand (health check loop, container restart, token refresh, shutdown)

### Phase 5: Tests (Python)
21. `tests/conftest.py`, `client.py`, fixtures
22. Auth, RBAC, integrity, session, goal, stats, resilience tests

### Phase 6: Frontend (TBD — vibe-coded separately)
23. React + TypeScript + Tailwind SPA
24. Add Nginx container to docker-compose (static files + /api proxy)

### Phase 7: Formalization
**In SWELib** (if not already sufficient):
- Flesh out `Security/Oauth` → OAuth2 JWT-bearer flow for service accounts
- Flesh out `Cloud/Gcp` → create `Cloud/Gce/` — GCE VM lifecycle state machine
- Create `Networking/Ssh/` → SSH semantics + `bridge/SWELibBridge/Ssh`
- Flesh out `Security/Rbac` → generic RBAC model
- Flesh out `Db/Transactions` → ACID transaction semantics
- Extend `Security/Hashing` → bcrypt password hashing

**In SWELibApp** (app-specific only):
- `spec/ProductivityTracker/Types.lean` — domain types
- `spec/ProductivityTracker/Schema.lean` — this app's DB schema invariants
- `spec/ProductivityTracker/SessionSplitting.lean` — midnight split correctness
- `spec/ProductivityTracker/Rbac.lean` — this app's user/admin role model
- `spec/ProductivityTracker/Invariants.lean` — category cap, cascades, duration > 0
- `spec/ProductivityTracker/Supervisor.lean` — this app's liveness/safety properties
