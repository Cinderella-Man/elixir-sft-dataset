  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table)
    name = Keyword.get(opts, :name, @default_name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{table_name: table_name}, gen_opts)
  end