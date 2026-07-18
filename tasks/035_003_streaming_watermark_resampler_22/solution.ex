  @doc """
  Force-finalize every still-open bucket up to and including the bucket
  containing the current watermark, then return the full sorted list of all
  finalized buckets.
  """
  @spec flush(GenServer.server()) :: [{integer(), number() | nil}]
  def flush(pid), do: GenServer.call(pid, :flush)