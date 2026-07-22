  @spec count_for(map(), integer(), map()) :: non_neg_integer()
  defp count_for(buckets, now, state) do
    cutoff = now - state.window_ms

    Enum.reduce(buckets, 0, fn {bucket, count}, acc ->
      if bucket * state.bucket_ms >= cutoff, do: acc + count, else: acc
    end)
  end