  @doc """
  Starts the payment server.

  Accepts `:clock`, `:ttl_ms`, `:cleanup_interval_ms`, `:processor` and the
  usual `:name` option forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end