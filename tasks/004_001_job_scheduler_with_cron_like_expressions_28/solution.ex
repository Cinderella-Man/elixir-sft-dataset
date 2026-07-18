  @doc """
  Starts the Scheduler process.

  ## Options

    * `:clock` – zero-arity function returning `NaiveDateTime` for the current
      time. Defaults to `fn -> NaiveDateTime.utc_now() end`.
    * `:name` – optional process registration name.
    * `:tick_interval_ms` – milliseconds between ticks (default `1_000`).
      Set to `:infinity` to disable automatic ticking.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = split_opts(opts)
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end