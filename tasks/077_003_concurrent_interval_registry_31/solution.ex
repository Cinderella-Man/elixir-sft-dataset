  @doc """
  Returns the sorted list of stored intervals that overlap `{start, finish}`.

  Two intervals overlap when they share at least one point.
  """
  @spec overlapping(GenServer.server(), interval()) :: [interval()]
  def overlapping(server, {s, f}) when is_integer(s) and is_integer(f) and s <= f do
    GenServer.call(server, {:overlapping, s, f})
  end