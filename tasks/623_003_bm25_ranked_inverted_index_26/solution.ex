  @doc """
  Removes the document `id` from the index entirely.

  Removing a non-existent `id` is a no-op. Returns `:ok`.
  """
  @spec remove(GenServer.server(), String.t()) :: :ok
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end