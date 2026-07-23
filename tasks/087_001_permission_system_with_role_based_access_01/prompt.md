# Design brief: role-based access control with owner overrides

## Problem

An application needs to decide, for a given user role, whether an action on a resource is allowed. Roles are hierarchical, so authorization checks should not have to enumerate every role that can perform an action — a more privileged role should satisfy a rule written for a less privileged one. Separately, some actions are not role-gated at all but ownership-gated: the acting user may perform them only on records they own, whatever their role. Both mechanisms have to coexist inside the same rule set.

## Constraints

- Deliver an Elixir module called `Permissions` implementing a role-based access control system with hierarchical roles and owner-based overrides.
- The role hierarchy, from least to most privileged, is: `:viewer < :editor < :manager < :admin`. A user with a higher role automatically inherits all permissions of lower roles.
- Permissions are defined as a map of the shape `%{resource => %{action => required_role}}`, for example:

```elixir
%{
  posts: %{read: :viewer, create: :editor, update: :editor, delete: :manager},
  settings: %{read: :manager, update: :admin}
}
```

- Ship the complete module in a single file with no external dependencies.

## Required interface

1. `Permissions.can?(role, resource, action, rules)` — returns `true` if the given role is at or above the role required by `rules` for `resource` + `action`, and `false` otherwise. Return `false` for unknown resources or actions rather than raising.
2. `Permissions.can?(role, resource, action, rules, opts)` — same as above but accepts an `opts` keyword list. When `opts` includes `[owner_id: id, user_id: id]` and the resource+action rule is the atom `:owner`, grant access if and only if `owner_id == user_id`, regardless of role. If the rule is `:owner` but no `opts` are provided (or the ids don't match), deny access.

## Acceptance criteria

- Role inheritance holds across the hierarchy: the `:admin` role must be able to do everything that any lower role can do.
- Unknown resources and unknown actions produce `false`, never an exception.
- The `:owner` special-case is composable — a resource action can require `:owner` while other actions on the same resource require normal roles.
- Both public functions are present and behave as specified above.
