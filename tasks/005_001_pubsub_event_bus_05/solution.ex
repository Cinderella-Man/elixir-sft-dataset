defp clean_pid_refs(state, pid, ref) do
  case Map.fetch(state.pids, pid) do
    {:ok, set} ->
      new_set = MapSet.delete(set, ref)

      if MapSet.size(new_set) == 0 do
        %{state | pids: Map.delete(state.pids, pid)}
      else
        %{state | pids: Map.put(state.pids, pid, new_set)}
      end

    :error ->
      state
  end
end
