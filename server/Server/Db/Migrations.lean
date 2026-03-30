import Server.Layers.Data

namespace Server.Db

/-- All migration SQL statements, run idempotently at startup.
    Uses IF NOT EXISTS / ON CONFLICT DO NOTHING throughout. -/
def migrationSQL : List String := [
  -- Users
  "CREATE TABLE IF NOT EXISTS users (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email        TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
  )",

  -- Roles
  "CREATE TABLE IF NOT EXISTS roles (
    id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL
  )",

  -- Permissions
  "CREATE TABLE IF NOT EXISTS permissions (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action   TEXT NOT NULL,
    resource TEXT NOT NULL,
    scope    TEXT NOT NULL,
    UNIQUE(action, resource, scope)
  )",

  -- Role-Permission mapping
  "CREATE TABLE IF NOT EXISTS role_permissions (
    role_id       UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
  )",

  -- User-Role mapping
  "CREATE TABLE IF NOT EXISTS user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
  )",

  -- Refresh tokens
  "CREATE TABLE IF NOT EXISTS refresh_tokens (
    token      TEXT PRIMARY KEY,
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )",

  -- Categories
  "CREATE TABLE IF NOT EXISTS categories (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    is_active  BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, name)
  )",

  -- Focus sessions
  "CREATE TABLE IF NOT EXISTS focus_sessions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID REFERENCES users(id) ON DELETE CASCADE,
    category_id      UUID REFERENCES categories(id) ON DELETE CASCADE,
    duration_seconds INTEGER NOT NULL CHECK(duration_seconds > 0),
    started_at       TIMESTAMPTZ NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
  )",

  -- Goals
  "CREATE TABLE IF NOT EXISTS goals (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID REFERENCES users(id) ON DELETE CASCADE,
    category_id    UUID REFERENCES categories(id) ON DELETE CASCADE,
    goal_type      TEXT NOT NULL CHECK(goal_type IN ('time_based', 'daily_checkbox', 'weekly_checkbox')),
    target_minutes INTEGER,
    description    TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, category_id, goal_type)
  )",

  -- Checkbox completions
  "CREATE TABLE IF NOT EXISTS checkbox_completions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    goal_id        UUID REFERENCES goals(id) ON DELETE CASCADE,
    completed_date DATE NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(goal_id, completed_date)
  )"
]

/-- Run all migrations idempotently. -/
def runMigrations [DataLayer ctx] (ctx_ : ctx) : IO Unit := do
  for sql in migrationSQL do
    DataLayer.execRaw ctx_ sql

end Server.Db
