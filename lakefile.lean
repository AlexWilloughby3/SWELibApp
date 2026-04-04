import Lake
open Lake DSL

package ProdTracker where
  leanOptions := #[⟨`autoImplicit, false⟩]

require SWELib from ".." / "SWELib"

/-- Run a shell command and return trimmed stdout, or empty string on failure. -/
private unsafe def runCmdImpl (cmd : String) (args : Array String) : String :=
  match unsafeBaseIO (IO.Process.output { cmd, args } |>.toBaseIO) with
  | Except.ok out => if out.exitCode == 0 then out.stdout.trimAscii.toString else ""
  | Except.error _ => ""

@[implemented_by runCmdImpl]
private opaque runCmd (cmd : String) (args : Array String) : String

/-- Platform-specific native link arguments.
    On macOS: use Homebrew -L paths + -l flags.
    On Linux: pass absolute .so paths to avoid contaminating Lean's bundled
    sysroot with system glibc (which causes __libc_csu_init errors on x86_64). -/
private def nativeLinkArgs : Array String :=
  if System.Platform.isOSX then #[
    "-L/opt/homebrew/opt/openssl@3/lib",
    "-L/opt/homebrew/opt/libssh2/lib",
    "-L/opt/homebrew/opt/curl/lib",
    "-L/opt/homebrew/lib/postgresql@18",
    "-lssl", "-lcrypto", "-lpq", "-lcurl", "-lssh2"
  ] else
    -- Detect multiarch triplet (e.g. x86_64-linux-gnu, aarch64-linux-gnu)
    let triple := runCmd "cc" #["-dumpmachine"]
    let libDir := s!"/usr/lib/{triple}"
    #["-Wl,--allow-shlib-undefined",
      s!"{libDir}/libssl.so", s!"{libDir}/libcrypto.so",
      s!"{libDir}/libpq.so", s!"{libDir}/libcurl.so",
      s!"{libDir}/libssh2.so"]

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
