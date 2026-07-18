  @spec start_link(keyword()) :: GenServer.on_start()
  @doc "Starts the runner. Accepts a `:name` option used for process registration."
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end