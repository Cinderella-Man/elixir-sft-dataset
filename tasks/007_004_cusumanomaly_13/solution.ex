  defp validate!(threshold, slack, warmup, epsilon) do
    if threshold <= 0.0, do: raise(ArgumentError, ":threshold must be positive")
    if slack < 0.0, do: raise(ArgumentError, ":slack must be non-negative")

    unless is_integer(warmup) and warmup > 0,
      do: raise(ArgumentError, ":warmup_samples must be a positive integer")

    if epsilon <= 0.0, do: raise(ArgumentError, ":epsilon must be positive")
  end