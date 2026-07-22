  def permitted?(principal, resource, action, role_defs) do
    target = "#{resource}:#{action}"
    target_segments = String.split(target, ":")

    principal
    |> effective_permissions(role_defs)
    |> Enum.any?(fn pattern -> pattern_match?(pattern, target_segments) end)
  end