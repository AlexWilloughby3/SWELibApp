import SWELib.Networking.FastApi
import SWELib.Networking.Http
import SWELibImpl.Networking.FastApi.CallableRegistry
import Impl.Server.Db

/-!
# Auth Handlers (Proof of Concept)

Implements `POST /auth/register` as a minimal DB-backed endpoint.
-/

namespace Impl.Server.Handlers.Auth

open SWELib.Networking.Http
open SWELibImpl.Networking.FastApi.CallableRegistry
open Impl.Server.Db

/-- Helper: build a JSON response with given status code. -/
private def jsonResponse (status : StatusCode) (json : Lean.Json) : Response := {
  status
  headers := [{ name := FieldName.contentType, value := "application/json" }]
  body := some json.pretty.toUTF8
}

/-- POST /auth/register
    Expects JSON body: `{"email": "...", "password": "..."}`.
    Inserts into pending_registrations with a generated verification code. -/
def register (db : DbConn) : HandlerFn := fun req => do
  let some bodyBytes := req.body
    | pure <| jsonResponse StatusCode.badRequest
        (Lean.Json.mkObj [("detail", .str "Missing request body")])
  let bodyStr := String.fromUTF8! bodyBytes
  match Lean.Json.parse bodyStr with
  | .error msg =>
    pure <| jsonResponse StatusCode.badRequest
      (Lean.Json.mkObj [("detail", .str s!"Invalid JSON: {msg}")])
  | .ok json =>
    let some email := json.getObjValAs? String "email" |>.toOption
      | pure <| jsonResponse StatusCode.unprocessableContent
          (Lean.Json.mkObj [("detail", .str "Missing field: email")])
    let some password := json.getObjValAs? String "password" |>.toOption
      | pure <| jsonResponse StatusCode.unprocessableContent
          (Lean.Json.mkObj [("detail", .str "Missing field: password")])
    -- Check if email already registered
    let existing ← Db.query db
      "SELECT email FROM users WHERE email = $1" #[email]
    if existing.size > 0 then
      pure <| jsonResponse StatusCode.conflict
        (Lean.Json.mkObj [("detail", .str "Email already registered")])
    else
      -- Generate a simple 6-digit verification code
      let code := s!"{(← IO.rand 100000 999999)}"
      let _ ← Db.execute db
        "INSERT INTO pending_registrations (email, hashed_password, verification_code) VALUES ($1, $2, $3) ON CONFLICT (email) DO UPDATE SET hashed_password = $2, verification_code = $3"
        #[email, password, code]
      IO.println s!"[auth] Registration pending for {email}, code: {code}"
      pure <| jsonResponse StatusCode.created
        (Lean.Json.mkObj [
          ("email", .str email),
          ("message", .str "Verification code sent")
        ])

end Impl.Server.Handlers.Auth
