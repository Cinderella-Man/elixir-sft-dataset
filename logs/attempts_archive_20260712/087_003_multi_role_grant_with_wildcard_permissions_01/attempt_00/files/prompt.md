Write me an Elixir module called `Rbac` that resolves permissions for a **principal that can hold multiple roles at once**, using **`"resource:action"` permission strings with wildcard patterns**.

Roles are defined as a map from a role atom to a list of permission-pattern strings:

```elixir
%{
  viewer: ["posts:read", "comments:read"],
  editor: ["posts:read", "posts:write", "comments:read", "comments:write"],
  admin:  ["*:*"]
}
```

A permission pattern is a colon-separated string of two segments, `"<resource>:<action>"`, where either segment may be the literal `"*"` wildcard which matches any value in that position. Examples: `"posts:read"`, `"posts:*"`, `"*:read"`, `"*:*"`.

A **principal** is either:

- a plain list of role atoms, e.g. `[:viewer, :editor]`, or
- a map `%{roles: [atom], grants: [String.t()]}` where `:grants` is a list of extra permission-pattern strings granted directly to that principal (in addition to those from its roles). Missing `:roles` / `:grants` keys default to `[]`.

A principal's effective permissions are the **union** of the patterns from every role it holds plus its direct grants.

I need the following public API:

- `Rbac.effective_permissions(principal, role_defs)` — returns a `MapSet` of the principal's effective permission-pattern strings.
- `Rbac.permitted?(principal, resource, action, role_defs)` — takes `resource` and `action` as atoms, builds the target `"resource:action"`, and returns `true` if **any** effective pattern matches the target (segment by segment, with `"*"` matching anything), else `false`. Unknown roles contribute no permissions rather than raising.

Give me the complete module in a single file with no external dependencies.