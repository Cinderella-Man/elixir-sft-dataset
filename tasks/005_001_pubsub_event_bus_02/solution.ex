defp topic_matches?(pattern, topic) do
  p_parts = String.split(pattern, ".")
  t_parts = String.split(topic, ".")

  length(p_parts) == length(t_parts) and
    segments_match?(p_parts, t_parts)
end
