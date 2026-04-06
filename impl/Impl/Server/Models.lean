import Lean.Data.Json

/-!
# Domain Models

Lean structures for ProdTracker domain entities.
These are the runtime representations used by handlers and DB queries.
-/

namespace Impl.Server.Models

structure User where
  email : String
  hashedPassword : String
  displayName : Option String := none
  showOnLeaderboard : Bool := true
  createdAt : String
  deriving Repr

structure PendingRegistration where
  email : String
  hashedPassword : String
  verificationCode : String
  createdAt : String
  deriving Repr

structure VerificationCode where
  email : String
  code : String
  createdAt : String
  expiresAt : String
  deriving Repr

structure FocusSession where
  id : Nat
  email : String
  category : String
  focusTimeSeconds : Nat
  time : String
  deriving Repr

structure Category where
  email : String
  name : String
  color : Option String := none
  deriving Repr

structure FocusGoal where
  id : Nat
  email : String
  category : String
  goalType : String
  targetSeconds : Option Nat := none
  deriving Repr

structure CheckboxGoalCompletion where
  email : String
  category : String
  goalType : String
  completionDate : String
  deriving Repr

structure PasswordResetToken where
  token : String
  email : String
  createdAt : String
  expiresAt : String
  used : Bool := false
  deriving Repr

-- JSON serialization helpers

open Lean Json in
/-- Public user representation (no password). -/
def User.toJson (u : User) : Json :=
  .mkObj [
    ("email", .str u.email),
    ("display_name", match u.displayName with | some n => .str n | none => .null),
    ("show_on_leaderboard", .bool u.showOnLeaderboard)
  ]

open Lean Json in
def FocusSession.toJson (s : FocusSession) : Json :=
  .mkObj [
    ("id", .num s.id),
    ("email", .str s.email),
    ("category", .str s.category),
    ("focus_time_seconds", .num s.focusTimeSeconds),
    ("time", .str s.time)
  ]

open Lean Json in
def Category.toJson (c : Category) : Json :=
  .mkObj [
    ("email", .str c.email),
    ("name", .str c.name),
    ("color", match c.color with | some v => .str v | none => .null)
  ]

open Lean Json in
def FocusGoal.toJson (g : FocusGoal) : Json :=
  .mkObj [
    ("id", .num g.id),
    ("email", .str g.email),
    ("category", .str g.category),
    ("goal_type", .str g.goalType),
    ("target_seconds", match g.targetSeconds with | some v => .num v | none => .null)
  ]

end Impl.Server.Models
