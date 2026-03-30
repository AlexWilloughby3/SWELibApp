import SWELibCode.Networking.HttpServer
import Server.Http.Router

namespace Server.Http

/-- Start the HTTP server on the given port, dispatching to the router. -/
def serve (_port : UInt16) : IO Unit := do
  sorry -- TODO: SWELibCode.Networking.HttpServer.serve + acceptLoop with Router.handle

end Server.Http
