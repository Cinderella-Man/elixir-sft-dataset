  @spec unarchive_node(GenServer.server(), id()) ::
          {:ok, %{node: node_map(), restored: [id()]}}
          | {:error, :not_found | :not_archived | :cascade_archived | :parent_archived}