  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, &System.monotonic_time/0)
    capacity = Keyword.fetch!(opts, :capacity)

    {:ok, %__MODULE__{clock: clock, capacity: capacity}}
  end