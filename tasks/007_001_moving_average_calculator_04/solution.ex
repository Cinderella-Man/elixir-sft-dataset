# Expects values in oldest-first order.
defp bootstrap_ema([], _period), do: 0.0

defp bootstrap_ema([seed | rest], period) do
  Enum.reduce(rest, seed * 1.0, fn value, prev ->
    ema_step(prev, value, period)
  end)
end