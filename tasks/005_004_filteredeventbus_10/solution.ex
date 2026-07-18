  @impl true
  def handle_call({:subscribe, topic, pid, filter}, _from, state) do
    ref = Process.monitor(pid)
    sub = %{ref: ref, pid: pid, filter: filter}

    subs_for_topic = Map.get(state.topics, topic, []) ++ [sub]

    monitors =
      Map.update(state.monitors, ref, {pid, [topic]}, fn {p, topics} ->
        {p, Enum.uniq([topic | topics])}
      end)

    {:reply, {:ok, ref},
     %{state | topics: Map.put(state.topics, topic, subs_for_topic), monitors: monitors}}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    {:reply, :ok, remove_ref_from_topic(state, topic, ref)}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    subs = Map.get(state.topics, topic, [])

    matched =
      Enum.reduce(subs, 0, fn sub, acc ->
        if eval_filter(sub.filter, event) do
          send(sub.pid, {:event, topic, event})
          acc + 1
        else
          acc
        end
      end)

    {:reply, {:ok, matched}, state}
  end