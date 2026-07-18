  @impl true
  def handle_call({:add, weight}, _from, %{current: current, peak: peak} = state) do
    new_current = current + weight
    {:reply, new_current, %{state | current: new_current, peak: max(new_current, peak)}}
  end

  def handle_call({:sub, weight}, _from, %{current: current} = state) do
    new_current = current - weight
    {:reply, new_current, %{state | current: new_current}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state), do: {:reply, peak, state}