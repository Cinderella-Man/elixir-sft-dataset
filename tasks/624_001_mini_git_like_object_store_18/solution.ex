  @doc """
  Creates a tree object from a list of entry maps.

  Each entry must contain:
    * `:name`  — filename (string)
    * `:hash`  — SHA-1 hex of an already-stored object
    * `:type`  — `:blob` or `:tree`

  Entries are sorted alphabetically by `:name` before serialization,
  so the resulting hash is independent of input order.
  """
  @spec tree(GenServer.server(), [map()]) :: {:ok, String.t()}
  def tree(server, entries) when is_list(entries) do
    GenServer.call(server, {:tree, entries})
  end