  @impl true
  def init(opts) do
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)

    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      max_keys: max_keys,
      tick: 0,
      counter: 0,
      payments: [],
      # key => {result, last_used_tick}
      idempotency_keys: %{}
    }

    {:ok, state}
  end