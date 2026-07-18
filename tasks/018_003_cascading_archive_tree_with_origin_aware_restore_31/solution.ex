  @doc """
  Restores a directly archived node together with the descendants that the same
  cascade took down.

  Descendants with `archive_origin: :direct` stay archived, along with their
  entire subtree.
  """
  @spec unarchive_node(GenServer.server(), id()) ::
          {:ok, %{node: node_map(), restored: [id()]}}
          | {:error, :not_found | :not_archived | :cascade_archived | :parent_archived}
  def unarchive_node(server, id) do
    GenServer.call(server, {:unarchive_node, id})
  end