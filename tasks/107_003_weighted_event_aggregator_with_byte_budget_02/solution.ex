  @impl true
  def handle_cast({:push, event}, state) do
    weight = state.size_fn.(event)

    state =
      %{state | buffer: [event | state.buffer], weight: state.weight + weight}
      |> ensure_timer()

    state =
      if state.weight >= state.max_bytes do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end