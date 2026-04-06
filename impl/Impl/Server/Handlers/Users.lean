import SWELib.Networking.FastApi
import SWELib.Networking.Http
import SWELibImpl.Networking.FastApi.CallableRegistry
import Impl.Server.Db
import Impl.Server.Models

/-!
# User Handlers

Implements user CRUD endpoints:
- `GET    /users/me`           — get current user
- `PATCH  /users/me`           — update display_name / show_on_leaderboard
- `DELETE /users/me`           — delete account and all data
- `POST   /auth/verify`        — verify registration code and create account
- `POST   /auth/login`         — password-based login
- `POST   /auth/request-code`  — send passwordless login code
- `POST   /auth/login-code`    — login with verification code
- `POST   /auth/change-password`       — change password (requires current)
- `POST   /auth/forgot-password`       — request password reset token
- `POST   /auth/reset-password`        — reset password with token
-/

namespace Impl.Server.Handlers.Users

open SWELib.Networking.Http
open SWELibImpl.Networking.FastApi.CallableRegistry
open Impl.Server.Db
open Impl.Server.Models

/-- Helper: build a JSON response with given status code. -/
private def jsonResponse (status : StatusCode) (json : Lean.Json) : Response := {
  status
  headers := [{ name := FieldName.contentType, value := "application/json" }]
  body := some json.pretty.toUTF8
}

/-- Helper: parse JSON body from request, returning error response if invalid. -/
private def parseJsonBody (req : Request) : IO (Except Response Lean.Json) := do
  let some bodyBytes := req.body
    | pure <| Except.error <| jsonResponse StatusCode.badRequest
        (Lean.Json.mkObj [("detail", .str "Missing request body")])
  let bodyStr := String.fromUTF8! bodyBytes
  match Lean.Json.parse bodyStr with
  | .error msg =>
    pure <| Except.error <| jsonResponse StatusCode.badRequest
      (Lean.Json.mkObj [("detail", .str s!"Invalid JSON: {msg}")])
  | .ok json => pure <| Except.ok json

/-- Helper: extract required string field from JSON. -/
private def requireField (json : Lean.Json) (field : String) : Except Response String :=
  match json.getObjValAs? String field |>.toOption with
  | some v => Except.ok v
  | none => Except.error <| jsonResponse StatusCode.unprocessableContent
      (Lean.Json.mkObj [("detail", .str s!"Missing field: {field}")])

/-- Helper: parse a user row from DB query result. -/
private def parseUserRow (row : Array (Option String)) : Option Models.User :=
  match row[0]?, row[1]?, row[2]?, row[3]?, row[4]? with
  | some (some email), some (some hpass), some displayName, some (some showLb), some (some createdAt) =>
    some {
      email
      hashedPassword := hpass
      displayName := displayName
      showOnLeaderboard := showLb == "t"
      createdAt
    }
  | _, _, _, _, _ => none

/-- Helper: look up a user by email, returning the full row. -/
private def getUser (db : DbConn) (email : String) : IO (Option Models.User) := do
  let rows ← Db.query db
    "SELECT email, hashed_password, display_name, show_on_leaderboard, created_at::text FROM users WHERE email = $1"
    #[email]
  match rows[0]? with
  | some row => pure (parseUserRow row)
  | none => pure none

-- ===================================================================
-- Auth Handlers
-- ===================================================================

/-- POST /auth/register
    Expects `{"email": "...", "password": "..."}`.
    Creates a pending registration with a 6-digit verification code.
    Password must be >= 8 characters. Max 50 accounts. -/
def register (db : DbConn) : HandlerFn := fun req => do
  match ← parseJsonBody req with
  | .error resp => pure resp
  | .ok json =>
    match requireField json "email", requireField json "password" with
    | .error resp, _ => pure resp
    | _, .error resp => pure resp
    | .ok email, .ok password =>
      -- Validate password length
      if password.length < 8 then
        pure <| jsonResponse StatusCode.badRequest
          (Lean.Json.mkObj [("detail", .str "Password must be at least 8 characters")])
      else
        -- Check if already registered
        let existing ← Db.query db
          "SELECT email FROM users WHERE email = $1" #[email]
        if existing.size > 0 then
          pure <| jsonResponse StatusCode.badRequest
            (Lean.Json.mkObj [("detail", .str "Email already registered")])
        else
          -- Check account limit
          let countRows ← Db.query db "SELECT COUNT(*) FROM users" #[]
          let count := match countRows[0]? >>= (·[0]?) with
            | some (some n) => n.toNat!
            | _ => 0
          if count >= 50 then
            pure <| jsonResponse StatusCode.forbidden
              (Lean.Json.mkObj [("detail", .str "Account limit reached. Registration is currently unavailable.")])
          else
            let code := s!"{(← IO.rand 100000 999999)}"
            let _ ← Db.execute db
              "INSERT INTO pending_registrations (email, hashed_password, verification_code) VALUES ($1, $2, $3) ON CONFLICT (email) DO UPDATE SET hashed_password = $2, verification_code = $3, created_at = NOW(), expires_at = NOW() + INTERVAL '15 minutes'"
              #[email, password, code]
            IO.println s!"[auth] Registration pending for {email}, code: {code}"
            pure <| jsonResponse StatusCode.ok
              (Lean.Json.mkObj [("message", .str "Verification code sent to email. Please check your inbox.")])

/-- POST /auth/verify
    Expects `{"email": "...", "code": "..."}`.
    Verifies the registration code, creates the user account with default categories. -/
def verifyRegistration (db : DbConn) : HandlerFn := fun req => do
  match ← parseJsonBody req with
  | .error resp => pure resp
  | .ok json =>
    match requireField json "email", requireField json "code" with
    | .error resp, _ => pure resp
    | _, .error resp => pure resp
    | .ok email, .ok code =>
      -- Look up non-expired pending registration
      let rows ← Db.query db
        "SELECT email, hashed_password, verification_code FROM pending_registrations WHERE email = $1 AND expires_at > NOW()"
        #[email]
      match rows[0]? with
      | none =>
        pure <| jsonResponse StatusCode.unauthorized
          (Lean.Json.mkObj [("detail", .str "Invalid or expired verification code")])
      | some row =>
        let storedCode := match row[2]? with | some (some c) => c | _ => ""
        if storedCode != code then
          pure <| jsonResponse StatusCode.unauthorized
            (Lean.Json.mkObj [("detail", .str "Invalid or expired verification code")])
        else
          let hashedPw := match row[1]? with | some (some p) => p | _ => ""
          -- Create user (display_name defaults to email)
          let _ ← Db.execute db
            "INSERT INTO users (email, hashed_password, display_name) VALUES ($1, $2, $1)"
            #[email, hashedPw]
          -- Create default categories
          let _ ← Db.execute db
            "INSERT INTO categories (email, name) VALUES ($1, 'Work'), ($1, 'Study'), ($1, 'Reading'), ($1, 'Exercise'), ($1, 'Meditation')"
            #[email]
          -- Clean up pending registration
          let _ ← Db.execute db
            "DELETE FROM pending_registrations WHERE email = $1" #[email]
          -- Return the new user
          match ← getUser db email with
          | some user =>
            pure <| jsonResponse StatusCode.created (user.toJson)
          | none =>
            pure <| jsonResponse StatusCode.internalServerError
              (Lean.Json.mkObj [("detail", .str "User creation failed")])

/-- POST /auth/login
    Expects `{"email": "...", "password": "..."}`.
    Verifies credentials and returns user object. -/
def login (db : DbConn) : HandlerFn := fun req => do
  match ← parseJsonBody req with
  | .error resp => pure resp
  | .ok json =>
    match requireField json "email", requireField json "password" with
    | .error resp, _ => pure resp
    | _, .error resp => pure resp
    | .ok email, .ok password =>
      match ← getUser db email with
      | none =>
        pure <| jsonResponse StatusCode.unauthorized
          (Lean.Json.mkObj [("detail", .str "Invalid email or password")])
      | some user =>
        -- TODO: Replace with bcrypt verify when FFI is ready
        if user.hashedPassword != password then
          pure <| jsonResponse StatusCode.unauthorized
            (Lean.Json.mkObj [("detail", .str "Invalid email or password")])
        else
          pure <| jsonResponse StatusCode.ok (user.toJson)

/-- POST /auth/request-code
    Expects `{"email": "..."}`.
    Sends a verification code for passwordless login. Does not reveal if email exists. -/
def requestVerificationCode (db : DbConn) : HandlerFn := fun req => do
  match ← parseJsonBody req with
  | .error resp => pure resp
  | .ok json =>
    match requireField json "email" with
    | .error resp => pure resp
    | .ok email =>
      -- Check if user exists (but don't reveal either way)
      let existing ← Db.query db
        "SELECT email FROM users WHERE email = $1" #[email]
      if existing.size > 0 then
        let code := s!"{(← IO.rand 100000 999999)}"
        let _ ← Db.execute db
          "INSERT INTO verification_codes (email, code) VALUES ($1, $2) ON CONFLICT (email) DO UPDATE SET code = $2, created_at = NOW(), expires_at = NOW() + INTERVAL '15 minutes'"
          #[email, code]
        IO.println s!"[auth] Verification code for {email}: {code}"
      -- Always return success (no email leak)
      pure <| jsonResponse StatusCode.ok
        (Lean.Json.mkObj [("message", .str "If email is registered, verification code has been sent")])

/-- POST /auth/login-code
    Expects `{"email": "...", "code": "..."}`.
    Login using a verification code (passwordless). Code is single-use. -/
def loginWithCode (db : DbConn) : HandlerFn := fun req => do
  match ← parseJsonBody req with
  | .error resp => pure resp
  | .ok json =>
    match requireField json "email", requireField json "code" with
    | .error resp, _ => pure resp
    | _, .error resp => pure resp
    | .ok email, .ok code =>
      let rows ← Db.query db
        "SELECT code FROM verification_codes WHERE email = $1 AND expires_at > NOW()"
        #[email]
      let storedCode := match rows[0]? >>= (·[0]?) with
        | some (some c) => c
        | _ => ""
      if storedCode != code || storedCode == "" then
        pure <| jsonResponse StatusCode.unauthorized
          (Lean.Json.mkObj [("detail", .str "Invalid or expired verification code")])
      else
        -- Delete used code (single-use)
        let _ ← Db.execute db
          "DELETE FROM verification_codes WHERE email = $1" #[email]
        match ← getUser db email with
        | some user =>
          pure <| jsonResponse StatusCode.ok (user.toJson)
        | none =>
          pure <| jsonResponse StatusCode.notFound
            (Lean.Json.mkObj [("detail", .str "User not found")])

/-- POST /auth/change-password
    Expects `{"email": "...", "current_password": "...", "new_password": "..."}`.
    Changes password after verifying the current one. -/
def changePassword (db : DbConn) : HandlerFn := fun req => do
  match ← parseJsonBody req with
  | .error resp => pure resp
  | .ok json =>
    match requireField json "email", requireField json "current_password",
          requireField json "new_password" with
    | .error resp, _, _ => pure resp
    | _, .error resp, _ => pure resp
    | _, _, .error resp => pure resp
    | .ok email, .ok currentPassword, .ok newPassword =>
      if newPassword.length < 8 then
        pure <| jsonResponse StatusCode.badRequest
          (Lean.Json.mkObj [("detail", .str "Password must be at least 8 characters")])
      else
        match ← getUser db email with
        | none =>
          pure <| jsonResponse StatusCode.unauthorized
            (Lean.Json.mkObj [("detail", .str "Current password is incorrect")])
        | some user =>
          -- TODO: Replace with bcrypt verify
          if user.hashedPassword != currentPassword then
            pure <| jsonResponse StatusCode.unauthorized
              (Lean.Json.mkObj [("detail", .str "Current password is incorrect")])
          else
            -- TODO: Replace with bcrypt hash
            let _ ← Db.execute db
              "UPDATE users SET hashed_password = $2 WHERE email = $1"
              #[email, newPassword]
            pure <| jsonResponse StatusCode.ok
              (Lean.Json.mkObj [("message", .str "Password changed successfully")])

/-- POST /auth/forgot-password
    Expects `{"email": "..."}`.
    Generates a password reset token. Does not reveal if email exists. -/
def forgotPassword (db : DbConn) : HandlerFn := fun req => do
  match ← parseJsonBody req with
  | .error resp => pure resp
  | .ok json =>
    match requireField json "email" with
    | .error resp => pure resp
    | .ok email =>
      let existing ← Db.query db
        "SELECT email FROM users WHERE email = $1" #[email]
      if existing.size > 0 then
        -- Generate a random token (hex encoded)
        let bytes ← IO.getRandomBytes 32
        let hexChars := "0123456789abcdef"
        let token := bytes.toList.map (fun b =>
          let n := b.toNat
          let hi := String.Pos.Raw.get hexChars ⟨n / 16⟩
          let lo := String.Pos.Raw.get hexChars ⟨n % 16⟩
          s!"{hi}{lo}") |>.foldl (· ++ ·) ""
        let _ ← Db.execute db
          "INSERT INTO password_reset_tokens (token, email) VALUES ($1, $2)"
          #[token, email]
        IO.println s!"[auth] Password reset token for {email}: {token}"
      -- Always return success
      pure <| jsonResponse StatusCode.ok
        (Lean.Json.mkObj [("message", .str "If email is registered, password reset link has been sent")])

/-- POST /auth/reset-password
    Expects `{"token": "...", "new_password": "..."}`.
    Resets password using a valid, unused, non-expired token. -/
def resetPassword (db : DbConn) : HandlerFn := fun req => do
  match ← parseJsonBody req with
  | .error resp => pure resp
  | .ok json =>
    match requireField json "token", requireField json "new_password" with
    | .error resp, _ => pure resp
    | _, .error resp => pure resp
    | .ok token, .ok newPassword =>
      if newPassword.length < 6 then
        pure <| jsonResponse StatusCode.badRequest
          (Lean.Json.mkObj [("detail", .str "Password must be at least 6 characters")])
      else
        let rows ← Db.query db
          "SELECT token, email, used FROM password_reset_tokens WHERE token = $1 AND expires_at > NOW()"
          #[token]
        match rows[0]? with
        | none =>
          pure <| jsonResponse StatusCode.unauthorized
            (Lean.Json.mkObj [("detail", .str "Invalid or expired reset token")])
        | some row =>
          let used := match row[2]? with | some (some u) => u != "0" | _ => true
          if used then
            pure <| jsonResponse StatusCode.unauthorized
              (Lean.Json.mkObj [("detail", .str "Invalid or expired reset token")])
          else
            let email := match row[1]? with | some (some e) => e | _ => ""
            -- TODO: Replace with bcrypt hash
            let _ ← Db.execute db
              "UPDATE users SET hashed_password = $2 WHERE email = $1"
              #[email, newPassword]
            let _ ← Db.execute db
              "UPDATE password_reset_tokens SET used = 1 WHERE token = $1"
              #[token]
            pure <| jsonResponse StatusCode.ok
              (Lean.Json.mkObj [("message", .str "Password reset successfully")])

-- ===================================================================
-- User CRUD Handlers
-- ===================================================================

/-- GET /users/{email}
    Returns user info. -/
def getMe (db : DbConn) : HandlerFn := fun req => do
  -- Extract email from query string (?email=...) since the framework
  -- doesn't support path params yet. In production this would come from
  -- auth middleware / JWT.
  let email := extractEmail req
  match ← getUser db email with
  | some user =>
    pure <| jsonResponse StatusCode.ok (user.toJson)
  | none =>
    pure <| jsonResponse StatusCode.notFound
      (Lean.Json.mkObj [("detail", .str "User not found")])
where
  extractEmail (req : Request) : String :=
    -- Try to get email from query string in the target
    match req.target with
    | .originForm _path (some query) =>
      -- Parse "email=foo@bar.com" from query string
      let pairs := query.splitOn "&"
      match pairs.findSome? (fun p =>
        let kv := p.splitOn "="
        match kv with
        | [k, v] => if k == "email" then some v else none
        | _ => none) with
      | some e => e
      | none => ""
    | _ => ""

/-- PATCH /users/{email}
    Expects optional fields: `{"display_name": "...", "show_on_leaderboard": true/false}`.
    Updates only provided fields. -/
def updateMe (db : DbConn) : HandlerFn := fun req => do
  let email := extractEmail req
  match ← getUser db email with
  | none =>
    pure <| jsonResponse StatusCode.notFound
      (Lean.Json.mkObj [("detail", .str "User not found")])
  | some _user =>
    match ← parseJsonBody req with
    | .error resp => pure resp
    | .ok json =>
      -- Update display_name if provided
      match json.getObjValAs? String "display_name" |>.toOption with
      | some name =>
        let _ ← Db.execute db
          "UPDATE users SET display_name = $2 WHERE email = $1"
          #[email, name]
      | none => pure ()
      -- Update show_on_leaderboard if provided
      match json.getObjValAs? Bool "show_on_leaderboard" |>.toOption with
      | some b =>
        let _ ← Db.execute db
          "UPDATE users SET show_on_leaderboard = $2::boolean WHERE email = $1"
          #[email, if b then "true" else "false"]
      | none => pure ()
      -- Return updated user
      match ← getUser db email with
      | some updated =>
        pure <| jsonResponse StatusCode.ok (updated.toJson)
      | none =>
        pure <| jsonResponse StatusCode.notFound
          (Lean.Json.mkObj [("detail", .str "User not found")])
where
  extractEmail (req : Request) : String :=
    match req.target with
    | .originForm _path (some query) =>
      let pairs := query.splitOn "&"
      match pairs.findSome? (fun p =>
        let kv := p.splitOn "="
        match kv with
        | [k, v] => if k == "email" then some v else none
        | _ => none) with
      | some e => e
      | none => ""
    | _ => ""

/-- DELETE /users/{email}
    Deletes user and all associated data (cascade). Returns 204 No Content. -/
def deleteMe (db : DbConn) : HandlerFn := fun req => do
  let email := extractEmail req
  let existing ← Db.query db
    "SELECT email FROM users WHERE email = $1" #[email]
  if existing.size == 0 then
    pure <| jsonResponse StatusCode.notFound
      (Lean.Json.mkObj [("detail", .str "User not found")])
  else
    let _ ← Db.execute db "DELETE FROM users WHERE email = $1" #[email]
    pure {
      status := StatusCode.noContent
      headers := [{ name := FieldName.contentType, value := "application/json" }]
      body := none
    }
where
  extractEmail (req : Request) : String :=
    match req.target with
    | .originForm _path (some query) =>
      let pairs := query.splitOn "&"
      match pairs.findSome? (fun p =>
        let kv := p.splitOn "="
        match kv with
        | [k, v] => if k == "email" then some v else none
        | _ => none) with
      | some e => e
      | none => ""
    | _ => ""

end Impl.Server.Handlers.Users
