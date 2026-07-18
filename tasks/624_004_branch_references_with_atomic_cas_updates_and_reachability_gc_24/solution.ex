  @doc """
  Starts the object store process.

  Accepts an optional `:name` for process registration; all other options are
  passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, :ok, opts)
      name -> GenServer.start_link(__MODULE__, :ok, [{:name, name} | opts])
    end
  end