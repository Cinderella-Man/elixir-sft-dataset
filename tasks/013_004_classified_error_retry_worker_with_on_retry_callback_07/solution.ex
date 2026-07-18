  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    do_execute(func, 0, opts, from, state)
    {:noreply, state}
  end