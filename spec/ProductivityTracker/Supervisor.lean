namespace ProductivityTracker

/-- Formal properties of the provisioner's supervisor loop. -/

-- TODO: formalize:
-- 1. Liveness: if Postgres is unhealthy, supervisor eventually restarts it
-- 2. Safety: supervisor never takes down a healthy component
-- 3. Idempotency: migrations can run multiple times safely
-- 4. Crash recovery: if provisioner restarts, it detects existing VM/containers
--    and reattaches rather than creating duplicates
-- 5. Token refresh: OAuth2 token is refreshed before expiry

end ProductivityTracker
