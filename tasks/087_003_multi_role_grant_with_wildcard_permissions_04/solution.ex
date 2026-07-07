def effective_permissions(principal, role_defs) do
  %{roles: roles, grants: grants} = normalize(principal)

  from_roles = Enum.flat_map(roles, fn role -> Map.get(role_defs, role, []) end)

  MapSet.new(from_roles ++ grants)
end