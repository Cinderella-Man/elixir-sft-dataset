  @spec add_edge(GenServer.server(), term(), term()) ::
          :ok | {:error, :cycle | :vertex_not_found}