  defp accumulate(acc, %{timestamp: dt, level: level, message: message}) do
    acc
    |> update_counts(level)
    |> update_timestamps(dt)
    |> maybe_update_errors(level, message, dt)
    |> Map.update!(:total, &(&1 + 1))
  end