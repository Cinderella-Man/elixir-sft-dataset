  @doc """
  Return a map of runtime statistics with `:late_dropped`, `:watermark`, and
  `:open_buckets` (the number of not-yet-finalized buckets currently buffered).
  """
  @spec stats(GenServer.server()) :: map()
  def stats(pid), do: GenServer.call(pid, :stats)