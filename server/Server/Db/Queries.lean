import Server.Layers.Data

namespace Server.Db.Queries

/-- Helper to build a parameterized query. -/
def mkQuery (sql : String) (params : Array String := #[]) : ParamQuery :=
  { sql, params }

-- User queries
def findUserByEmail (email : String) : ParamQuery :=
  mkQuery "SELECT id, email, display_name, password_hash FROM users WHERE email = $1" #[email]

def findUserById (id : String) : ParamQuery :=
  mkQuery "SELECT id, email, display_name FROM users WHERE id = $1" #[id]

def deleteUser (id : String) : ParamQuery :=
  mkQuery "DELETE FROM users WHERE id = $1" #[id]

-- Category queries
def categoriesForUser (userId : String) : ParamQuery :=
  mkQuery "SELECT id, user_id, name, is_active FROM categories WHERE user_id = $1 ORDER BY name" #[userId]

def categoryCount (userId : String) : ParamQuery :=
  mkQuery "SELECT COUNT(*) FROM categories WHERE user_id = $1" #[userId]

-- Session queries
def sessionsForUser (userId : String) (from_ : String) (to_ : String) (limit : Nat) (offset : Nat) : ParamQuery :=
  mkQuery
    "SELECT id, user_id, category_id, duration_seconds, started_at FROM focus_sessions WHERE user_id = $1 AND started_at >= $2 AND started_at < $3 ORDER BY started_at DESC LIMIT $4 OFFSET $5"
    #[userId, from_, to_, toString limit, toString offset]

-- Stats queries
def statsByCategory (userId : String) (from_ : String) (to_ : String) : ParamQuery :=
  mkQuery
    "SELECT c.id, c.name, COALESCE(SUM(s.duration_seconds), 0), COUNT(s.id) FROM categories c LEFT JOIN focus_sessions s ON s.category_id = c.id AND s.started_at >= $2 AND s.started_at < $3 WHERE c.user_id = $1 GROUP BY c.id, c.name ORDER BY c.name"
    #[userId, from_, to_]

end Server.Db.Queries
