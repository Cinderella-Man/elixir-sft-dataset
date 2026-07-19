  @spec list_children(GenServer.server(), id(), keyword()) ::
          {:ok, [node_map()]} | {:error, :not_found}