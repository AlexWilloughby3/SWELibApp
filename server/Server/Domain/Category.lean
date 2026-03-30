namespace Server

abbrev CategoryId := String  -- UUID as string

structure Category where
  id       : CategoryId
  userId   : UserId
  name     : String
  isActive : Bool
  deriving Repr

/-- Default categories seeded on user registration. -/
def defaultCategoryNames : List String :=
  ["Work", "Study", "Exercise", "Reading", "Personal"]

/-- Maximum categories per user. -/
def maxCategoriesPerUser : Nat := 20

end Server
