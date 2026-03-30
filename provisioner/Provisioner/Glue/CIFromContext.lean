import Provisioner.Layers.CI
import Provisioner.Config
import SWELibCode.OS.ProcessOps

namespace Provisioner

/-- Runtime state for the provisioner. -/
structure ProvisionerContext where
  config     : ProvisionerConfig
  oauthToken : IO.Ref String
  vmIp       : IO.Ref (Option String)

/-- Concrete CILayer: uses SSH/SCP (via SWELib's ProcessOps) to deploy to the VM. -/
instance : CILayer ProvisionerContext where
  deployArtifact ctx artifact := do
    let ip ← ctx.vmIp.get
    match ip with
    | none => pure (.failed "VM IP not known — provision first")
    | some vmIp =>
      -- SCP the artifact to the VM
      let scpResult ← SWELibCode.OS.ProcessOps.exec "scp"
        #["-i", ctx.config.sshKeyPath, "-o", "StrictHostKeyChecking=no",
          artifact.localPath,
          s!"{ctx.config.sshUser}@{vmIp}:{artifact.remotePath}"]
      if scpResult.exitCode != 0 then
        pure (.failed s!"scp failed: {scpResult.stderr}")
      else
        pure .success

  runMigration ctx migration := do
    match migration.sql with
    | none => pure .alreadyApplied
    | some sql =>
      let ip ← ctx.vmIp.get
      match ip with
      | none => pure (.failed "VM IP not known")
      | some vmIp =>
        let result ← SWELibCode.OS.ProcessOps.exec "ssh"
          #["-i", ctx.config.sshKeyPath, "-o", "StrictHostKeyChecking=no",
            s!"{ctx.config.sshUser}@{vmIp}",
            s!"docker exec productivity-db psql -U productivity -c \"{sql}\""]
        if result.exitCode != 0 then
          pure (.failed result.stderr)
        else
          pure .success

  rollback _ctx := do
    sorry -- TODO: SSH into VM, docker compose down, docker compose up with previous version

end Provisioner
