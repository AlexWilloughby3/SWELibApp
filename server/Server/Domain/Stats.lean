namespace Server

structure CategoryStats where
  categoryId       : CategoryId
  categoryName     : String
  totalSeconds     : Nat
  sessionCount     : Nat
  avgSessionSeconds: Nat
  deriving Repr

structure UserStats where
  categories : List CategoryStats
  totalSeconds : Nat
  totalSessions : Nat
  deriving Repr

structure WeeklySummary where
  stats     : UserStats
  weekStart : String  -- ISO date
  weekEnd   : String
  deriving Repr

structure DataPoint where
  date     : String  -- ISO date
  category : String
  seconds  : Nat
  deriving Repr

end Server
