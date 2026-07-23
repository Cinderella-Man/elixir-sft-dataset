**Ticket:** Implement `Rbac` — permission resolution for a principal that may hold multiple roles at once, over `"resource:action"` permission strings with wildcard patterns.

**Deliverable**
- Complete Elixir module named `Rbac`, single file, no external dependencies.

**Role definitions**
- Roles are a map from a role atom to a list of permission-pattern strings.
- Shape:

```elixir
%{
  viewer: ["posts:read", "comments:read"],
  editor: ["posts:read", "posts:write", "comments:read", "comments:write"],
  admin:  ["*:*"]
}
```

**Permission patterns**
- A pattern is a colon-separated string of two segments, `"<resource>:<action>"`.
- Either segment may be the literal `"*"` wildcard, which matches any value in that position.
- Examples: `"posts:read"`, `"posts:*"`, `"*:read"`, `"*:*"`.

**Principal shapes**
- A plain list of role atoms, e.g. `[:viewer, :editor]`; or
- a map `%{roles: [atom], grants: [String.t()]}`, where `:grants` is a list of extra permission-pattern strings granted directly to that principal, in addition to those from its roles.
- Missing `:roles` / `:grants` keys default to `[]`.
- Effective permissions = the **union** of the patterns from every role held plus the direct grants.

**API — `Rbac.effective_permissions(principal, role_defs)`**
- Returns a `MapSet` of the principal's effective permission-pattern strings (deduplicated by the set).
- An empty principal, or one holding only unknown roles, yields `MapSet.new()`.

**API — `Rbac.permitted?(principal, resource, action, role_defs)`**
- `resource` and `action` arrive as atoms; build the target `"resource:action"` from them.
- Returns `true` if **any** effective pattern matches the target, else `false`.
- Match segment-by-segment after splitting both pattern and target on `":"`; `"*"` matches any value in its position.
- A pattern matches only when it has the **same number of segments** as the two-segment target. A pattern with a different segment count — e.g. a bare `"posts"`, or a three-segment `"posts:read:extra"` / `"*:*:*"` — never matches.
- Unknown roles contribute no permissions rather than raising.
