  def resample(data, interval_ms, opts)
      when is_list(data) and is_integer(interval_ms) and interval_ms > 0 do
    agg  = fetch_opt!(opts, :agg,  :last,  @valid_agg)
    fill = fetch_opt!(opts, :fill, :nil,   @valid_fill)

    # 1. Sort ascending by timestamp so :first/:last are well-defined.
    sorted = Enum.sort_by(data, &elem(&1, 0))

    # 2. Determine the bucket grid.
    {min_ts, _} = hd(sorted)
    {max_ts, _} = List.last(sorted)

    first_bucket = floor_bucket(min_ts, interval_ms)
    last_bucket  = floor_bucket(max_ts, interval_ms)

    # 3. Group data points into their buckets.
    grouped =
      Enum.group_by(sorted, fn {ts, _v} -> floor_bucket(ts, interval_ms) end)

    # 4. Walk every bucket in order, aggregate, then fill gaps.
    first_bucket
    |> Stream.iterate(&(&1 + interval_ms))
    |> Stream.take_while(&(&1 <= last_bucket))
    |> Enum.map_reduce(nil, fn bucket_start, last_value ->
      agg_value =
        case Map.fetch(grouped, bucket_start) do
          {:ok, points} -> aggregate(points, agg)
          :error        -> nil
        end

      filled_value =
        case {agg_value, fill} do
          {nil, :forward} -> last_value          # carry forward (may still be nil)
          {nil, :nil}     -> nil
          {v,   _}        -> v
        end

      next_last = if agg_value != nil, do: agg_value, else: last_value

      {{bucket_start, filled_value}, next_last}
    end)
    |> elem(0)
  end