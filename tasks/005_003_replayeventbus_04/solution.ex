  defp remove_ref_from_topic(state, topic, ref) do
    case Map.get(state.topics, topic) do
      nil ->
        state

      t ->
        new_subs = Enum.reject(t.subs, &(&1.ref == ref))
        topics = Map.put(state.topics, topic, %{t | subs: new_subs})

        # Each ref guards exactly one topic (see subscribe), so removing the
        # subscription always retires the whole monitor.
        monitors =
          if Map.has_key?(state.monitors, ref) do
            Process.demonitor(ref, [:flush])
            Map.delete(state.monitors, ref)
          else
            state.monitors
          end

        %{state | topics: topics, monitors: monitors}
    end
  end