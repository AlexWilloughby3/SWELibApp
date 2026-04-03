import Lake
open Lake DSL

package ProdTracker where
  leanOptions := #[⟨`autoImplicit, false⟩]

require SWELib from ".." / "SWELib"

/-- Platform-specific library search paths.
    Lean's bundled clang uses its own sysroot, so we must explicitly provide
    -L paths to system libraries on both macOS (Homebrew) and Linux. -/
private def libSearchPaths : Array String :=
  if System.Platform.isOSX then #[
    "-L/opt/homebrew/opt/openssl@3/lib",
    "-L/opt/homebrew/opt/libssh2/lib",
    "-L/opt/homebrew/opt/curl/lib",
    "-L/opt/homebrew/lib/postgresql@18"
  ] else #[
    "-L/usr/lib/x86_64-linux-gnu"
  ]

private def nativeLinkArgs : Array String :=
  libSearchPaths ++ #["-lssl", "-lcrypto", "-lpq", "-lcurl", "-lssh2"]

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
