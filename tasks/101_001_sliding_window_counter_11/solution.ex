  @doc """
  Starts the `SlidingCounter` process.

  ## Options

  | key                    | type / default                   | description                    |
  |------------------------|----------------------------------|--------------------------------|
  | `:clock`               | `(-> integer)` / monotonic       | Current time in ms (0-arity)   |
  | `:bucket_ms`           | `pos_integer` / `1_000`          | Width of each sub-bucket       |
  | `:max_window_ms`       | `pos_integer` / `bucket_ms * 60` | Oldest data retained; cutoff   |
  | `:cleanup_interval_ms` | `pos_integer`/`:infinity`/`60_000` | Background cleanup interval   |
  | `:name`                | atom / `nil`                     | Optional registration name     |
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    # Separate GenServer start options (like :name) from our init options so
    # we can forward them cleanly.
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end