@impl true
def handle_call({:subscribe, topic, pid, priority}, _from, state) do
  ref = Process.monitor(pid)
  seq = state.next_seq

  sub = %{ref: ref, pid: pid, priority: priority, seq: seq}

  new_subs_for_topic = insert_sorted([sub | Map.get(state.topics, topic, []) |> without(ref)], sub)

  monitors = Map.update(state.monitors, ref, {pid, [topic]}, fn {p, topics} ->
    {p, Enum.uniq([topic | topics])}
  end)

  new_state = %{
    state
    | topics: Map.put(state.topics, topic, new_subs_for_topic),
      monitors: monitors,
      next_seq: seq + 1
  }

  {:reply, {:ok, ref}, new_state}
end
