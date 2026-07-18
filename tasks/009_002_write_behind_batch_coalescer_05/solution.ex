  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    flush_interval_ms = Keyword.fetch!(opts, :flush_interval_ms)
    server_opts = Keyword.take(opts, [:name])
    # Initializing state with an empty batches map
    GenServer.start_link(
      __MODULE__,
      %{flush_interval_ms: flush_interval_ms, batches: %{}},
      server_opts
    )
  end