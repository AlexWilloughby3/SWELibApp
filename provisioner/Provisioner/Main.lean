import Provisioner.Config
import Provisioner.Glue.CIFromContext
import Provisioner.Glue.InfraFromCI
import Provisioner.Supervisor

namespace Provisioner

def main : IO Unit := do
  let args ← IO.getArgs

  let config ← ProvisionerConfig.fromEnv
  let oauthToken ← IO.mkRef ""
  let vmIp ← IO.mkRef (none : Option String)
  let ctx : ProvisionerContext := { config, oauthToken, vmIp }

  match args.get? 0 with
  | some "deploy" =>
    -- Provision VM, deploy containers, run migrations
    deploy ctx
  | some "supervise" =>
    -- Deploy first, then enter supervisor loop
    deploy ctx
    supervisorLoop ctx
  | some "shutdown" =>
    -- Detect existing VM and shut it down
    InfraLayer.refreshToken ctx
    let status ← InfraLayer.getVMStatus ctx
    match status with
    | .running =>
      -- Get VM IP so shutdown can SSH in
      let ip ← InfraLayer.provisionVM ctx  -- reattaches, doesn't create new
      ctx.vmIp.set (some ip)
      shutdown ctx
    | _ =>
      IO.println "provisioner: VM is not running, nothing to shut down"
  | some "status" =>
    -- Just check VM status
    InfraLayer.refreshToken ctx
    let status ← InfraLayer.getVMStatus ctx
    IO.println s!"VM status: {repr status}"
  | _ =>
    IO.println "usage: provisioner <deploy|supervise|shutdown|status>"

end Provisioner

def main : IO Unit := Provisioner.main
