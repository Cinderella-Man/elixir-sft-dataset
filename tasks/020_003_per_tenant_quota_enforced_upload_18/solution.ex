  @doc """
  Starts the store. Accepts `:name` (registration) and `:quota_bytes` (per-account
  budget, default `10_000_000`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end