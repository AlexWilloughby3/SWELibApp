namespace Provisioner

/-- Migration descriptor — SQL or container deployment. -/
structure Migration where
  name : String
  sql  : Option String  -- for DB migrations
  deriving Repr

inductive MigrationResult where
  | success
  | alreadyApplied
  | failed (msg : String)
  deriving Repr

/-- Artifact to deploy — docker-compose.yml, nginx.conf, .env, or the server container image. -/
structure Artifact where
  localPath : String
  remotePath : String
  deriving Repr

inductive DeployResult where
  | success
  | failed (msg : String)
  deriving Repr

/-- CI layer — deployment primitives.
    The provisioner uses these to push files to the VM and bring up containers.
    This is NOT GitHub Actions CI — it's the provisioner self-deploying at runtime. -/
class CILayer (ctx : Type) where
  /-- SCP a file to the VM and run a deploy command via SSH. -/
  deployArtifact : ctx → Artifact → IO DeployResult

  /-- Run a SQL migration on the remote Postgres (via SSH + psql). -/
  runMigration : ctx → Migration → IO MigrationResult

  /-- Roll back to a previous docker-compose state. -/
  rollback : ctx → IO DeployResult

end Provisioner
