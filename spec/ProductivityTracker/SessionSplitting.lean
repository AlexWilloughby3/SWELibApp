import ProductivityTracker.Types

namespace ProductivityTracker

/-- Formal specification of midnight session splitting.
    This is the core app-specific business rule. -/

/-- A session crosses midnight if start + duration > midnight. -/
def crossesMidnight (startSeconds : Nat) (durationSeconds : Nat) (midnightSeconds : Nat) : Prop :=
  startSeconds + durationSeconds > midnightSeconds ∧ startSeconds < midnightSeconds

/-- Split a duration at midnight into before/after parts. -/
def splitAtMidnight (startSeconds : Nat) (durationSeconds : Nat) (midnightSeconds : Nat) :
    Nat × Nat :=
  let before := midnightSeconds - startSeconds
  let after := durationSeconds - before
  (before, after)

/-- Split preserves total duration. -/
theorem split_preserves_duration (start dur midnight : Nat)
    (h : crossesMidnight start dur midnight) :
    let (before, after) := splitAtMidnight start dur midnight
    before + after = dur := by
  sorry -- TODO: unfold splitAtMidnight, use Nat arithmetic

/-- No split when session doesn't cross midnight. -/
theorem no_split_same_day (start dur midnight : Nat)
    (h : ¬crossesMidnight start dur midnight) :
    start + dur ≤ midnight ∨ start ≥ midnight := by
  sorry -- TODO: unfold crossesMidnight, use not-and logic

end ProductivityTracker
