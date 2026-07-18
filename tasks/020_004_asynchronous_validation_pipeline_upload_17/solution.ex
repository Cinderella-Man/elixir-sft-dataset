  @doc """
  Starts the store `GenServer`. Accepts a `:name` option used to register the
  process. Returns the standard `GenServer.on_start/0` result.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end