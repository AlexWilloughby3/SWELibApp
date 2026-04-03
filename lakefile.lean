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

lean_exe server where
  srcDir := "impl"
  root := `Impl.Server
  moreLinkArgs := #[
    "-L/opt/homebrew/opt/openssl@3/lib",
    "-L/opt/homebrew/opt/libssh2/lib",
    "-L/opt/homebrew/opt/curl/lib",
    "-L/opt/homebrew/lib/postgresql@18",
    "-lssl", "-lcrypto", "-lpq", "-lcurl", "-lssh2"
  ]
