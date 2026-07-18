  @doc """
  Starts the ORSet process.

  ## Options

    * `:name` — optional name for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end