  @doc """
  Records that `member` was observed for `key` at the current clock time.

  Always returns `:ok`.
  """
  @spec add(server(), key(), member()) :: :ok
  def add(server, key, member) do
    GenServer.call(server, {:add, key, member})
  end