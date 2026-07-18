  defp update_samples_per_hour(acc, dt) do
    bucket = hour_bucket(dt)

    Map.update!(acc, :samples_per_hour, fn sph ->
      Map.update(sph, bucket, 1, &(&1 + 1))
    end)
  end