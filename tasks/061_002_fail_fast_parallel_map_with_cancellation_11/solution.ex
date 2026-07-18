  @impl true
  def handle_call(:increment, _from, %{count: count, peak: peak, started: started} = state) do
    new_count = count + 1
    new_state = %{state | count: new_count, peak: max(new_count, peak), started: started + 1}
    {:reply, new_count, new_state}
  end

  def handle_call(:decrement, _from, %{count: count} = state) do
    new_count = count - 1
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state), do: {:reply, peak, state}
  def handle_call(:started, _from, %{started: started} = state), do: {:reply, started, state}