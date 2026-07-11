  @impl true
  def handle_call({:increment, key}, _from, state) do
    now = state.clock.()
    bucket = bucket_for(now, state.bucket_ms)

    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, 1, &(&1 + 1))

    {:reply, :ok, put_in(state, [:keys, key], buckets)}
  end

  @impl true
  def handle_call({:count, key, window_ms}, _from, state) do
    now = state.clock.()

    # Derive the smallest bucket index whose *start* falls within [now-window_ms, now].
    #
    # Bucket b starts at b * bucket_ms.  We want to include bucket b iff:
    #
    #   b * bucket_ms  >=  now - window_ms
    #   b              >=  (now - window_ms) / bucket_ms   [ceiling]
    #
    # Ceiling integer division (works for negative values too):
    #   ceil(a / b)  =  -floor_div(-a, b)
    #
    # This is stricter than an overlap test: a bucket that merely *overlaps*
    # the window boundary (its end > window_start) would be included by floor,
    # but the tests require that we only count buckets whose start time is
    # already within the window — keeping the semantics consistent with
    # "an event at time T is in the window iff T >= now - window_ms".
    min_bucket = -Integer.floor_div(-(now - window_ms), state.bucket_ms)

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {b, cnt}, acc ->
        if b >= min_bucket, do: acc + cnt, else: acc
      end)

    {:reply, total, state}
  end