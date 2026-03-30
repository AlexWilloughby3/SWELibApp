namespace Provisioner

/-- Provisioner configuration parsed from environment or .env file.
    Used to authenticate to GCP and manage the VM. -/
structure ProvisionerConfig where
  gcpProject         : String  -- e.g. "my-project-123"
  gcpZone            : String  -- e.g. "us-central1-a"
  serviceAccountKey  : String  -- path to JSON key file
  vmName             : String  -- e.g. "productivity-tracker-vm"
  vmMachineType      : String  -- e.g. "e2-small"
  sshKeyPath         : String  -- path to private key for SSH to VM
  sshUser            : String  -- e.g. "deploy"
  stopVmOnShutdown   : Bool    -- whether to stop VM when provisioner exits
  deriving Repr

def ProvisionerConfig.fromEnv : IO ProvisionerConfig := do
  let get (key : String) : IO String := do
    match (← IO.getEnv key) with
    | some v => pure v
    | none => throw (IO.userError s!"missing required env var: {key}")
  pure {
    gcpProject := ← get "GCP_PROJECT"
    gcpZone := (← IO.getEnv "GCP_ZONE").getD "us-central1-a"
    serviceAccountKey := ← get "GCP_SERVICE_ACCOUNT_KEY"
    vmName := (← IO.getEnv "VM_NAME").getD "productivity-tracker-vm"
    vmMachineType := (← IO.getEnv "VM_MACHINE_TYPE").getD "e2-small"
    sshKeyPath := ← get "SSH_KEY_PATH"
    sshUser := (← IO.getEnv "SSH_USER").getD "deploy"
    stopVmOnShutdown := (← IO.getEnv "STOP_VM_ON_SHUTDOWN").getD "false" == "true"
  }

end Provisioner
