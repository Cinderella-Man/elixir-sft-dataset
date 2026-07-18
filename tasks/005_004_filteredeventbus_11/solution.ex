  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topics}, monitors} ->
        new_topics =
          Enum.reduce(topics, state.topics, fn topic, acc ->
            case Map.get(acc, topic) do
              nil -> acc
              subs -> Map.put(acc, topic, Enum.reject(subs, &(&1.ref == ref)))
            end
          end)

        {:noreply, %{state | topics: new_topics, monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}