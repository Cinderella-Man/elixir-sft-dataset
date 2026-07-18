  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {name, _opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{processor: processor}, gen_opts)
  end