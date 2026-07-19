  @spec forest(GenServer.server()) ::
          {:ok, [tree_node()]} | {:error, {:cycle_detected, [id()]}}