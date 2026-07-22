  @spec status_for(map(), integer(), map()) :: status()
  defp status_for(buckets, now, state) do
    if count_for(buckets, now, state) >= state.threshold, do: :alarm, else: :ok
  end