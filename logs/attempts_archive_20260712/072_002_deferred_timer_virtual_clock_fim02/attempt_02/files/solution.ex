  @impl GenServer
  def handle_call(:now, _from, state), do: {:reply, state.time, state}

  def handle_call(:pending, _from, state), do: {:reply, length(state.timers), state}

  def handle_call({:schedule, duration, fun}, _from, state) do
    at = apply_duration(state.time, duration)
    ref = state.next_ref
    timer = %{ref: ref, at: at, seq: state.next_seq, fun: fun}

    state = %{
      state
      | timers: [timer | state.timers],
        next_seq: state.next_seq + 1,
        next_ref: ref + 1
    }

    {:reply, ref, state}
  end

  def handle_call({:cancel, ref}, _from, state) do
    {removed, remaining} = Enum.split_with(state.timers, &(&1.ref == ref))
    reply = if removed == [], do: :error, else: :ok
    {:reply, reply, %{state | timers: remaining}}
  end

  def handle_call({:advance, duration}, _from, state) do
    new_time = apply_duration(state.time, duration)

    {due, remaining} =
      Enum.split_with(state.timers, fn t ->
        DateTime.compare(t.at, new_time) in [:lt, :eq]
      end)

    ordered = Enum.sort_by(due, fn t -> {DateTime.to_unix(t.at, :microsecond), t.seq} end)
    Enum.each(ordered, fn t -> t.fun.() end)

    fired = Enum.map(ordered, & &1.ref)
    {:reply, fired, %{state | time: new_time, timers: remaining}}
  end