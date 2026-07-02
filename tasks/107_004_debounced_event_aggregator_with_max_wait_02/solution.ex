@impl true
def handle_cast({:push, event}, state) do
  # A push into an empty buffer begins a new batch and arms the max-wait cap.
  state = if state.count == 0, do: start_batch(state), else: state

  state = %{state | buffer: [event | state.buffer], count: state.count + 1}

  # The idle timer is (re)armed on every push — this is the debounce.
  state = reset_idle(state)

  state =
    if size_reached?(state) do
      flush(state)
    else
      state
    end

  {:noreply, state}
end