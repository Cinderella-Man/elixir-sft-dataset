  defp bump(stats, name, duration) do
    Map.update(stats, name, {1, duration}, fn {count, total} ->
      {count + 1, total + duration}
    end)
  end