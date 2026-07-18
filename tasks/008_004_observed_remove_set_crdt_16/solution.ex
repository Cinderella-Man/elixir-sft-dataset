  @doc """
  Adds `element` to the set, tagged with `node_id`.

  A unique tag `{node_id, counter}` is generated internally. If the element
  is already present, a new tag is added alongside existing ones. This is safe
  because each tag is unique.

  Returns `:ok`.
  """
  @spec add(server(), element(), node_id()) :: :ok
  def add(server, element, node_id) do
    GenServer.call(server, {:add, element, node_id})
  end