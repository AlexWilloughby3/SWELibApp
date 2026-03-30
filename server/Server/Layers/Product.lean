import Server.Domain.User
import Server.Domain.Category
import Server.Domain.Session
import Server.Domain.Goal
import Server.Domain.Stats
import Server.Domain.Rbac

namespace Server

/-- Domain error type for operations that can fail with business logic errors. -/
inductive DomainError where
  | notFound
  | conflict
  | forbidden
  | limitReached
  | invalidInput (msg : String)
  deriving Repr

/-- A page of results with pagination metadata. -/
structure Page (α : Type) where
  items    : List α
  total    : Nat
  page     : Nat
  perPage  : Nat
  deriving Repr

/-- Date range filter for queries. -/
structure DateRange where
  from_ : String  -- ISO date string
  to_   : String
  deriving Repr

/-- Pagination parameters. -/
structure PageParams where
  page    : Nat := 1
  perPage : Nat := 20
  deriving Repr

/-- JWT token pair returned on login/refresh. -/
structure TokenPair where
  accessToken  : String
  refreshToken : String
  deriving Repr

/-- The product layer typeclass. Speaks entirely in domain language:
    users, sessions, goals, categories, stats, auth, RBAC.
    No mention of SQL, connections, or infrastructure.

    Handlers import only this typeclass — never DataLayer or SWELib directly. -/
class ProductLayer (ctx : Type) where
  -- Auth
  register      : ctx → String → String → String → IO User
  login         : ctx → String → String → IO (Option TokenPair)
  validateToken : ctx → String → IO (Option User)
  refreshAuth   : ctx → String → IO (Option TokenPair)
  changePassword: ctx → UserId → String → String → IO Bool

  -- RBAC
  authorize     : ctx → User → Permission → IO Bool

  -- Categories
  createCategory : ctx → UserId → String → IO (Except DomainError Category)
  listCategories : ctx → UserId → IO (List Category)
  deleteCategory : ctx → UserId → CategoryId → IO (Except DomainError Unit)

  -- Sessions
  logSession    : ctx → UserId → CategoryId → Nat → String → IO (List Session)
  listSessions  : ctx → UserId → DateRange → PageParams → IO (Page Session)
  deleteSession : ctx → UserId → SessionId → IO (Except DomainError Unit)

  -- Goals
  createGoal : ctx → UserId → CategoryId → GoalType → IO (Except DomainError Goal)
  toggleGoal : ctx → UserId → GoalId → String → IO Bool
  goalProgress : ctx → UserId → CategoryId → DateRange → IO GoalProgress

  -- Stats
  userStats     : ctx → UserId → DateRange → IO UserStats
  weeklySummary : ctx → UserId → IO WeeklySummary

end Server
