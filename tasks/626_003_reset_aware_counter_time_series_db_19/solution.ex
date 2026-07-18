  @doc """
  Starts the storage engine.

  Options:

    * `:chunk_duration_ms` — width of each storage chunk (default `60_000`).
    * `:clock` — zero-arity function returning the current time in
      milliseconds (default `System.monotonic_time(:millisecond)`).
    * `:name` — optional process registration name.
    * `:retention_ms` — how long chunks are kept (default `3_600_000`).
    * `:cleanup_interval_ms` — how often automatic cleanup runs, or `:infinity`
      to disable (default `60_000`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end