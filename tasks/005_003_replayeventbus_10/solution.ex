  @impl true
  def handle_call({:subscribe, topic, pid, sub_opts}, _from, state) do
    now = state.clock.()
    replay = Keyword.get(sub_opts, :replay, :none)

    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> evict_expired(now, state.history_ttl_ms)

    # Send replay events BEFORE registering, preserving oldest→newest order.
    replay_events(topic_state.history, replay, pid, topic)

    monitor_ref = Process.monitor(pid)

    new_topic_state = %{
      topic_state
      | subs: topic_state.subs ++ [%{ref: monitor_ref, pid: pid}]
    }

    monitors =
      Map.update(state.monitors, monitor_ref, {pid, [topic]}, fn {p, topics} ->
        {p, Enum.uniq([topic | topics])}
      end)

    new_state = %{
      state
      | topics: Map.put(state.topics, topic, new_topic_state),
        monitors: monitors
    }

    {:reply, {:ok, monitor_ref}, new_state}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    new_state = remove_ref_from_topic(state, topic, ref)
    {:reply, :ok, new_state}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    now = state.clock.()

    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> evict_expired(now, state.history_ttl_ms)

    # Deliver live to all current subscribers
    Enum.each(topic_state.subs, fn %{pid: pid} ->
      send(pid, {:event, topic, event})
    end)

    # Append to history, enforce count bound
    new_history =
      (topic_state.history ++ [{now, event}])
      |> Enum.take(-topic_state.history_size)

    new_topic_state = %{topic_state | history: new_history}

    {:reply, :ok, %{state | topics: Map.put(state.topics, topic, new_topic_state)}}
  end

  def handle_call({:history, topic}, _from, state) do
    now = state.clock.()

    case Map.get(state.topics, topic) do
      nil ->
        {:reply, [], state}

      t ->
        fresh = evict_expired(t, now, state.history_ttl_ms)
        events = Enum.map(fresh.history, fn {_ts, evt} -> evt end)
        {:reply, events, %{state | topics: Map.put(state.topics, topic, fresh)}}
    end
  end

  def handle_call({:set_history_size, topic, size}, _from, state) do
    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> Map.put(:history_size, size)

    # Trim existing history to new size.
    trimmed = Enum.take(topic_state.history, -size)
    new_topic_state = %{topic_state | history: trimmed}

    {:reply, :ok, %{state | topics: Map.put(state.topics, topic, new_topic_state)}}
  end