  @doc """
  Start and link an `LFUCache` process.

  ## Options

  * `:name` (required) – atom used to register the process and derive the ETS
    table names (`<name>_data` and `<name>_order`).
  * `:max_size` (required) – maximum number of entries; a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end