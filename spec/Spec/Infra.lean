import SWELib.OS.Isolation.Types
import SWELib.OS.Isolation.Nodes

/-!
# Infrastructure Specification

Formal specification of the productivity tracker's infrastructure requirements.
The app runs on a single GCE VM. We import the GCE VM lifecycle LTS from SWELib
and define what a valid deployment looks like.
-/

namespace Spec.Infra

open SWELib.Foundations (LTS)
open SWELib.OS.Isolation (VMStatus VMLifecycleAction VMAction VMNode gceVMNodeLTS)

/-- The GCP project configuration for our deployment. -/
structure DeployConfig where
  project : String
  zone : String
  vmName : String
  machineType : String
  imageFamily : String := "debian-12"
  imageProject : String := "debian-cloud"
  diskSizeGb : Nat := 10

/-- A deployment is valid when the VM reaches the `running` state. -/
def deployedState : VMStatus := .running

/-- A VM is in a safe-to-delete state. -/
def canDelete (s : VMStatus) : Prop :=
  s = .terminated ∨ s = .stopping

/-- After a successful deploy, the VM must be running.
    This is the postcondition we want our deploy executable to satisfy. -/
theorem deploy_reaches_running :
    (gceVMNodeLTS (α := Unit)).Tr .staging (.lifecycle .bootComplete) .running := by
  simp [gceVMNodeLTS]

/-- After stop + stopComplete, we reach terminated (safe to delete). -/
theorem shutdown_reaches_terminated :
    (gceVMNodeLTS (α := Unit)).Tr .running (.lifecycle .stop) .pendingStop ∧
    (gceVMNodeLTS (α := Unit)).Tr .pendingStop (.lifecycle .gracefulPeriodEnded) .stopping ∧
    (gceVMNodeLTS (α := Unit)).Tr .stopping (.lifecycle .stopComplete) .terminated := by
  simp [gceVMNodeLTS]

end Spec.Infra
