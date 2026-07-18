  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.mons, ref) do
      {nil, _mons} ->
        {:noreply, state}

      {{user_id, pid}, mons} ->
        subs = Map.update(state.subs, user_id, [], fn pids -> List.delete(pids, pid) end)
        {:noreply, %{state | subs: subs, mons: mons}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}