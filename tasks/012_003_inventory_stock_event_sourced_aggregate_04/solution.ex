@impl true
def handle_call({:execute, id, command}, _from, store) do
  current_instance = Map.get(store, id, %{state: nil, events: []})

  case validate_command(current_instance.state, command) do
    {:ok, new_events} ->
      updated_state = Enum.reduce(new_events, current_instance.state, &apply_event/2)

      updated_instance = %{
        state: updated_state,
        events: current_instance.events ++ new_events
      }

      {:reply, {:ok, new_events}, Map.put(store, id, updated_instance)}

    {:error, reason} ->
      {:reply, {:error, reason}, store}
  end
end