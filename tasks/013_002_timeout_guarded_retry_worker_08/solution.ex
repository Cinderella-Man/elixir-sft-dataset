  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    # Attempt 0 launches from handle_info exactly like every retry — the
    # contract pins "spawned from within the GenServer's handle_info".
    send(self(), {:retry, func, 0, opts, from})
    {:noreply, state}
  end