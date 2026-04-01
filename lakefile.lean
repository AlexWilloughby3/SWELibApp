import Lake
open Lake DSL

package ProdTracker where
  leanOptions := #[⟨`autoImplicit, false⟩]

require SWELib from ".." / "SWELib"

lean_lib Spec where
  srcDir := "spec"
  roots := #[`Spec]

lean_lib Impl where
  srcDir := "impl"
  roots := #[`Impl]
  moreLinkArgs := #["-lssl", "-lcrypto", "-lpq", "-lcurl", "-lssh2"]

@[default_target]
lean_exe deploy where
  srcDir := "impl"
  root := `Impl.Deploy
