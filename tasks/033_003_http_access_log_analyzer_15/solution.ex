  defp update_method(acc, method) do
    Map.update!(acc, :by_method, fn m -> Map.update(m, method, 1, &(&1 + 1)) end)
  end