import SWELib.Cloud.Docker

/-!
# Docker Command Generation

Converts `DockerRunConfig` values into shell command strings using
`serializeFlags` from SWELib. These commands are then executed on
the VM via `gcloud compute ssh`.
-/

namespace Impl.StartupScript

open SWELib.Cloud.Docker

/-- Shell-escape a single argument (wrap in single quotes, escape inner quotes). -/
def shellEscape (s : String) : String :=
  "'" ++ s.replace "'" "'\\''" ++ "'"

/-- Convert a `DockerRunConfig` to a `docker run` command string. -/
def dockerRunCommand (cfg : DockerRunConfig) : String :=
  let flags := serializeFlags cfg
  let escaped := flags.map shellEscape
  "docker run " ++ " ".intercalate escaped.toList

/-- Generate a single shell script that installs Docker (if needed),
    pulls images, removes old containers, and starts new ones.
    Containers are started in dependency order (callers put deps first). -/
def generateProvisionScript (configs : Array DockerRunConfig) : String :=
  let header := "set -euo pipefail"
  let installDocker := String.intercalate "\n" [
    "if ! command -v docker &> /dev/null; then",
    "  sudo apt-get update -y",
    "  sudo apt-get install -y docker.io",
    "  sudo systemctl enable docker",
    "  sudo systemctl start docker",
    "fi",
    "for i in $(seq 1 30); do sudo docker info &>/dev/null && break; sleep 1; done"
  ]
  let pullAndRun := configs.map fun cfg =>
    let pullCmd := s!"sudo docker pull {shellEscape cfg.image}"
    let stopOld := s!"sudo docker rm -f {shellEscape cfg.name} 2>/dev/null || true"
    let runCmd := "sudo " ++ dockerRunCommand cfg
    s!"{pullCmd}\n{stopOld}\n{runCmd}"
  let body := "\n\n".intercalate pullAndRun.toList
  s!"{header}\n\n{installDocker}\n\n{body}"

end Impl.StartupScript
