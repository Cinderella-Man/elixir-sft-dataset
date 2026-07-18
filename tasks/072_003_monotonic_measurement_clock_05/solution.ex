  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {initial_ms, opts} = Keyword.pop(opts, :initial, @default_initial_ms)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    # Store the counter in microseconds internally.
    GenServer.start_link(__MODULE__, initial_ms * 1000, gen_opts)
  end