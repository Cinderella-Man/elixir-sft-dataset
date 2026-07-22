defmodule Rbac do
  @moduledoc """
  Multi-role RBAC with wildcard `"resource:action"` permission patterns.

  A principal may hold several roles simultaneously; its effective permission
  set is the union of every held role's patterns plus any direct grants.
  Authorization matches a `"resource:action"` target against each pattern
  segment-by-segment, where the literal `"*"` matches any value in that
  position.

  ## Role definitions

      %{role_atom => ["resource:action", "resource:*", "*:action", "*:*"]}

  ## Principal

    * a list of role atoms — `[:viewer, :editor]`, or
    * a map — `%{roles: [atom], grants: [String.t()]}` (missing keys default
      to `[]`).
  """

  @type principal :: [atom()] | %{optional(:roles) => [atom()], optional(:grants) => [String.t()]}
  @type role_defs :: %{optional(atom()) => [String.t()]}

  @doc """
  Returns the `MapSet` of effective permission patterns for `principal`.

  Unknown roles contribute no permissions.
  """
  @spec effective_permissions(principal(), role_defs()) :: MapSet.t()
  def effective_permissions(principal, role_defs) do
    %{roles: roles, grants: grants} = normalize(principal)

    from_roles = Enum.flat_map(roles, fn role -> Map.get(role_defs, role, []) end)

    MapSet.new(from_roles ++ grants)
  end

  @doc """
  Returns `true` when any effective pattern matches `"resource:action"`.
  """
  @spec permitted?(principal(), atom(), atom(), role_defs()) :: boolean()
  def permitted?(principal, resource, action, role_defs) do
    target = "#{resource}:#{action}"
    target_segments = String.split(target, ":")

    principal
    |> effective_permissions(role_defs)
    |> Enum.any?(fn pattern -> pattern_match?(pattern, target_segments) end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp normalize(principal) when is_list(principal), do: %{roles: principal, grants: []}

  defp normalize(principal) when is_map(principal) do
    %{roles: Map.get(principal, :roles, []), grants: Map.get(principal, :grants, [])}
  end

  defp pattern_match?(pattern, target_segments) do
    segments_match?(String.split(pattern, ":"), target_segments)
  end

  defp segments_match?([p | ps], [t | ts]) do
    (p == "*" or p == t) and segments_match?(ps, ts)
  end

  defp segments_match?([], []), do: true
  defp segments_match?(_, _), do: false
end