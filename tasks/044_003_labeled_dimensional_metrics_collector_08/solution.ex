  # Canonicalise labels to a sorted list so key/value order is irrelevant.
  defp key(name, labels), do: {name, Enum.sort(labels)}