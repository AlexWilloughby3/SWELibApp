import Server.Layers.Product

namespace Server.Handlers

def handleCreateGoal [ProductLayer ctx] (_ctx : ctx) (_user : User) (_body : String) : IO String := do
  sorry -- TODO: parse body, call ProductLayer.createGoal

def handleListGoals [ProductLayer ctx] (_ctx : ctx) (_user : User) : IO String := do
  sorry -- TODO: call ProductLayer goals listing

def handleToggleGoal [ProductLayer ctx] (_ctx : ctx) (_user : User) (_goalId : String) : IO String := do
  sorry -- TODO: call ProductLayer.toggleGoal

end Server.Handlers
