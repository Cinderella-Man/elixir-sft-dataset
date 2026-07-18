  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, 60_000)
    refresh_threshold = Keyword.get(opts, :refresh_threshold, 0.8)

    schedule_sweep(sweep_interval_ms)

    {:ok,
     %__MODULE__{
       clock: clock,
       sweep_interval_ms: sweep_interval_ms,
       refresh_threshold: refresh_threshold * 1.0
     }}
  end