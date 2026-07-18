  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      next_id: 0,
      # queue_name => list of entries, kept in oldest-first insertion order
      queues: %{}
    }

    {:ok, state}
  end