  @doc """
  Starts the config store.

  Supported options: `:base`, `:name`, `:list_strategy`, `:list_strategies` and
  `:locked`. See the module documentation for their meaning.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {base, opts1} = Keyword.pop(opts, :base, %{})
    {name, opts2} = Keyword.pop(opts1, :name)

    resolved = resolve_opts(opts2)
    state = %{base: base, layers: [], opts: resolved}

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, state, gen_opts)
  end