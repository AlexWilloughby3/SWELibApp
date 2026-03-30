import Provisioner.Layers.Infra
import Provisioner.Layers.CI
import Provisioner.Glue.CIFromContext
import SWELibCode.Cloud.GcpClient
import SWELibCode.OS.ProcessOps

namespace Provisioner

/-- Concrete InfraLayer: uses SWELib's GcpClient for VM lifecycle
    and CILayer for deployments. -/
instance [CILayer ProvisionerContext] : InfraLayer ProvisionerContext where

  provisionVM ctx := do
    let token ← ctx.oauthToken.get
    let cfg : SWELibCode.Cloud.GcpClient.GcpConfig := {
      accessToken := token
      projectId := ctx.config.gcpProject
    }
    -- Check if VM already exists
    let status ← InfraLayer.getVMStatus ctx
    match status with
    | .running =>
      -- VM already running, get its IP
      let result ← SWELibCode.Cloud.GcpClient.getInstance cfg ctx.config.gcpZone ctx.config.vmName
      sorry -- TODO: parse JSON response for external IP
    | .terminated =>
      -- Start the stopped VM
      InfraLayer.startVM ctx
      sorry -- TODO: wait for RUNNING, get IP
    | .notFound =>
      -- Create new VM
      sorry -- TODO: POST to GCE API to create VM, wait for RUNNING, get IP
    | _ =>
      sorry -- TODO: wait for transition to complete

  getVMStatus ctx := do
    let token ← ctx.oauthToken.get
    let cfg : SWELibCode.Cloud.GcpClient.GcpConfig := {
      accessToken := token
      projectId := ctx.config.gcpProject
    }
    let result ← SWELibCode.Cloud.GcpClient.getInstance cfg ctx.config.gcpZone ctx.config.vmName
    match result with
    | .error (404, _) => pure .notFound
    | .error (_, msg) => throw (IO.userError s!"GCE API error: {msg}")
    | .ok body =>
      sorry -- TODO: parse JSON for "status" field, map to VMStatus

  startVM ctx := do
    let token ← ctx.oauthToken.get
    let cfg : SWELibCode.Cloud.GcpClient.GcpConfig := {
      accessToken := token
      projectId := ctx.config.gcpProject
    }
    let path := s!"/compute/v1/projects/{ctx.config.gcpProject}/zones/{ctx.config.gcpZone}/instances/{ctx.config.vmName}/start"
    let _ ← SWELibCode.Cloud.GcpClient.postResource cfg path ""
    pure ()

  stopVM ctx := do
    let token ← ctx.oauthToken.get
    let cfg : SWELibCode.Cloud.GcpClient.GcpConfig := {
      accessToken := token
      projectId := ctx.config.gcpProject
    }
    let path := s!"/compute/v1/projects/{ctx.config.gcpProject}/zones/{ctx.config.gcpZone}/instances/{ctx.config.vmName}/stop"
    let _ ← SWELibCode.Cloud.GcpClient.postResource cfg path ""
    pure ()

  deployStack ctx := do
    -- SCP docker-compose.yml and .env to VM, then docker compose up
    let _ ← CILayer.deployArtifact ctx { localPath := "docker-compose.yml", remotePath := "~/docker-compose.yml" }
    let ip ← ctx.vmIp.get
    match ip with
    | none => throw (IO.userError "VM IP not known")
    | some vmIp =>
      let _ ← SWELibCode.OS.ProcessOps.exec "ssh"
        #["-i", ctx.config.sshKeyPath, s!"{ctx.config.sshUser}@{vmIp}",
          "cd ~ && docker compose up -d"]
      pure ()

  containerHealth ctx containerName := do
    let ip ← ctx.vmIp.get
    match ip with
    | none => pure .notRunning
    | some vmIp =>
      let result ← SWELibCode.OS.ProcessOps.exec "ssh"
        #["-i", ctx.config.sshKeyPath, s!"{ctx.config.sshUser}@{vmIp}",
          s!"docker inspect --format='{{{{.State.Health.Status}}}}' {containerName}"]
      if result.exitCode != 0 then pure .notRunning
      else if result.stdout.trim == "healthy" then pure .healthy
      else pure .unhealthy

  restartContainer ctx containerName := do
    let ip ← ctx.vmIp.get
    match ip with
    | none => throw (IO.userError "VM IP not known")
    | some vmIp =>
      let _ ← SWELibCode.OS.ProcessOps.exec "ssh"
        #["-i", ctx.config.sshKeyPath, s!"{ctx.config.sshUser}@{vmIp}",
          s!"docker compose restart {containerName}"]
      pure ()

  refreshToken ctx := do
    sorry -- TODO: read service account JSON, create JWT, exchange for access token

  tokenValid _ctx := do
    sorry -- TODO: check token expiry

end Provisioner
