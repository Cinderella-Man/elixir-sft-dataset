  @doc """
  Return the buckets finalized so far as `{bucket_start_ms, aggregated_value}`
  tuples, sorted ascending by bucket start.
  """
  @spec finalized(GenServer.server()) :: [{integer(), number() | nil}]
  def finalized(pid), do: GenServer.call(pid, :finalized)