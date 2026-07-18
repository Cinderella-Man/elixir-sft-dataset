  @doc """
  Insert or update `key` with `value` in the cache named `name`.

  * **Existing key** – value is updated and the entry is promoted to
    most-recently used.
  * **New key, cache not full** – entry is inserted.
  * **New key, cache full** – the least-recently used entry is evicted first,
    then the new entry is inserted.

  Always returns `:ok`.
  """
  @spec put(name(), key(), value()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end