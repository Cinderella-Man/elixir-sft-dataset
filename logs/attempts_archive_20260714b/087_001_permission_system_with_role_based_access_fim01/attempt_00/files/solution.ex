  def can?(role, resource, action, rules, opts) do
    with {:ok, action_rules} <- fetch_resource(rules, resource),
         {:ok, rule} <- fetch_action(action_rules, action) do
      check(rule, role, opts)
    else
      :error -> false
    end
  end