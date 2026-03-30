namespace Server

abbrev GoalId := String  -- UUID as string

inductive GoalType where
  | timeBased
  | dailyCheckbox
  | weeklyCheckbox
  deriving Repr, DecidableEq

structure Goal where
  id            : GoalId
  userId        : UserId
  categoryId    : CategoryId
  goalType      : GoalType
  targetMinutes : Option Nat  -- only for timeBased
  description   : Option String
  deriving Repr

structure GoalProgress where
  goal             : Goal
  currentMinutes   : Nat       -- for timeBased: minutes logged so far
  completedToday   : Bool      -- for checkbox: checked today?
  completedThisWeek: Bool      -- for weekly checkbox
  progressPercent  : Float     -- 0.0 to 100.0
  deriving Repr

end Server
