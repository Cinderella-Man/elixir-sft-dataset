defp remove_ref_from_topic(state, topic, ref) do
  case Map.get(state.topics, topic) do
    nil ->
      state

    subs ->
      new_subs = without(subs, ref)
      topics = Map.put(state.topics, topic, new_subs)

      # Update monitors map: drop topic from this ref's list; demonitor
      # if no topics remain.
      monitors =
        case Map.fetch(state.monitors, ref) do
          {:ok, {pid, topics_list}} ->
            remaining = List.delete(topics_list, topic)

            if remaining == [] do
              Process.demonitor(ref, [:flush])
              Map.delete(state.monitors, ref)
            else
              Map.put(state.monitors, ref, {pid, remaining})
            end

          :error ->
            state.monitors
        end

      %{state | topics: topics, monitors: monitors}
  end
end
