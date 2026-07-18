  @spec state(GenServer.server()) :: :closed | :open | :half_open | :recovering
  def state(name), do: GenServer.call(name, :get_state)