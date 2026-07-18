  @doc """
  Returns `:ok` or `:alarm` for `key` based on the current clock time, without
  recording anything.
  """
  @spec status(GenServer.server(), key()) :: status()
  def status(server, key) do
    GenServer.call(server, {:status, key})
  end