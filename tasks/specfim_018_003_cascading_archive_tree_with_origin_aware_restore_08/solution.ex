  @spec archive_node(GenServer.server(), id()) ::
          {:ok, %{node: node_map(), cascaded: [id()]}}