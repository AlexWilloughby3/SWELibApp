import Server.Layers.Product

namespace Server.Handlers

def handleUserStats [ProductLayer ctx] (_ctx : ctx) (_user : User) (_queryParams : String) : IO String := do
  sorry -- TODO: parse date range, call ProductLayer.userStats

def handleWeeklySummary [ProductLayer ctx] (_ctx : ctx) (_user : User) : IO String := do
  sorry -- TODO: call ProductLayer.weeklySummary

end Server.Handlers
