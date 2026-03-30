import Server.Layers.Product

namespace Server.Handlers

def handleListUsers [ProductLayer ctx] (_ctx : ctx) (_admin : User) : IO String := do
  sorry -- TODO: admin-only endpoint, list all users

def handleSetUserRole [ProductLayer ctx] (_ctx : ctx) (_admin : User) (_userId : String) (_body : String) : IO String := do
  sorry -- TODO: admin-only, assign/remove roles

end Server.Handlers
