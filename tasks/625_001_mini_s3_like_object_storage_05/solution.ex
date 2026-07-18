  @doc "Starts the ObjectStorage server linked to the current process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    root_dir = Keyword.get(opts, :root_dir, "./object_storage_data")
    name = Keyword.get(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, root_dir, server_opts)
  end