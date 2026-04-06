import Spec.Domain

/-!
# Category Endpoint Specifications

Preconditions, postconditions, and pure transition functions for
category management endpoints.
-/

namespace Spec.CategoryOps

open Spec.Domain

-- ═══════════════════════════════════════════════════════════
-- Constants
-- ═══════════════════════════════════════════════════════════

def maxCategories : Nat := 20
def maxCategoryNameLength : Nat := 50

-- ═══════════════════════════════════════════════════════════
-- POST /users/{email}/categories
-- ═══════════════════════════════════════════════════════════

namespace CreateCategory

/-- Precondition: user exists, under category limit, name is valid. -/
def pre (s : DomainState) (email : Email) (name : String) : Prop :=
  userExists s email ∧
  name.length ≥ 1 ∧
  name.length ≤ maxCategoryNameLength ∧
  (s.categories email).length < maxCategories

/-- On success: if category already exists, no-op; otherwise add it. -/
def apply (s : DomainState) (email : Email) (name : String) : DomainState :=
  if (s.categories email).any (fun c => c.name == name) then s
  else
    { s with
      categories := fun e =>
        if e = email then s.categories email ++ [⟨name, true⟩]
        else s.categories e }

/-- Postcondition: the category exists for this user. -/
def post (s' : DomainState) (email : Email) (name : String) : Prop :=
  ownsCategory s' email name

/-- Creating a category is idempotent. -/
theorem apply_idempotent (s : DomainState) (email : Email) (name : String)
    (h : ownsCategory s email name) :
    apply s email name = s := by
  unfold apply
  obtain ⟨c, hc_mem, hc_name⟩ := h
  have : (s.categories email).any (fun c => c.name == name) = true := by
    simp [List.any_eq_true]
    exact ⟨c, hc_mem, by simp [hc_name]⟩
  simp [this]

end CreateCategory

-- ═══════════════════════════════════════════════════════════
-- GET /users/{email}/categories
-- ═══════════════════════════════════════════════════════════

namespace ListCategories

/-- Precondition: user exists. -/
def pre (s : DomainState) (email : Email) : Prop :=
  userExists s email

/-- Read-only — no state change. -/
def apply (s : DomainState) : DomainState := s

/-- Postcondition: state unchanged, result matches state. -/
def post (s s' : DomainState) (email : Email) (result : List CategoryRecord) : Prop :=
  s' = s ∧ result = s.categories email

end ListCategories

-- ═══════════════════════════════════════════════════════════
-- PATCH /users/{email}/categories/{category}
-- ═══════════════════════════════════════════════════════════

namespace ToggleCategoryActive

/-- Precondition: user exists and owns the category. -/
def pre (s : DomainState) (email : Email) (name : String) : Prop :=
  userExists s email ∧ ownsCategory s email name

/-- On success: update the active flag on the matching category. -/
def apply (s : DomainState) (email : Email) (name : String) (active : Bool) : DomainState :=
  { s with
    categories := fun e =>
      if e = email then
        (s.categories email).map (fun c =>
          if c.name == name then { c with active := active } else c)
      else s.categories e }

/-- Postcondition: the category still exists with the new active status. -/
def post (s' : DomainState) (email : Email) (name : String) (active : Bool) : Prop :=
  ∃ c, c ∈ s'.categories email ∧ c.name = name ∧ c.active = active

/-- Toggling does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other name : String) (active : Bool)
    (h : other ≠ email) :
    (apply s email name active).categories other = s.categories other := by
  simp [apply, h]

end ToggleCategoryActive

-- ═══════════════════════════════════════════════════════════
-- DELETE /users/{email}/categories/{category}
-- ═══════════════════════════════════════════════════════════

namespace DeleteCategory

/-- Precondition: user exists and owns the category. -/
def pre (s : DomainState) (email : Email) (name : String) : Prop :=
  userExists s email ∧ ownsCategory s email name

/-- On success: remove category, cascade delete sessions and goals for it. -/
def apply (s : DomainState) (email : Email) (name : String) : DomainState :=
  { s with
    categories := fun e =>
      if e = email then (s.categories email).filter (fun c => c.name != name)
      else s.categories e
    sessions := fun e =>
      if e = email then (s.sessions email).filter (fun sess => sess.category != name)
      else s.sessions e
    goals := fun e =>
      if e = email then (s.goals email).filter (fun g => g.category != name)
      else s.goals e
    checkboxCompletions := fun e =>
      if e = email then (s.checkboxCompletions email).filter (fun cc => cc.category != name)
      else s.checkboxCompletions e }

/-- Postcondition: category is gone, no sessions/goals reference it. -/
def post (s' : DomainState) (email : Email) (name : String) : Prop :=
  ¬ ownsCategory s' email name ∧
  ∀ sess, sess ∈ s'.sessions email → sess.category ≠ name ∧
  ∀ goal, goal ∈ s'.goals email → goal.category ≠ name

/-- Deleting does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other name : String) (h : other ≠ email) :
    (apply s email name).categories other = s.categories other ∧
    (apply s email name).sessions other = s.sessions other ∧
    (apply s email name).goals other = s.goals other := by
  simp [apply, h]

end DeleteCategory

-- ═══════════════════════════════════════════════════════════
-- PUT /users/{email}/categories/{category}  (rename / merge)
-- ═══════════════════════════════════════════════════════════

namespace RenameCategory

/-- Precondition: user exists, source category exists, names differ. -/
def pre (s : DomainState) (email : Email) (oldName newName : String) : Prop :=
  userExists s email ∧
  ownsCategory s email oldName ∧
  oldName ≠ newName ∧
  newName.length ≥ 1 ∧
  newName.length ≤ maxCategoryNameLength

/-- Whether the target category already exists (merge required). -/
def requiresMerge (s : DomainState) (email : Email) (newName : String) : Prop :=
  ownsCategory s email newName

/-- Simple rename (target does not exist): update category name, move sessions and goals. -/
def applyRename (s : DomainState) (email : Email) (oldName newName : String) : DomainState :=
  { s with
    categories := fun e =>
      if e = email then
        (s.categories email).map (fun c =>
          if c.name == oldName then { c with name := newName } else c)
      else s.categories e
    sessions := fun e =>
      if e = email then
        (s.sessions email).map (fun sess =>
          if sess.category == oldName then { sess with category := newName } else sess)
      else s.sessions e
    goals := fun e =>
      if e = email then
        (s.goals email).map (fun g =>
          if g.category == oldName then { g with category := newName } else g)
      else s.goals e
    checkboxCompletions := fun e =>
      if e = email then
        (s.checkboxCompletions email).map (fun cc =>
          if cc.category == oldName then { cc with category := newName } else cc)
      else s.checkboxCompletions e }

/-- Merge (target exists): move sessions to target, delete source category and its goals. -/
def applyMerge (s : DomainState) (email : Email) (oldName newName : String) : DomainState :=
  { s with
    categories := fun e =>
      if e = email then (s.categories email).filter (fun c => c.name != oldName)
      else s.categories e
    sessions := fun e =>
      if e = email then
        (s.sessions email).map (fun sess =>
          if sess.category == oldName then { sess with category := newName } else sess)
      else s.sessions e
    goals := fun e =>
      if e = email then (s.goals email).filter (fun g => g.category != oldName)
      else s.goals e
    checkboxCompletions := fun e =>
      if e = email then (s.checkboxCompletions email).filter (fun cc => cc.category != oldName)
      else s.checkboxCompletions e }

/-- Postcondition (rename): old name gone, new name exists. -/
def postRename (s' : DomainState) (email : Email) (oldName newName : String) : Prop :=
  ¬ ownsCategory s' email oldName ∧
  ownsCategory s' email newName

/-- Postcondition (merge): old name gone, target still exists, sessions moved. -/
def postMerge (s' : DomainState) (email : Email) (oldName newName : String) : Prop :=
  ¬ ownsCategory s' email oldName ∧
  ownsCategory s' email newName ∧
  ∀ sess, sess ∈ s'.sessions email → sess.category ≠ oldName

end RenameCategory

end Spec.CategoryOps
