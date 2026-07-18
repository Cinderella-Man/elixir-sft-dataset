  defp add_dispensed(state, cs, amount) do
    update_in(state.dispensed[cs], &((&1 || 0) + amount))
  end