  @doc """
  Starts the registry server.

  Accepts standard `GenServer` options (e.g. `:name`) and returns
  `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, opts)