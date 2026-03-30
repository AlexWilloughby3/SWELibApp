import Lake
open Lake DSL

require SWELib from ./ ".." / ".." / "SWELib"

package server where
  leanOptions := #[⟨`autoImplicit, false⟩]

@[default_target]
lean_exe server where
  root := `Server.Main
  moreLinkArgs := #["-lssl", "-lcrypto", "-lpq", "-lcurl", "-lssh2"]
