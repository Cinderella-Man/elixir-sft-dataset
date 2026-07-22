  defp collect_one(%{running: running} = state) do
    receive do
      {ref, result} when is_map_key(running, ref) ->
        {mon, idx, w} = Map.fetch!(running, ref)
        Process.demonitor(mon, [:flush])

        outcome =
          case result do
            {:ok, value} -> value
            {:error, reason} -> {:error, reason}
          end

        %{
          state
          | running: Map.delete(running, ref),
            weight: state.weight - w,
            results: Map.put(state.results, idx, outcome)
        }

      {:DOWN, mon, :process, _pid, reason} ->
        case Enum.find(running, fn {_ref, {m, _idx, _w}} -> m == mon end) do
          {ref, {_mon, idx, w}} ->
            %{
              state
              | running: Map.delete(running, ref),
                weight: state.weight - w,
                results: Map.put(state.results, idx, {:error, reason})
            }

          nil ->
            collect_one(state)
        end

      _other ->
        collect_one(state)
    end
  end