  @doc """
  Start and link a `WeightedLRUCache`.

  ## Options

  * `:name` (required) – atom to register the process and derive ETS table names.
  * `:max_weight` (required) – positive integer total weight budget.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end