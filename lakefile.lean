import Lake
open Lake DSL

package ProdTracker where
  leanOptions := #[⟨`autoImplicit, false⟩]

require SWELib from ".." / "SWELib"

/-- macOS Homebrew library search paths (no-op on Linux where libs are in standard paths). -/
private def brewLibPaths : Array String :=
  if System.Platform.isOSX then #[
    "-L/opt/homebrew/opt/openssl@3/lib",
    "-L/opt/homebrew/opt/libssh2/lib",
    "-L/opt/homebrew/opt/curl/lib",
    "-L/opt/homebrew/lib/postgresql@18"
  ] else #[]

private def nativeLinkArgs : Array String :=
  brewLibPaths ++ #["-lssl", "-lcrypto", "-lpq", "-lcurl", "-lssh2"]

lean_lib Spec where
  srcDir := "spec"
  roots := #[`Spec]

lean_lib Impl where
  srcDir := "impl"
  roots := #[`Impl]
  moreLinkArgs := nativeLinkArgs

@[default_target]
lean_exe deploy where
  srcDir := "impl"
  root := `Impl.Deploy

lean_exe server where
  srcDir := "impl"
  root := `Impl.Server
  moreLinkArgs := nativeLinkArgs
