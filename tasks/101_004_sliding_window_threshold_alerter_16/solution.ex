  @doc """
  Returns the number of events recorded for `key` that fall within the last
  `:window_ms` milliseconds relative to the current clock time.
  """
  @spec count(GenServer.server(), key()) :: non_neg_integer()
  def count(server, key) do
    GenServer.call(server, {:count, key})
  end