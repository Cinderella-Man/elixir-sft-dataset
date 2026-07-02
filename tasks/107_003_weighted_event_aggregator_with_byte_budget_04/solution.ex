@impl true
def handle_info({:flush, ref}, %{timer_ref: ref} = state) do
  state =
    if state.buffer == [] do
      clear_timer(state)
    else
      flush(state)
    end

  {:noreply, state}
end

def handle_info({:flush, _stale_ref}, state) do
  {:noreply, state}
end

def handle_info(_msg, state) do
  {:noreply, state}
end