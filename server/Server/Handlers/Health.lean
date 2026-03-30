import Server.Layers.Data

namespace Server.Handlers

/-- Simple health check — 200 if server is up and DB is reachable. -/
def handleHealth [DataLayer ctx] (ctx_ : ctx) : IO String := do
  let connected ← DataLayer.isConnected ctx_
  if connected then
    pure """{"status": "healthy"}"""
  else
    throw (IO.userError """{"status": "degraded", "issues": ["database unreachable"]}""")

/-- Detailed health check for operators. -/
def handleHealthDetailed [DataLayer ctx] (_ctx : ctx) : IO String := do
  sorry -- TODO: check PG, report connection pool stats, uptime

end Server.Handlers
