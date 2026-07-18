  defp update_counts(acc, level) do
    Map.update!(acc, :counts_by_level, fn counts ->
      Map.update(counts, level, 1, &(&1 + 1))
    end)
  end