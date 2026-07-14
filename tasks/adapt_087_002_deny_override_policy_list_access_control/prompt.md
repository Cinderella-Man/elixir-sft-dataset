# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Permissions do
  @moduledoc """
  Role-based access control with hierarchical roles and owner-based overrides.

  ## Role Hierarchy (least → most privileged)

      :viewer < :editor < :manager < :admin

  ## Rules Map Shape

      %{
        resource => %{
          action => required_role | :owner
        }
      }

  ## Owner Override

  When a rule is set to `:owner`, access is granted if and only if the
  `owner_id` and `user_id` supplied in `opts` are equal (and non-nil).
  The caller's role is irrelevant for `:owner`-gated actions.
  """

  # ---------------------------------------------------------------------------
  # Role hierarchy
  # ---------------------------------------------------------------------------

  @role_rank %{viewer: 0, editor: 1, manager: 2, admin: 3}

  @roles Map.keys(@role_rank)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns `true` when `role` satisfies the rule for `{resource, action}` in
  `rules`, `false` otherwise (including unknown resources / actions).

  Equivalent to `can?(role, resource, action, rules, [])`.
  """
  @spec can?(atom(), atom(), atom(), map()) :: boolean()
  def can?(role, resource, action, rules) do
    can?(role, resource, action, rules, [])
  end

  @doc """
  Same as `can?/4` but accepts an `opts` keyword list.

  ## Options

  * `:owner_id` – the ID of whoever owns the resource.
  * `:user_id`  – the ID of the user requesting access.

  When the rule for `{resource, action}` is the atom `:owner`, access is
  granted if and only if `owner_id == user_id` (both must be present and
  equal). The caller's role plays no part in this decision.

  For all other rule values the options are ignored and normal role
  comparison applies.
  """
  @spec can?(atom(), atom(), atom(), map(), keyword()) :: boolean()
  def can?(role, resource, action, rules, opts) do
    with {:ok, action_rules} <- fetch_resource(rules, resource),
         {:ok, rule} <- fetch_action(action_rules, action) do
      check(rule, role, opts)
    else
      :error -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Retrieve the action-rule map for a resource, returning :error when absent.
  defp fetch_resource(rules, resource) do
    case Map.fetch(rules, resource) do
      {:ok, action_rules} when is_map(action_rules) -> {:ok, action_rules}
      _ -> :error
    end
  end

  # Retrieve the rule for a single action, returning :error when absent.
  defp fetch_action(action_rules, action) do
    Map.fetch(action_rules, action)
  end

  # `:owner` rule — identity check only, role is irrelevant.
  defp check(:owner, _role, opts) do
    owner_id = Keyword.get(opts, :owner_id)
    user_id = Keyword.get(opts, :user_id)

    not is_nil(owner_id) and not is_nil(user_id) and owner_id == user_id
  end

  # Normal role rule — compare ranks, ignore opts.
  defp check(required_role, role, _opts)
       when required_role in @roles and role in @roles do
    rank(role) >= rank(required_role)
  end

  # Unknown role or required_role value — deny.
  defp check(_required_role, _role, _opts), do: false

  defp rank(role), do: Map.fetch!(@role_rank, role)
end
```

## New specification

Write me an Elixir module called `AccessPolicy` that evaluates authorization requests against an **ordered-independent list of policy statements** using **explicit-deny precedence** (deny always overrides allow).

Unlike a simple role-hierarchy check, there is no notion of one role being "higher" than another here. Authorization is decided purely by matching policy statements. A policy is a plain list of statement maps of this shape:

```elixir
[
  %{effect: :allow, roles: :any,             resource: :posts,    action: :read},
  %{effect: :allow, roles: [:editor, :admin], resource: :posts,    action: :write},
  %{effect: :deny,  roles: [:editor],         resource: :posts,    action: :delete},
  %{effect: :allow, roles: [:admin],          resource: :any,      action: :any},
  %{effect: :deny,  roles: :any,              resource: :settings, action: :delete}
]
```

Each statement has:

- `:effect` — `:allow` or `:deny` (default to `:allow` if the key is missing).
- `:roles` — a single role atom, a list of role atoms, or the atom `:any` (matches every role). Defaults to `:any` if missing.
- `:resource` — a single resource atom, a list of resource atoms, or `:any`. Defaults to `:any`.
- `:action` — a single action atom, a list of action atoms, or `:any`. Defaults to `:any`.

A statement **matches** a request `(role, resource, action)` when the role matches the statement's `:roles`, the resource matches its `:resource`, and the action matches its `:action` (where `:any` matches everything, and a list matches when the value is a member).

I need the following public API:

- `AccessPolicy.evaluate(role, resource, action, policies)` — returns `:deny` if **any** matching statement has effect `:deny`; otherwise returns `:allow` if **any** matching statement has effect `:allow`; otherwise (nothing matches) returns `:deny` (default deny). Explicit deny must win over allow regardless of statement order in the list.
- `AccessPolicy.authorized?(role, resource, action, policies)` — convenience wrapper returning `true` when `evaluate/4` is `:allow`, else `false`.

Give me the complete module in a single file with no external dependencies.
