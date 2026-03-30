import ProductivityTracker.Types

namespace ProductivityTracker

/-- Formal specification of the database schema.
    Proves referential integrity and constraint properties. -/

-- TODO: formalize schema using SWELib.Db.Sql.Schema
-- Key properties to prove:
-- 1. Cascade completeness: deleting a user removes all dependent rows
-- 2. Goal uniqueness: at most one goal per (user, category, goal_type)
-- 3. Session duration positive: CHECK(duration_seconds > 0) is enforced
-- 4. Category uniqueness per user: UNIQUE(user_id, name) is enforced

end ProductivityTracker
