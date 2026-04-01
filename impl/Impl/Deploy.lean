import SWELibImpl.Cloud.GceVm
import Spec

/-!
# GCE VM Deployment

Provisions a GCE VM using SWELib's formally-specified GceVm client.
Reads configuration from environment variables so it works both locally
and in GitHub Actions.
-/

namespace Impl.Deploy

open SWELibImpl.Cloud.GceVm
open SWELibImpl.Cloud.GceVmJson (vmStatusToString)
open Spec.Infra (DeployConfig)

/-- Read deployment config from environment variables. -/
def readConfig : IO DeployConfig := do
  let project ← IO.getEnv "GCP_PROJECT"
    |>.map (·.getD "")
  let zone ← IO.getEnv "GCP_ZONE"
    |>.map (·.getD "us-central1-a")
  let vmName ← IO.getEnv "VM_NAME"
    |>.map (·.getD "prodtracker-vm")
  let machineType ← IO.getEnv "VM_MACHINE_TYPE"
    |>.map (·.getD "e2-small")
  if project.isEmpty then
    throw <| IO.userError "GCP_PROJECT environment variable is required"
  return {
    project
    zone
    vmName
    machineType
  }

/-- Try to attach to an existing VM; if it doesn't exist, create it. -/
def ensureVM (cfg : DeployConfig) : IO VMHandle := do
  IO.println s!"Checking for existing VM '{cfg.vmName}' in {cfg.project}/{cfg.zone}..."
  try
    let h ← attachInstance cfg.project cfg.zone cfg.vmName
    let status ← h.getStatus
    IO.println s!"Found existing VM in state: {vmStatusToString status}"
    return h
  catch _ =>
    IO.println s!"VM not found. Creating '{cfg.vmName}' ({cfg.machineType})..."
    let h ← createInstance cfg.project cfg.zone cfg.vmName cfg.machineType
      cfg.imageFamily cfg.imageProject cfg.diskSizeGb
    IO.println s!"VM created and running."
    return h

/-- Ensure the VM is in the running state. -/
def ensureRunning (h : VMHandle) : IO Unit := do
  let status ← refreshStatus h
  match status with
  | .running =>
    IO.println "VM is running."
  | .terminated => do
    IO.println "VM is terminated. Starting..."
    startInstance h
    IO.println "VM started."
  | .suspended => do
    IO.println "VM is suspended. Resuming..."
    resumeInstance h
    IO.println "VM resumed."
  | other =>
    IO.println s!"VM is in state {vmStatusToString other}, waiting for it to settle..."
    -- In a real deploy we'd poll; for now just report
    throw <| IO.userError s!"Cannot deploy: VM is in transient state {vmStatusToString other}"

end Impl.Deploy

open Impl.Deploy SWELibImpl.Cloud.GceVm SWELibImpl.Cloud.GceVmJson in
def main (args : List String) : IO Unit := do
  match args with
  | ["deploy"] => do
    let cfg ← readConfig
    let h ← ensureVM cfg
    ensureRunning h
    IO.println "Deploy complete. VM is running and ready."
  | ["status"] => do
    let cfg ← readConfig
    let h ← attachInstance cfg.project cfg.zone cfg.vmName
    let status ← refreshStatus h
    IO.println s!"VM '{cfg.vmName}': {vmStatusToString status}"
  | ["stop"] => do
    let cfg ← readConfig
    let h ← attachInstance cfg.project cfg.zone cfg.vmName
    IO.println s!"Stopping VM '{cfg.vmName}'..."
    stopInstance h
    IO.println "VM stopped."
  | ["delete"] => do
    let cfg ← readConfig
    let h ← attachInstance cfg.project cfg.zone cfg.vmName
    let status ← h.getStatus
    if status != .terminated then do
      IO.println "Stopping VM before delete..."
      stopInstance h
    IO.println s!"Deleting VM '{cfg.vmName}'..."
    deleteInstance h
    IO.println "VM deleted."
  | _ => do
    IO.println "Usage: deploy [deploy|status|stop|delete]"
    IO.println ""
    IO.println "  deploy  — Create or start the VM"
    IO.println "  status  — Show current VM state"
    IO.println "  stop    — Stop the VM"
    IO.println "  delete  — Stop and delete the VM"
