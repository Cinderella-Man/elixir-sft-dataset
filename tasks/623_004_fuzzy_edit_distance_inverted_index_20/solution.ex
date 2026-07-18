  @doc """
  Remove the document `id` entirely.

  After removal the document no longer appears in search results, the document count
  decreases, and any vocabulary term that no longer appears in any document is dropped.
  Removing an unknown `id` is a no-op that returns `:ok`.
  """
  @spec remove(GenServer.server(), String.t()) :: :ok
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end