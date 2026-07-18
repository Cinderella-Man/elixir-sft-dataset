  @doc """
  Schedules `func` for `key`, coalescing with `delay_ms` but guaranteeing a fire
  within `max_ms` of the burst's first call. Returns `:ok` promptly.
  """
  @spec call(term(), non_neg_integer(), non_neg_integer(), (-> any())) :: :ok
  def call(key, delay_ms, max_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_integer(max_ms) and
             max_ms >= delay_ms and
             is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, max_ms, func})
  end