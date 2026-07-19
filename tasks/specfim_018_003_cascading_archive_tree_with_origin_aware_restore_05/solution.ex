  @spec fetch_node(GenServer.server(), id(), keyword()) ::
          {:ok, node_map()} | {:error, :not_found}