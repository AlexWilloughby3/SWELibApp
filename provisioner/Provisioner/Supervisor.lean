import Provisioner.Layers.Infra
import Provisioner.Glue.CIFromContext

namespace Provisioner

/-- Supervisor loop — runs in the background, monitoring VM and container health.
    On detecting an issue, takes corrective action (restart container, start VM, etc.).

    The key property: you can kill and restart the provisioner and it will
    detect existing VM/container state and reattach rather than duplicate. -/
def supervisorLoop [InfraLayer ProvisionerContext] (ctx : ProvisionerContext) : IO Unit := do
  IO.println "supervisor: starting health check loop"
  sorry -- TODO: implement the loop:
  -- loop forever:
  --   1. Refresh OAuth2 token if near expiry
  --   2. Check VM status — if TERMINATED, start it
  --   3. Check container health (api, db) — if unhealthy, restart
  --   4. Sleep supervisorInterval (default 5s)

/-- Deploy subcommand: provision VM, deploy containers, run migrations.
    Idempotent — detects existing state. -/
def deploy [InfraLayer ProvisionerContext] (ctx : ProvisionerContext) : IO Unit := do
  IO.println "provisioner: starting deployment..."

  -- 1. Refresh token
  InfraLayer.refreshToken ctx

  -- 2. Provision or reattach to VM
  let vmIp ← InfraLayer.provisionVM ctx
  ctx.vmIp.set (some vmIp)
  IO.println s!"provisioner: VM ready at {vmIp}"

  -- 3. Deploy docker-compose stack
  InfraLayer.deployStack ctx
  IO.println "provisioner: containers deployed"

  -- 4. Wait for containers to be healthy
  sorry -- TODO: poll containerHealth for "api" and "db" until healthy

  IO.println "provisioner: deployment complete"

/-- Shutdown: gracefully stop containers and optionally stop the VM. -/
def shutdown [InfraLayer ProvisionerContext] (ctx : ProvisionerContext) : IO Unit := do
  IO.println "provisioner: shutting down..."

  -- Stop containers via SSH
  let ip ← ctx.vmIp.get
  match ip with
  | some vmIp =>
    IO.println s!"provisioner: stopping containers on {vmIp}"
    -- docker compose down on the VM
    sorry -- TODO: SSH docker compose down
  | none =>
    IO.println "provisioner: no VM IP known, skipping container shutdown"

  -- Optionally stop the VM to save cost
  if ctx.config.stopVmOnShutdown then
    IO.println "provisioner: stopping VM"
    InfraLayer.stopVM ctx
  else
    IO.println "provisioner: leaving VM running for faster restart"

end Provisioner
