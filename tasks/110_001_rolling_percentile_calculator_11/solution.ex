  @doc """
  Starts and registers the process.

  ## Options

    * `:name` — the name to register the process under. Default: `Percentile`.
    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Default: `fn -> System.monotonic_time(:millisecond) end`.
    * `:window_ms` — positive integer enabling a time-based window.
    * `:max_samples` — positive integer enabling a count-based window.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end