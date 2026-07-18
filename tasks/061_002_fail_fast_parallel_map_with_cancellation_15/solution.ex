  @doc """
  Starts the counter process.

  Accepts a `:name` option; any other options are forwarded to
  `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    init_state = %{count: 0, peak: 0, started: 0}
    GenServer.start_link(__MODULE__, init_state, [{:name, name} | server_opts])
  end