  @spec series_key(metric_name(), labels()) :: {metric_name(), [{String.t(), String.t()}]}
  defp series_key(metric_name, labels) do
    {metric_name, Enum.sort(Map.to_list(labels))}
  end