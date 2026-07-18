  @doc """
  Returns `{:ok, total_used}` — the total usage for `key` within `window_ms`.
  """
  @spec usage(server(), key(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def usage(server, key, window_ms) do
    GenServer.call(server, {:usage, key, window_ms})
  end