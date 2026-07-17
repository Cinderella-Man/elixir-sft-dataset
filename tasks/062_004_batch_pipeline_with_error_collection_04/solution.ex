  defp bump(stats, position, duration) do
    Map.update(stats, position, {1, duration}, fn {count, total} ->
      {count + 1, total + duration}
    end)
  end