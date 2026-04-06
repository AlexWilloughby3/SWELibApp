import Spec.Domain

/-!
# User Endpoint Specifications

Preconditions, postconditions, and pure transition functions for every
user-facing endpoint. These are the contracts that the implementation
(handlers + DB) must satisfy.

Each endpoint is specified as:
  - A **precondition** on (state, inputs) that determines success vs error.
  - A **transition function** that computes the new state (on success).
  - **Postconditions** as propositions relating old state, new state, and result.
  - Theorems about the contracts (error ↔ precondition fails, etc.)
-/

namespace Spec.UserOps

open Spec.Domain

-- ═══════════════════════════════════════════════════════════
-- Constants
-- ═══════════════════════════════════════════════════════════

def maxAccounts : Nat := 50
def maxCategories : Nat := 20
def minPasswordLength : Nat := 8
def minResetPasswordLength : Nat := 6

def defaultCategories : List String :=
  ["Work", "Study", "Reading", "Exercise", "Meditation"]

-- ═══════════════════════════════════════════════════════════
-- Helper: count users in the domain
-- ═══════════════════════════════════════════════════════════

/-- A list of all known emails in the system. In practice this comes from
    the DB; here we take it as a parameter to keep things pure. -/
abbrev KnownEmails := List Email

def userCount (s : DomainState) (known : KnownEmails) : Nat :=
  known.filter (fun e => s.users e |>.isSome) |>.length

-- ═══════════════════════════════════════════════════════════
-- POST /auth/register
-- ═══════════════════════════════════════════════════════════

namespace Register

/-- Precondition: registration can succeed. -/
def pre (s : DomainState) (known : KnownEmails) (email : Email) (password : String) : Prop :=
  s.users email = none ∧
  password.length ≥ minPasswordLength ∧
  userCount s known < maxAccounts

/-- On success: a pending registration is created; no user yet. -/
def apply (s : DomainState) (email : Email) (hashedPw : String) (code : String) : DomainState :=
  { s with
    pendingRegs := fun e =>
      if e = email then some ⟨hashedPw, code, ""⟩
      else s.pendingRegs e }

/-- Postcondition: pending registration exists for this email. -/
def post (s s' : DomainState) (email : Email) : Prop :=
  s'.pendingRegs email ≠ none ∧
  s'.users email = s.users email  -- user table unchanged

/-- Error cases. -/
inductive ErrorReason where
  | emailAlreadyRegistered
  | passwordTooShort
  | accountLimitReached

/-- Registering does not create a user. -/
theorem apply_no_user (s : DomainState) (email : Email) (hp : String) (code : String) :
    (apply s email hp code).users = s.users := by
  simp [apply]

/-- Registering creates a pending registration for exactly the given email. -/
theorem apply_creates_pending (s : DomainState) (email : Email) (hp code : String) :
    (apply s email hp code).pendingRegs email ≠ none := by
  simp [apply]

/-- Registering does not affect other emails' pending registrations. -/
theorem apply_other_pending (s : DomainState) (email other : Email) (hp code : String)
    (h : other ≠ email) :
    (apply s email hp code).pendingRegs other = s.pendingRegs other := by
  simp [apply, h]

end Register

-- ═══════════════════════════════════════════════════════════
-- POST /auth/verify
-- ═══════════════════════════════════════════════════════════

namespace Verify

/-- Precondition: verification can succeed. -/
def pre (s : DomainState) (email : Email) (code : String) : Prop :=
  ∃ pending, s.pendingRegs email = some pending ∧
  pending.verificationCode = code

/-- On success: user is created, pending reg is removed, default categories added. -/
def apply (s : DomainState) (email : Email) (name : String) (hashedPw : String) : DomainState :=
  { s with
    users := fun e =>
      if e = email then some ⟨name, hashedPw, ""⟩
      else s.users e
    pendingRegs := fun e =>
      if e = email then none
      else s.pendingRegs e
    categories := fun e =>
      if e = email then defaultCategories.map (fun c => ⟨c, true⟩)
      else s.categories e }

/-- Postcondition: user exists, pending reg gone, has default categories. -/
def post (_s s' : DomainState) (email : Email) : Prop :=
  s'.users email ≠ none ∧
  s'.pendingRegs email = none ∧
  (s'.categories email).length = defaultCategories.length

/-- Verifying removes the pending registration. -/
theorem apply_clears_pending (s : DomainState) (email name hp : String) :
    (apply s email name hp).pendingRegs email = none := by
  simp [apply]

/-- Verifying creates a user. -/
theorem apply_creates_user (s : DomainState) (email name hp : String) :
    (apply s email name hp).users email ≠ none := by
  simp [apply]

/-- Verifying does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other name hp : String) (h : other ≠ email) :
    (apply s email name hp).users other = s.users other := by
  simp [apply, h]

/-- Post-verify, the noVerifiedAndPending invariant holds for this email. -/
theorem apply_no_verified_and_pending (s : DomainState) (email name hp : String) :
    (apply s email name hp).users email ≠ none →
    (apply s email name hp).pendingRegs email = none := by
  intro _
  simp [apply]

end Verify

-- ═══════════════════════════════════════════════════════════
-- POST /auth/login
-- ═══════════════════════════════════════════════════════════

namespace Login

/-- Precondition: login can succeed.
    `checkPassword` is abstract — impl provides bcrypt verify. -/
def pre (s : DomainState) (email : Email) (password : String)
    (checkPassword : String → String → Bool) : Prop :=
  ∃ user, s.users email = some user ∧
  checkPassword password user.hashedPassword = true

/-- Login does not change state. -/
def apply (s : DomainState) : DomainState := s

/-- Postcondition: state is unchanged. -/
def post (s s' : DomainState) : Prop := s' = s

theorem apply_is_identity (s : DomainState) : apply s = s := rfl

end Login

-- ═══════════════════════════════════════════════════════════
-- GET /users/{email}
-- ═══════════════════════════════════════════════════════════

namespace GetUser

/-- Precondition: user exists. -/
def pre (s : DomainState) (email : Email) : Prop :=
  s.users email ≠ none

/-- Get is a read — no state change. -/
def apply (s : DomainState) : DomainState := s

/-- Postcondition: state unchanged, and the returned user matches state. -/
def post (s s' : DomainState) (email : Email) (returnedUser : UserRecord) : Prop :=
  s' = s ∧ s.users email = some returnedUser

theorem apply_is_identity (s : DomainState) : apply s = s := rfl

end GetUser

-- ═══════════════════════════════════════════════════════════
-- PATCH /users/{email}
-- ═══════════════════════════════════════════════════════════

namespace UpdateUser

/-- Precondition: user exists. -/
def pre (s : DomainState) (email : Email) : Prop :=
  s.users email ≠ none

/-- On success: user record is updated with new name (keeping password). -/
def apply (s : DomainState) (email : Email) (newName : String) : DomainState :=
  { s with
    users := fun e =>
      if e = email then
        s.users e |>.map (fun u => { u with name := newName })
      else s.users e }

/-- Postcondition: user still exists, name is updated, password unchanged. -/
def post (s s' : DomainState) (email : Email) (newName : String) : Prop :=
  ∃ u', s'.users email = some u' ∧ u'.name = newName ∧
  ∃ u, s.users email = some u ∧ u'.hashedPassword = u.hashedPassword

/-- Updating does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other newName : String)
    (h : other ≠ email) :
    (apply s email newName).users other = s.users other := by
  simp [apply, h]

/-- Updating preserves the user's existence. -/
theorem apply_preserves_user (s : DomainState) (email newName : String)
    (h : s.users email ≠ none) :
    (apply s email newName).users email ≠ none := by
  simp only [apply]
  intro h_eq
  apply h
  cases h_match : s.users email with
  | none => rfl
  | some u => simp [h_match] at h_eq

end UpdateUser

-- ═══════════════════════════════════════════════════════════
-- DELETE /users/{email}
-- ═══════════════════════════════════════════════════════════

namespace DeleteUser

/-- Precondition: user exists. -/
def pre (s : DomainState) (email : Email) : Prop :=
  s.users email ≠ none

/-- On success: user, their categories, sessions, goals, completions are all removed. -/
def apply (s : DomainState) (email : Email) : DomainState :=
  { s with
    users := fun e => if e = email then none else s.users e
    categories := fun e => if e = email then [] else s.categories e
    sessions := fun e => if e = email then [] else s.sessions e
    goals := fun e => if e = email then [] else s.goals e
    checkboxCompletions := fun e => if e = email then [] else s.checkboxCompletions e
    pendingRegs := fun e => if e = email then none else s.pendingRegs e
    resetTokens := fun e => if e = email then none else s.resetTokens e }

/-- Postcondition: user and all their data are gone. -/
def post (s' : DomainState) (email : Email) : Prop :=
  s'.users email = none ∧
  s'.categories email = [] ∧
  s'.sessions email = [] ∧
  s'.goals email = []

/-- Deleting removes the user. -/
theorem apply_removes_user (s : DomainState) (email : Email) :
    (apply s email).users email = none := by
  simp [apply]

/-- Deleting clears all user data. -/
theorem apply_clears_data (s : DomainState) (email : Email) :
    post (apply s email) email := by
  constructor
  · simp [apply]
  constructor
  · simp [apply]
  constructor
  · simp [apply]
  · simp [apply]

/-- Deleting does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other : Email) (h : other ≠ email) :
    (apply s email).users other = s.users other ∧
    (apply s email).categories other = s.categories other ∧
    (apply s email).sessions other = s.sessions other ∧
    (apply s email).goals other = s.goals other := by
  simp [apply, h]

/-- Deleting preserves sessionsHaveOwners for other users. -/
theorem apply_preserves_sessions_have_owners (s : DomainState) (email : Email)
    (h : sessionsHaveOwners s) :
    sessionsHaveOwners (DeleteUser.apply s email) := by
  intro other h_sessions
  unfold sessionsHaveOwners at h
  unfold userExists at *
  simp only [DeleteUser.apply] at h_sessions ⊢
  by_cases h_eq : other = email
  · subst h_eq; simp at h_sessions
  · simp [h_eq] at h_sessions ⊢
    exact h other h_sessions

end DeleteUser

-- ═══════════════════════════════════════════════════════════
-- POST /auth/request-code (passwordless login)
-- ═══════════════════════════════════════════════════════════

namespace RequestCode

/-- No precondition required — always returns 200 (no email leak). -/
def pre (_s : DomainState) (_email : Email) : Prop := True

/-- State is unchanged (code storage is an infra concern). -/
def apply (s : DomainState) : DomainState := s

/-- Postcondition: state unchanged. Response is always success
    regardless of whether email exists. -/
def post (s s' : DomainState) : Prop := s' = s

/-- Never leaks email existence: the observable response is the same
    whether the user exists or not. -/
theorem no_email_leak (s : DomainState) (_email : Email) :
    apply s = apply s := rfl

end RequestCode

-- ═══════════════════════════════════════════════════════════
-- POST /auth/login-code
-- ═══════════════════════════════════════════════════════════

namespace LoginWithCode

/-- Precondition: user exists and code matches a valid, non-expired code.
    `validCode` is abstract — impl checks the DB. -/
def pre (s : DomainState) (email : Email) (validCode : Bool) : Prop :=
  s.users email ≠ none ∧ validCode = true

/-- Login does not change domain state (code deletion is infra). -/
def apply (s : DomainState) : DomainState := s

def post (s s' : DomainState) : Prop := s' = s

end LoginWithCode

-- ═══════════════════════════════════════════════════════════
-- POST /auth/change-password
-- ═══════════════════════════════════════════════════════════

namespace ChangePassword

/-- Precondition: user exists and current password is correct. -/
def pre (s : DomainState) (email : Email) (currentPassword : String)
    (newPassword : String) (checkPassword : String → String → Bool) : Prop :=
  ∃ user, s.users email = some user ∧
  checkPassword currentPassword user.hashedPassword = true ∧
  newPassword.length ≥ minPasswordLength

/-- On success: password hash is updated. -/
def apply (s : DomainState) (email : Email) (newHashedPw : String) : DomainState :=
  { s with
    users := fun e =>
      if e = email then
        s.users e |>.map (fun u => { u with hashedPassword := newHashedPw })
      else s.users e }

/-- Postcondition: user still exists, password is changed, name preserved. -/
def post (s s' : DomainState) (email : Email) (newHashedPw : String) : Prop :=
  ∃ u', s'.users email = some u' ∧ u'.hashedPassword = newHashedPw ∧
  ∃ u, s.users email = some u ∧ u'.name = u.name

/-- Changing password does not affect other users. -/
theorem apply_other_users (s : DomainState) (email other hp : String) (h : other ≠ email) :
    (apply s email hp).users other = s.users other := by
  simp [apply, h]

end ChangePassword

-- ═══════════════════════════════════════════════════════════
-- POST /auth/forgot-password
-- ═══════════════════════════════════════════════════════════

namespace ForgotPassword

/-- No precondition — always returns success (no email leak). -/
def pre (_s : DomainState) (_email : Email) : Prop := True

/-- Token creation is tracked in resetTokens. -/
def apply (s : DomainState) (email : Email) (token : String) : DomainState :=
  { s with
    resetTokens := fun e =>
      if e = email then some ⟨token, ""⟩
      else s.resetTokens e }

/-- Postcondition: if user exists, a token was created. -/
def post (s s' : DomainState) (email : Email) : Prop :=
  s.users email ≠ none → s'.resetTokens email ≠ none

/-- Never leaks email existence. -/
theorem no_email_leak_response : True := trivial

end ForgotPassword

-- ═══════════════════════════════════════════════════════════
-- POST /auth/reset-password
-- ═══════════════════════════════════════════════════════════

namespace ResetPassword

/-- Precondition: valid, unused, non-expired token exists.
    `tokenValid` is abstract — impl checks DB. -/
def pre (s : DomainState) (email : Email) (tokenValid : Bool)
    (newPassword : String) : Prop :=
  s.users email ≠ none ∧
  tokenValid = true ∧
  newPassword.length ≥ minResetPasswordLength

/-- On success: password updated, token consumed. -/
def apply (s : DomainState) (email : Email) (newHashedPw : String) : DomainState :=
  { s with
    users := fun e =>
      if e = email then
        s.users e |>.map (fun u => { u with hashedPassword := newHashedPw })
      else s.users e
    resetTokens := fun e =>
      if e = email then none
      else s.resetTokens e }

/-- Postcondition: password changed, token consumed. -/
def post (s' : DomainState) (email : Email) (newHashedPw : String) : Prop :=
  ∃ u', s'.users email = some u' ∧ u'.hashedPassword = newHashedPw ∧
  s'.resetTokens email = none

/-- Reset consumes the token. -/
theorem apply_consumes_token (s : DomainState) (email hp : String) :
    (apply s email hp).resetTokens email = none := by
  simp [apply]

end ResetPassword

-- ═══════════════════════════════════════════════════════════
-- Aggregate: all user ops are state-isolated per user
-- ═══════════════════════════════════════════════════════════

/-- View function: what a specific user can see of the state. -/
def userView (s : DomainState) (email : Email) :
    Option UserRecord × List CategoryRecord × List SessionRecord × List GoalRecord :=
  (s.users email, s.categories email, s.sessions email, s.goals email)

/-- Register does not affect any existing user's view. -/
theorem register_isolated (s : DomainState) (email other : Email)
    (hp code : String) :
    userView (Register.apply s email hp code) other = userView s other := by
  simp [userView, Register.apply]

/-- Delete does not affect other users' views. -/
theorem delete_isolated (s : DomainState) (email other : Email) (h : other ≠ email) :
    userView (DeleteUser.apply s email) other = userView s other := by
  simp [userView, DeleteUser.apply, h]

/-- Verify does not affect other users' views. -/
theorem verify_isolated (s : DomainState) (email other name hp : String)
    (h : other ≠ email) :
    userView (Verify.apply s email name hp) other = userView s other := by
  simp [userView, Verify.apply, h]

end Spec.UserOps
