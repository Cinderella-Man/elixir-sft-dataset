  @doc """
  Starts the server with an empty graph.

  `opts` are forwarded to `GenServer.start_link/3` (e.g. `:name`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end