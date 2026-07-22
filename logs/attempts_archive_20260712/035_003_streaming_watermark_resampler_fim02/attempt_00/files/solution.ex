  @impl true
  def handle_call({:push, ts, value}, _from, state) do
    state = ensure_started(state, ts)
    state = %{state | watermark: bump(state.watermark, ts)}
    bucket = floor_bucket(ts, state.interval)

    state =
      if bucket < state.next_emit do
        %{state | late_dropped: state.late_dropped + 1}
      else
        open = Map.update(state.open, bucket, [{ts, value}], &[{ts, value} | &1])
        %{state | open: open}
      end

    {:reply, :ok, finalize(state)}
  end

  def handle_call(:finalized, _from, state) do
    {:reply, Enum.reverse(state.emitted), state}
  end

  def handle_call(:flush, _from, state) do
    state = flush_all(state)
    {:reply, Enum.reverse(state.emitted), state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      late_dropped: state.late_dropped,
      watermark: state.watermark,
      open_buckets: map_size(state.open)
    }

    {:reply, stats, state}
  end