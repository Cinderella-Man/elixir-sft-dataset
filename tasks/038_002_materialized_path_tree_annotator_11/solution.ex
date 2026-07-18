  @doc """
  Returns `{:ok, slice}` — the node with the given id and all of its
  descendants (every node whose `:path` contains `id`) in pre-order — or
  `{:error, :not_found}` when the id is not present.
  """
  @spec subtree([map()], id()) :: {:ok, [map()]} | {:error, :not_found}
  def subtree(nodes, id) when is_list(nodes) do
    if Enum.any?(nodes, &(&1.id == id)) do
      {:ok, Enum.filter(nodes, fn node -> id in node.path end)}
    else
      {:error, :not_found}
    end
  end