import SWELib.Cloud.Docker

/-!
# Container Configurations

Typed `DockerRunConfig` definitions for the two containers that run on
the GCE VM: a PostgreSQL database and the backend API server.
These replace the old `docker-compose.yml` with SWELib-native types
that are validated and serialized via `serializeFlags`.
-/

namespace Impl.Containers

open SWELib.Cloud.Docker

/-- Environment values needed to configure both containers. -/
structure ContainerEnv where
  pgPassword : String
  jwtSecret : String
  backendImage : String

/-- Read container environment from env vars. -/
def readContainerEnv : IO ContainerEnv := do
  let pgPassword ← IO.getEnv "PG_PASSWORD"
    |>.map (·.getD "")
  let jwtSecret ← IO.getEnv "JWT_SECRET"
    |>.map (·.getD "")
  let backendImage ← IO.getEnv "BACKEND_IMAGE"
    |>.map (·.getD "")
  if pgPassword.isEmpty then
    throw <| IO.userError "PG_PASSWORD environment variable is required"
  if jwtSecret.isEmpty then
    throw <| IO.userError "JWT_SECRET environment variable is required"
  if backendImage.isEmpty then
    throw <| IO.userError "BACKEND_IMAGE environment variable is required"
  return { pgPassword, jwtSecret, backendImage }

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
  image := env.backendImage
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
