  # Replays historical values oldest-first to build up the raw_buffer
  # incrementally, keeping the last buffer_size derived values.
  defp bootstrap_raw_buffer(values_newest_first, period, buffer_size) do
    wma1_period = div(period, 2)
    wma2_period = period

    # Rebuild prefixes: for each suffix (oldest→newest), compute raw over the
    # values available *up to that point*.  values[k..end] in newest-first is
    # the "history up to value at index k" where index 0 is the newest.
    total = length(values_newest_first)

    # For each position i (0 = newest), the "history-so-far" is values[i..]
    # (newest-first), which corresponds to all values up to and including the
    # i-th-from-newest value.  Walk from oldest-position (total-1) down to 0
    # so we emit raw values in chronological order.
    raws_oldest_first =
      for i <- (total - 1)..0//-1 do
        window = Enum.drop(values_newest_first, i)
        wma1 = compute_wma(window, wma1_period)
        wma2 = compute_wma(window, wma2_period)
        2 * wma1 - wma2
      end

    # Convert to newest-first and take the last `buffer_size` raws.
    raws_oldest_first
    |> Enum.reverse()
    |> Enum.take(buffer_size)
  end