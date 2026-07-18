  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, 60_000)

    schedule_sweep(sweep_interval_ms)

    {:ok, %__MODULE__{clock: clock, sweep_interval_ms: sweep_interval_ms}}
  end