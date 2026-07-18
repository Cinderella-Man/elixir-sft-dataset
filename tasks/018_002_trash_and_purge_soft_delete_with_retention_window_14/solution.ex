  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.system_time(:millisecond) end)
    retention = Keyword.get(opts, :retention_ms, @default_retention_ms)
    {:ok, %{docs: %{}, next_id: 1, clock: clock, retention: retention}}
  end