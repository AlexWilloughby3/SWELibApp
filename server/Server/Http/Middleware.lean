import Server.Layers.Product

namespace Server.Http

/-- Extract Bearer token from Authorization header. -/
def extractBearerToken (authHeader : Option String) : Option String :=
  authHeader.bind fun h =>
    if h.startsWith "Bearer " then some (h.drop 7) else none

/-- Auth middleware: validate JWT and attach user to request context. -/
def withAuth [ProductLayer ctx] (ctx_ : ctx) (token : String) (f : User → IO α) : IO α := do
  match ← ProductLayer.validateToken ctx_ token with
  | some user => f user
  | none => throw (IO.userError "401 Unauthorized")

/-- RBAC middleware: check that the authenticated user has the required permission. -/
def withPermission [ProductLayer ctx] (ctx_ : ctx) (user : User) (perm : Permission) (f : IO α) : IO α := do
  if ← ProductLayer.authorize ctx_ user perm then f
  else throw (IO.userError "403 Forbidden")

end Server.Http
