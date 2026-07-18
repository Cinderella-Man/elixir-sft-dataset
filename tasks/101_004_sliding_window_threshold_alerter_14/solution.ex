  @doc """
  Records one event for `key` at the current clock time and returns the key's
  resulting status (`:ok` or `:alarm`).
  """
  @spec record(GenServer.server(), key()) :: status()
  def record(server, key) do
    GenServer.call(server, {:record, key})
  end