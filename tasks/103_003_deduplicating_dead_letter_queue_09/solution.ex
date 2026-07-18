  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {:ok, %{clock: clock, next_id: 0, queues: %{}}}
  end