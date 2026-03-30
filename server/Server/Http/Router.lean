import SWELib.Networking.Http
import Server.Layers.Product

namespace Server.Http

/-- Route an incoming HTTP request to the appropriate handler.
    All handlers receive a ProductLayer instance — never DataLayer. -/
def handle [ProductLayer ctx] (_ctx : ctx) (_method : String) (_path : String) (_body : String) (_authToken : Option String) : IO String := do
  sorry -- TODO: match on (method, path) and dispatch to Handlers.*

end Server.Http
