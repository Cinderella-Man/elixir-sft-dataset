  defp pattern_match?(pattern, target_segments) do
    segments_match?(String.split(pattern, ":"), target_segments)
  end