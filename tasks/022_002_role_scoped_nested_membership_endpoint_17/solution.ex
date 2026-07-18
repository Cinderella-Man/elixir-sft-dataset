  @doc """
  Starts a `TeamStore` process.

  Accepts a `:name` option which, when present, registers the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end