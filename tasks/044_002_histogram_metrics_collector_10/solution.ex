  @doc """
  Starts the backing GenServer and creates the ETS table.

  ## Options

    * `:name` — registration name for the process. Defaults to `#{__MODULE__}`.
    * `:buckets` — sorted ascending list of integer upper bounds.
      Defaults to `#{inspect(@default_buckets)}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end