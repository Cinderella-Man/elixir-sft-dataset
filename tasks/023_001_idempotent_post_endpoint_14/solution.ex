  @doc """
  Starts the payment server.

  Options:

    * `:clock` — zero-arity function returning the current time in milliseconds
      (default `fn -> System.monotonic_time(:millisecond) end`).
    * `:ttl_ms` — how long idempotency keys are remembered (default 86_400_000).
    * `:cleanup_interval_ms` — how often expired idempotency entries are purged
      (default 60_000). Pass `:infinity` to disable automatic cleanup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end