import SWELib.Cloud.Docker

/-!
# Container Configurations

Typed `DockerRunConfig` definitions for the two containers that run on
the GCE VM: a PostgreSQL database and the backend API server.
The backend Dockerfile is defined in Lean using SWELib's
`DockerfileInstruction` types and built directly on the VM.
-/

namespace Impl.Containers

open SWELib.Cloud.Docker

/-- Environment values needed to configure both containers. -/
structure ContainerEnv where
  pgPassword : String
  jwtSecret : String

/-- Read container environment from env vars. -/
def readContainerEnv : IO ContainerEnv := do
  let pgPassword ← IO.getEnv "PG_PASSWORD"
    |>.map (·.getD "")
  let jwtSecret ← IO.getEnv "JWT_SECRET"
    |>.map (·.getD "")
  if pgPassword.isEmpty then
    throw <| IO.userError "PG_PASSWORD environment variable is required"
  if jwtSecret.isEmpty then
    throw <| IO.userError "JWT_SECRET environment variable is required"
  return { pgPassword, jwtSecret }

/-- The backend Dockerfile, defined as typed instructions.
    Expects the `server` binary in the Docker build context. -/
def backendDockerfile : Dockerfile := #[
  .from "debian:12-slim",
  .run #["apt-get", "update", "-y"] true,
  .run #["apt-get", "install", "-y", "--no-install-recommends",
         "libpq5", "libssl3", "libcurl4", "libssh2-1", "ca-certificates"] true,
  .run #["rm", "-rf", "/var/lib/apt/lists/*"] true,
  .workdir "/app",
  .copy #["server"] "/app/server" "",
  .run #["chmod", "+x", "/app/server"] true,
  .expose 8000,
  .cmd #["/app/server"] false
]

/-- The image tag used for the locally-built backend image. -/
def backendImageTag : String := "prodtracker-api:latest"

/-- Render a `DockerfileInstruction` to its textual form. -/
def renderInstruction : DockerfileInstruction → String
  | .from image asName =>
    if asName.isEmpty then s!"FROM {image}" else s!"FROM {image} AS {asName}"
  | .run cmd shell =>
    if shell then s!"RUN {" ".intercalate cmd.toList}"
    else s!"RUN {reprJsonArray cmd}"
  | .copy srcs dest from_ =>
    let fromClause := if from_.isEmpty then "" else s!"--from={from_} "
    s!"COPY {fromClause}{" ".intercalate srcs.toList} {dest}"
  | .add srcs dest =>
    s!"ADD {" ".intercalate srcs.toList} {dest}"
  | .env key value => s!"ENV {key}={value}"
  | .workdir path => s!"WORKDIR {path}"
  | .expose port protocol => s!"EXPOSE {port}/{protocol}"
  | .cmd args shell =>
    if shell then s!"CMD {" ".intercalate args.toList}"
    else s!"CMD {reprJsonArray args}"
  | .entrypoint args shell =>
    if shell then s!"ENTRYPOINT {" ".intercalate args.toList}"
    else s!"ENTRYPOINT {reprJsonArray args}"
  | .arg name default_ =>
    match default_ with
    | some d => s!"ARG {name}={d}"
    | none => s!"ARG {name}"
  | .label key value => s!"LABEL {key}={value}"
  | .volume path => s!"VOLUME {path}"
  | .user user group =>
    if group.isEmpty then s!"USER {user}" else s!"USER {user}:{group}"
  | .healthcheck cmd interval timeout startPeriod retries =>
    match cmd with
    | none => "HEALTHCHECK NONE"
    | some args =>
      let opts := s!"--interval={interval}s --timeout={timeout}s --start-period={startPeriod}s --retries={retries}"
      s!"HEALTHCHECK {opts} CMD {" ".intercalate args.toList}"
  | .shell args => s!"SHELL {reprJsonArray args}"
  | .stopsignal signal => s!"STOPSIGNAL {signal}"
where
  reprJsonArray (arr : Array String) : String :=
    let elems := arr.toList.map (fun s => s!"\"{s}\"")
    "[" ++ ", ".intercalate elems ++ "]"

/-- Render a full Dockerfile to a string. -/
def renderDockerfile (df : Dockerfile) : String :=
  "\n".intercalate ((df : Array DockerfileInstruction).toList.map renderInstruction)

/-- PostgreSQL 16 container configuration. -/
def postgresConfig (env : ContainerEnv) : DockerRunConfig := {
  image := "postgres:16-alpine"
  name := "prodtracker-db"
  networkMode := "host"
  env := #[
    "POSTGRES_USER=productivity",
    s!"POSTGRES_PASSWORD={env.pgPassword}",
    "POSTGRES_DB=productivity"
  ]
  volumes := #[{
    source := "pg-data"
    target := "/var/lib/postgresql/data"
  }]
  restart := .unlessStopped
  detach := true
}

/-- Backend API server container configuration. -/
def backendConfig (env : ContainerEnv) : DockerRunConfig := {
  image := backendImageTag
  name := "prodtracker-api"
  networkMode := "host"
  env := #[
    "PG_HOST=localhost",
    "PG_PORT=5432",
    "PG_USER=productivity",
    s!"PG_PASSWORD={env.pgPassword}",
    "PG_DATABASE=productivity",
    s!"JWT_SECRET={env.jwtSecret}",
    "HTTP_PORT=8000"
  ]
  restart := .unlessStopped
  detach := true
}

end Impl.Containers
