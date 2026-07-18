  @doc """
  Starts the `Dedup` GenServer.

  Accepts all standard `GenServer.start_link/3` options, notably `:name`
  for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end