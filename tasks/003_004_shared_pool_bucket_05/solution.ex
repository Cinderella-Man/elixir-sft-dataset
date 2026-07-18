  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    _ = Keyword.fetch!(opts, :global_capacity)
    _ = Keyword.fetch!(opts, :global_refill_rate)

    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end