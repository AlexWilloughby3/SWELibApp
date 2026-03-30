import SWELibBridge.Libpq

namespace Server

/-- A parameterized query: SQL text + bound parameters.
    Parameters are always bound (never interpolated) to prevent SQL injection. -/
structure ParamQuery where
  sql    : String
  params : Array String
  deriving Repr

/-- A single row from a query result: array of nullable string columns. -/
abbrev Row := Array (Option String)

/-- Result of a SELECT query: column names + rows. -/
structure ResultSet where
  columns : Array String
  rows    : Array Row
  deriving Repr

/-- Result of an INSERT/UPDATE/DELETE: number of rows affected. -/
structure ExecResult where
  rowsAffected : Nat
  deriving Repr

/-- The data layer typeclass. Speaks in terms of parameterized queries,
    result sets, and transactions. No knowledge of VMs, containers, or
    domain types — just SQL execution.

    The server runs on the same VM as Postgres, so there's no infra
    dependency. DataLayer is instantiated directly over AppContext. -/
class DataLayer (ctx : Type) where
  /-- Execute a SELECT query, returning rows. -/
  execQuery : ctx → ParamQuery → IO ResultSet

  /-- Execute an INSERT with RETURNING, getting back the inserted row. -/
  execInsert : ctx → ParamQuery → IO (Option Row)

  /-- Execute an UPDATE or DELETE, returning rows affected. -/
  execMutate : ctx → ParamQuery → IO ExecResult

  /-- Execute a raw SQL statement (for migrations, DDL). -/
  execRaw : ctx → String → IO Unit

  /-- Run a function inside a BEGIN/COMMIT transaction.
      If the function throws, ROLLBACK is issued instead. -/
  withTransaction : ctx → (ctx → IO α) → IO α

  /-- Check if the connection pool has a healthy connection. -/
  isConnected : ctx → IO Bool

end Server
