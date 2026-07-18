  @doc """
  Starts the backing GenServer and creates the ETS table.

  ## Options

    * `:name` — registration name for the GenServer process.
      Defaults to `#{__MODULE__}`.

  Returns `{:ok, pid}` on success, or `{:error, {:already_started, pid}}`
  if the server is already running.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end