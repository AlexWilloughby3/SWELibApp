import Spec.Domain

/-!
# Focus Session Endpoint Specifications

Preconditions, postconditions, and pure transition functions for
focus session endpoints.

## Midnight splitting

If a session spans midnight in the user's timezone, it is split into
multiple DB rows (one per calendar day). This spec models the split as
producing a list of SessionRecords rather than a single one. The actual
timezone math is an implementation concern — the spec just requires that
the total seconds are preserved across splits.
-/

namespace Spec.SessionOps

open Spec.Domain

-- ═══════════════════════════════════════════════════════════
-- Constants
-- ═══════════════════════════════════════════════════════════

def maxCategories : Nat := 20

-- ═══════════════════════════════════════════════════════════
-- POST /users/{email}/focus-sessions  (and /with-time)
-- ═══════════════════════════════════════════════════════════

namespace RecordSession

/-- Precondition: user exists. Category will be auto-created if needed
    (unless at the 20-category limit and category is new). -/
def pre (s : DomainState) (email : Email) (category : String) : Prop :=
  userExists s email ∧
  (ownsCategory s email category ∨
   (s.categories email).length < maxCategories)

/-- The total focus time across a list of sessions. -/
def totalFocusTime (sessions : List SessionRecord) : Nat :=
  sessions.foldl (fun acc s => acc + s.focusTimeSeconds) 0

/-- A split result: multiple sessions whose total equals the original. -/
structure SplitResult where
  sessions : List SessionRecord
  totalSeconds : Nat
  preserved : totalFocusTime sessions = totalSeconds

/-- On success: sessions are added (possibly multiple from midnight split),
    category auto-created if needed. -/
def apply (s : DomainState) (email : Email) (category : String)
    (newSessions : List SessionRecord) : DomainState :=
  let s' := if (s.categories email).any (fun c => c.name == category) then s
    else { s with
      categories := fun e =>
        if e = email then s.categories email ++ [⟨category, true⟩]
        else s.categories e }
  { s' with
    sessions := fun e =>
      if e = email then newSessions ++ s'.sessions email
      else s'.sessions e
    nextSessionId := s.nextSessionId + newSessions.length }

/-- Postcondition: sessions exist for this user, category exists. -/
def post (s' : DomainState) (email : Email) (category : String)
    (newSessions : List SessionRecord) : Prop :=
  ownsCategory s' email category ∧
  ∀ sess, sess ∈ newSessions → sess ∈ s'.sessions email

/-- Recording does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other category : String)
    (sessions : List SessionRecord) (h : other ≠ email) :
    (apply s email category sessions).sessions other = s.sessions other := by
  unfold apply
  split <;> simp_all

end RecordSession

-- ═══════════════════════════════════════════════════════════
-- GET /users/{email}/focus-sessions
-- ═══════════════════════════════════════════════════════════

namespace ListSessions

/-- Precondition: user exists. -/
def pre (s : DomainState) (email : Email) : Prop :=
  userExists s email

/-- Read-only — no state change. -/
def apply (s : DomainState) : DomainState := s

/-- Postcondition: state unchanged. The implementation applies
    pagination (skip/limit) and optional category/date filters,
    but the spec just says the result is a subset of the user's sessions. -/
def post (s s' : DomainState) (email : Email) (result : List SessionRecord) : Prop :=
  s' = s ∧ ∀ sess, sess ∈ result → sess ∈ s.sessions email

end ListSessions

-- ═══════════════════════════════════════════════════════════
-- DELETE /users/{email}/focus-sessions/{timestamp}
-- ═══════════════════════════════════════════════════════════

namespace DeleteSession

/-- Precondition: user exists and the session exists. -/
def pre (s : DomainState) (email : Email) (sessionId : Nat) : Prop :=
  userExists s email ∧ sessionBelongsTo s email sessionId

/-- On success: remove the session. -/
def apply (s : DomainState) (email : Email) (sessionId : Nat) : DomainState :=
  { s with
    sessions := fun e =>
      if e = email then (s.sessions email).filter (fun sess => sess.id != sessionId)
      else s.sessions e }

/-- Postcondition: session is gone. -/
def post (s' : DomainState) (email : Email) (sessionId : Nat) : Prop :=
  ¬ sessionBelongsTo s' email sessionId

/-- Deleting does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other : Email) (sid : Nat)
    (h : other ≠ email) :
    (apply s email sid).sessions other = s.sessions other := by
  simp [apply, h]

end DeleteSession

end Spec.SessionOps
