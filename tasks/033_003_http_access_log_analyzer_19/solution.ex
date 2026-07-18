  defp update_requests_per_minute(acc, dt) do
    bucket = minute_bucket(dt)

    Map.update!(acc, :requests_per_minute, fn rpm ->
      Map.update(rpm, bucket, 1, &(&1 + 1))
    end)
  end