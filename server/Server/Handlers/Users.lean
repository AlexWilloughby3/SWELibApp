import Server.Layers.Product

namespace Server.Handlers

def handleGetMe [ProductLayer ctx] (_ctx : ctx) (_user : User) : IO String := do
  sorry -- TODO: return user profile as JSON

def handleUpdateMe [ProductLayer ctx] (_ctx : ctx) (_user : User) (_body : String) : IO String := do
  sorry -- TODO: parse body, update display name

def handleDeleteMe [ProductLayer ctx] (_ctx : ctx) (_user : User) : IO String := do
  sorry -- TODO: delete user account (cascades)

def handleChangePassword [ProductLayer ctx] (_ctx : ctx) (_user : User) (_body : String) : IO String := do
  sorry -- TODO: parse body, call ProductLayer.changePassword

end Server.Handlers
