import Server.Layers.Product

namespace Server.Handlers

def handleCreateCategory [ProductLayer ctx] (_ctx : ctx) (_user : User) (_body : String) : IO String := do
  sorry -- TODO: parse body, call ProductLayer.createCategory

def handleListCategories [ProductLayer ctx] (_ctx : ctx) (_user : User) : IO String := do
  sorry -- TODO: call ProductLayer.listCategories, return JSON

def handleDeleteCategory [ProductLayer ctx] (_ctx : ctx) (_user : User) (_catId : String) : IO String := do
  sorry -- TODO: call ProductLayer.deleteCategory

end Server.Handlers
