  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topics}, monitors} ->
        # For a DOWN, remove this ref from every topic it was subscribed to.
        topics_map =
          Enum.reduce(topics, state.topics, fn topic, acc ->
            case Map.get(acc, topic) do
              nil -> acc
              subs -> Map.put(acc, topic, without(subs, ref))
            end
          end)

        {:noreply, %{state | topics: topics_map, monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}