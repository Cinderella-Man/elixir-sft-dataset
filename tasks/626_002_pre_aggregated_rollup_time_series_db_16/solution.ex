  @doc """
  Starts the `RollupTSDB` server.

  Options:

    * `:bucket_duration_ms` - width of each rollup bucket in milliseconds
      (default `#{@default_bucket_duration_ms}`).
    * `:clock` - zero-arity function returning the current time in
      milliseconds (default `System.monotonic_time/1` in `:millisecond`).
    * `:name` - optional process registration name.
    * `:retention_ms` - how long buckets are kept before becoming eligible for
      cleanup (default `#{@default_retention_ms}`).
    * `:cleanup_interval_ms` - how often automatic cleanup runs, or `:infinity`
      to disable it (default `#{@default_cleanup_interval_ms}`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end