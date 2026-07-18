  # Called only when length(stream.values) >= period.
  defp compute_hma(stream, period) do
    buffer_size = round(:math.sqrt(period))

    {hma_state, stream} =
      case Map.get(stream.hma, period) do
        nil ->
          # Bootstrap from full available history.
          buffer = bootstrap_raw_buffer(stream.values, period, buffer_size)
          hma_state = %{raw_buffer: buffer}

          # Grow max_period to cover period (and period/2).
          stream =
            stream
            |> maybe_grow_max_period(period)
            |> put_hma(period, hma_state)

          {hma_state, stream}

        existing ->
          stream = maybe_grow_max_period(stream, period)
          {existing, stream}
      end

    # Final WMA of the raw_buffer with window = round(sqrt(period))
    hma_value = compute_wma(hma_state.raw_buffer, buffer_size)

    # Only trim after HMA accumulator is set up — trimming before bootstrap
    # would lose history the bootstrap needed.
    stream = trim_values(stream)

    {hma_value, stream}
  end