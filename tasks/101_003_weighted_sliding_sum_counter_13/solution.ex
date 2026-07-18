  @doc """
  Returns the total of all amounts recorded for `key` that fall within the last
  `window_ms` milliseconds relative to the current clock time.

  Amounts outside the window are not included. A key with no recorded amounts
  returns `0`.
  """
  @spec sum(GenServer.server(), key(), non_neg_integer()) :: number()
  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end