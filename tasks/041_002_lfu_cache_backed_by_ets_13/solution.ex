  @doc """
  Insert or update `key` with `value`.

  A new entry starts at frequency 1. Updating an existing key refreshes its
  value and increments its frequency. When the cache is full and the key is
  new, the least-frequently-used entry (LRU tie-break) is evicted first.
  Always returns `:ok`.
  """
  @spec put(name(), key(), value()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end