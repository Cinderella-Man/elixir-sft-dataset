  @doc """
  Inserts or updates the association between `key` and `value`, preserving the
  bijection invariant. Always returns `:ok`.
  """
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end