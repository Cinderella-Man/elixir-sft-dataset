  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    capacity = Keyword.get(opts, :capacity, :infinity)
    {:ok, %{clock: clock, capacity: capacity, next_id: 0, queues: %{}}}
  end