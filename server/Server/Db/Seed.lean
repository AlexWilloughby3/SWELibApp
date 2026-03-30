import Server.Layers.Data

namespace Server.Db

/-- Seed default roles and permissions. Idempotent via ON CONFLICT DO NOTHING. -/
def seedDefaults [DataLayer ctx] (ctx_ : ctx) : IO Unit := do
  -- Seed roles
  DataLayer.execRaw ctx_ "INSERT INTO roles (name) VALUES ('user') ON CONFLICT DO NOTHING"
  DataLayer.execRaw ctx_ "INSERT INTO roles (name) VALUES ('admin') ON CONFLICT DO NOTHING"

  -- Seed permissions for user role
  let userPerms := [
    ("create", "session", "own"), ("read", "session", "own"), ("delete", "session", "own"),
    ("create", "category", "own"), ("read", "category", "own"), ("update", "category", "own"), ("delete", "category", "own"),
    ("create", "goal", "own"), ("read", "goal", "own"), ("update", "goal", "own"), ("delete", "goal", "own"),
    ("read", "stats", "own"),
    ("update", "user", "own"), ("delete", "user", "own")
  ]
  for (action, resource, scope) in userPerms do
    DataLayer.execRaw ctx_ s!"INSERT INTO permissions (action, resource, scope) VALUES ('{action}', '{resource}', '{scope}') ON CONFLICT DO NOTHING"

  -- Link user role to its permissions
  DataLayer.execRaw ctx_ "INSERT INTO role_permissions (role_id, permission_id) SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.name = 'user' ON CONFLICT DO NOTHING"

  -- Admin gets all permissions (including scope='any')
  let adminPerms := [
    ("read", "user", "any"), ("update", "user", "any"), ("delete", "user", "any"),
    ("read", "session", "any"), ("read", "stats", "any"),
    ("manage", "roles", "any")
  ]
  for (action, resource, scope) in adminPerms do
    DataLayer.execRaw ctx_ s!"INSERT INTO permissions (action, resource, scope) VALUES ('{action}', '{resource}', '{scope}') ON CONFLICT DO NOTHING"

  DataLayer.execRaw ctx_ "INSERT INTO role_permissions (role_id, permission_id) SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.name = 'admin' ON CONFLICT DO NOTHING"

end Server.Db
