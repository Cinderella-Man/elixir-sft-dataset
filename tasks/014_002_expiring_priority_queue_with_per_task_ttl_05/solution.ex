  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {default_ttl_ms, opts} = Keyword.pop(opts, :default_ttl_ms, 5000)
    {clock, opts} = Keyword.pop(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {name, _opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      %{processor: processor, default_ttl_ms: default_ttl_ms, clock: clock},
      gen_opts
    )
  end