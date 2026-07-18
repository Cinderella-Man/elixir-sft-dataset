  @spec series_key(String.t(), labels()) :: {String.t(), [{term(), term()}]}
  defp series_key(metric, labels), do: {metric, Enum.sort(Map.to_list(labels))}