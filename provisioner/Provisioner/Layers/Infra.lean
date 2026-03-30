namespace Provisioner

/-- VM status as reported by GCE API. -/
inductive VMStatus where
  | provisioning
  | staging
  | running
  | stopping
  | terminated
  | notFound
  deriving Repr, DecidableEq

/-- Health status of a container on the VM. -/
inductive ContainerHealth where
  | healthy
  | unhealthy
  | notRunning
  deriving Repr, DecidableEq

/-- Infra layer — VM and container lifecycle management.
    Uses CILayer to deploy artifacts after provisioning. -/
class InfraLayer (ctx : Type) where
  /-- Create or start the GCE VM. Returns external IP. -/
  provisionVM : ctx → IO String

  /-- Get current VM status. -/
  getVMStatus : ctx → IO VMStatus

  /-- Start a stopped VM. -/
  startVM : ctx → IO Unit

  /-- Stop the VM (preserves disk). -/
  stopVM : ctx → IO Unit

  /-- Deploy docker-compose stack to the VM. -/
  deployStack : ctx → IO Unit

  /-- Check health of a specific container. -/
  containerHealth : ctx → String → IO ContainerHealth

  /-- Restart a specific container. -/
  restartContainer : ctx → String → IO Unit

  /-- Refresh the GCP OAuth2 access token. -/
  refreshToken : ctx → IO Unit

  /-- Check if the current OAuth2 token is still valid. -/
  tokenValid : ctx → IO Bool

end Provisioner
