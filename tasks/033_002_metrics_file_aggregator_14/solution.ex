  defp accumulate(acc, %{timestamp: dt, name: name, value: value, tags: tags}) do
    acc
    |> update_metric_stats(name, value)
    |> update_timestamps(dt)
    |> update_samples_per_hour(dt)
    |> update_unique_tags(tags)
    |> Map.update!(:total, &(&1 + 1))
  end