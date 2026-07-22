  defp admit(%{queue: []} = state), do: state

  defp admit(%{queue: [{elem, idx, w} | rest]} = state) do
    %{running: running, weight: weight, budget: budget} = state

    cond do
      weight + w <= budget ->
        {ref, entry} = spawn_task(state.parent, state.func, elem, idx, w)
        admit(%{state | queue: rest, running: Map.put(running, ref, entry), weight: weight + w})

      weight == 0 and w > budget ->
        {ref, entry} = spawn_task(state.parent, state.func, elem, idx, w)
        admit(%{state | queue: rest, running: Map.put(running, ref, entry), weight: weight + w})

      true ->
        state
    end
  end