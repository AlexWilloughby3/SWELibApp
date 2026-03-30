import Server.Layers.Data
import Server.AppContext
import SWELibCode.Db.ConnectionPool
import SWELibCode.Ffi.Libpq
import SWELibBridge.Libpq.Result

namespace Server

/-- Extract column names from a QueryResult. -/
private def extractColumns (result : SWELibBridge.Libpq.QueryResult) : IO (Array String) := do
  let nfields ← SWELibBridge.Libpq.pq_nfields result
  let mut cols := #[]
  for i in List.range nfields do
    let name ← SWELibBridge.Libpq.pq_fname result i
    cols := cols.push name
  pure cols

/-- Extract all rows from a QueryResult. -/
private def extractRows (result : SWELibBridge.Libpq.QueryResult) : IO (Array Row) := do
  let ntuples ← SWELibBridge.Libpq.pq_ntuples result
  let nfields ← SWELibBridge.Libpq.pq_nfields result
  let mut rows := #[]
  for r in List.range ntuples do
    let mut row := #[]
    for c in List.range nfields do
      let val ← SWELibBridge.Libpq.pq_getvalue result r c
      row := row.push val
    rows := rows.push row
  pure rows

/-- Concrete DataLayer instance for AppContext.
    Uses SWELib's ConnectionPool to get connections and Libpq FFI to execute queries.
    The server runs in the same Docker network as Postgres, so connection is direct TCP. -/
instance : DataLayer AppContext where

  execQuery ctx q := do
    let connResult ← SWELibCode.Db.ConnectionPool.getConnection ctx.pool
    match connResult with
    | .error e => throw (IO.userError s!"pool error: {repr e}")
    | .ok conn =>
      -- Use parameterized queries to prevent SQL injection
      let result ← SWELibCode.Ffi.Libpq.execParamsRows conn.handle.ptr q.sql q.params
      let (status, rows, errMsg) := result
      SWELibCode.Db.ConnectionPool.releaseConnection ctx.pool conn
      if status != 0 then
        throw (IO.userError s!"query failed: {errMsg}")
      -- For execParamsRows, result is already parsed into rows
      -- We need column names from a separate call, but execParamsRows
      -- returns rows directly. Build ResultSet from the raw data.
      pure { columns := #[], rows := rows }

  execInsert ctx q := do
    let connResult ← SWELibCode.Db.ConnectionPool.getConnection ctx.pool
    match connResult with
    | .error e => throw (IO.userError s!"pool error: {repr e}")
    | .ok conn =>
      let result ← SWELibCode.Ffi.Libpq.execParamsRows conn.handle.ptr q.sql q.params
      let (status, rows, errMsg) := result
      SWELibCode.Db.ConnectionPool.releaseConnection ctx.pool conn
      if status != 0 then
        throw (IO.userError s!"insert failed: {errMsg}")
      -- RETURNING clause gives us the inserted row
      pure (rows.get? 0)

  execMutate ctx q := do
    let connResult ← SWELibCode.Db.ConnectionPool.getConnection ctx.pool
    match connResult with
    | .error e => throw (IO.userError s!"pool error: {repr e}")
    | .ok conn =>
      let result ← SWELibCode.Ffi.Libpq.execParams conn.handle.ptr q.sql q.params
      let (status, affected, errMsg) := result
      SWELibCode.Db.ConnectionPool.releaseConnection ctx.pool conn
      if status != 0 then
        throw (IO.userError s!"mutate failed: {errMsg}")
      pure { rowsAffected := affected.toNat }

  execRaw ctx sql := do
    let connResult ← SWELibCode.Db.ConnectionPool.getConnection ctx.pool
    match connResult with
    | .error e => throw (IO.userError s!"pool error: {repr e}")
    | .ok conn =>
      let result ← conn.exec sql
      SWELibCode.Db.ConnectionPool.releaseConnection ctx.pool conn
      match result with
      | some _ => pure ()
      | none =>
        let errMsg ← conn.errorMessage
        throw (IO.userError s!"raw exec failed: {errMsg}")

  withTransaction ctx f := do
    let connResult ← SWELibCode.Db.ConnectionPool.getConnection ctx.pool
    match connResult with
    | .error e => throw (IO.userError s!"pool error: {repr e}")
    | .ok conn =>
      let _ ← SWELibCode.Ffi.Libpq.begin_ conn.handle.ptr
      try
        let result ← f ctx
        let _ ← SWELibCode.Ffi.Libpq.commit conn.handle.ptr
        SWELibCode.Db.ConnectionPool.releaseConnection ctx.pool conn
        pure result
      catch e =>
        let _ ← SWELibCode.Ffi.Libpq.rollback conn.handle.ptr
        SWELibCode.Db.ConnectionPool.releaseConnection ctx.pool conn
        throw e

  isConnected ctx := do
    SWELibCode.Db.ConnectionPool.hasCapacity ctx.pool

end Server
