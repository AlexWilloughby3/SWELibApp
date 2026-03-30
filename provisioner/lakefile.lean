import Lake
open Lake DSL

-- Depend on SWELib for specs, bridges, and code (GcpClient, ProcessOps, etc.)
require SWELib from FileSystem.FilePath.mk "/Users/alexdubs/Dropbox/Alex/Work/SWELib"

package provisioner where
  leanOptions := #[⟨`autoImplicit, false⟩]

@[default_target]
lean_exe provisioner where
  root := `Provisioner.Main
  moreLinkArgs := #["-lssl", "-lcrypto", "-lcurl"]
