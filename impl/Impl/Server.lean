import SWELib.Networking.FastApi
import SWELibImpl.Networking.FastApi.Server
import SWELibImpl.Networking.FastApi.Router
import Impl.Server.App
import Impl.Server.Routers
import Impl.Server.Models
import Impl.Server.Db

/-!
# ProdTracker Server Entry Point

Connects to PostgreSQL, runs migrations, builds the FastAPIApp from routers,
and starts the HTTP server on port 8000.
-/

open SWELib.Networking.FastApi
open SWELibImpl.Networking.FastApi.Router
open Impl.Server.App
open Impl.Server.Routers
open Impl.Server.Db

def main : IO Unit := do
  IO.println "Connecting to PostgreSQL..."
  let db ← Impl.Server.Db.connect
  Impl.Server.Db.runMigrations db
  let app := buildApp appDef allRouters
  let registry := buildRegistry
  let server ← SWELibImpl.Networking.FastApi.Server.serve app registry (port := 8000)
  IO.println "ProdTracker API running on http://0.0.0.0:8000"
  IO.println "Docs: http://0.0.0.0:8000/docs"
  SWELibImpl.Networking.FastApi.Server.run server
