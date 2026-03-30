import Server.Config
import Server.AppContext
import Server.Layers.Data
import Server.Layers.Product
import Server.Glue.DataFromContext
import Server.Glue.ProductFromData
import Server.Http.Server

namespace Server

def main : IO Unit := do
  IO.println "productivity-tracker server starting..."

  -- 1. Load config from environment
  let config ← AppConfig.fromEnv
  IO.println s!"config loaded (pg={config.pgHost}:{config.pgPort}, http=:{config.httpPort})"

  -- 2. Create connection pool
  -- TODO: create pool using SWELibCode.Db.ConnectionPool.createPool
  -- 3. Run migrations
  -- TODO: Db.Migrations.run
  -- 4. Seed default roles/permissions
  -- TODO: Db.Seed.run
  -- 5. Start HTTP server
  -- TODO: Http.Server.serve config.httpPort

  IO.println "server ready"

end Server

def main : IO Unit := Server.main
