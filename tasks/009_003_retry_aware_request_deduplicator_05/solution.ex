  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, %{}, server_opts)
  end