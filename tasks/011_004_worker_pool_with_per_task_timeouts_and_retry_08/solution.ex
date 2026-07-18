  @spec status(GenServer.server()) :: map()
  def status(pool) do
    GenServer.call(pool, :status)
  end