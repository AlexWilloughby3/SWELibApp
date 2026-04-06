import SWELib.Networking.FastApi
import SWELib.Networking.Http
import SWELibImpl.Networking.FastApi.CallableRegistry
import SWELibImpl.Networking.FastApi.Router
import Impl.Server.Db
import Impl.Server.Handlers.Health
import Impl.Server.Handlers.Auth
import Impl.Server.Handlers.Users

/-!
# Router Definitions

APIRouter declarations for each domain and the combined registry builder.
-/

namespace Impl.Server.Routers

open SWELib.Networking.FastApi
open SWELib.Networking.Http
open SWELibImpl.Networking.FastApi.CallableRegistry
open SWELibImpl.Networking.FastApi.Router
open Impl.Server.Db

-- Health check route

def healthRouter : APIRouter := {
  «prefix» := ""
  tags := ["health"]
  routes := [
    { path := ⟨"/health"⟩, method := "GET", operationId := some "health_check" }
  ]
}

-- Auth routes (no auth required)

def authRouter : APIRouter := {
  «prefix» := "/auth"
  tags := ["auth"]
  routes := [
    { path := ⟨"/register"⟩, method := "POST", operationId := some "register" },
    { path := ⟨"/verify"⟩, method := "POST", operationId := some "verify_registration" },
    { path := ⟨"/login"⟩, method := "POST", operationId := some "login" },
    { path := ⟨"/request-code"⟩, method := "POST", operationId := some "request_verification_code" },
    { path := ⟨"/login-code"⟩, method := "POST", operationId := some "login_with_code" },
    { path := ⟨"/change-password"⟩, method := "POST", operationId := some "change_password" },
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
    { path := ⟨"/me"⟩, method := "PATCH", operationId := some "update_current_user" },
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
  [healthRouter, authRouter, userRouter, sessionRouter, categoryRouter, goalRouter]

/-- Placeholder handler that returns 501 Not Implemented. -/
def stubHandler : HandlerFn := fun _req => do
  let body := Lean.Json.mkObj [("detail", .str "Not implemented")]
  pure {
    status := StatusCode.notImplemented
    headers := [{ name := FieldName.contentType, value := "application/json" }]
    body := some body.pretty.toUTF8
  }

/-- Register all route handlers in the callable registry.
    Auth and User handlers are fully implemented; others are stubs. -/
def buildRegistry (db : DbConn) : CallableRegistry :=
  let reg := CallableRegistry.empty
  -- Health
  let reg := reg.registerHandler (routeKey "GET" "/health") Handlers.Health.healthCheck
  -- Auth (all implemented)
  let reg := reg.registerHandler (routeKey "POST" "/auth/register") (Handlers.Users.register db)
  let reg := reg.registerHandler (routeKey "POST" "/auth/verify") (Handlers.Users.verifyRegistration db)
  let reg := reg.registerHandler (routeKey "POST" "/auth/login") (Handlers.Users.login db)
  let reg := reg.registerHandler (routeKey "POST" "/auth/request-code") (Handlers.Users.requestVerificationCode db)
  let reg := reg.registerHandler (routeKey "POST" "/auth/login-code") (Handlers.Users.loginWithCode db)
  let reg := reg.registerHandler (routeKey "POST" "/auth/change-password") (Handlers.Users.changePassword db)
  let reg := reg.registerHandler (routeKey "POST" "/auth/forgot-password") (Handlers.Users.forgotPassword db)
  let reg := reg.registerHandler (routeKey "POST" "/auth/reset-password") (Handlers.Users.resetPassword db)
  -- Users (all implemented)
  let reg := reg.registerHandler (routeKey "GET" "/users/me") (Handlers.Users.getMe db)
  let reg := reg.registerHandler (routeKey "PATCH" "/users/me") (Handlers.Users.updateMe db)
  let reg := reg.registerHandler (routeKey "DELETE" "/users/me") (Handlers.Users.deleteMe db)
  -- Sessions (stubs)
  let reg := reg.registerHandler (routeKey "POST" "/sessions") stubHandler
  let reg := reg.registerHandler (routeKey "GET" "/sessions") stubHandler
  let reg := reg.registerHandler (routeKey "DELETE" "/sessions/{id}") stubHandler
  -- Categories (stubs)
  let reg := reg.registerHandler (routeKey "POST" "/categories") stubHandler
  let reg := reg.registerHandler (routeKey "GET" "/categories") stubHandler
  let reg := reg.registerHandler (routeKey "PUT" "/categories/{name}") stubHandler
  let reg := reg.registerHandler (routeKey "DELETE" "/categories/{name}") stubHandler
  -- Goals (stubs)
  let reg := reg.registerHandler (routeKey "POST" "/goals") stubHandler
  let reg := reg.registerHandler (routeKey "GET" "/goals") stubHandler
  let reg := reg.registerHandler (routeKey "PUT" "/goals/{id}") stubHandler
  let reg := reg.registerHandler (routeKey "DELETE" "/goals/{id}") stubHandler
  let reg := reg.registerHandler (routeKey "POST" "/goals/{id}/complete") stubHandler
  reg

end Impl.Server.Routers
