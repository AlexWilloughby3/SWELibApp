import SWELib.Networking.FastApi
import SWELib.Networking.Http
import SWELibImpl.Networking.FastApi.CallableRegistry

/-!
# Health Check Handler

Returns `{"status": "ok"}` — proves the full request/response cycle works.
-/

namespace Impl.Server.Handlers.Health

open SWELib.Networking.Http
open SWELibImpl.Networking.FastApi.CallableRegistry

def healthCheck : HandlerFn := fun _req => do
  let body := Lean.Json.mkObj [("status", .str "ok")]
  pure {
    status := StatusCode.ok
    headers := [{ name := FieldName.contentType, value := "application/json" }]
    body := some body.pretty.toUTF8
  }

end Impl.Server.Handlers.Health
