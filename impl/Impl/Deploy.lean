import SWELibImpl.Cloud.GceVm
import Spec
import Impl.Containers
import Impl.StartupScript

/-!
# GCE VM Deployment

Provisions a GCE VM using SWELib's formally-specified GceVm client,
then deploys Docker containers via `gcloud compute ssh`.
Reads configuration from environment variables so it works both locally
and in GitHub Actions.
-/

namespace Impl.Deploy

open SWELibImpl.Cloud.GceVm
open SWELibImpl.Cloud.GceVmJson (vmStatusToString)
open Spec.Infra (DeployConfig)
open SWELib.OS.Isolation (SshResult)
open Impl.Containers
open Impl.StartupScript

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
    throw <| IO.userError s!"Cannot deploy: VM is in transient state {vmStatusToString other}"

/-- Run a command on the VM via gcloud compute ssh. Throws on non-zero exit. -/
def sshRun (h : VMHandle) (command : String) : IO SshResult := do
  IO.println s!"[ssh] {command.take 80}..."
  let result ← sshInstance h command { strictHostKeyChecking := false }
  if result.exitCode != 0 then
    IO.eprintln s!"[ssh stderr] {result.stderr}"
    throw <| IO.userError s!"SSH command failed (exit {result.exitCode})"
  return result

/-- Path to the server binary (set via SERVER_BINARY_PATH env var, or default). -/
def serverBinaryPath : IO String := do
  let path ← IO.getEnv "SERVER_BINARY_PATH"
  pure (path.getD ".lake/build/bin/server")

/-- Deploy Docker containers onto the VM via SSH.
    SCPs the server binary to the VM's Docker build context,
    then generates docker run commands from typed DockerRunConfig values
    and executes them on the VM. -/
def deployContainers (h : VMHandle) (env : ContainerEnv) : IO Unit := do
  let buildDir := "/tmp/prodtracker-build"
  -- Ensure build directory exists on VM
  let _ ← sshRun h s!"mkdir -p {buildDir}"
  -- SCP the server binary to the VM's Docker build context
  let binPath ← serverBinaryPath
  IO.println s!"Uploading server binary ({binPath}) to VM..."
  let scpResult ← scpToInstance h [binPath] s!"{buildDir}/server"
  if scpResult.exitCode != 0 then
    IO.eprintln s!"[scp stderr] {scpResult.stderr}"
    throw <| IO.userError s!"SCP failed (exit {scpResult.exitCode})"
  IO.println "Server binary uploaded."
  let pgCfg := postgresConfig env
  let apiCfg := backendConfig env
  let script := generateProvisionScript #[pgCfg, apiCfg]
  IO.println "Deploying containers to VM..."
  let _ ← sshRun h script
  IO.println "Containers deployed."

/-- Run a soft SSH command (don't throw on non-zero exit). -/
def sshQuery (h : VMHandle) (command : String) : IO SshResult :=
  sshInstance h command { strictHostKeyChecking := false }

/-- Check container health and restart any that are not running.
    Returns the number of containers that had to be restarted. -/
def checkAndRestart (h : VMHandle) (env : ContainerEnv) : IO Nat := do
  let containers := #[postgresConfig env, backendConfig env]
  let mut restartCount := 0
  for cfg in containers do
    let fmt := "{{.State.Running}}"
    let result ← sshQuery h
      s!"sudo docker inspect --format '{fmt}' {cfg.name} 2>/dev/null || echo missing"
    let status := result.stdout.trimAscii.toString
    if status != "true" then
      IO.println s!"Container '{cfg.name}' is {status}. Restarting..."
      let runCmd := "sudo docker rm -f " ++ shellEscape cfg.name ++
        " 2>/dev/null || true && sudo " ++ dockerRunCommand cfg
      let restart ← sshQuery h runCmd
      if restart.exitCode == 0 then
        IO.println s!"Container '{cfg.name}' restarted."
      else
        IO.eprintln s!"Failed to restart '{cfg.name}': {restart.stderr}"
      restartCount := restartCount + 1
    else
      IO.println s!"Container '{cfg.name}' is running."
  return restartCount

/-- Supervisor loop: poll container health at a fixed interval.
    Runs until interrupted or `maxIterations` is reached (0 = unlimited). -/
def superviseLoop (h : VMHandle) (env : ContainerEnv)
    (intervalSecs : Nat := 30) (maxIterations : Nat := 0) : IO Unit := do
  IO.println s!"Supervising containers (interval: {intervalSecs}s)..."
  let mut i := 0
  while maxIterations == 0 || i < maxIterations do
    let restarted ← checkAndRestart h env
    if restarted > 0 then
      IO.println s!"[iter {i + 1}] Restarted {restarted} container(s)."
    else
      IO.println s!"[iter {i + 1}] All containers healthy."
    IO.sleep (intervalSecs * 1000).toUInt32
    i := i + 1

end Impl.Deploy

open Impl.Deploy Impl.Containers SWELibImpl.Cloud.GceVm SWELibImpl.Cloud.GceVmJson in
def main (args : List String) : IO Unit := do
  match args with
  | ["deploy"] => do
    let cfg ← readConfig
    let containerEnv ← readContainerEnv
    let h ← ensureVM cfg
    ensureRunning h
    deployContainers h containerEnv
    IO.println "Deploy complete. VM is running with containers."
  | ["containers"] => do
    let cfg ← readConfig
    let containerEnv ← readContainerEnv
    let h ← attachInstance cfg.project cfg.zone cfg.vmName
    ensureRunning h
    deployContainers h containerEnv
    IO.println "Container redeployment complete."
  | ["supervise"] => do
    let cfg ← readConfig
    let containerEnv ← readContainerEnv
    let h ← attachInstance cfg.project cfg.zone cfg.vmName
    ensureRunning h
    superviseLoop h containerEnv
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
    IO.println "Usage: deploy [deploy|containers|supervise|status|stop|delete]"
    IO.println ""
    IO.println "  deploy      — Create/start VM and deploy containers"
    IO.println "  containers  — Redeploy containers on running VM"
    IO.println "  supervise   — Poll container health, restart failures"
    IO.println "  status      — Show current VM state"
    IO.println "  stop        — Stop the VM"
    IO.println "  delete      — Stop and delete the VM"
