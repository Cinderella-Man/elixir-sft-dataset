  @doc """
  Starts the cache GenServer.

  Accepts the standard GenServer options, notably `:name` for process
  registration. The started process owns the lifecycle of every ETS table it
  creates.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end