@impl true
def init(opts) do
  clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
  sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms)

  state = %__MODULE__{
    clock: clock,
    sweep_interval_ms: sweep_interval_ms
  }

  schedule_sweep(sweep_interval_ms)

  {:ok, state}
end