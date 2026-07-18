  defp check_budget(%{budget: nil}, _cs, _state), do: :ok

  defp check_budget(%{budget: budget}, cs, state) do
    if budget - dispensed_of(state, cs) <= 0, do: {:error, :budget_exhausted}, else: :ok
  end