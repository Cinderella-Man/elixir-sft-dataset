Write me an Elixir module called `Permissions` that implements a role-based access control system with hierarchical roles and owner-based overrides.

The role hierarchy, from least to most privileged, is: `:viewer < :editor < :manager < :admin`. A user with a higher role automatically inherits all permissions of lower roles.

Permissions are defined as a map of the shape `%{resource => %{action => required_role}}`, for example:
```elixir
%{
  posts: %{read: :viewer, create: :editor, update: :editor, delete: :manager},
  settings: %{read: :manager, update: :admin}
}
```

I need the following in the public API:

- `Permissions.can?(role, resource, action, rules)` — returns `true` if the given role is at or above the role required by `rules` for `resource` + `action`, and `false` otherwise. Return `false` for unknown resources or actions rather than raising.
- `Permissions.can?(role, resource, action, rules, opts)` — same as above but accepts an `opts` keyword list. When `opts` includes `[owner_id: id, user_id: id]` and the resource+action rule is the atom `:owner`, grant access if and only if `owner_id == user_id`, regardless of role. If the rule is `:owner` but no `opts` are provided (or the ids don't match), deny access.

The `:admin` role must be able to do everything that any lower role can do. The `:owner` special-case should be composable — a resource action can require `:owner` while other actions on the same resource require normal roles.

Give me the complete module in a single file with no external dependencies.