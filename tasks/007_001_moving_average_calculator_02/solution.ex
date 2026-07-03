  defp compute(stream, :sma, period) do
    {grew, stream} = maybe_grow_max_period(stream, period)
    stream         = if grew, do: stream, else: trim_values(stream)

    window = Enum.take(stream.values, period)
    sma    = Enum.sum(window) / length(window)
    {sma, stream}
  end

  defp compute(stream, :ema, period) do
    case Map.get(stream.ema, period) do
      nil ->
        # Bootstrap from the full buffer BEFORE any trim (oldest-first).
        ema_val =
          stream.values
          |> Enum.reverse()
          |> bootstrap_ema(period)

        {grew, stream} = maybe_grow_max_period(stream, period)
        stream         = if grew, do: stream, else: trim_values(stream)
        stream         = %{stream | ema: Map.put(stream.ema, period, ema_val)}
        {ema_val, stream}

      ema_val ->
        # Accumulator already current from incremental push_value updates.
        {grew, stream} = maybe_grow_max_period(stream, period)
        stream         = if grew, do: stream, else: trim_values(stream)
        {ema_val, stream}
    end
  end