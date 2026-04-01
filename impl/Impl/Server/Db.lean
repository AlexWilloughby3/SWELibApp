import SWELib.Db.ConnectionPool.Types
import SWELibImpl.Bridge.Libpq
import SWELibImpl.Ffi.Libpq

/-!
# Database Layer

PostgreSQL connection management and query helpers.
Uses `pq_connect`/`pq_exec` from the bridge for connection + DDL,
and `execParamsRows`/`execParams` from the FFI for parameterized queries.
-/

namespace Impl.Server.Db

open SWELib.Db.ConnectionPool
open SWELibImpl.Bridge.Libpq

/-- Application-level database handle.
    Stores both the opaque `ConnectionHandle` (for bridge ops)
    and the raw pointer as `USize` (for FFI parameterized queries). -/
structure DbConn where
  handle : ConnectionHandle
  ptr : USize

/-- Connect to PostgreSQL using PG_* env vars. -/
def connect : IO DbConn := do
  let params ← readParams
  let some handle ← pq_connect params
    | throw (IO.userError "Failed to connect to PostgreSQL")
  let status ← pq_status handle
  match status with
  | .CONNECTION_OK =>
    let ptr := connHandleToUSize handle
    pure ⟨handle, ptr⟩
  | _ =>
    let msg ← pq_error_message handle
    pq_close handle
    throw (IO.userError s!"PostgreSQL connection failed: {msg}")
where
  readParams : IO ConnectionParameters := do
    let host ← IO.getEnv "PG_HOST"
    let port ← IO.getEnv "PG_PORT"
    let dbname ← IO.getEnv "PG_DBNAME"
    let user ← IO.getEnv "PG_USER"
    let password ← IO.getEnv "PG_PASSWORD"
    pure {
      host := host
      port := port.bind (·.toNat?)
      dbname := dbname <|> some "prodtracker"
      user := user <|> some "postgres"
      password := password
    }

/-- Execute a DDL/DML statement (no result rows needed). Throws on failure. -/
def execDDL (db : DbConn) (sql : String) : IO Unit := do
  let some _result ← pq_exec db.handle sql
    | do
      let msg ← pq_error_message db.handle
      throw (IO.userError s!"Query failed: {msg}")
  pure ()

/-- Execute a parameterized query returning rows.
    Returns an array of rows, each row an array of optional string values.
    Uses server-side parameter binding to prevent SQL injection. -/
def query (db : DbConn) (sql : String) (params : Array String := #[])
    : IO (Array (Array (Option String))) := do
  let (status, rows, errMsg) ← SWELibImpl.Ffi.Libpq.execParamsRows db.ptr sql params
  if status == 2 || status == 5 then  -- COMMAND_OK or TUPLES_OK
    pure rows
  else
    throw (IO.userError s!"Query error: {errMsg}")

/-- Execute a parameterized command (INSERT/UPDATE/DELETE).
    Returns (statusCode, rowCount, errorMessage). -/
def execute (db : DbConn) (sql : String) (params : Array String := #[])
    : IO Nat := do
  let (status, rowCount, errMsg) ← SWELibImpl.Ffi.Libpq.execParams db.ptr sql params
  if status == 2 || status == 5 then
    pure rowCount.toNat
  else
    throw (IO.userError s!"Execute error: {errMsg}")

/-- Close the database connection. -/
def close (db : DbConn) : IO Unit :=
  pq_close db.handle

/-- Run schema migrations (create tables if they don't exist). -/
def runMigrations (db : DbConn) : IO Unit := do
  execDDL db "
    CREATE TABLE IF NOT EXISTS users (
      email TEXT PRIMARY KEY,
      hashed_password TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )"
  execDDL db "
    CREATE TABLE IF NOT EXISTS pending_registrations (
      email TEXT PRIMARY KEY,
      hashed_password TEXT NOT NULL,
      verification_code TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )"
  execDDL db "
    CREATE TABLE IF NOT EXISTS password_reset_tokens (
      token TEXT PRIMARY KEY,
      email TEXT NOT NULL REFERENCES users(email) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )"
  execDDL db "
    CREATE TABLE IF NOT EXISTS categories (
      email TEXT NOT NULL REFERENCES users(email) ON DELETE CASCADE,
      name TEXT NOT NULL,
      color TEXT,
      PRIMARY KEY (email, name)
    )"
  execDDL db "
    CREATE TABLE IF NOT EXISTS focus_sessions (
      id SERIAL PRIMARY KEY,
      email TEXT NOT NULL REFERENCES users(email) ON DELETE CASCADE,
      category TEXT NOT NULL,
      focus_time_seconds INTEGER NOT NULL,
      time TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )"
  execDDL db "
    CREATE TABLE IF NOT EXISTS focus_goals (
      id SERIAL PRIMARY KEY,
      email TEXT NOT NULL REFERENCES users(email) ON DELETE CASCADE,
      category TEXT NOT NULL,
      goal_type TEXT NOT NULL,
      target_seconds INTEGER
    )"
  execDDL db "
    CREATE TABLE IF NOT EXISTS checkbox_goal_completions (
      email TEXT NOT NULL,
      category TEXT NOT NULL,
      goal_type TEXT NOT NULL,
      completion_date DATE NOT NULL,
      PRIMARY KEY (email, category, goal_type, completion_date)
    )"
  IO.println "Database migrations complete"

end Impl.Server.Db
