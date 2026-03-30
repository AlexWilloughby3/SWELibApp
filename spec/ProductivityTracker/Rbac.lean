import SWELib.Security.Rbac

namespace ProductivityTracker

/-- This app's RBAC model: two roles (user, admin), action-centric permissions.
    Admin is a strict superset of user. -/

-- TODO: formalize using SWELib.Security.Rbac when that spec is fleshed out
-- Key properties to prove:
-- 1. Default deny: no role granting permission → request denied
-- 2. No self-escalation: user without "manage_roles" can't grant roles
-- 3. Admin superset: admin can do everything user can do (and more)
-- 4. Scope enforcement: "own" scope means owner_id = user.id

end ProductivityTracker
