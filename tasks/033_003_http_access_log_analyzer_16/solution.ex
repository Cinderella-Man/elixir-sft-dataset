  defp update_status(acc, status_code) do
    Map.update!(acc, :by_status, fn m -> Map.update(m, status_code, 1, &(&1 + 1)) end)
  end