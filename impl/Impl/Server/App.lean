import SWELib.Networking.FastApi

/-!
# FastAPI App Definition

Top-level `FastAPIApp` with CORS middleware configuration.
-/

namespace Impl.Server.App

open SWELib.Networking.FastApi

def corsConfig : CORSConfig := {
  allowOrigins := ["http://localhost:3000", "http://localhost:5173"]
  allowMethods := ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  allowHeaders := ["*"]
  allowCredentials := true
  allowOriginRegex := none
  exposeHeaders := []
  maxAge := 600
}

def appDef : FastAPIApp := {
  title := "ProdTracker API"
  version := "1.0.0"
  description := some "Focus time tracking API"
  middleware := [
    { config := .corsConfig corsConfig }
  ]
}

end Impl.Server.App
