  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    config = %{
      window_size: Keyword.get(opts, :window_size, 20),
      error_rate_threshold: Keyword.get(opts, :error_rate_threshold, 0.5),
      min_calls_in_window: Keyword.get(opts, :min_calls_in_window, 10),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, 30_000),
      half_open_max_probes: Keyword.get(opts, :half_open_max_probes, 1)
    }

    {:ok,
     %{
       state: :closed,
       # outcomes are :ok or :error atoms, newest first, max length window_size
       outcomes: [],
       opened_at: nil,
       probes_in_flight: 0,
       clock: clock,
       config: config
     }}
  end