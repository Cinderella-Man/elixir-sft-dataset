@impl true
def handle_cast({:push, event}, state) do
  state = add_event(state, event)

  state =
    if state.count >= state.batch_size do
      flush(state)
    else
      state
    end

  {:noreply, state}
end