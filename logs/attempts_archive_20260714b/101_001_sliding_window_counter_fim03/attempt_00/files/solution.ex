defp bucket_for(timestamp_ms, bucket_ms) do
  Integer.floor_div(timestamp_ms, bucket_ms)
end