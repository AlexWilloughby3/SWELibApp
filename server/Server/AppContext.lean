import Server.Config
import SWELibCode.Db.ConnectionPool

namespace Server

/-- Runtime state for the server. Not a layer — just the concrete struct
    that all layer instances are resolved over. -/
structure AppContext where
  pool   : SWELibCode.Db.ConnectionPool.Pool
  config : AppConfig

end Server
