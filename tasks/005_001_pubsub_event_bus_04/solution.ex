defp drop_subscription_entry(state, topic, ref) do
  refs = Map.delete(state.refs, ref)

  topics =
    case Map.fetch(state.topics, topic) do
      {:ok, subs} ->
        new_subs = Map.delete(subs, ref)

        if map_size(new_subs) == 0 do
          Map.delete(state.topics, topic)
        else
          Map.put(state.topics, topic, new_subs)
        end

      :error ->
        state.topics
    end

  %{state | topics: topics, refs: refs}
end
