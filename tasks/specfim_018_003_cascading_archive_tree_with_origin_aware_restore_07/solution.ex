  @spec rename_node(GenServer.server(), id(), String.t()) ::
          {:ok, node_map()} | {:error, :invalid_name | :not_found}