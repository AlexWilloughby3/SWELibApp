import Server.Layers.Product

namespace Server.Handlers

def handleLogSession [ProductLayer ctx] (_ctx : ctx) (_user : User) (_body : String) : IO String := do
  sorry -- TODO: parse body, call ProductLayer.logSession

def handleListSessions [ProductLayer ctx] (_ctx : ctx) (_user : User) (_queryParams : String) : IO String := do
  sorry -- TODO: parse date range + pagination, call ProductLayer.listSessions

def handleDeleteSession [ProductLayer ctx] (_ctx : ctx) (_user : User) (_sessionId : String) : IO String := do
  sorry -- TODO: call ProductLayer.deleteSession

end Server.Handlers
