  @doc """
  Returns the number of **distinct** members observed for `key` that fall
  within the last `window_ms` milliseconds relative to the current clock time.

  Members observed only outside that window are not counted. A member observed
  in more than one in-window bucket is counted once (the union of all in-window
  buckets).
  """
  @spec distinct_count(server(), key(), non_neg_integer()) :: non_neg_integer()
  def distinct_count(server, key, window_ms) do
    GenServer.call(server, {:distinct_count, key, window_ms})
  end