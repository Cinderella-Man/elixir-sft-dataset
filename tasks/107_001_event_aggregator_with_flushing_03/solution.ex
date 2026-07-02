@impl true
def handle_cast({:push, event}, state) do
  state =
    state
    |> add_event(event)
    |> ensure_timer()

  state =
    if state.count >= state.batch_size do
      flush(state)
    else
      state
    end

  {:noreply, state}
end