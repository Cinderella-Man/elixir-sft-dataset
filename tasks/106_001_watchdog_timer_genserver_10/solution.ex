  @doc """
  Starts the `Watchdog` server.

  Accepts a `:name` option for process registration. If not provided the server
  registers itself under `#{inspect(__MODULE__)}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end