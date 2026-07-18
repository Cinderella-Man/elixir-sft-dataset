  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    {capacity, opts} = Keyword.pop(opts, :capacity)
    GenServer.start_link(__MODULE__, capacity, [name: name] ++ opts)
  end