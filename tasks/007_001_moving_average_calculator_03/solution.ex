defp push_value(stream, value) when is_number(value) do
  value = value * 1.0

  updated_emas =
    Map.new(stream.ema, fn {period, prev_ema} ->
      {period, ema_step(prev_ema, value, period)}
    end)

  %{
    stream
    | values: [value | stream.values],
      total_count: stream.total_count + 1,
      ema: updated_emas
  }
end