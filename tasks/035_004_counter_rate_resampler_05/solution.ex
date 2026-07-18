  defp do_resample([], _interval_ms, _mode, _reset, _fill), do: []

  defp do_resample(data, interval_ms, mode, reset, fill) do
    sorted = Enum.sort_by(data, &elem(&1, 0))

    {min_ts, _} = hd(sorted)
    {max_ts, _} = List.last(sorted)

    first_bucket = floor_bucket(min_ts, interval_ms)
    last_bucket = floor_bucket(max_ts, interval_ms)

    increments =
      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(%{}, fn [{_t0, v0}, {t1, v1}], acc ->
        inc = increment(v0, v1, reset)
        bucket = floor_bucket(t1, interval_ms)
        Map.update(acc, bucket, inc, &(&1 + inc))
      end)

    first_bucket
    |> Stream.iterate(&(&1 + interval_ms))
    |> Stream.take_while(&(&1 <= last_bucket))
    |> Enum.map(fn bucket_start ->
      value =
        case Map.fetch(increments, bucket_start) do
          {:ok, inc} -> project(inc, mode, interval_ms)
          :error -> empty_value(mode, interval_ms, fill)
        end

      {bucket_start, value}
    end)
  end