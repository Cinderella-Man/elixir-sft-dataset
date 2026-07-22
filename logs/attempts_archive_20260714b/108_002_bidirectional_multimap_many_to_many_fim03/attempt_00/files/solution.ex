def start_link(opts) do
  {name, opts} = Keyword.pop(opts, :name)
  GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
end