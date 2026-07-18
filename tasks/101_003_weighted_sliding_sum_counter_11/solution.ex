  @doc """
  Starts the `SlidingSum` server.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often to run the periodic cleanup. Defaults
      to `60_000`. Pass `:infinity` to disable periodic cleanup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end