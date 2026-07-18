  @doc """
  Start the object store process.

  Accepts a `:name` option used to register the process; any other options
  are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, server_opts)
  end