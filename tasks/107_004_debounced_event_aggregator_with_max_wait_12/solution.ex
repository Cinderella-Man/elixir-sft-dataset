  @doc """
  Start a debounce aggregator process.

  ## Options

    * `:idle_ms` — positive integer milliseconds of quiet after which the batch
      is flushed; reset on every push. Defaults to `#{@default_idle_ms}`.
    * `:max_wait_ms` — positive integer milliseconds after the first event of a
      batch at which it is flushed regardless of activity. Defaults to
      `#{@default_max_wait_ms}`.
    * `:batch_size` — positive integer or `:infinity`; flush once this many events
      are buffered. Defaults to `:infinity`.
    * `:on_flush` — one-arity function called with the batch (a list) on each
      flush. Defaults to a no-op.
    * `:name` — optional registration name, passed to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end