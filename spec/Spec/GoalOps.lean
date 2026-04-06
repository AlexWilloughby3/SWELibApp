import Spec.Domain

/-!
# Focus Goal & Checkbox Completion Specifications

Preconditions, postconditions, and pure transition functions for
focus goal and checkbox completion endpoints.

## Goal types

- `timeBased`: tracks seconds per week against a target. Requires `targetSeconds`.
- `dailyCheckbox`: a daily yes/no habit. Requires `description`.
- `weeklyCheckbox`: a weekly yes/no habit. Requires `description`.

Goals are keyed by (email, category, goalType) — at most one goal
per type per category per user. POST is an upsert.
-/

namespace Spec.GoalOps

open Spec.Domain

-- ═══════════════════════════════════════════════════════════
-- Constants
-- ═══════════════════════════════════════════════════════════

def maxGoalTimePerWeek : Nat := 604800  -- 168 hours in seconds

-- ═══════════════════════════════════════════════════════════
-- POST /users/{email}/focus-goals  (upsert)
-- ═══════════════════════════════════════════════════════════

namespace UpsertGoal

/-- Precondition: user exists, type-specific validation passes. -/
def pre (s : DomainState) (email : Email) (_category : String) (goalType : GoalType)
    (targetSeconds : Option Nat) (description : Option String) : Prop :=
  userExists s email ∧
  -- TIME_BASED must have targetSeconds
  (goalType = .timeBased → ∃ t, targetSeconds = some t ∧ t ≤ maxGoalTimePerWeek) ∧
  -- Checkbox types must have a description
  ((goalType = .dailyCheckbox ∨ goalType = .weeklyCheckbox) →
    ∃ d, description = some d ∧ d.length ≤ 255)

/-- On success: insert or update the goal for (email, category, goalType). -/
def apply (s : DomainState) (email : Email) (category : String) (goalType : GoalType)
    (targetSeconds : Option Nat) (description : Option String) : DomainState :=
  let newGoal : GoalRecord := ⟨category, goalType, targetSeconds, description⟩
  let existing := (s.goals email).any (fun g => g.category == category && g.goalType == goalType)
  { s with
    goals := fun e =>
      if e = email then
        if existing then
          (s.goals email).map (fun g =>
            if g.category == category && g.goalType == goalType then newGoal else g)
        else
          s.goals email ++ [newGoal]
      else s.goals e }

/-- Postcondition: a goal with the given key exists. -/
def post (s' : DomainState) (email : Email) (category : String) (goalType : GoalType) : Prop :=
  hasGoal s' email category goalType

/-- Upserting does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other category : String)
    (gt : GoalType) (ts : Option Nat) (desc : Option String) (h : other ≠ email) :
    (apply s email category gt ts desc).goals other = s.goals other := by
  simp [apply, h]

end UpsertGoal

-- ═══════════════════════════════════════════════════════════
-- GET /users/{email}/focus-goals
-- ═══════════════════════════════════════════════════════════

namespace ListGoals

/-- Precondition: user exists. -/
def pre (s : DomainState) (email : Email) : Prop :=
  userExists s email

def apply (s : DomainState) : DomainState := s

def post (s s' : DomainState) (email : Email) (result : List GoalRecord) : Prop :=
  s' = s ∧ result = s.goals email

end ListGoals

-- ═══════════════════════════════════════════════════════════
-- GET /users/{email}/focus-goals/{category}?goal_type=...
-- ═══════════════════════════════════════════════════════════

namespace GetGoal

/-- Precondition: user exists and the goal exists. -/
def pre (s : DomainState) (email : Email) (category : String) (goalType : GoalType) : Prop :=
  userExists s email ∧ hasGoal s email category goalType

def apply (s : DomainState) : DomainState := s

def post (s s' : DomainState) (email : Email) (category : String) (goalType : GoalType)
    (result : GoalRecord) : Prop :=
  s' = s ∧ result ∈ s.goals email ∧
  result.category = category ∧ result.goalType = goalType

end GetGoal

-- ═══════════════════════════════════════════════════════════
-- DELETE /users/{email}/focus-goals/{category}?goal_type=...
-- ═══════════════════════════════════════════════════════════

namespace DeleteGoal

/-- Precondition: user exists and the goal exists. -/
def pre (s : DomainState) (email : Email) (category : String) (goalType : GoalType) : Prop :=
  userExists s email ∧ hasGoal s email category goalType

/-- On success: remove the goal. For checkbox goals, also remove completions. -/
def apply (s : DomainState) (email : Email) (category : String) (goalType : GoalType) : DomainState :=
  { s with
    goals := fun e =>
      if e = email then
        (s.goals email).filter (fun g => ¬(g.category == category && g.goalType == goalType))
      else s.goals e
    checkboxCompletions := fun e =>
      if e = email then
        (s.checkboxCompletions email).filter (fun cc =>
          ¬(cc.category == category && cc.goalType == goalType))
      else s.checkboxCompletions e }

/-- Postcondition: goal is gone. -/
def post (s' : DomainState) (email : Email) (category : String) (goalType : GoalType) : Prop :=
  ¬ hasGoal s' email category goalType

/-- Deleting does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other : Email) (cat : String)
    (gt : GoalType) (h : other ≠ email) :
    (apply s email cat gt).goals other = s.goals other ∧
    (apply s email cat gt).checkboxCompletions other = s.checkboxCompletions other := by
  simp [apply, h]

end DeleteGoal

-- ═══════════════════════════════════════════════════════════
-- POST /users/{email}/checkbox-completions  (toggle)
-- ═══════════════════════════════════════════════════════════

namespace ToggleCheckbox

/-- Precondition: user exists, a matching checkbox goal exists.
    `goalType` must be dailyCheckbox or weeklyCheckbox. -/
def pre (s : DomainState) (email : Email) (category : String) (goalType : GoalType) : Prop :=
  userExists s email ∧
  hasGoal s email category goalType ∧
  (goalType = .dailyCheckbox ∨ goalType = .weeklyCheckbox)

/-- Find existing completion for this (category, goalType, date). -/
def findCompletion (s : DomainState) (email : Email) (category : String)
    (goalType : GoalType) (date : String) : Option CheckboxCompletion :=
  (s.checkboxCompletions email).find? (fun cc =>
    cc.category == category && cc.goalType == goalType && cc.completionDate == date)

/-- On success: toggle the completion.
    - If no row exists: create with completed=true
    - If row exists: flip completed -/
def apply (s : DomainState) (email : Email) (category : String)
    (goalType : GoalType) (date : String) : DomainState :=
  match findCompletion s email category goalType date with
  | none =>
    { s with
      checkboxCompletions := fun e =>
        if e = email then
          ⟨category, goalType, date, true⟩ :: s.checkboxCompletions email
        else s.checkboxCompletions e }
  | some _ =>
    { s with
      checkboxCompletions := fun e =>
        if e = email then
          (s.checkboxCompletions email).map (fun cc =>
            if cc.category == category && cc.goalType == goalType && cc.completionDate == date
            then { cc with completed := !cc.completed }
            else cc)
        else s.checkboxCompletions e }

/-- Postcondition: a completion record exists for this date. -/
def post (s' : DomainState) (email : Email) (category : String)
    (goalType : GoalType) (date : String) : Prop :=
  ∃ cc, cc ∈ s'.checkboxCompletions email ∧
    cc.category = category ∧ cc.goalType = goalType ∧ cc.completionDate = date

/-- Toggling does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other : Email) (cat : String)
    (gt : GoalType) (date : String) (h : other ≠ email) :
    (apply s email cat gt date).checkboxCompletions other = s.checkboxCompletions other := by
  simp [apply]
  cases findCompletion s email cat gt date <;> simp_all

end ToggleCheckbox

-- ═══════════════════════════════════════════════════════════
-- GET /users/{email}/checkbox-completions
-- ═══════════════════════════════════════════════════════════

namespace ListCheckboxCompletions

/-- Precondition: user exists. -/
def pre (s : DomainState) (email : Email) : Prop :=
  userExists s email

def apply (s : DomainState) : DomainState := s

/-- Postcondition: result is a subset of user's completions
    (impl applies category/goalType/date filters). -/
def post (s s' : DomainState) (email : Email) (result : List CheckboxCompletion) : Prop :=
  s' = s ∧ ∀ cc, cc ∈ result → cc ∈ s.checkboxCompletions email

end ListCheckboxCompletions

end Spec.GoalOps
