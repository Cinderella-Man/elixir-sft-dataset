defp should_trip?(outcomes, config) do
  total = length(outcomes)

  cond do
    total == 0 -> false
    total < config.min_calls_in_window -> false
    true ->
      errors = Enum.count(outcomes, &(&1 == :error))
      errors / total >= config.error_rate_threshold
  end
end
