import Server.Layers.Product

namespace Server.Handlers

def handleRegister [ProductLayer ctx] (_ctx : ctx) (_body : String) : IO String := do
  sorry -- TODO: parse JSON body, call ProductLayer.register, return JSON

def handleLogin [ProductLayer ctx] (_ctx : ctx) (_body : String) : IO String := do
  sorry -- TODO: parse JSON body, call ProductLayer.login, return token pair

def handleRefresh [ProductLayer ctx] (_ctx : ctx) (_body : String) : IO String := do
  sorry -- TODO: parse JSON body, call ProductLayer.refreshAuth

end Server.Handlers
