namespace Server

/-- Server configuration parsed from environment variables.
    The server runs inside a Docker container on the VM,
    so PG_HOST is typically "db" (the compose service name). -/
structure AppConfig where
  pgHost     : String  -- e.g. "db"
  pgPort     : UInt16  -- e.g. 5432
  pgUser     : String  -- e.g. "productivity"
  pgPassword : String
  pgDatabase : String  -- e.g. "productivity"
  jwtSecret  : String  -- HMAC key for signing JWTs
  httpPort   : UInt16  -- e.g. 8000
  deriving Repr

def AppConfig.pgConnString (cfg : AppConfig) : String :=
  s!"host={cfg.pgHost} port={cfg.pgPort} user={cfg.pgUser} password={cfg.pgPassword} dbname={cfg.pgDatabase}"

/-- Read config from environment. Fails if required vars are missing. -/
def AppConfig.fromEnv : IO AppConfig := do
  let get (key : String) : IO String := do
    match (← IO.getEnv key) with
    | some v => pure v
    | none => throw (IO.userError s!"missing required env var: {key}")
  let pgHost ← get "PG_HOST"
  let pgPort := (← IO.getEnv "PG_PORT").getD "5432"
  let pgUser ← get "PG_USER"
  let pgPassword ← get "PG_PASSWORD"
  let pgDatabase ← get "PG_DATABASE"
  let jwtSecret ← get "JWT_SECRET"
  let httpPort := (← IO.getEnv "HTTP_PORT").getD "8000"
  pure {
    pgHost, pgUser, pgPassword, pgDatabase, jwtSecret
    pgPort := pgPort.toNat!.toUInt16
    httpPort := httpPort.toNat!.toUInt16
  }

end Server
