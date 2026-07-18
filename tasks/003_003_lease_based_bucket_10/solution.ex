  defp get_bucket(state, bucket_name, capacity, refill_rate, now) do
    case Map.fetch(state.buckets, bucket_name) do
      {:ok, bucket} ->
        # Allow the caller to update refill_rate / capacity mid-stream.
        %{bucket | capacity: capacity, refill_rate: refill_rate}

      :error ->
        # Fresh bucket starts full.
        %{
          free: capacity * 1.0,
          capacity: capacity,
          refill_rate: refill_rate,
          last_update_at: now,
          leases: %{}
        }
    end
  end