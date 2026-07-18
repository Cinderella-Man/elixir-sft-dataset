  @doc """
  Starts the document store.

  Options: `:clock` (zero-arity fn returning integer milliseconds) and
  `:retention_ms` (how long a trashed document stays restorable).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)