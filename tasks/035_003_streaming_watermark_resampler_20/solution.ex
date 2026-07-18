  @doc """
  Ingest one `{timestamp_ms, value}` data point.

  Advances the watermark (the maximum timestamp seen) and may finalize buckets.
  A point mapping to an already-finalized bucket is dropped and counted as late.
  Returns `:ok`.
  """
  @spec push(GenServer.server(), integer(), number()) :: :ok
  def push(pid, timestamp_ms, value) when is_integer(timestamp_ms) do
    GenServer.call(pid, {:push, timestamp_ms, value})
  end