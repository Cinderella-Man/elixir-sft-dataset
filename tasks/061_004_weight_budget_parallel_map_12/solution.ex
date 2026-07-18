  @doc """
  Starts the meter. Accepts `:name` to register the process; any other options
  are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    GenServer.start_link(__MODULE__, %{current: 0, peak: 0}, [{:name, name} | server_opts])
  end