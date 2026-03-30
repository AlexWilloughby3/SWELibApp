namespace Server

abbrev UserId := String  -- UUID as string

structure User where
  id          : UserId
  email       : String
  displayName : String
  deriving Repr

end Server
