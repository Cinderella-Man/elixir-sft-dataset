  @doc """
  Begins monitoring `name`. Replaces any existing registration for `name`.

  The clock starts immediately: if no heartbeat arrives within `interval_ms`,
  `on_timeout_fn.(name)` is invoked. Synchronous — once it returns, the timer is
  armed.
  """
  @spec register(term(), pid(), non_neg_integer(), (term() -> any())) :: :ok
  def register(name, pid, interval_ms, on_timeout_fn)
      when is_integer(interval_ms) and interval_ms >= 0 and is_function(on_timeout_fn, 1) do
    GenServer.call(__MODULE__, {:register, name, pid, interval_ms, on_timeout_fn})
  end