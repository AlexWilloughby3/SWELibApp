import SWELib.Networking.FastApi
import SWELib.Networking.Http
import SWELibImpl.Networking.FastApi.CallableRegistry
import Impl.Server.Db
import Impl.Server.Handlers.Users

/-!
# Auth Handlers

Re-exports auth handlers from `Handlers.Users` for backward compatibility.
All auth logic lives in `Handlers.Users` to keep user-related code together.
-/

namespace Impl.Server.Handlers.Auth

open Impl.Server.Db

/-- POST /auth/register — delegates to Users.register -/
def register (db : DbConn) := Handlers.Users.register db

end Impl.Server.Handlers.Auth
