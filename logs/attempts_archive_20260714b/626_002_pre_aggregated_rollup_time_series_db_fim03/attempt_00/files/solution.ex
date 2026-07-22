  defp drop_expired_buckets(buckets, cutoff, bucket_duration_ms) do
    buckets
    |> Enum.reject(fn {bucket_start, _acc} ->
      bucket_start + bucket_duration_ms <= cutoff
    end)
    |> Map.new()
  end