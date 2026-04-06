import SWELib.Foundations.Domain

/-!
# ProdTracker Domain Specification

Domain types, state, relationships, events, and invariants for the
productivity tracker app. Everything here is pure — no HTTP, no SQL,
no tables. Just the business logic as math.
-/

namespace Spec.Domain

open SWELib.Foundations.Domain (EventResult EventSpec AuthContext)

-- ═══════════════════════════════════════════════════════════
-- Entity Types
-- ═══════════════════════════════════════════════════════════

/-- A registered, verified user. -/
structure UserRecord where
  name : String
  hashedPassword : String
  createdAt : String
  deriving Repr, DecidableEq

/-- A pending registration awaiting email verification. -/
structure PendingReg where
  hashedPassword : String
  verificationCode : String
  createdAt : String
  deriving Repr, DecidableEq

/-- A focus category owned by a user. -/
structure CategoryRecord where
  name : String
  active : Bool := true
  deriving Repr, DecidableEq

/-- A recorded focus session. -/
structure SessionRecord where
  id : Nat
  category : String
  focusTimeSeconds : Nat
  time : String
  deriving Repr, DecidableEq

/-- Goal types. -/
inductive GoalType where
  | timeBased
  | dailyCheckbox
  | weeklyCheckbox
  deriving Repr, DecidableEq, BEq

/-- A focus goal for a category. -/
structure GoalRecord where
  category : String
  goalType : GoalType
  targetSeconds : Option Nat     -- required for timeBased
  description : Option String     -- required for checkbox types
  deriving Repr, DecidableEq

/-- A checkbox goal completion record. -/
structure CheckboxCompletion where
  category : String
  goalType : GoalType             -- dailyCheckbox or weeklyCheckbox
  completionDate : String         -- date anchor (day or week start)
  completed : Bool
  deriving Repr, DecidableEq

/-- A password reset token. -/
structure ResetToken where
  token : String
  createdAt : String
  deriving Repr, DecidableEq

-- ═══════════════════════════════════════════════════════════
-- Domain State
--
-- State is functions, not tables. How these map to Postgres
-- is an impl concern.
-- ═══════════════════════════════════════════════════════════

/-- Email is the user identity. -/
abbrev Email := String

/-- The complete domain state. -/
structure DomainState where
  /-- Verified users, keyed by email. -/
  users : Email → Option UserRecord
  /-- Pending registrations, keyed by email. -/
  pendingRegs : Email → Option PendingReg
  /-- Password reset tokens, keyed by email. -/
  resetTokens : Email → Option ResetToken
  /-- Categories owned by a user. -/
  categories : Email → List CategoryRecord
  /-- Sessions recorded by a user. -/
  sessions : Email → List SessionRecord
  /-- Goals set by a user. -/
  goals : Email → List GoalRecord
  /-- Checkbox completions for a user. -/
  checkboxCompletions : Email → List CheckboxCompletion
  /-- Next available ID for sessions. -/
  nextSessionId : Nat

/-- The empty initial state. -/
def DomainState.empty : DomainState :=
  { users := fun _ => none
  , pendingRegs := fun _ => none
  , resetTokens := fun _ => none
  , categories := fun _ => []
  , sessions := fun _ => []
  , goals := fun _ => []
  , checkboxCompletions := fun _ => []
  , nextSessionId := 1 }

-- ═══════════════════════════════════════════════════════════
-- Relationships (as propositions on state)
-- ═══════════════════════════════════════════════════════════

/-- A user exists. -/
def userExists (s : DomainState) (email : Email) : Prop :=
  s.users email ≠ none

/-- A user owns a category with the given name. -/
def ownsCategory (s : DomainState) (email : Email) (catName : String) : Prop :=
  ∃ c, c ∈ s.categories email ∧ c.name = catName

/-- A session belongs to a user. -/
def sessionBelongsTo (s : DomainState) (email : Email) (sid : Nat) : Prop :=
  ∃ sess, sess ∈ s.sessions email ∧ sess.id = sid

/-- A goal belongs to a user (keyed by category + goalType). -/
def hasGoal (s : DomainState) (email : Email) (cat : String) (gt : GoalType) : Prop :=
  ∃ goal, goal ∈ s.goals email ∧ goal.category = cat ∧ goal.goalType = gt

-- ═══════════════════════════════════════════════════════════
-- Events
-- ═══════════════════════════════════════════════════════════

/-- Every possible mutation in the domain. -/
inductive DomainEvent where
  -- Auth flow
  | register (email : Email) (password : String)
  | verify (email : Email) (code : String)
  | login (email : Email) (password : String)
  | forgotPassword (email : Email)
  | resetPassword (email : Email) (token : String) (newPassword : String)
  -- Categories
  | createCategory (email : Email) (name : String)
  | toggleCategoryActive (email : Email) (name : String) (active : Bool)
  | deleteCategory (email : Email) (name : String)
  | renameCategory (email : Email) (oldName : String) (newName : String)
  -- Sessions
  | recordSession (email : Email) (category : String) (seconds : Nat) (time : String)
  | deleteSession (email : Email) (sessionId : Nat)
  -- Goals
  | upsertGoal (email : Email) (category : String) (goalType : GoalType)
      (targetSeconds : Option Nat) (description : Option String)
  | deleteGoal (email : Email) (category : String) (goalType : GoalType)
  -- Checkbox completions
  | toggleCheckbox (email : Email) (category : String) (goalType : GoalType) (date : String)
  -- User management
  | deleteUser (email : Email)
  deriving Repr

/-- Which user does an event belong to? -/
def DomainEvent.email : DomainEvent → Email
  | .register e _ | .verify e _ | .login e _ | .forgotPassword e
  | .resetPassword e _ _ | .createCategory e _ | .toggleCategoryActive e _ _
  | .deleteCategory e _ | .renameCategory e _ _
  | .recordSession e _ _ _ | .deleteSession e _
  | .upsertGoal e _ _ _ _ | .deleteGoal e _ _
  | .toggleCheckbox e _ _ _ | .deleteUser e => e

-- ═══════════════════════════════════════════════════════════
-- Queries
-- ═══════════════════════════════════════════════════════════

/-- Every possible read in the domain. -/
inductive DomainQuery where
  | getUser (email : Email)
  | listCategories (email : Email)
  | listSessions (email : Email)
  | listGoals (email : Email)
  | getGoal (email : Email) (category : String) (goalType : GoalType)
  | listCheckboxCompletions (email : Email)
  deriving Repr

-- ═══════════════════════════════════════════════════════════
-- Invariants
-- ═══════════════════════════════════════════════════════════

/-- Sessions only exist for existing users. -/
def sessionsHaveOwners (s : DomainState) : Prop :=
  ∀ email, s.sessions email ≠ [] → userExists s email

/-- Categories only exist for existing users. -/
def categoriesHaveOwners (s : DomainState) : Prop :=
  ∀ email, s.categories email ≠ [] → userExists s email

/-- Goals only exist for existing users. -/
def goalsHaveOwners (s : DomainState) : Prop :=
  ∀ email, s.goals email ≠ [] → userExists s email

/-- Sessions reference categories the user actually owns. -/
def sessionsUseOwnCategories (s : DomainState) : Prop :=
  ∀ email sess, sess ∈ s.sessions email →
    ownsCategory s email sess.category

/-- Goals reference categories the user actually owns. -/
def goalsUseOwnCategories (s : DomainState) : Prop :=
  ∀ email goal, goal ∈ s.goals email →
    ownsCategory s email goal.category

/-- Category names are unique per user. -/
def categoryNamesUnique (s : DomainState) : Prop :=
  ∀ email c₁ c₂, c₁ ∈ s.categories email → c₂ ∈ s.categories email →
    c₁.name = c₂.name → c₁ = c₂

/-- Session IDs are globally unique. -/
def sessionIdsUnique (s : DomainState) : Prop :=
  ∀ e₁ e₂ s₁ s₂, s₁ ∈ s.sessions e₁ → s₂ ∈ s.sessions e₂ →
    s₁.id = s₂.id → e₁ = e₂ ∧ s₁ = s₂

/-- Goals are unique per (email, category, goalType). -/
def goalsUnique (s : DomainState) : Prop :=
  ∀ email g₁ g₂, g₁ ∈ s.goals email → g₂ ∈ s.goals email →
    g₁.category = g₂.category → g₁.goalType = g₂.goalType → g₁ = g₂

/-- Checkbox completions only exist for existing checkbox goals. -/
def checkboxCompletionsHaveGoals (s : DomainState) : Prop :=
  ∀ email cc, cc ∈ s.checkboxCompletions email →
    hasGoal s email cc.category cc.goalType

/-- A user can't be both verified and pending. -/
def noVerifiedAndPending (s : DomainState) : Prop :=
  ∀ email, s.users email ≠ none → s.pendingRegs email = none

/-- All domain invariants bundled. -/
def allInvariants (s : DomainState) : Prop :=
  sessionsHaveOwners s ∧
  categoriesHaveOwners s ∧
  goalsHaveOwners s ∧
  sessionsUseOwnCategories s ∧
  goalsUseOwnCategories s ∧
  categoryNamesUnique s ∧
  sessionIdsUnique s ∧
  goalsUnique s ∧
  checkboxCompletionsHaveGoals s ∧
  noVerifiedAndPending s

/-- The empty state satisfies all invariants. -/
theorem empty_satisfies_invariants : allInvariants DomainState.empty := by
  unfold allInvariants
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> {
    intro _ <;> simp [DomainState.empty, userExists]
  }

end Spec.Domain
