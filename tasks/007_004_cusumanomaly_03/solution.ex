  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream = stream_for(state, name)
    value = value * 1.0

    cond do
      # Stream was alerted and is frozen until explicit reset.
      Map.get(stream, :alerted, false) ->
        {:reply, :warming_up, state}

      # Still warming up — update Welford only, no CUSUM yet.
      stream.samples < state.warmup_samples ->
        new_stream = welford_update(stream, value)
        {:reply, :warming_up, put_stream(state, name, new_stream)}

      # CUSUM-active but stddev is below the slack tolerance — z-scores
      # against such a tiny stddev are meaningless and cause false alerts.
      welford_stddev(stream) < state.slack ->
        post_welford = welford_update(stream, value)
        {:reply, :ok, put_stream(state, name, post_welford)}

      true ->
        # Z-score against the prior mean/stddev.
        prior_mean = stream.mean
        prior_std = max(welford_stddev(stream), state.epsilon)
        z = (value - prior_mean) / prior_std

        new_s_high = max(0.0, stream.s_high + z - state.slack)
        new_s_low = max(0.0, stream.s_low - z - state.slack)

        # Always update Welford AFTER z-scoring.
        post_welford = welford_update(stream, value)

        updated = %{post_welford | s_high: new_s_high, s_low: new_s_low}

        cond do
          new_s_high >= state.threshold ->
            {:reply, {:alert, :upward_shift}, put_stream(state, name, alerted_stream())}

          new_s_low >= state.threshold ->
            {:reply, {:alert, :downward_shift}, put_stream(state, name, alerted_stream())}

          true ->
            {:reply, :ok, put_stream(state, name, updated)}
        end
    end
  end

  def handle_call({:check, name}, _from, state) do
    case Map.fetch(state.streams, name) do
      :error ->
        {:reply, {:error, :no_data}, state}

      {:ok, stream} ->
        status = if stream.samples < state.warmup_samples, do: :warming_up, else: :normal

        info = %{
          mean: stream.mean,
          stddev: welford_stddev(stream),
          s_high: stream.s_high,
          s_low: stream.s_low,
          samples: stream.samples,
          status: status
        }

        {:reply, {:ok, info}, state}
    end
  end

  def handle_call({:reset, name}, _from, state) do
    new_streams =
      case Map.fetch(state.streams, name) do
        {:ok, _} -> Map.put(state.streams, name, reset_stream())
        :error -> state.streams
      end

    {:reply, :ok, %{state | streams: new_streams}}
  end