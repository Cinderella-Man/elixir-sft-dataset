  # Retrieve the action-rule map for a resource, returning :error when absent.
  defp fetch_resource(rules, resource) do
    case Map.fetch(rules, resource) do
      {:ok, action_rules} when is_map(action_rules) -> {:ok, action_rules}
      _ -> :error
    end
  end