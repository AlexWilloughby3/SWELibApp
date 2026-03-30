namespace Server

abbrev SessionId := String  -- UUID as string

structure Session where
  id              : SessionId
  userId          : UserId
  categoryId      : CategoryId
  durationSeconds : Nat
  startedAt       : String  -- ISO timestamp
  deriving Repr

/-- A duration split at midnight into two parts. -/
structure MidnightSplit where
  before : Nat    -- seconds before midnight
  after  : Nat    -- seconds after midnight
  deriving Repr

/-- Check if a session starting at `startedAt` with `durationSeconds`
    crosses a midnight boundary. -/
def crossesMidnight (_startedAt : String) (_durationSeconds : Nat) : Bool :=
  sorry -- TODO: parse ISO timestamp, check if start + duration crosses midnight

/-- Split a duration at midnight. Returns (before, after) seconds.
    Invariant: split.before + split.after = durationSeconds -/
def splitAtMidnight (_startedAt : String) (durationSeconds : Nat) : MidnightSplit :=
  sorry -- TODO: compute actual split point

/-- The split preserves total duration. -/
theorem splitAtMidnight_sum_eq (startedAt : String) (dur : Nat) :
    let s := splitAtMidnight startedAt dur
    s.before + s.after = dur := by
  sorry -- TODO: prove from splitAtMidnight definition

end Server
