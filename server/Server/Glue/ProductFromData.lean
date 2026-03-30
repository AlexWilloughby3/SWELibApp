import Server.Layers.Product
import Server.Layers.Data
import Server.AppContext
import Server.Domain.Session
import SWELibCode.Security.HashOps
import SWELibCode.Security.JwtValidator

namespace Server

/-- Concrete ProductLayer instance for AppContext.
    Implements all domain logic using DataLayer for persistence
    and SWELib's HashOps/JwtValidator for crypto. -/
instance [DataLayer AppContext] : ProductLayer AppContext where

  register ctx email password displayName := do
    -- Hash password with SHA-256 (TODO: switch to bcrypt when SWELib adds it)
    let hash := SWELibCode.Security.HashOps.hashString .sha256 password
    let q : ParamQuery := {
      sql := "INSERT INTO users (id, email, display_name, password_hash) VALUES (gen_random_uuid(), $1, $2, $3) RETURNING id, email, display_name"
      params := #[email, displayName, toString hash.digest]
    }
    let row ← DataLayer.execInsert ctx q
    match row with
    | some r =>
      let id := (r.get! 0).getD ""
      -- Assign default role
      let _ ← DataLayer.execMutate ctx {
        sql := "INSERT INTO user_roles (user_id, role_id) SELECT $1, id FROM roles WHERE name = 'user'"
        params := #[id]
      }
      -- Seed default categories
      for catName in defaultCategoryNames do
        let _ ← DataLayer.execMutate ctx {
          sql := "INSERT INTO categories (id, user_id, name) VALUES (gen_random_uuid(), $1, $2)"
          params := #[id, catName]
        }
      pure { id, email, displayName }
    | none => throw (IO.userError "registration insert returned no row")

  login _ctx _email _password := do
    sorry -- TODO: look up user, verify hash, create JWT pair

  validateToken _ctx _token := do
    sorry -- TODO: parse JWT, check expiry/signature, look up user

  refreshAuth _ctx _refreshToken := do
    sorry -- TODO: validate refresh token, issue new pair, invalidate old

  changePassword _ctx _userId _oldPw _newPw := do
    sorry -- TODO: verify old password, hash new, update

  authorize _ctx _user _perm := do
    sorry -- TODO: look up user roles, check roleGrantsPermission

  createCategory ctx userId name := do
    -- Check category cap
    let countResult ← DataLayer.execQuery ctx {
      sql := "SELECT COUNT(*) FROM categories WHERE user_id = $1"
      params := #[userId]
    }
    let count := match countResult.rows.get? 0 with
      | some row => ((row.get! 0).getD "0").toNat!
      | none => 0
    if count >= maxCategoriesPerUser then
      pure (.error .limitReached)
    else
      let q : ParamQuery := {
        sql := "INSERT INTO categories (id, user_id, name) VALUES (gen_random_uuid(), $1, $2) RETURNING id, user_id, name, is_active"
        params := #[userId, name]
      }
      let row ← DataLayer.execInsert ctx q
      match row with
      | some r => pure (.ok {
          id := (r.get! 0).getD ""
          userId := (r.get! 1).getD ""
          name := (r.get! 2).getD ""
          isActive := (r.get! 3).getD "true" == "true"
        })
      | none => pure (.error (.invalidInput "insert failed"))

  listCategories ctx userId := do
    let result ← DataLayer.execQuery ctx {
      sql := "SELECT id, user_id, name, is_active FROM categories WHERE user_id = $1 ORDER BY name"
      params := #[userId]
    }
    pure (result.rows.toList.map fun r => {
      id := (r.get! 0).getD ""
      userId := (r.get! 1).getD ""
      name := (r.get! 2).getD ""
      isActive := (r.get! 3).getD "true" == "true"
    })

  deleteCategory _ctx _userId _catId := do
    sorry -- TODO: verify ownership, DELETE CASCADE

  logSession ctx userId catId durationSeconds startedAt := do
    if crossesMidnight startedAt durationSeconds then
      let split := splitAtMidnight startedAt durationSeconds
      -- Transaction: insert both halves atomically
      DataLayer.withTransaction ctx fun c => do
        let s1 ← DataLayer.execInsert c {
          sql := "INSERT INTO focus_sessions (id, user_id, category_id, duration_seconds, started_at) VALUES (gen_random_uuid(), $1, $2, $3, $4) RETURNING id, user_id, category_id, duration_seconds, started_at"
          params := #[userId, catId, toString split.before, startedAt]
        }
        let s2 ← DataLayer.execInsert c {
          sql := "INSERT INTO focus_sessions (id, user_id, category_id, duration_seconds, started_at) VALUES (gen_random_uuid(), $1, $2, $3, $4) RETURNING id, user_id, category_id, duration_seconds, started_at"
          params := #[userId, catId, toString split.after, startedAt]  -- TODO: adjust start time for second half
        }
        pure [s1, s2].filterMap id |>.map fun r => {
          id := (r.get! 0).getD ""
          userId := (r.get! 1).getD ""
          categoryId := (r.get! 2).getD ""
          durationSeconds := ((r.get! 3).getD "0").toNat!
          startedAt := (r.get! 4).getD ""
        }
    else
      let row ← DataLayer.execInsert ctx {
        sql := "INSERT INTO focus_sessions (id, user_id, category_id, duration_seconds, started_at) VALUES (gen_random_uuid(), $1, $2, $3, $4) RETURNING id, user_id, category_id, duration_seconds, started_at"
        params := #[userId, catId, toString durationSeconds, startedAt]
      }
      match row with
      | some r => pure [{
          id := (r.get! 0).getD ""
          userId := (r.get! 1).getD ""
          categoryId := (r.get! 2).getD ""
          durationSeconds := ((r.get! 3).getD "0").toNat!
          startedAt := (r.get! 4).getD ""
        }]
      | none => pure []

  listSessions _ctx _userId _range _params := do
    sorry -- TODO: SELECT with date range filter + pagination

  deleteSession _ctx _userId _sessionId := do
    sorry -- TODO: verify ownership, DELETE

  createGoal _ctx _userId _catId _goalType := do
    sorry -- TODO: check uniqueness (user, category, goal_type), INSERT

  toggleGoal _ctx _userId _goalId _date := do
    sorry -- TODO: INSERT/DELETE checkbox_completions

  goalProgress _ctx _userId _catId _range := do
    sorry -- TODO: aggregate sessions + checkbox completions

  userStats _ctx _userId _range := do
    sorry -- TODO: aggregate by category within date range

  weeklySummary _ctx _userId := do
    sorry -- TODO: userStats for current week

end Server
