import SWELib.Basics.Uuid
import SWELib.Basics.Time

namespace ProductivityTracker

/-- Formal domain types for the productivity tracker.
    These mirror the runtime types in server/Server/Domain/
    but exist in the spec world for proving properties. -/

structure UserId where
  uuid : SWELib.Basics.Uuid.UUID
  deriving DecidableEq

structure CategoryId where
  uuid : SWELib.Basics.Uuid.UUID
  deriving DecidableEq

structure SessionId where
  uuid : SWELib.Basics.Uuid.UUID
  deriving DecidableEq

structure GoalId where
  uuid : SWELib.Basics.Uuid.UUID
  deriving DecidableEq

inductive GoalType where
  | timeBased
  | dailyCheckbox
  | weeklyCheckbox
  deriving DecidableEq

structure Duration where
  seconds : Nat
  positive : seconds > 0

end ProductivityTracker
