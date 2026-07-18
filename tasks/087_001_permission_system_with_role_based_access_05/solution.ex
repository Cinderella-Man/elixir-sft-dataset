  # Retrieve the rule for a single action, returning :error when absent.
  defp fetch_action(action_rules, action) do
    Map.fetch(action_rules, action)
  end