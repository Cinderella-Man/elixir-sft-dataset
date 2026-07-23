# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

# `RoleRegistry` — Runtime-Mutable Role Inheritance Graph

## Overview

This specification describes an Elixir GenServer module named `RoleRegistry` that maintains a **mutable, arbitrary role-inheritance graph** with **runtime grant/revoke of permissions**. The structure is not a fixed four-level ladder; it is a directed acyclic graph of roles that can be reshaped while the server is running.

Inheritance carries the following meaning: if `child` inherits `parent`, then `child` has every permission `parent` has, and everything `parent` inherits, transitively. Revoking a grant from `parent` must immediately affect what `child` can do.

The deliverable is the complete module in a single file with no external dependencies.

## API

The module exposes the public functions below. Each one takes the server `pid` or registered name as its first argument.

- `RoleRegistry.start_link(opts \\ [])` — starts the GenServer. Standard `GenServer` options such as `:name` are honored. Initial state has no roles, no inheritance edges, and no grants.
- `RoleRegistry.add_role(server, role)` — registers a role atom. It returns `:ok`, and it is idempotent: adding an existing role is fine.
- `RoleRegistry.add_inheritance(server, child, parent)` — records that `child` inherits `parent`'s permissions, transitively. Both roles must already exist; otherwise the call returns `{:error, :unknown_role}`. On success it returns `:ok`.
- `RoleRegistry.grant(server, role, resource, action)` — grants permission for `{resource, action}` directly to `role`. The role must exist, otherwise `{:error, :unknown_role}`. It returns `:ok` and is idempotent.
- `RoleRegistry.revoke(server, role, resource, action)` — removes a direct `{resource, action}` grant from `role`, affecting only that role's own grant and not inherited ones. It returns `:ok`.
- `RoleRegistry.can?(server, role, resource, action)` — returns `true` if `role`, or **any role it inherits transitively** (directly, or through a chain of inheritance edges), has a direct grant for `{resource, action}`; otherwise it returns `false`.

## Edge cases

- Adding an inheritance edge that would create a cycle — including a self-edge — must be rejected with `{:error, :cycle}`, and state must be left unchanged.
- `RoleRegistry.add_inheritance(server, child, parent)` with either role not yet registered returns `{:error, :unknown_role}`.
- `RoleRegistry.grant(server, role, resource, action)` for a role that does not exist returns `{:error, :unknown_role}`.
- `RoleRegistry.revoke(server, role, resource, action)` returns `:ok` even if the grant was not present.
- `RoleRegistry.can?(server, role, resource, action)` returns `false` for an unknown role.
- Re-adding an already registered role, and re-granting an already granted `{resource, action}` pair, are both no-ops that still return `:ok`.
