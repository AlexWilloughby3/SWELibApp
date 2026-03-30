namespace Server

/-- Permissions are (action, resource, scope) triples. -/
structure Permission where
  action   : String  -- e.g. "create", "read", "update", "delete"
  resource : String  -- e.g. "session", "category", "user"
  scope    : String  -- "own" or "any"
  deriving Repr, DecidableEq

/-- Role names used in this application. -/
inductive RoleName where
  | user
  | admin
  deriving Repr, DecidableEq

/-- Check if a role grants a specific permission.
    Admin is a strict superset of user. -/
def roleGrantsPermission (role : RoleName) (perm : Permission) : Bool :=
  match role with
  | .admin => true  -- admin can do everything
  | .user =>
    -- users can only act on their own resources
    perm.scope == "own" && perm.resource != "user"

end Server
