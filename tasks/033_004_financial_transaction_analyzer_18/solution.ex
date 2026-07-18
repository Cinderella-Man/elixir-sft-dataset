  defp update_daily_volume(acc, dt, amount) do
    day = day_bucket(dt)

    Map.update!(acc, :daily_volume, fn dv ->
      Map.update(dv, day, amount, &(&1 + amount))
    end)
  end