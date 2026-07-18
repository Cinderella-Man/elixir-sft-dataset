  @impl GenServer
  def handle_call({:monotonic, unit}, _from, micros) do
    {:reply, convert(micros, unit), micros}
  end

  def handle_call({:advance, duration}, _from, micros) do
    {:reply, :ok, micros + duration_to_micros(duration)}
  end