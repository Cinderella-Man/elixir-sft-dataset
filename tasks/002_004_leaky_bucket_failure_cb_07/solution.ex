  @spec state(GenServer.server()) :: :closed | :open | :half_open
  def state(name), do: GenServer.call(name, :get_state)