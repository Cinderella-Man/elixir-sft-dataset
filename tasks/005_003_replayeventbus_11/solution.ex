  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topic}, monitors} ->
        new_topics =
          case Map.get(state.topics, topic) do
            nil ->
              state.topics

            t ->
              Map.put(state.topics, topic, %{t | subs: Enum.reject(t.subs, &(&1.ref == ref))})
          end

        {:noreply, %{state | topics: new_topics, monitors: monitors}}
    end
  end