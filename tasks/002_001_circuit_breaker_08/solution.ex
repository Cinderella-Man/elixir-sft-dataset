  @doc "Returns the current state: `:closed`, `:open`, or `:half_open`."
  @spec state(name()) :: :closed | :open | :half_open
  def state(name) do
    GenServer.call(name, :state)
  end