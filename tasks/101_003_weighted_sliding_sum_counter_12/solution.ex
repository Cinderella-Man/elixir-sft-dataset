  @doc """
  Records `amount` for `key` at the current clock time.

  `amount` may be any number: an integer or a float, and it may be negative.
  This call is synchronous so that the amount is guaranteed to be recorded at
  the clock time observed when `add/3` is invoked. Always returns `:ok`.
  """
  @spec add(GenServer.server(), key(), number()) :: :ok
  def add(server, key, amount) when is_number(amount) do
    GenServer.call(server, {:add, key, amount})
  end