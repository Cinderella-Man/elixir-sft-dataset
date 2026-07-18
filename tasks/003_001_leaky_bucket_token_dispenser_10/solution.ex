  @doc """
  Starts the LeakyBucket GenServer.

  ## Options

    * `:clock` — zero-arity function returning current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` — optional name for process registration.
    * `:cleanup_interval_ms` — how often the cleanup sweep runs (default 60_000).
    * `:cleanup_ttl_ms` — buckets idle longer than this are evicted (default 300_000).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = extract_gen_opts(opts)
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end