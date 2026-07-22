Write me an Elixir GenServer module called `RoleRegistry` that maintains a **mutable, arbitrary role-inheritance graph** with **runtime grant/revoke of permissions** — not a fixed four-level ladder, but a directed acyclic graph of roles that can be reshaped while the server is running.

I need the following public API (each takes the server `pid` or registered name as its first argument):

- `RoleRegistry.start_link(opts \\ [])` — starts the GenServer. Standard `GenServer` options like `:name` should be honored. Initial state has no roles, no inheritance edges, and no grants.
- `RoleRegistry.add_role(server, role)` — registers a role atom. Returns `:ok` (idempotent — adding an existing role is fine).
- `RoleRegistry.add_inheritance(server, child, parent)` — records that `child` inherits `parent`'s permissions (transitively). Both roles must already exist, otherwise return `{:error, :unknown_role}`. Adding an edge that would create a cycle (including a self-edge) must be rejected with `{:error, :cycle}` and leave state unchanged. On success return `:ok`.
- `RoleRegistry.grant(server, role, resource, action)` — grants permission for `{resource, action}` directly to `role`. The role must exist, otherwise `{:error, :unknown_role}`. Returns `:ok`. Idempotent.
- `RoleRegistry.revoke(server, role, resource, action)` — removes a direct `{resource, action}` grant from `role` (only that role's own grant, not inherited ones). Returns `:ok` even if the grant was not present.
- `RoleRegistry.can?(server, role, resource, action)` — returns `true` if `role`, or **any role it inherits transitively** (directly or through a chain of inheritance edges), has a direct grant for `{resource, action}`; otherwise `false`. Returns `false` for an unknown role.

Inheritance means: if `child` inherits `parent`, then `child` has every permission `parent` has (and everything `parent` inherits, transitively). Revoking a grant from `parent` must immediately affect what `child` can do.

Give me the complete module in a single file with no external dependencies.