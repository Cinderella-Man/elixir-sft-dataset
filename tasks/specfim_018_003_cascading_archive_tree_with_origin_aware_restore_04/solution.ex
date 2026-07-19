  @spec create_file(GenServer.server(), map()) ::
          {:ok, node_map()} | {:error, :invalid_name | :parent_not_found | :parent_archived}