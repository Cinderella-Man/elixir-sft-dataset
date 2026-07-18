  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> NaiveDateTime.utc_now() end)
    tick_interval = Keyword.get(opts, :tick_interval_ms, 1_000)

    schedule_tick(tick_interval)

    {:ok,
     %{
       jobs: %{},
       clock: clock,
       tick_interval_ms: tick_interval
     }}
  end