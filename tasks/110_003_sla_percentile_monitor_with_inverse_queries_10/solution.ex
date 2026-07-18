  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    window_ms = validate_positive(Keyword.get(opts, :window_ms))
    max_samples = validate_positive(Keyword.get(opts, :max_samples))

    {:ok,
     %{
       clock: clock,
       window_ms: window_ms,
       max_samples: max_samples,
       series: %{}
     }}
  end