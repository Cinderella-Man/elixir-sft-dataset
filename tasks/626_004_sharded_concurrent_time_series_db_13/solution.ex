  defp series_key(metric, labels) do
    {metric, Enum.sort(Map.to_list(labels))}
  end