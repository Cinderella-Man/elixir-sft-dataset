  @doc """
  Synchronously runs cleanup across all shards and returns `:ok`.

  Removes any chunk whose `chunk_start + chunk_duration_ms` is less than or
  equal to `now - retention_ms` (with `now` from `:clock`) and drops any
  series left with zero chunks.
  """
  @spec cleanup(server()) :: :ok
  def cleanup(server) do
    GenServer.call(server, :cleanup)
  end