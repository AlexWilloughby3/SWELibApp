import Spec.Domain
import Spec.CategoryOps
import Spec.SessionOps
import Spec.GoalOps

/-!
# Invariant Preservation Theorems

Proofs that each mutating spec operation preserves the relevant
domain invariants from `allInvariants`.
-/

namespace Spec.Preservation

open Spec.Domain
open Spec.CategoryOps
open Spec.SessionOps
open Spec.GoalOps

-- ═══════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════

/-- ToggleCheckbox does not modify goals. -/
private theorem toggleCheckbox_goals_unchanged
    (s : DomainState) (email category : String) (goalType : GoalType) (date : String) :
    (ToggleCheckbox.apply s email category goalType date).goals = s.goals := by
  unfold ToggleCheckbox.apply
  cases ToggleCheckbox.findCompletion s email category goalType date <;> simp

/-- UpsertGoal does not modify categories. -/
private theorem upsertGoal_categories_unchanged
    (s : DomainState) (email category : String) (goalType : GoalType)
    (targetSeconds : Option Nat) (description : Option String) :
    (UpsertGoal.apply s email category goalType targetSeconds description).categories = s.categories := by
  simp [UpsertGoal.apply]

/-- RecordSession does not modify users. -/
private theorem recordSession_users_unchanged
    (s : DomainState) (email category : String) (newSessions : List SessionRecord) :
    (RecordSession.apply s email category newSessions).users = s.users := by
  unfold RecordSession.apply; split <;> simp

-- ═══════════════════════════════════════════════════════════
-- CreateCategory
-- ═══════════════════════════════════════════════════════════

/-- CreateCategory preserves categoriesHaveOwners. -/
theorem createCategory_preserves_categoriesHaveOwners
    (s : DomainState) (email name : String)
    (h_inv : categoriesHaveOwners s)
    (h_pre : CreateCategory.pre s email name) :
    categoriesHaveOwners (CreateCategory.apply s email name) := by
  unfold CreateCategory.apply
  split
  · exact h_inv
  · intro other h_cats
    unfold categoriesHaveOwners at h_inv
    unfold userExists at *
    by_cases h_eq : other = email
    · subst h_eq; exact h_pre.1
    · simp [h_eq] at h_cats; exact h_inv other h_cats

/-- CreateCategory preserves categoryNamesUnique. -/
theorem createCategory_preserves_categoryNamesUnique
    (s : DomainState) (email name : String)
    (h_inv : categoryNamesUnique s) :
    categoryNamesUnique (CreateCategory.apply s email name) := by
  unfold CreateCategory.apply
  split
  · exact h_inv
  · rename_i h_not_any
    simp [List.any_eq_true] at h_not_any
    -- h_not_any : ∀ x ∈ s.categories email, x.name ≠ name
    intro other c₁ c₂ hc₁ hc₂ h_name_eq
    by_cases h_eq : other = email
    · subst h_eq
      simp at hc₁ hc₂
      rcases hc₁ with hc₁_old | hc₁_new
      · rcases hc₂ with hc₂_old | hc₂_new
        · exact h_inv _ c₁ c₂ hc₁_old hc₂_old h_name_eq
        · exfalso; exact h_not_any c₁ hc₁_old (by rw [h_name_eq, hc₂_new])
      · rcases hc₂ with hc₂_old | hc₂_new
        · exfalso; exact h_not_any c₂ hc₂_old (by rw [← h_name_eq, hc₁_new])
        · rw [hc₁_new, hc₂_new]
    · simp [h_eq] at hc₁ hc₂
      exact h_inv other c₁ c₂ hc₁ hc₂ h_name_eq

-- ═══════════════════════════════════════════════════════════
-- DeleteCategory
-- ═══════════════════════════════════════════════════════════

/-- DeleteCategory preserves sessionsUseOwnCategories. -/
theorem deleteCategory_preserves_sessionsUseOwnCategories
    (s : DomainState) (email name : String)
    (h_inv : sessionsUseOwnCategories s) :
    sessionsUseOwnCategories (DeleteCategory.apply s email name) := by
  intro other sess h_sess
  unfold DeleteCategory.apply at h_sess ⊢
  unfold ownsCategory
  by_cases h_eq : other = email
  · subst h_eq
    simp at h_sess ⊢
    obtain ⟨h_mem, h_ne⟩ := h_sess
    have h_old := h_inv _ sess h_mem
    obtain ⟨c, hc_mem, hc_name⟩ := h_old
    exact ⟨c, ⟨hc_mem, by rw [hc_name]; exact h_ne⟩, hc_name⟩
  · simp [h_eq] at h_sess ⊢
    exact h_inv other sess h_sess

/-- DeleteCategory preserves goalsUseOwnCategories. -/
theorem deleteCategory_preserves_goalsUseOwnCategories
    (s : DomainState) (email name : String)
    (h_inv : goalsUseOwnCategories s) :
    goalsUseOwnCategories (DeleteCategory.apply s email name) := by
  intro other goal h_goal
  unfold DeleteCategory.apply at h_goal ⊢
  unfold ownsCategory
  by_cases h_eq : other = email
  · subst h_eq
    simp at h_goal ⊢
    obtain ⟨h_mem, h_ne⟩ := h_goal
    have h_old := h_inv _ goal h_mem
    obtain ⟨c, hc_mem, hc_name⟩ := h_old
    exact ⟨c, ⟨hc_mem, by rw [hc_name]; exact h_ne⟩, hc_name⟩
  · simp [h_eq] at h_goal ⊢
    exact h_inv other goal h_goal

/-- DeleteCategory preserves checkboxCompletionsHaveGoals. -/
theorem deleteCategory_preserves_checkboxCompletionsHaveGoals
    (s : DomainState) (email name : String)
    (h_inv : checkboxCompletionsHaveGoals s) :
    checkboxCompletionsHaveGoals (DeleteCategory.apply s email name) := by
  intro other cc h_cc
  unfold DeleteCategory.apply at h_cc ⊢
  unfold hasGoal
  by_cases h_eq : other = email
  · subst h_eq
    simp at h_cc ⊢
    obtain ⟨h_mem, h_ne⟩ := h_cc
    have h_old := h_inv _ cc h_mem
    obtain ⟨goal, hg_mem, hg_cat, hg_type⟩ := h_old
    exact ⟨goal, ⟨hg_mem, by rw [hg_cat]; exact h_ne⟩, hg_cat, hg_type⟩
  · simp [h_eq] at h_cc ⊢
    exact h_inv other cc h_cc

-- ═══════════════════════════════════════════════════════════
-- RecordSession
-- ═══════════════════════════════════════════════════════════

/-- RecordSession preserves sessionsHaveOwners. -/
theorem recordSession_preserves_sessionsHaveOwners
    (s : DomainState) (email category : String) (newSessions : List SessionRecord)
    (h_inv : sessionsHaveOwners s)
    (h_pre : RecordSession.pre s email category) :
    sessionsHaveOwners (RecordSession.apply s email category newSessions) := by
  have h_users := recordSession_users_unchanged s email category newSessions
  intro other h_sessions
  unfold userExists
  rw [h_users]
  unfold sessionsHaveOwners at h_inv
  unfold userExists at h_inv
  by_cases h_eq : other = email
  · subst h_eq; exact h_pre.1
  · apply h_inv
    unfold RecordSession.apply at h_sessions
    simp at h_sessions
    by_cases h_eq2 : other = email
    · exact absurd h_eq2 h_eq
    · simp [h_eq2] at h_sessions
      split at h_sessions <;> simp_all

-- ═══════════════════════════════════════════════════════════
-- UpsertGoal
-- ═══════════════════════════════════════════════════════════

/-- UpsertGoal preserves goalsUseOwnCategories when the category exists. -/
theorem upsertGoal_preserves_goalsUseOwnCategories
    (s : DomainState) (email category : String) (goalType : GoalType)
    (targetSeconds : Option Nat) (description : Option String)
    (h_inv : goalsUseOwnCategories s)
    (h_cat : ownsCategory s email category) :
    goalsUseOwnCategories (UpsertGoal.apply s email category goalType targetSeconds description) := by
  have h_cats := upsertGoal_categories_unchanged s email category goalType targetSeconds description
  intro other goal h_goal
  -- ownsCategory only uses categories, which is unchanged
  show ownsCategory (UpsertGoal.apply s email category goalType targetSeconds description) other goal.category
  unfold ownsCategory; rw [h_cats]
  -- Determine what goal is from the modified goals list
  by_cases h_eq : other = email
  · subst h_eq
    -- Use apply_other_users-style reasoning: unfold and split ifs
    unfold UpsertGoal.apply at h_goal
    simp at h_goal
    split at h_goal
    · -- Update case: goal is in mapped list
      rw [List.mem_map] at h_goal
      obtain ⟨g_orig, hg_mem, hg_eq⟩ := h_goal
      split at hg_eq
      · subst hg_eq; exact h_cat
      · subst hg_eq; exact h_inv _ g_orig hg_mem
    · -- Insert case: goal in old ++ [newGoal]
      rcases List.mem_append.mp h_goal with h_old | h_new
      · exact h_inv _ goal h_old
      · simp at h_new; subst h_new; exact h_cat
  · have : (UpsertGoal.apply s email category goalType targetSeconds description).goals other = s.goals other :=
      (UpsertGoal.apply_other_users s email other category goalType targetSeconds description h_eq)
    rw [this] at h_goal
    exact h_inv other goal h_goal

-- ═══════════════════════════════════════════════════════════
-- DeleteGoal
-- ═══════════════════════════════════════════════════════════

/-- DeleteGoal preserves checkboxCompletionsHaveGoals. -/
theorem deleteGoal_preserves_checkboxCompletionsHaveGoals
    (s : DomainState) (email category : String) (goalType : GoalType)
    (h_inv : checkboxCompletionsHaveGoals s) :
    checkboxCompletionsHaveGoals (DeleteGoal.apply s email category goalType) := by
  intro other cc h_cc
  unfold DeleteGoal.apply at h_cc ⊢
  unfold hasGoal
  by_cases h_eq : other = email
  · subst h_eq
    simp at h_cc ⊢
    obtain ⟨h_mem, h_ne⟩ := h_cc
    have h_old := h_inv _ cc h_mem
    obtain ⟨goal, hg_mem, hg_cat, hg_type⟩ := h_old
    refine ⟨goal, ⟨hg_mem, ?_⟩, hg_cat, hg_type⟩
    rw [hg_cat, hg_type]; exact h_ne
  · simp [h_eq] at h_cc ⊢
    exact h_inv other cc h_cc

-- ═══════════════════════════════════════════════════════════
-- ToggleCheckbox
-- ═══════════════════════════════════════════════════════════

/-- ToggleCheckbox preserves checkboxCompletionsHaveGoals. -/
theorem toggleCheckbox_preserves_checkboxCompletionsHaveGoals
    (s : DomainState) (email category : String) (goalType : GoalType) (date : String)
    (h_inv : checkboxCompletionsHaveGoals s)
    (h_pre : ToggleCheckbox.pre s email category goalType) :
    checkboxCompletionsHaveGoals (ToggleCheckbox.apply s email category goalType date) := by
  have h_goals := toggleCheckbox_goals_unchanged s email category goalType date
  intro other cc h_cc
  -- hasGoal only depends on .goals, which is unchanged
  unfold hasGoal
  rw [h_goals]
  -- Now we need to show hasGoal s other cc.category cc.goalType
  unfold ToggleCheckbox.apply at h_cc
  cases h_find : ToggleCheckbox.findCompletion s email category goalType date
  · -- No existing: new completion prepended
    simp [h_find] at h_cc
    by_cases h_eq : other = email
    · subst h_eq
      simp at h_cc
      rcases h_cc with h_new | h_old
      · subst h_new; exact h_pre.2.1
      · exact h_inv _ cc h_old
    · simp [h_eq] at h_cc
      exact h_inv other cc h_cc
  · -- Existing: flip
    rename_i existing
    simp [h_find] at h_cc
    by_cases h_eq : other = email
    · subst h_eq
      simp at h_cc
      obtain ⟨cc_orig, hcc_mem, hcc_eq⟩ := h_cc
      have h_old := h_inv _ cc_orig hcc_mem
      -- Whether flipped or not, category and goalType are preserved
      split at hcc_eq
      · subst hcc_eq; exact h_old
      · subst hcc_eq; exact h_old
    · simp [h_eq] at h_cc
      exact h_inv other cc h_cc

end Spec.Preservation
