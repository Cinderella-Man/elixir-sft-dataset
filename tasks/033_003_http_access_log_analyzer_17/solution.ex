  defp update_path(acc, path) do
    Map.update!(acc, :path_counts, fn m -> Map.update(m, path, 1, &(&1 + 1)) end)
  end