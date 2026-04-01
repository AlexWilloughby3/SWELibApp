import SWELib.Networking.FastApi
import SWELib.Networking.Http
import SWELibImpl.Networking.FastApi.CallableRegistry
import SWELibImpl.Networking.FastApi.Router

/-!
# Router Definitions

APIRouter declarations for each domain and the combined registry builder.
-/

namespace Impl.Server.Routers

open SWELib.Networking.FastApi
open SWELib.Networking.Http
open SWELibImpl.Networking.FastApi.CallableRegistry
open SWELibImpl.Networking.FastApi.Router

-- Auth routes (no auth required)

def authRouter : APIRouter := {
  «prefix» := "/auth"
  tags := ["auth"]
  routes := [
    { path := ⟨"/register"⟩, method := "POST", operationId := some "register" },
    { path := ⟨"/verify"⟩, method := "POST", operationId := some "verify_registration" },
    { path := ⟨"/login"⟩, method := "POST", operationId := some "login" },
    { path := ⟨"/forgot-password"⟩, method := "POST", operationId := some "forgot_password" },
    { path := ⟨"/reset-password"⟩, method := "POST", operationId := some "reset_password" }
  ]
}

-- User routes (auth required)

def userRouter : APIRouter := {
  «prefix» := "/users"
  tags := ["users"]
  routes := [
    { path := ⟨"/me"⟩, method := "GET", operationId := some "get_current_user" },
    { path := ⟨"/me"⟩, method := "DELETE", operationId := some "delete_current_user" }
  ]
}

-- Session routes (auth required)

def sessionRouter : APIRouter := {
  «prefix» := "/sessions"
  tags := ["sessions"]
  routes := [
    { path := ⟨""⟩, method := "POST", operationId := some "create_session", statusCode := 201 },
    { path := ⟨""⟩, method := "GET", operationId := some "list_sessions" },
    { path := ⟨"/{id}"⟩, method := "DELETE", operationId := some "delete_session" }
  ]
}

-- Category routes (auth required)

def categoryRouter : APIRouter := {
  «prefix» := "/categories"
  tags := ["categories"]
  routes := [
    { path := ⟨""⟩, method := "POST", operationId := some "create_category", statusCode := 201 },
    { path := ⟨""⟩, method := "GET", operationId := some "list_categories" },
    { path := ⟨"/{name}"⟩, method := "PUT", operationId := some "update_category" },
    { path := ⟨"/{name}"⟩, method := "DELETE", operationId := some "delete_category" }
  ]
}

-- Goal routes (auth required)

def goalRouter : APIRouter := {
  «prefix» := "/goals"
  tags := ["goals"]
  routes := [
    { path := ⟨""⟩, method := "POST", operationId := some "create_goal", statusCode := 201 },
    { path := ⟨""⟩, method := "GET", operationId := some "list_goals" },
    { path := ⟨"/{id}"⟩, method := "PUT", operationId := some "update_goal" },
    { path := ⟨"/{id}"⟩, method := "DELETE", operationId := some "delete_goal" },
    { path := ⟨"/{id}/complete"⟩, method := "POST", operationId := some "complete_goal" }
  ]
}

def allRouters : List APIRouter :=
  [authRouter, userRouter, sessionRouter, categoryRouter, goalRouter]

/-- Placeholder handler that returns 501 Not Implemented. -/
def stubHandler : HandlerFn := fun _req => do
  let body := Lean.Json.mkObj [("detail", .str "Not implemented")]
  pure {
    status := StatusCode.notImplemented
    headers := [{ name := FieldName.contentType, value := "application/json" }]
    body := some body.pretty.toUTF8
  }

/-- Register all route handlers in the callable registry.
    Initially all handlers are stubs; they get replaced as we implement each domain. -/
def buildRegistry : CallableRegistry :=
  let reg := CallableRegistry.empty
  -- Auth
  let reg := reg.registerHandler (routeKey "POST" "/auth/register") stubHandler
  let reg := reg.registerHandler (routeKey "POST" "/auth/verify") stubHandler
  let reg := reg.registerHandler (routeKey "POST" "/auth/login") stubHandler
  let reg := reg.registerHandler (routeKey "POST" "/auth/forgot-password") stubHandler
  let reg := reg.registerHandler (routeKey "POST" "/auth/reset-password") stubHandler
  -- Users
  let reg := reg.registerHandler (routeKey "GET" "/users/me") stubHandler
  let reg := reg.registerHandler (routeKey "DELETE" "/users/me") stubHandler
  -- Sessions
  let reg := reg.registerHandler (routeKey "POST" "/sessions") stubHandler
  let reg := reg.registerHandler (routeKey "GET" "/sessions") stubHandler
  let reg := reg.registerHandler (routeKey "DELETE" "/sessions/{id}") stubHandler
  -- Categories
  let reg := reg.registerHandler (routeKey "POST" "/categories") stubHandler
  let reg := reg.registerHandler (routeKey "GET" "/categories") stubHandler
  let reg := reg.registerHandler (routeKey "PUT" "/categories/{name}") stubHandler
  let reg := reg.registerHandler (routeKey "DELETE" "/categories/{name}") stubHandler
  -- Goals
  let reg := reg.registerHandler (routeKey "POST" "/goals") stubHandler
  let reg := reg.registerHandler (routeKey "GET" "/goals") stubHandler
  let reg := reg.registerHandler (routeKey "PUT" "/goals/{id}") stubHandler
  let reg := reg.registerHandler (routeKey "DELETE" "/goals/{id}") stubHandler
  let reg := reg.registerHandler (routeKey "POST" "/goals/{id}/complete") stubHandler
  reg

end Impl.Server.Routers
