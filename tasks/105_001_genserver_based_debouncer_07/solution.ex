  @doc """
  Starts the debouncer process.

  Accepts a `:name` option for process registration, defaulting to `Debouncer`
  (the module name) when not provided.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end