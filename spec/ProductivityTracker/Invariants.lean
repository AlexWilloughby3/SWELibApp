import ProductivityTracker.Types
import ProductivityTracker.Schema
import ProductivityTracker.SessionSplitting
import ProductivityTracker.Rbac

namespace ProductivityTracker

/-- Cross-cutting application invariants. -/

-- TODO: formalize and prove:
-- 1. Category cap: a user can have at most 20 categories
-- 2. Cascade completeness: deleting a user removes ALL their data
-- 3. Session duration positive: every session has duration > 0
-- 4. Category ownership: a session's category belongs to the same user
-- 5. Expired JWTs are always rejected
-- 6. Tampered JWTs are always rejected
-- 7. Refresh token rotation: used token is invalidated
-- 8. No plaintext passwords stored

end ProductivityTracker
