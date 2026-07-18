  @doc """
  Starts the state-machine GenServer.

  Accepts a required `:repo` option (an Ecto repo module) and an optional `:name`
  option for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end