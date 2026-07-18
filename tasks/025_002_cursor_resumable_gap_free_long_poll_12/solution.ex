  @doc """
  Starts the backing `GenServer`.

  Options:
    * `:name` — registration name and server reference (default `Notifications`)
    * `:buffer_size` — max retained events per user (default `100`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end